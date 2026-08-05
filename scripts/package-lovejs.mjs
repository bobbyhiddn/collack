#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  constants,
  copyFile,
  lstat,
  mkdir,
  open,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import https from "node:https";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const toolchainEvidenceName = "callack-toolchain-identity.json";
export const toolchainEvidenceSchema = "callack-lovejs-toolchain-v1";
export const toolchainLockPath = "scripts/lovejs-toolchain-lock.json";
export const toolchainPackagerPath = "scripts/package-lovejs.mjs";

function fail(message) {
  throw new Error(`[lovejs-toolchain] ${message}`);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function digest(algorithm, bytes, encoding = "hex") {
  return createHash(algorithm).update(bytes).digest(encoding);
}

function sha256(bytes) {
  return digest("sha256", bytes);
}

function canonicalBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function fileRecord(absolute, relative) {
  const info = await lstat(absolute);
  assert(info.isFile() && !info.isSymbolicLink(),
    `trusted input is not a regular file: ${relative}`);
  const bytes = await readFile(absolute);
  return { path: relative, bytes: bytes.length, sha256: sha256(bytes) };
}

function validateRecord(record, label) {
  assert(record && typeof record === "object" && !Array.isArray(record),
    `${label} is missing or malformed`);
  assert(typeof record.path === "string" && record.path !== ""
      && record.path === path.posix.normalize(record.path)
      && !record.path.startsWith("/") && !record.path.startsWith("../")
      && !record.path.includes("\\"),
  `${label} has an unsafe path`);
  assert(Number.isSafeInteger(record.bytes) && record.bytes >= 0,
    `${label} has an invalid byte count`);
  assert(/^[0-9a-f]{64}$/.test(record.sha256 ?? ""),
    `${label} has an invalid SHA-256`);
}

export function validateToolchainLock(lock) {
  assert(lock && typeof lock === "object" && !Array.isArray(lock),
    "candidate toolchain lock is not an object");
  assert(lock.schema === "callack-lovejs-toolchain-lock-v1",
    `candidate toolchain lock schema is ${lock.schema ?? "missing"}`);
  assert(lock.package?.name === "love.js" && lock.package?.version === "11.4.1",
    "candidate toolchain lock package identity is not love.js@11.4.1");
  const archive = lock.package.archive;
  assert(archive?.name === "love.js-11.4.1.tgz",
    "candidate toolchain archive name is not pinned");
  assert(archive.url === "https://registry.npmjs.org/love.js/-/love.js-11.4.1.tgz",
    "candidate toolchain archive URL is not pinned");
  assert(Number.isSafeInteger(archive.bytes) && archive.bytes > 0,
    "candidate toolchain archive byte count is invalid");
  assert(/^[0-9a-f]{64}$/.test(archive.sha256 ?? ""),
    "candidate toolchain archive SHA-256 is invalid");
  assert(/^[0-9a-f]{128}$/.test(archive.sha512 ?? ""),
    "candidate toolchain archive SHA-512 is invalid");
  assert(archive.integrity === `sha512-${Buffer.from(archive.sha512, "hex").toString("base64")}`,
    "candidate toolchain archive SRI disagrees with its SHA-512");
  assert(Array.isArray(lock.runtimeFiles) && lock.runtimeFiles.length === 5,
    "candidate toolchain runtime file set is incomplete");
  const paths = [];
  for (const record of lock.runtimeFiles) {
    validateRecord(record, "candidate toolchain runtime file");
    paths.push(record.path);
  }
  assert(new Set(paths).size === paths.length,
    "candidate toolchain runtime file set contains duplicates");
  assert(paths.join("\n") === [...paths].sort().join("\n"),
    "candidate toolchain runtime file set is not sorted");
  return lock;
}

function argumentsFrom(argv) {
  const values = new Map();
  for (let index = 2; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    assert(name?.startsWith("--") && value !== undefined,
      `invalid command argument near ${name ?? "end of command"}`);
    assert(!values.has(name), `duplicate command argument: ${name}`);
    values.set(name, value);
  }
  for (const required of ["--root", "--cache", "--archive", "--output", "--scratch"]) {
    assert(values.has(required), `missing required command argument: ${required}`);
  }
  return Object.fromEntries([...values].map(([name, value]) => [name.slice(2), value]));
}

function isWithin(parent, candidate) {
  const relative = path.relative(parent, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

async function assertNoSymlinkComponents(absolute, label) {
  assert(path.isAbsolute(absolute) && path.resolve(absolute) === absolute,
    `${label} must be an absolute normalized path`);
  const parsed = path.parse(absolute);
  let cursor = parsed.root;
  for (const component of absolute.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, component);
    let info;
    try {
      info = await lstat(cursor);
    } catch (error) {
      if (error?.code === "ENOENT") return;
      throw error;
    }
    assert(!info.isSymbolicLink(), `${label} crosses a symbolic link: ${cursor}`);
  }
}

function verifyArchiveBytes(bytes, archive, source) {
  assert(bytes.length === archive.bytes,
    `${source} byte count mismatch before extraction: ${bytes.length}, expected ${archive.bytes}`);
  const actualSha256 = digest("sha256", bytes);
  assert(actualSha256 === archive.sha256,
    `${source} SHA-256 mismatch before extraction: ${actualSha256}, expected ${archive.sha256}`);
  const actualSha512 = digest("sha512", bytes);
  assert(actualSha512 === archive.sha512,
    `${source} SHA-512 mismatch before extraction: ${actualSha512}, expected ${archive.sha512}`);
}

async function readRegularNoFollow(absolute, label) {
  const info = await lstat(absolute);
  assert(info.isFile() && !info.isSymbolicLink(), `${label} is not a regular file`);
  const handle = await open(
    absolute,
    constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0),
  );
  try {
    return await handle.readFile();
  } finally {
    await handle.close();
  }
}

async function downloadExactArchive(archive) {
  return await new Promise((resolve, reject) => {
    const request = https.get(archive.url, {
      headers: { "user-agent": "callack-authenticated-lovejs-builder/1" },
    }, (response) => {
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(
          `[lovejs-toolchain] authenticated archive download returned HTTP ${response.statusCode}; redirects are forbidden`,
        ));
        return;
      }
      const chunks = [];
      let received = 0;
      response.on("data", (chunk) => {
        received += chunk.length;
        if (received > archive.bytes) {
          request.destroy(new Error(
            `[lovejs-toolchain] archive download exceeded pinned byte count ${archive.bytes}`,
          ));
          return;
        }
        chunks.push(chunk);
      });
      response.on("end", () => resolve(Buffer.concat(chunks)));
      response.on("error", reject);
    });
    request.on("error", reject);
  });
}

