#!/usr/bin/env node

import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const paddleReleaseTarget = "paddle-web";
export const paddleReleaseOutputPath = "dist/paddle-web";
export const paddleReleaseRuntimePath = "targets/paddle/src";
export const paddleReleaseShellPath = "targets/paddle/web-shell/index.html";
export const paddleReleaseRecipePath = "scripts/build-paddle-web.sh";
export const paddleReleaseManifestName = "callack-build-manifest.json";
export const paddleReleaseManifestSchema = "callack-web-build-v2";
export const paddleReleaseToolchainSchema = "callack-lovejs-toolchain-v1";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function safeRelativePath(value) {
  return typeof value === "string"
    && value !== ""
    && value === path.posix.normalize(value)
    && !value.startsWith("/")
    && !value.startsWith("../")
    && !value.includes("\\");
}

function validateRecord(record, label) {
  assert(record && typeof record === "object" && !Array.isArray(record),
    `${label} is missing or malformed`);
  assert(safeRelativePath(record.path), `${label} has an unsafe path: ${record.path}`);
  assert(Number.isSafeInteger(record.bytes) && record.bytes >= 0,
    `${label} has an invalid byte length: ${record.path}`);
  assert(/^[0-9a-f]{64}$/.test(record.sha256 ?? ""),
    `${label} has an invalid SHA-256: ${record.path}`);
}

function recordSetSha256(records) {
  return sha256(Buffer.from(JSON.stringify(records), "utf8"));
}

async function filesBelow(root, relativeDirectory = "") {
  const directory = path.join(root, relativeDirectory);
  const directoryInfo = await lstat(directory);
  assert(directoryInfo.isDirectory() && !directoryInfo.isSymbolicLink(),
    `paddle release contains a non-directory or symbolic directory: ${relativeDirectory || "."}`);
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relative = path.posix.join(relativeDirectory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await filesBelow(root, relative));
    } else if (entry.isFile()) {
      files.push(relative);
    } else {
      throw new Error(`paddle release contains a non-file entry: ${relative}`);
    }
  }
  return files.sort();
}

async function localRecord(root, relativePath) {
  const absolute = path.join(root, relativePath);
  const info = await lstat(absolute);
  assert(info.isFile() && !info.isSymbolicLink(),
    `paddle release asset is not a regular file: ${relativePath}`);
  const bytes = await readFile(absolute);
  return { path: relativePath, bytes: bytes.length, sha256: sha256(bytes) };
}

export function assertCanonicalPaddleArtifactPath(artifactRoot) {
  const resolved = path.resolve(artifactRoot);
  const expectedSuffix = `${path.sep}dist${path.sep}paddle-web`;
  assert(resolved.endsWith(expectedSuffix),
    `paddle release artifact path is ${resolved}, expected canonical ${paddleReleaseOutputPath}`);
  return resolved;
}

