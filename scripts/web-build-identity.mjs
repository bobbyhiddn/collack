import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, readdir, realpath, stat, writeFile } from "node:fs/promises";
import path from "node:path";

export const buildManifestName = "callack-build-manifest.json";
export const buildManifestSchema = "callack-web-build-v2";
export const buildTarget = "web";
export const buildProfiles = Object.freeze({
  web: Object.freeze({
    target: "web",
    outputPath: "dist/web",
    runtimePath: "src",
    shellPath: "web-shell/index.html",
    recipePath: "scripts/build-web.sh",
    sourcePaths: Object.freeze(["battle", "src", "web-shell"]),
  }),
  "paddle-web": Object.freeze({
    target: "paddle-web",
    outputPath: "dist/paddle-web",
    runtimePath: "targets/paddle/src",
    shellPath: "targets/paddle/web-shell/index.html",
    recipePath: "scripts/build-paddle-web.sh",
    sourcePaths: Object.freeze([
      "targets/paddle/src",
      "targets/paddle/web-shell",
    ]),
  }),
});

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function gitText(root, args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

async function localGitIdentity(sourceRoot) {
  try {
    const sourceReal = await realpath(sourceRoot);
    const top = await realpath(gitText(sourceRoot, ["rev-parse", "--show-toplevel"]));
    if (sourceReal !== top) return null;
    const revision = gitText(sourceRoot, ["rev-parse", "HEAD"]);
    return {
      revision,
      tree: gitText(sourceRoot, ["rev-parse", `${revision}^{tree}`]),
      trackedStatus: execFileSync("git", [
        "status",
        "--porcelain=v1",
        "--untracked-files=no",
      ], {
        cwd: sourceRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trimEnd(),
    };
  } catch {
    return null;
  }
}

function profileFor(name) {
  const profile = buildProfiles[name];
  assert(profile, `unknown web build target: ${name ?? "missing"}`);
  return profile;
}

export async function sourceIdentity(
  sourceRoot,
  environment = process.env,
  profileName = buildTarget,
) {
  const profile = profileFor(profileName);
  const local = await localGitIdentity(sourceRoot);
  const declaredRevision = environment.CALLACK_BUILD_REVISION ?? null;
  const declaredTree = environment.CALLACK_BUILD_TREE ?? null;

  if (local) {
    assert(local.trackedStatus === "",
      `build manifest requires a clean tracked source tree; found ${local.trackedStatus}`);
    assert(!declaredRevision || declaredRevision === local.revision,
      `CALLACK_BUILD_REVISION ${declaredRevision} disagrees with source HEAD ${local.revision}`);
    assert(!declaredTree || declaredTree === local.tree,
      `CALLACK_BUILD_TREE ${declaredTree} disagrees with source tree ${local.tree}`);
    return { revision: local.revision, tree: local.tree, target: profile.target };
  }

  assert(environment.CALLACK_ALLOW_EXTERNAL_BUILD_IDENTITY === "1",
    "build manifest source is not a Git worktree; external identity was not authorized");
  assert(/^[0-9a-f]{40}$/.test(declaredRevision ?? ""),
    "external build manifest requires a full CALLACK_BUILD_REVISION");
  assert(/^[0-9a-f]{40}$/.test(declaredTree ?? ""),
    "external build manifest requires a full CALLACK_BUILD_TREE");
  return { revision: declaredRevision, tree: declaredTree, target: profile.target };
}

async function filesBelow(root, relativeDirectory = "") {
  const directory = path.join(root, relativeDirectory);
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relative = path.posix.join(relativeDirectory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await filesBelow(root, relative));
    } else if (entry.isFile()) {
      if (relative !== buildManifestName) files.push(relative);
    } else {
      throw new Error(`web build contains a non-file entry: ${relative}`);
    }
  }
  return files.sort();
}

async function assetRecord(webRoot, relativePath) {
  const absolute = path.join(webRoot, relativePath);
  const info = await stat(absolute);
  assert(info.isFile(), `web build asset is not a file: ${relativePath}`);
  const bytes = await readFile(absolute);
  return { path: relativePath, bytes: bytes.length, sha256: sha256(bytes) };
}

async function buildInputRecords(sourceRoot, profile) {
  const inputPaths = [];
  for (const sourcePath of profile.sourcePaths) {
    const info = await stat(path.join(sourceRoot, sourcePath));
    if (info.isDirectory()) {
      inputPaths.push(...await filesBelow(sourceRoot, sourcePath));
    } else if (info.isFile()) {
      inputPaths.push(sourcePath);
    } else {
      throw new Error(`build input is not a regular file or directory: ${sourcePath}`);
    }
  }
  const records = [];
  for (const inputPath of [...new Set(inputPaths)].sort()) {
    records.push(await assetRecord(sourceRoot, inputPath));
  }
  return records;
}

export function assetSetSha256(assets) {
  return sha256(Buffer.from(JSON.stringify(assets), "utf8"));
}

export async function generateBuildManifest(
  webRoot,
  sourceRoot,
  profileName = buildTarget,
  environment = process.env,
) {
  const profile = profileFor(profileName);
  const identity = await sourceIdentity(sourceRoot, environment, profileName);
  const assets = [];
  for (const relativePath of await filesBelow(webRoot)) {
    assets.push(await assetRecord(webRoot, relativePath));
  }
  assert(assets.some((asset) => asset.path === "index.html"),
    "web build manifest requires index.html");
  const sources = await buildInputRecords(sourceRoot, profile);
  const recipe = await assetRecord(sourceRoot, profile.recipePath);
  const manifest = {
    schema: buildManifestSchema,
    revision: identity.revision,
    tree: identity.tree,
    target: identity.target,
    outputPath: profile.outputPath,
    runtimePath: profile.runtimePath,
    shellPath: profile.shellPath,
    recipe,
    sources,
    sourceSetSha256: assetSetSha256(sources),
    entrypoint: "index.html",
    assets,
    assetSetSha256: assetSetSha256(assets),
  };
  const bytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  await writeFile(path.join(webRoot, buildManifestName), bytes);
  return { manifest, bytes };
}

function validateAssetPath(value) {
  return typeof value === "string"
    && value !== ""
    && value === path.posix.normalize(value)
    && !value.startsWith("/")
    && !value.startsWith("../")
    && !value.includes("\\")
    && value !== buildManifestName;
}

function validateRepoPath(value) {
  return typeof value === "string"
    && value !== ""
    && value === path.posix.normalize(value)
    && !value.startsWith("/")
    && !value.startsWith("../")
    && !value.includes("\\");
}

function gitRecord(repoRoot, revision, relativePath) {
  let bytes;
  try {
    bytes = execFileSync("git", ["show", `${revision}:${relativePath}`], {
      cwd: repoRoot,
      encoding: null,
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    throw new Error(
      `build manifest source is absent from candidate revision ${revision}: ${relativePath}`,
    );
  }
  return { path: relativePath, bytes: bytes.length, sha256: sha256(bytes) };
}

export function validateBuildManifest(manifest, repoRoot, callerClaims = {}) {
  assert(manifest && typeof manifest === "object" && !Array.isArray(manifest),
    "build manifest must be a JSON object");
  assert(manifest.schema === buildManifestSchema,
    `build manifest schema is ${manifest.schema ?? "missing"}, expected ${buildManifestSchema}`);
  assert(/^[0-9a-f]{40}$/.test(manifest.revision ?? ""),
    "build manifest revision is missing or not a full commit SHA");
  assert(/^[0-9a-f]{40}$/.test(manifest.tree ?? ""),
    "build manifest tree is missing or not a full tree SHA");
  const profile = profileFor(manifest.target);
  assert(manifest.outputPath === profile.outputPath,
    `build manifest output path is ${manifest.outputPath ?? "missing"}, expected ${profile.outputPath}`);
  assert(manifest.runtimePath === profile.runtimePath,
    `build manifest runtime path is ${manifest.runtimePath ?? "missing"}, expected ${profile.runtimePath}`);
  assert(manifest.shellPath === profile.shellPath,
    `build manifest shell path is ${manifest.shellPath ?? "missing"}, expected ${profile.shellPath}`);
  assert(manifest.recipe?.path === profile.recipePath,
    `build manifest recipe path is ${manifest.recipe?.path ?? "missing"}, expected ${profile.recipePath}`);
  assert(manifest.entrypoint === "index.html",
    `build manifest entrypoint is ${manifest.entrypoint ?? "missing"}, expected index.html`);
  assert(Array.isArray(manifest.assets) && manifest.assets.length > 0,
    "build manifest asset set is missing or empty");

  const paths = [];
  for (const asset of manifest.assets) {
    assert(asset && typeof asset === "object" && !Array.isArray(asset),
      "build manifest contains a malformed asset record");
    assert(validateAssetPath(asset.path),
      `build manifest contains an unsafe asset path: ${asset.path}`);
    assert(Number.isSafeInteger(asset.bytes) && asset.bytes >= 0,
      `build manifest asset has invalid byte length: ${asset.path}`);
    assert(/^[0-9a-f]{64}$/.test(asset.sha256 ?? ""),
      `build manifest asset has invalid SHA-256: ${asset.path}`);
    paths.push(asset.path);
  }
  assert(new Set(paths).size === paths.length,
    "build manifest contains duplicate asset paths");
  assert(paths.join("\n") === [...paths].sort().join("\n"),
    "build manifest asset paths are not sorted");
  assert(paths.includes(manifest.entrypoint),
    "build manifest entrypoint is absent from its asset set");
  assert(manifest.assetSetSha256 === assetSetSha256(manifest.assets),
    "build manifest asset-set digest mismatch");
  assert(Array.isArray(manifest.sources) && manifest.sources.length > 0,
    "build manifest source set is missing or empty");
  const sourcePaths = [];
  for (const source of manifest.sources) {
    assert(source && typeof source === "object" && !Array.isArray(source),
      "build manifest contains a malformed source record");
    assert(validateRepoPath(source.path),
      `build manifest contains an unsafe source path: ${source.path}`);
    assert(Number.isSafeInteger(source.bytes) && source.bytes >= 0,
      `build manifest source has invalid byte length: ${source.path}`);
    assert(/^[0-9a-f]{64}$/.test(source.sha256 ?? ""),
      `build manifest source has invalid SHA-256: ${source.path}`);
    assert(profile.sourcePaths.some(
      (prefix) => source.path === prefix || source.path.startsWith(`${prefix}/`),
    ), `build manifest source is outside target inputs: ${source.path}`);
    sourcePaths.push(source.path);
  }
  assert(new Set(sourcePaths).size === sourcePaths.length,
    "build manifest contains duplicate source paths");
  assert(sourcePaths.join("\n") === [...sourcePaths].sort().join("\n"),
    "build manifest source paths are not sorted");
  assert(manifest.sourceSetSha256 === assetSetSha256(manifest.sources),
    "build manifest source-set digest mismatch");
  assert(validateRepoPath(manifest.recipe.path),
    `build manifest contains an unsafe recipe path: ${manifest.recipe.path}`);
  assert(Number.isSafeInteger(manifest.recipe.bytes) && manifest.recipe.bytes >= 0,
    "build manifest recipe has invalid byte length");
  assert(/^[0-9a-f]{64}$/.test(manifest.recipe.sha256 ?? ""),
    "build manifest recipe has invalid SHA-256");

  let actualTree;
  try {
    actualTree = gitText(repoRoot, ["rev-parse", `${manifest.revision}^{tree}`]);
  } catch {
    throw new Error(`build manifest revision is not present in candidate Git history: ${manifest.revision}`);
  }
  assert(actualTree === manifest.tree,
    `build manifest revision/tree disagreement: ${manifest.revision} has tree ${actualTree}, not ${manifest.tree}`);

  let committedSourcePaths;
  try {
    committedSourcePaths = gitText(repoRoot, [
      "ls-tree",
      "-r",
      "--name-only",
      manifest.revision,
      "--",
      ...profile.sourcePaths,
    ]).split("\n").filter(Boolean).sort();
  } catch {
    throw new Error(`cannot enumerate ${manifest.target} source inputs at ${manifest.revision}`);
  }
  assert(sourcePaths.join("\n") === committedSourcePaths.join("\n"),
    `build manifest source set disagrees with candidate revision: manifest=${sourcePaths} candidate=${committedSourcePaths}`);
  for (const source of manifest.sources) {
    const committed = gitRecord(repoRoot, manifest.revision, source.path);
    assert(source.bytes === committed.bytes && source.sha256 === committed.sha256,
      `build manifest source mismatch for ${source.path}: ${source.sha256}/${source.bytes}, candidate ${committed.sha256}/${committed.bytes}`);
  }
  const committedRecipe = gitRecord(repoRoot, manifest.revision, profile.recipePath);
  assert(manifest.recipe.bytes === committedRecipe.bytes
      && manifest.recipe.sha256 === committedRecipe.sha256,
  `build manifest recipe mismatch for ${profile.recipePath}: ${manifest.recipe.sha256}/${manifest.recipe.bytes}, candidate ${committedRecipe.sha256}/${committedRecipe.bytes}`);

  if (callerClaims.revision !== null && callerClaims.revision !== undefined) {
    assert(callerClaims.revision === manifest.revision,
      `caller revision ${callerClaims.revision} disagrees with manifest revision ${manifest.revision}`);
  }
  if (callerClaims.tree !== null && callerClaims.tree !== undefined) {
    assert(callerClaims.tree === manifest.tree,
      `caller tree ${callerClaims.tree} disagrees with manifest tree ${manifest.tree}`);
  }
  if (callerClaims.target !== null && callerClaims.target !== undefined) {
    assert(callerClaims.target === manifest.target,
      `caller target ${callerClaims.target} disagrees with manifest target ${manifest.target}`);
  }
  return manifest;
}

export async function readBuildManifest(manifestPath, repoRoot, callerClaims = {}) {
  let bytes;
  try {
    bytes = await readFile(manifestPath);
  } catch (error) {
    throw new Error(`expected build manifest is missing: ${manifestPath} (${error.message})`);
  }
  let manifest;
  try {
    manifest = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new Error(`expected build manifest is invalid JSON: ${error.message}`);
  }
  validateBuildManifest(manifest, repoRoot, callerClaims);
  return { manifest, bytes, sha256: sha256(bytes), path: manifestPath };
}

export async function validateLocalBuild(webRoot, manifest, options = {}) {
  const expectedPaths = new Set(manifest.assets.map((asset) => asset.path));
  const actualPaths = new Set(await filesBelow(webRoot));
  if (!options.allowExtraFiles) {
    assert([...actualPaths].join("\n") === [...expectedPaths].sort().join("\n"),
      `local build asset set disagrees with manifest: actual=${[...actualPaths]} expected=${[...expectedPaths].sort()}`);
  }
  for (const asset of manifest.assets) {
    const actual = await assetRecord(webRoot, asset.path);
    assert(actual.bytes === asset.bytes && actual.sha256 === asset.sha256,
      `local build asset mismatch for ${asset.path}: ${actual.sha256}/${actual.bytes}, expected ${asset.sha256}/${asset.bytes}`);
  }
}

export function assertExactManifestBytes(expected, served) {
  assert(Buffer.from(served).equals(Buffer.from(expected)),
    `served build manifest digest ${sha256(served)} disagrees with expected ${sha256(expected)}`);
}

export function assertNavigationIdentity({ requestedUrl, finalUrl, redirects = [] }) {
  const requested = new URL(requestedUrl).href;
  const final = new URL(finalUrl).href;
  assert(redirects.length === 0,
    `target navigation redirected unexpectedly: ${[requested, ...redirects, final].join(" -> ")}`);
  assert(final === requested,
    `target navigation reached unintended URL ${final}; requested ${requested}`);
}

function relativeAssetUrl(url, baseUrl, entrypoint, resourceType) {
  const parsed = new URL(url);
  const base = new URL("./", baseUrl);
  assert(parsed.origin === base.origin,
    `loaded asset escaped target origin: ${parsed.href}`);
  assert(parsed.search === "" && parsed.hash === "",
    `loaded asset URL has an unmanifested query or fragment: ${parsed.href}`);
  assert(parsed.pathname.startsWith(base.pathname),
    `loaded asset escaped target directory: ${parsed.href}`);
  const relative = decodeURIComponent(parsed.pathname.slice(base.pathname.length));
  return resourceType === "document" && relative === "" ? entrypoint : relative;
}

export function validateResponseRecords(manifest, records, baseUrl, options = {}) {
  const expected = new Map(manifest.assets.map((asset) => [asset.path, asset]));
  const observed = new Map();
  for (const record of records) {
    assert(record.redirects?.length === 0,
      `asset redirected unexpectedly: ${[record.requestUrl, ...(record.redirects ?? []), record.url].join(" -> ")}`);
    assert(record.requestUrl === record.url,
      `asset request reached unintended URL ${record.url}; requested ${record.requestUrl}`);
    assert(record.status >= 200 && record.status < 300,
      `asset returned HTTP ${record.status}: ${record.url}`);
    const relative = relativeAssetUrl(record.url, baseUrl, manifest.entrypoint, record.resourceType);
    if (relative === buildManifestName && options.allowManifest) continue;
    const asset = expected.get(relative);
    assert(asset, `loaded asset is absent from expected manifest: ${relative || record.url}`);
    assert(record.sha256 === asset.sha256 && record.bytes === asset.bytes,
      `loaded asset mismatch for ${relative}: ${record.sha256}/${record.bytes}, expected ${asset.sha256}/${asset.bytes}`);
    const prior = observed.get(relative);
    assert(!prior || (prior.sha256 === record.sha256 && prior.bytes === record.bytes),
      `mixed loaded bytes observed for ${relative}`);
    observed.set(relative, record);
  }
  if (options.requireAll) {
    assert(observed.size === expected.size,
      `served asset set is incomplete: observed ${[...observed.keys()].sort()}, expected ${[...expected.keys()].sort()}`);
  } else {
    assert(observed.has(manifest.entrypoint),
      "loaded response trace is missing the manifest entrypoint");
  }
  return [...observed.entries()].sort(([left], [right]) => left.localeCompare(right))
    .map(([assetPath, record]) => ({ assetPath, ...record }));
}