async function authenticatedArchive(cacheDirectory, archive) {
  await assertNoSymlinkComponents(cacheDirectory, "CALLACK_NODE_CACHE_DIR");
  await mkdir(cacheDirectory, { recursive: true, mode: 0o755 });
  await assertNoSymlinkComponents(cacheDirectory, "CALLACK_NODE_CACHE_DIR");
  const cacheReal = await realpath(cacheDirectory);
  assert(cacheReal === cacheDirectory,
    `CALLACK_NODE_CACHE_DIR changed identity: ${cacheDirectory} -> ${cacheReal}`);

  const entries = await readdir(cacheDirectory, { withFileTypes: true });
  for (const entry of entries) {
    assert(entry.name === archive.name,
      `cache contains unexpected entry before authentication: ${entry.name}`);
    assert(entry.isFile() && !entry.isSymbolicLink(),
      `cached toolchain archive is not a regular file before authentication: ${entry.name}`);
  }

  const cacheArchive = path.join(cacheDirectory, archive.name);
  let bytes;
  let cacheState;
  try {
    bytes = await readRegularNoFollow(cacheArchive, "cached toolchain archive");
    cacheState = "warm";
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    bytes = await downloadExactArchive(archive);
    verifyArchiveBytes(bytes, archive, "downloaded toolchain archive");
    await assertNoSymlinkComponents(cacheDirectory, "CALLACK_NODE_CACHE_DIR");
    try {
      const handle = await open(cacheArchive, "wx", 0o644);
      try {
        await handle.writeFile(bytes);
        await handle.sync();
      } finally {
        await handle.close();
      }
    } catch (writeError) {
      if (writeError?.code !== "EEXIST") throw writeError;
      bytes = await readRegularNoFollow(cacheArchive, "raced cached toolchain archive");
    }
    cacheState = "cold";
  }
  verifyArchiveBytes(bytes, archive, "cached toolchain archive");
  return { bytes, cacheState, cacheArchive };
}

