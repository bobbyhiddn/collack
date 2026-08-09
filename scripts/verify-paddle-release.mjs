#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFile,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  rm,
  symlink,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  assertExactManifestBytes,
  readBuildManifest,
  validateLocalBuild,
} from "./web-build-identity.mjs";
import {
  paddleOutputPath,
  trustedPaddleBuild,
} from "./paddle-verification-policy.mjs";
import {
  paddleReleaseManifestName,
  validatePaddleReleaseArtifact,
} from "./paddle-release-contract.mjs";

const requiredReleasePaths = Object.freeze([
  "deploy/fly/Dockerfile.paddle",
  "deploy/fly/Dockerfile.paddle.dockerignore",
  "deploy/fly/nginx.paddle.conf",
  "deploy/fly/paddle.fly.toml",
  "scripts/build-paddle-release-image.sh",
  "scripts/paddle-release-contract.mjs",
  "scripts/release-paddle-fly.sh",
  "scripts/verify-paddle-release-image.sh",
  "scripts/verify-paddle-release.mjs",
]);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function git(root, ...args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function copyTrackedCandidate(root, destination) {
  const tracked = execFileSync("git", ["ls-files", "-z"], {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).split("\0").filter(Boolean);
  assert(tracked.length > 0, "checked-out candidate has no tracked files");
  for (const relative of tracked) {
    const source = path.join(root, relative);
    const target = path.join(destination, relative);
    const info = await lstat(source);
    await mkdir(path.dirname(target), { recursive: true });
    if (info.isFile()) {
      await copyFile(source, target);
    } else if (info.isSymbolicLink()) {
      await symlink(await readlink(source), target);
    } else {
      throw new Error(`tracked candidate path is not a file or symlink: ${relative}`);
    }
  }
}

function attachCandidateIdentity(sourceRoot, candidateRoot, revision, tree) {
  git(sourceRoot, "init", "-q");
  git(sourceRoot, "fetch", "-q", "--no-tags", candidateRoot, revision);
  git(sourceRoot, "update-ref", "HEAD", revision);
  git(sourceRoot, "read-tree", revision);
  git(sourceRoot, "config", "core.fileMode", "false");
  assert(git(sourceRoot, "rev-parse", "HEAD") === revision,
    "isolated paddle release rebuild revision drifted");
  assert(git(sourceRoot, "rev-parse", "HEAD^{tree}") === tree,
    "isolated paddle release rebuild tree drifted");
  assert(git(sourceRoot, "status", "--porcelain=v1", "--untracked-files=no") === "",
    "isolated paddle release source is not clean");
}

function sameRecords(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

async function rebuildExpectedRelease(root, trusted, environment, quiet) {
  const distRoot = path.join(root, "dist");
  await mkdir(distRoot, { recursive: true });
  const temporaryRoot = await mkdtemp(path.join(distRoot, ".paddle-release-expected."));
  const sourceRoot = path.join(temporaryRoot, "source");
  await mkdir(sourceRoot, { recursive: true });
  try {
    await copyTrackedCandidate(root, sourceRoot);
    attachCandidateIdentity(
      sourceRoot,
      root,
      trusted.claims.revision,
      trusted.claims.tree,
    );
    const rebuildEnvironment = {
      ...environment,
      CALLACK_NODE_CACHE_DIR: path.join(root, ".love_cache", "lovejs-11.4.1"),
    };
    execFileSync("bash", ["scripts/build-paddle-web.sh"], {
      cwd: sourceRoot,
      env: rebuildEnvironment,
      encoding: quiet ? "utf8" : undefined,
      stdio: quiet ? ["ignore", "pipe", "pipe"] : "inherit",
    });
    const artifact = await validatePaddleReleaseArtifact(
      path.join(sourceRoot, paddleOutputPath),
    );
    const archiveBytes = await readFile(path.join(sourceRoot, "dist", "collack-paddle.love"));
    return {
      artifact,
      archiveSha256: sha256(archiveBytes),
      archiveBytes: archiveBytes.length,
    };
  } catch (error) {
    if (quiet && error?.stderr) {
      error.message += `; isolated rebuild stderr: ${String(error.stderr).trim()}`;
    }
    throw error;
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
}

export async function verifyPaddleRelease(root, options = {}) {
  const candidateRoot = path.resolve(root);
  const environment = options.environment ?? process.env;
  const canonicalArtifactRoot = path.join(candidateRoot, paddleOutputPath);
  const artifactRoot = path.resolve(options.artifactRoot ?? canonicalArtifactRoot);
  const enforceCanonicalPath = options.enforceCanonicalPath ?? true;
  const quiet = options.quiet ?? false;

  for (const forbidden of [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
  ]) {
    assert(!Object.hasOwn(environment, forbidden),
      `${forbidden} is forbidden during paddle release identity derivation`);
  }

  const trackedStatus = git(
    candidateRoot,
    "status",
    "--porcelain=v1",
    "--untracked-files=no",
  );
  assert(trackedStatus === "",
    `paddle release requires a clean tracked checkout; found ${trackedStatus}`);
  if (enforceCanonicalPath) {
    assert(artifactRoot === canonicalArtifactRoot,
      `paddle release artifact substitution is forbidden: ${artifactRoot}; expected ${canonicalArtifactRoot}`);
  }
  for (const releasePath of requiredReleasePaths) {
    git(candidateRoot, "ls-files", "--error-unmatch", releasePath);
  }

  const trusted = trustedPaddleBuild(candidateRoot, environment);
  const expectedManifest = await readBuildManifest(
    path.join(artifactRoot, paddleReleaseManifestName),
    candidateRoot,
    trusted.claims,
  );
  await validateLocalBuild(artifactRoot, expectedManifest.manifest);
  const artifact = await validatePaddleReleaseArtifact(artifactRoot);
  assertExactManifestBytes(expectedManifest.bytes, artifact.manifestBytes);
  assert(artifact.manifest.revision === trusted.claims.revision
      && artifact.manifest.tree === trusted.claims.tree
      && artifact.manifest.target === trusted.claims.target,
  "paddle release manifest identity disagrees with the checked-out candidate");

  const rebuilt = await rebuildExpectedRelease(
    candidateRoot,
    trusted,
    environment,
    quiet,
  );
  assertExactManifestBytes(rebuilt.artifact.manifestBytes, artifact.manifestBytes);
  assert(sameRecords(rebuilt.artifact.releaseFiles, artifact.releaseFiles),
    `paddle release differs from independent exact-source rebuild: candidate=${artifact.releaseFileSetSha256} expected=${rebuilt.artifact.releaseFileSetSha256}`);

  const archiveBytes = await readFile(path.join(candidateRoot, "dist", "collack-paddle.love"));
  const archiveSha256 = sha256(archiveBytes);
  assert(archiveSha256 === rebuilt.archiveSha256 && archiveBytes.length === rebuilt.archiveBytes,
    `paddle archive differs from independent exact-source rebuild: candidate=${archiveSha256}/${archiveBytes.length} expected=${rebuilt.archiveSha256}/${rebuilt.archiveBytes}`);

  return {
    ...artifact,
    archiveSha256,
    archiveBytes: archiveBytes.length,
    independentReleaseFileSetSha256: rebuilt.artifact.releaseFileSetSha256,
  };
}

const invokedPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  assert(process.argv.length === 2,
    "verify-paddle-release takes no artifact or identity arguments; it verifies canonical dist/paddle-web");
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const release = await verifyPaddleRelease(root);
  console.log(
    `[paddle-release] OK: exact checked-out ${release.manifest.revision}/${release.manifest.tree} `
      + `target=${release.manifest.target} files=${release.releaseFiles.length} `
      + `manifest=${release.manifestSha256} fileSet=${release.releaseFileSetSha256} `
      + `archive=${release.archiveSha256}`,
  );
}
