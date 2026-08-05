import { execFileSync } from "node:child_process";
import path from "node:path";

import { buildManifestName } from "./web-build-identity.mjs";

export const paddleBuildTarget = "paddle-web";
export const paddleRuntimePath = "targets/paddle/src";
export const paddleOutputPath = "dist/paddle-web";
export const paddleBuildRecipe = "scripts/build-paddle-web.sh";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function git(root, ...args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

export function trustedPaddleBuild(root, environment = process.env) {
  for (const forbidden of [
    "CALLACK_EXPECTED_BUILD_MANIFEST",
    "CALLACK_BUILD_REVISION",
    "CALLACK_BUILD_TREE",
    "CALLACK_ALLOW_EXTERNAL_BUILD_IDENTITY",
  ]) {
    assert(!Object.hasOwn(environment, forbidden),
      `${forbidden} is forbidden: trusted paddle identity comes only from the checked-out candidate`);
  }

  const claims = Object.freeze({
    revision: git(root, "rev-parse", "HEAD"),
    tree: git(root, "rev-parse", "HEAD^{tree}"),
    target: paddleBuildTarget,
  });
  const callerClaims = {
    revision: environment.CALLACK_TARGET_SOURCE_COMMIT ?? null,
    tree: environment.CALLACK_TARGET_SOURCE_TREE ?? null,
    target: environment.CALLACK_TARGET_NAME ?? null,
  };
  for (const [field, value] of Object.entries(callerClaims)) {
    if (value !== null) {
      assert(value === claims[field],
        `caller ${field} ${value} disagrees with checked-out candidate ${claims[field]}`);
    }
  }

  return Object.freeze({
    root,
    claims,
    callerClaims: Object.freeze(callerClaims),
    manifestPath: path.join(root, paddleOutputPath, buildManifestName),
    buildScript: path.join(root, paddleBuildRecipe),
    runtimePath: paddleRuntimePath,
    outputPath: paddleOutputPath,
    recipePath: paddleBuildRecipe,
  });
}

export function rebuildPaddleExpectation(
  trusted,
  environment = process.env,
  execute = execFileSync,
) {
  const current = trustedPaddleBuild(trusted.root, environment);
  assert(current.manifestPath === trusted.manifestPath
      && current.claims.revision === trusted.claims.revision
      && current.claims.tree === trusted.claims.tree,
  "checked-out candidate identity changed before rebuilding the trusted paddle manifest");
  execute("bash", [trusted.buildScript], {
    cwd: trusted.root,
    env: environment,
    stdio: "inherit",
  });
  return trusted;
}