async function verifyExtractedRuntime(packageRoot, runtimeFiles) {
  const verified = [];
  for (const expected of runtimeFiles) {
    const absolute = path.join(packageRoot, ...expected.path.split("/"));
    await assertNoSymlinkComponents(absolute, `extracted runtime file ${expected.path}`);
    const actual = await fileRecord(absolute, expected.path);
    assert(actual.bytes === expected.bytes && actual.sha256 === expected.sha256,
      `extracted runtime file mismatch for ${expected.path}: ${actual.sha256}/${actual.bytes}, expected ${expected.sha256}/${expected.bytes}`);
    verified.push(actual);
  }
  return verified;
}

function replaceExactlyOnce(template, marker, value) {
  const first = template.indexOf(marker);
  const last = template.lastIndexOf(marker);
  assert(first !== -1 && first === last,
    `authenticated game template must contain exactly one ${marker}`);
  return `${template.slice(0, first)}${value}${template.slice(first + marker.length)}`;
}

async function run() {
  const args = argumentsFrom(process.argv);
  const root = path.resolve(args.root);
  const cache = path.resolve(args.cache);
  const archivePath = path.resolve(args.archive);
  const output = path.resolve(args.output);
  const scratch = path.resolve(args.scratch);
  for (const [label, original, resolved] of [
    ["root", args.root, root],
    ["CALLACK_NODE_CACHE_DIR", args.cache, cache],
    ["candidate archive", args.archive, archivePath],
    ["build output", args.output, output],
    ["toolchain scratch", args.scratch, scratch],
  ]) {
    assert(path.isAbsolute(original) && original === resolved,
      `${label} must be an absolute normalized path`);
  }
  const protectedPaths = [
    path.join(root, "scripts"),
    path.join(root, "src"),
    path.join(root, "battle"),
    path.join(root, "targets"),
    path.join(root, "web-shell"),
    path.join(root, "dist/web"),
    path.join(root, "dist/paddle-web"),
    path.join(root, "dist/collack-spike.love"),
    path.join(root, "dist/collack-paddle.love"),
    archivePath,
    output,
    scratch,
  ];
  for (const protectedPath of protectedPaths) {
    assert(!isWithin(cache, protectedPath) && !isWithin(protectedPath, cache),
      `CALLACK_NODE_CACHE_DIR overlaps protected build path: ${protectedPath}`);
  }
  await assertNoSymlinkComponents(root, "candidate root");
  await assertNoSymlinkComponents(archivePath, "candidate archive");
  await assertNoSymlinkComponents(output, "build output");
  await assertNoSymlinkComponents(scratch, "toolchain scratch");

  const lockAbsolute = path.join(root, toolchainLockPath);
  const packagerAbsolute = fileURLToPath(import.meta.url);
  const lockBytes = await readFile(lockAbsolute);
  let lock;
  try {
    lock = validateToolchainLock(JSON.parse(lockBytes.toString("utf8")));
  } catch (error) {
    if (error?.message?.startsWith("[lovejs-toolchain]")) throw error;
    fail(`candidate toolchain lock is invalid JSON: ${error.message}`);
  }

  const cached = await authenticatedArchive(cache, lock.package.archive);
  await rm(scratch, { recursive: true, force: true });
  await mkdir(scratch, { recursive: true, mode: 0o755 });
  const localArchive = path.join(scratch, lock.package.archive.name);
  await writeFile(localArchive, cached.bytes, { mode: 0o644 });

  const extracted = path.join(scratch, "extracted");
  await mkdir(extracted, { recursive: true, mode: 0o755 });
  const tar = "/usr/bin/tar";
  const tarResolved = await realpath(tar);
  assert(tarResolved === "/usr/bin/tar" || tarResolved === "/usr/bin/bsdtar",
    `trusted system extractor resolved outside the fixed platform allowlist: ${tarResolved}`);
  const tarInfo = await lstat(tarResolved);
  assert(tarInfo.isFile() && !tarInfo.isSymbolicLink(),
    `trusted system extractor is unavailable: ${tarResolved}`);
  execFileSync(tarResolved, ["-xzf", localArchive, "-C", extracted], {
    cwd: root,
    env: { LC_ALL: "C", PATH: "/usr/bin:/bin" },
    stdio: ["ignore", "ignore", "pipe"],
  });
  const packageRoot = path.join(extracted, "package");
  const runtimeFiles = await verifyExtractedRuntime(packageRoot, lock.runtimeFiles);

  const candidateArchive = await fileRecord(archivePath, path.basename(archivePath));
  await rm(output, { recursive: true, force: true });
  await mkdir(path.join(output, "theme"), { recursive: true, mode: 0o755 });
  const gameData = await readFile(archivePath);
  await writeFile(path.join(output, "game.data"), gameData, { mode: 0o644 });

  const gameTemplatePath = path.join(packageRoot, "src", "game.js");
  let gameScript = (await readFile(gameTemplatePath)).toString("utf8");
  const metadata = JSON.stringify({
    package_uuid: `sha256-${candidateArchive.sha256}`,
    remote_package_size: candidateArchive.bytes,
    files: [{
      filename: "/game.love",
      crunched: 0,
      start: 0,
      end: candidateArchive.bytes,
      audio: false,
    }],
  });
  gameScript = replaceExactlyOnce(gameScript, "{{{create_file_paths}}}", "");
  gameScript = replaceExactlyOnce(gameScript, "{{{metadata}}}", metadata);
  assert(!gameScript.includes("{{{"),
    "authenticated game template still contains an unresolved raw placeholder");
  await writeFile(path.join(output, "game.js"), gameScript, { mode: 0o644 });

  for (const [source, destination] of [
    ["src/compat/love.js", "love.js"],
    ["src/compat/love.wasm", "love.wasm"],
    ["src/compat/theme/bg.png", "theme/bg.png"],
    ["src/compat/theme/love.css", "theme/love.css"],
  ]) {
    await copyFile(
      path.join(packageRoot, ...source.split("/")),
      path.join(output, ...destination.split("/")),
    );
  }

  const identity = {
    schema: toolchainEvidenceSchema,
    package: lock.package,
    lock: await fileRecord(lockAbsolute, toolchainLockPath),
    packager: await fileRecord(packagerAbsolute, toolchainPackagerPath),
    runtimeFiles,
    candidateArchive,
  };
  await writeFile(path.join(output, toolchainEvidenceName), canonicalBytes(identity), {
    mode: 0o644,
  });
  console.log(
    `[lovejs-toolchain] authenticated ${cached.cacheState} cache archive ${lock.package.archive.sha256} before extraction`,
  );
  console.log(
    `[lovejs-toolchain] packaged candidate archive ${candidateArchive.sha256}/${candidateArchive.bytes} without executing cached content`,
  );
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : null;
if (invokedPath === fileURLToPath(import.meta.url)) {
  run().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