function validateManifestShape(manifest) {
  assert(manifest && typeof manifest === "object" && !Array.isArray(manifest),
    "paddle release manifest must be a JSON object");
  assert(manifest.schema === paddleReleaseManifestSchema,
    `paddle release manifest schema is ${manifest.schema ?? "missing"}`);
  assert(/^[0-9a-f]{40}$/.test(manifest.revision ?? ""),
    "paddle release manifest revision is missing or malformed");
  assert(/^[0-9a-f]{40}$/.test(manifest.tree ?? ""),
    "paddle release manifest tree is missing or malformed");
  assert(manifest.target === paddleReleaseTarget,
    `paddle release manifest target is ${manifest.target ?? "missing"}, expected ${paddleReleaseTarget}`);
  assert(manifest.outputPath === paddleReleaseOutputPath,
    `paddle release manifest output path is ${manifest.outputPath ?? "missing"}, expected ${paddleReleaseOutputPath}`);
  assert(manifest.runtimePath === paddleReleaseRuntimePath,
    `paddle release manifest runtime path is ${manifest.runtimePath ?? "missing"}, expected ${paddleReleaseRuntimePath}`);
  assert(manifest.shellPath === paddleReleaseShellPath,
    `paddle release manifest shell path is ${manifest.shellPath ?? "missing"}, expected ${paddleReleaseShellPath}`);
  assert(manifest.recipe?.path === paddleReleaseRecipePath,
    `paddle release manifest recipe is ${manifest.recipe?.path ?? "missing"}, expected ${paddleReleaseRecipePath}`);
  validateRecord(manifest.recipe, "paddle release recipe");
  assert(manifest.entrypoint === "index.html",
    `paddle release entrypoint is ${manifest.entrypoint ?? "missing"}`);

  assert(Array.isArray(manifest.assets) && manifest.assets.length > 0,
    "paddle release manifest asset set is missing or empty");
  const assetPaths = [];
  for (const asset of manifest.assets) {
    validateRecord(asset, "paddle release asset");
    assert(asset.path !== paddleReleaseManifestName,
      "paddle release manifest must not recursively list itself as an asset");
    assetPaths.push(asset.path);
  }
  assert(new Set(assetPaths).size === assetPaths.length,
    "paddle release manifest contains duplicate asset paths");
  assert(assetPaths.join("\n") === [...assetPaths].sort().join("\n"),
    "paddle release manifest asset paths are not sorted");
  assert(assetPaths.includes("index.html"),
    "paddle release manifest does not contain index.html");
  assert(manifest.assetSetSha256 === recordSetSha256(manifest.assets),
    "paddle release manifest asset-set digest mismatch");

  assert(Array.isArray(manifest.sources) && manifest.sources.length > 0,
    "paddle release manifest source set is missing or empty");
  const sourcePaths = [];
  for (const source of manifest.sources) {
    validateRecord(source, "paddle release source");
    assert(source.path.startsWith("targets/paddle/"),
      `paddle release source escaped targets/paddle: ${source.path}`);
    sourcePaths.push(source.path);
  }
  assert(new Set(sourcePaths).size === sourcePaths.length,
    "paddle release manifest contains duplicate source paths");
  assert(sourcePaths.join("\n") === [...sourcePaths].sort().join("\n"),
    "paddle release manifest source paths are not sorted");
  assert(manifest.sourceSetSha256 === recordSetSha256(manifest.sources),
    "paddle release manifest source-set digest mismatch");

  const toolchain = manifest.toolchain;
  assert(toolchain && typeof toolchain === "object" && !Array.isArray(toolchain),
    "paddle release manifest toolchain identity is missing");
  assert(toolchain.schema === paddleReleaseToolchainSchema,
    `paddle release toolchain schema is ${toolchain.schema ?? "missing"}`);
  validateRecord(toolchain.lock, "paddle release toolchain lock");
  validateRecord(toolchain.packager, "paddle release toolchain packager");
  validateRecord(toolchain.candidateArchive, "paddle release candidate archive");
  assert(toolchain.candidateArchive.path === "collack-paddle.love",
    `paddle release candidate archive is ${toolchain.candidateArchive.path}`);
  const gameData = manifest.assets.filter(
    (asset) => /^game\.[0-9a-f]{16}\.data$/.test(asset.path),
  );
  assert(gameData.length === 1,
    `paddle release must contain one packaged game archive, found ${gameData.length}`);
  assert(gameData[0].bytes === toolchain.candidateArchive.bytes
      && gameData[0].sha256 === toolchain.candidateArchive.sha256,
  "paddle release game data disagrees with authenticated candidate archive identity");
  return manifest;
}

export async function validatePaddleReleaseArtifact(artifactRoot) {
  const resolvedRoot = assertCanonicalPaddleArtifactPath(artifactRoot);
  const manifestPath = path.join(resolvedRoot, paddleReleaseManifestName);
  let manifestBytes;
  try {
    manifestBytes = await readFile(manifestPath);
  } catch (error) {
    throw new Error(`paddle release manifest is missing: ${manifestPath} (${error.message})`);
  }
  let manifest;
  try {
    manifest = JSON.parse(manifestBytes.toString("utf8"));
  } catch (error) {
    throw new Error(`paddle release manifest is invalid JSON: ${error.message}`);
  }
  validateManifestShape(manifest);

  const actualPaths = await filesBelow(resolvedRoot);
  const expectedPaths = [paddleReleaseManifestName, ...manifest.assets.map((asset) => asset.path)].sort();
  assert(actualPaths.join("\n") === expectedPaths.join("\n"),
    `paddle release file set disagrees with manifest: actual=${actualPaths} expected=${expectedPaths}`);

  const actualAssets = [];
  for (const expected of manifest.assets) {
    const actual = await localRecord(resolvedRoot, expected.path);
    assert(actual.bytes === expected.bytes && actual.sha256 === expected.sha256,
      `paddle release asset mismatch for ${expected.path}: ${actual.sha256}/${actual.bytes}, expected ${expected.sha256}/${expected.bytes}`);
    actualAssets.push(actual);
  }
  const manifestRecord = {
    path: paddleReleaseManifestName,
    bytes: manifestBytes.length,
    sha256: sha256(manifestBytes),
  };
  const releaseFiles = [manifestRecord, ...actualAssets].sort(
    (left, right) => left.path.localeCompare(right.path),
  );
  return {
    root: resolvedRoot,
    manifest,
    manifestBytes,
    manifestSha256: manifestRecord.sha256,
    releaseFiles,
    releaseFileSetSha256: recordSetSha256(releaseFiles),
  };
}

const invokedPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  const scriptRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const artifactRoot = path.resolve(process.argv[2] ?? path.join(scriptRoot, paddleReleaseOutputPath));
  const release = await validatePaddleReleaseArtifact(artifactRoot);
  console.log(
    `[paddle-release-contract] OK: target=${release.manifest.target} `
      + `revision=${release.manifest.revision} tree=${release.manifest.tree} `
      + `files=${release.releaseFiles.length} manifest=${release.manifestSha256} `
      + `fileSet=${release.releaseFileSetSha256}`,
  );
}
