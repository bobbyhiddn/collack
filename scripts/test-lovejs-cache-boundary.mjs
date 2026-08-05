#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import {
  access,
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const lock = JSON.parse(await readFile(path.join(root, "scripts/lovejs-toolchain-lock.json")));
const archiveName = lock.package.archive.name;
const historicalDigest = "355213dabdb3cd9abe0e54408d7a0cb33437b8f7d16a67a0490408a67ca2748e";
const historicalFixture = path.join(
  root,
  "tests/fixtures/e2dd610-collack-spike.love.base64",
);
const head = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
const tree = execFileSync("git", ["rev-parse", "HEAD^{tree}"], {
  cwd: root,
  encoding: "utf8",
}).trim();
const sandbox = await mkdtemp(path.join(root, "dist/.lovejs-cache-control-"));
let positive = 0;
let mutations = 0;

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function exists(absolute) {
  try {
    await access(absolute);
    return true;
  } catch {
    return false;
  }
}

async function filesBelow(directory, relative = "") {
  const entries = await readdir(path.join(directory, relative), { withFileTypes: true });
  const records = [];
  for (const entry of entries) {
    const name = path.posix.join(relative, entry.name);
    if (entry.isDirectory()) {
      records.push(...await filesBelow(directory, name));
    } else {
      assert(entry.isFile(), `build output contains non-file entry: ${name}`);
      const bytes = await readFile(path.join(directory, name));
      records.push({ path: name, bytes: bytes.length, sha256: sha256(bytes) });
    }
  }
  return records.sort((left, right) => left.path.localeCompare(right.path));
}

async function buildSnapshot() {
  const archive = await readFile(path.join(root, "dist/collack-paddle.love"));
  return {
    archive: { bytes: archive.length, sha256: sha256(archive) },
    output: await filesBelow(path.join(root, "dist/paddle-web")),
  };
}

function runBuild(cache, extraEnvironment = {}) {
  return spawnSync("bash", ["scripts/build-paddle-web.sh"], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      CALLACK_NODE_CACHE_DIR: cache,
      ...extraEnvironment,
    },
  });
}

