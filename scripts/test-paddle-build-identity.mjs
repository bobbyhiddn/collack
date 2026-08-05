#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertExactManifestBytes,
  readBuildManifest,
  validateBuildManifest,
  validateLocalBuild,
  validateResponseRecords,
} from "./web-build-identity.mjs";
import {
  rebuildPaddleExpectation,
  trustedPaddleBuild,
} from "./paddle-verification-policy.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const git = (...args) => execFileSync("git", args, {
  cwd: root,
  encoding: "utf8",
}).trim();
const revision = git("rev-parse", "HEAD");
const tree = git("rev-parse", "HEAD^{tree}");
const oldRevision = "e2dd6107d51a6cbcffbb5aa5de18e53f34e181a1";
const oldTree = "e97bb3dab9d85c0086c3c6a0fa5bdb4e26554d32";
let checks = 0;

function assert(condition, message) {
  checks += 1;
  if (!condition) throw new Error(message);
}

function expectFailure(name, callback, pattern) {
  let error;
  try {
    callback();
  } catch (caught) {
    error = caught;
  }
  assert(error, `${name}: control unexpectedly passed`);
  assert(pattern.test(error.message),
    `${name}: wrong failure: ${error.message}; expected ${pattern}`);
}

const trusted = trustedPaddleBuild(root, {});
assert(trusted.claims.revision === revision, "trusted revision is not checked-out HEAD");
assert(trusted.claims.tree === tree, "trusted tree is not checked-out HEAD tree");
assert(trusted.claims.target === "paddle-web", "trusted target is not paddle-web");
assert(trusted.runtimePath === "targets/paddle/src", "trusted runtime path drifted");
assert(trusted.manifestPath === path.join(root, "dist/paddle-web/callack-build-manifest.json"),
  "trusted manifest path is not fixed to the candidate paddle output");

let rebuilt;
rebuildPaddleExpectation(trusted, {}, (command, args, options) => {
  rebuilt = { command, args, options };
});
assert(rebuilt.command === "bash"
    && rebuilt.args.length === 1
    && rebuilt.args[0] === path.join(root, "scripts/build-paddle-web.sh")
    && rebuilt.options.cwd === root,
"trusted expectation does not invoke the fixed candidate paddle recipe");

expectFailure("caller-selected canonical manifest", () => {
  trustedPaddleBuild(root, {
    CALLACK_EXPECTED_BUILD_MANIFEST: "/tmp/e2dd610/callack-build-manifest.json",
  });
}, /CALLACK_EXPECTED_BUILD_MANIFEST is forbidden/);

for (const [name, environment, pattern] of [
  ["candidate label over old revision", { CALLACK_TARGET_SOURCE_COMMIT: oldRevision }, /caller revision/],
  ["changed tree label", { CALLACK_TARGET_SOURCE_TREE: oldTree }, /caller tree/],
  ["changed target label", { CALLACK_TARGET_NAME: "web" }, /caller target/],
]) {
  expectFailure(name, () => trustedPaddleBuild(root, environment), pattern);
}

const expected = await readBuildManifest(trusted.manifestPath, root, trusted.claims);
await validateLocalBuild(path.dirname(trusted.manifestPath), expected.manifest);
assert(expected.manifest.runtimePath === trusted.runtimePath,
  "manifest runtime path is not the candidate-owned paddle target");
assert(expected.manifest.recipe.path === trusted.recipePath,
  "manifest recipe is not the fixed paddle build entry point");
assert(expected.manifest.sources.every(
  (source) => source.path.startsWith("targets/paddle/"),
), "manifest source identity escaped the candidate-owned paddle target");
assertExactManifestBytes(expected.bytes, expected.bytes);

const baseUrl = "http://127.0.0.1:4173/";
const exactRecords = expected.manifest.assets.map((asset) => ({
  requestUrl: new URL(asset.path, baseUrl).href,
  url: new URL(asset.path, baseUrl).href,
  redirects: [],
  resourceType: asset.path === "index.html" ? "document" : "script",
  status: 200,
  bytes: asset.bytes,
  sha256: asset.sha256,
}));
validateResponseRecords(expected.manifest, exactRecords, baseUrl, { requireAll: true });

expectFailure("candidate labels over wrong bytes", () => {
  const wrong = structuredClone(exactRecords);
  wrong.find((record) => record.resourceType === "document").sha256 = "0".repeat(64);
  validateResponseRecords(expected.manifest, wrong, baseUrl, { requireAll: true });
}, /loaded asset mismatch for index\.html/);

expectFailure("older e2dd610 build with matching revision and tree", () => {
  const old = structuredClone(expected.manifest);
  old.revision = oldRevision;
  old.tree = oldTree;
  validateBuildManifest(old, root, trusted.claims);
}, /source set disagrees|source is absent|caller revision/);

for (const [name, mutate, pattern] of [
  ["changed runtime path", (manifest) => { manifest.runtimePath = "src"; }, /runtime path/],
  ["changed output path", (manifest) => { manifest.outputPath = "dist/web"; }, /output path/],
  ["changed recipe path", (manifest) => { manifest.recipe.path = "scripts/build-web.sh"; }, /recipe path/],
  ["changed recipe bytes", (manifest) => { manifest.recipe.sha256 = "1".repeat(64); }, /recipe mismatch/],
  ["changed source metadata", (manifest) => {
    manifest.sources[0].sha256 = "2".repeat(64);
    manifest.sourceSetSha256 = "3".repeat(64);
  }, /source-set digest mismatch/],
  ["missing source identity", (manifest) => { delete manifest.sources; }, /source set is missing/],
]) {
  expectFailure(name, () => {
    const changed = structuredClone(expected.manifest);
    mutate(changed);
    validateBuildManifest(changed, root, trusted.claims);
  }, pattern);
}

console.log(`[paddle-identity-control] OK: ${checks} assertions passed for ${revision}/${tree}`);