function assertBuildPasses(label, result) {
  assert.equal(result.status, 0, `${label} failed:\n${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /without executing cached content/,
    `${label} did not report the non-execution trust boundary`);
  positive += 1;
}

function assertBuildFails(label, result, diagnostic) {
  assert.notEqual(result.status, 0, `${label} unexpectedly passed`);
  const output = `${result.stdout}\n${result.stderr}`;
  assert.match(output, diagnostic, `${label} used an imprecise diagnostic:\n${output}`);
  mutations += 1;
  console.log(`[lovejs-cache-control] OK rejected ${label}: ${output.trim().split("\n").at(-1)}`);
}

async function cacheWithValidArchive(name, validArchive) {
  const cache = path.join(sandbox, name);
  await mkdir(cache, { recursive: true });
  await copyFile(validArchive, path.join(cache, archiveName));
  return cache;
}

try {
  const historical = Buffer.from(
    (await readFile(historicalFixture, "utf8")).replace(/\s/g, ""),
    "base64",
  );
  assert.equal(sha256(historical), historicalDigest,
    "historical e2dd610 fixture does not contain the exact rejected archive bytes");

  const validCache = path.join(sandbox, "valid-cache");
  const cold = runBuild(validCache);
  assertBuildPasses("clean cold cache candidate build", cold);
  assert.match(cold.stdout, /authenticated cold cache archive/,
    "clean cache did not exercise authenticated cold-cache acquisition");
  const coldSnapshot = await buildSnapshot();
  const validArchive = path.join(validCache, archiveName);
  const validBytes = await readFile(validArchive);
  assert.equal(validBytes.length, lock.package.archive.bytes);
  assert.equal(sha256(validBytes), lock.package.archive.sha256);

  const warm = runBuild(validCache);
  assertBuildPasses("valid warm cache candidate build", warm);
  assert.match(warm.stdout, /authenticated warm cache archive/,
    "second build did not exercise authenticated warm-cache reuse");
  assert.deepEqual(await buildSnapshot(), coldSnapshot,
    "clean and warm cache builds produced different candidate output bytes");

  const historicalCache = path.join(sandbox, "historical-e2dd610-cache");
  await mkdir(historicalCache, { recursive: true });
  await writeFile(path.join(historicalCache, archiveName), historical);
  assertBuildFails(
    "exact historical e2dd610 archive with candidate labels",
    runBuild(historicalCache, {
      CALLACK_TARGET_SOURCE_COMMIT: head,
      CALLACK_TARGET_SOURCE_TREE: tree,
      CALLACK_TARGET_NAME: "paddle-web",
    }),
    /cached toolchain archive byte count mismatch before extraction/,
  );
  assert.equal(await exists(path.join(root, "dist/paddle-web/callack-build-manifest.json")), false,
    "poisoned historical cache left a stale or newly generated manifest");

  const executableCache = path.join(sandbox, "swapped-executable-cache");
  const fakeExecutable = path.join(executableCache, "node_modules/.bin/love.js");
  const sentinel = path.join(sandbox, "poisoned-executable-ran");
  await mkdir(path.dirname(fakeExecutable), { recursive: true });
  await writeFile(fakeExecutable, `#!/usr/bin/env bash\nprintf used > ${JSON.stringify(sentinel)}\n`);
  await chmod(fakeExecutable, 0o755);
  assertBuildFails(
    "swapped cached executable",
    runBuild(executableCache),
    /cache contains unexpected entry before authentication: node_modules/,
  );
  assert.equal(await exists(sentinel), false,
    "poisoned cache executable ran before the authentication gate");

  const alteredCache = await cacheWithValidArchive("altered-archive-cache", validArchive);
  const alteredPath = path.join(alteredCache, archiveName);
  const altered = Buffer.from(await readFile(alteredPath));
  altered[altered.length - 1] ^= 0xff;
  await writeFile(alteredPath, altered);
  assertBuildFails(
    "altered cached archive",
    runBuild(alteredCache),
    /cached toolchain archive SHA-256 mismatch before extraction/,
  );

  const mixedCache = await cacheWithValidArchive("mixed-cache", validArchive);
  await writeFile(path.join(mixedCache, "stale-package.json"), "{}\n");
  assertBuildFails(
    "stale mixed cache entries",
    runBuild(mixedCache),
    /cache contains unexpected entry before authentication: stale-package\.json/,
  );

  const symlinkEntryCache = path.join(sandbox, "symlink-entry-cache");
  await mkdir(symlinkEntryCache, { recursive: true });
  await symlink(validArchive, path.join(symlinkEntryCache, archiveName));
  assertBuildFails(
    "symlink archive substitution",
    runBuild(symlinkEntryCache),
    /cached toolchain archive is not a regular file before authentication/,
  );

  const symlinkRoot = path.join(sandbox, "symlink-root-cache");
  await symlink(validCache, symlinkRoot);
  assertBuildFails(
    "symlink cache-root substitution",
    runBuild(symlinkRoot),
    /CALLACK_NODE_CACHE_DIR crosses a symbolic link/,
  );

  const overlappingCache = path.join(root, "dist/paddle-web");
  assertBuildFails(
    "cache/output path substitution",
    runBuild(overlappingCache),
    /CALLACK_NODE_CACHE_DIR overlaps protected build path/,
  );

  const staleCache = path.join(sandbox, "stale-output-poison");
  await mkdir(path.join(root, "dist/paddle-web"), { recursive: true });
  await writeFile(
    path.join(root, "dist/paddle-web/callack-build-manifest.json"),
    "{\"stale\":true}\n",
  );
  await mkdir(staleCache, { recursive: true });
  await writeFile(path.join(staleCache, archiveName), historical);
  assertBuildFails(
    "stale output plus poisoned cache",
    runBuild(staleCache),
    /cached toolchain archive byte count mismatch before extraction/,
  );
  assert.equal(await exists(path.join(root, "dist/paddle-web/callack-build-manifest.json")), false,
    "failed authentication left stale build evidence available");
  assert.equal(await exists(path.join(root, "dist/collack-paddle.love")), false,
    "failed authentication left a stale final paddle archive available");

  const restored = runBuild(validCache);
  assertBuildPasses("restored authenticated candidate build", restored);
  assert.deepEqual(await buildSnapshot(), coldSnapshot,
    "restored candidate output differs from the clean-cache baseline");

  console.log(
    `[lovejs-cache-control] OK: ${positive} positive builds and ${mutations} cache/path mutations; `
      + `historical=${historicalDigest} tool-archive=${lock.package.archive.sha256}`,
  );
} finally {
  await rm(sandbox, { recursive: true, force: true });
}
