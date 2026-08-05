#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertExactManifestBytes,
  assertNavigationIdentity,
  buildManifestName,
  readBuildManifest,
  validateBuildManifest,
  validateLocalBuild,
  validateResponseRecords,
} from "./web-build-identity.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const webRoot = path.resolve(process.argv[2] ?? path.join(root, "dist", "web"));
const manifestPath = path.join(webRoot, buildManifestName);
const git = (...args) => execFileSync("git", args, {
  cwd: root,
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
}).trim();

let checks = 0;
function assert(condition, message) {
  checks += 1;
  if (!condition) throw new Error(message);
}

async function expectFailure(name, operation, pattern) {
  let error;
  try {
    await operation();
  } catch (caught) {
    error = caught;
  }
  assert(error, `${name}: control unexpectedly passed`);
  assert(pattern.test(error.message),
    `${name}: wrong failure: ${error.message}; expected ${pattern}`);
  console.log(`[web-identity-control] OK rejected ${name}: ${error.message}`);
}

const expected = await readBuildManifest(manifestPath, root);
await validateLocalBuild(webRoot, expected.manifest);
assert(expected.manifest.revision === git("rev-parse", "HEAD"),
  "positive exact-head build manifest revision is stale");
assert(expected.manifest.tree === git("rev-parse", "HEAD^{tree}"),
  "positive exact-head build manifest tree is stale");
assert(expected.manifest.target === "web",
  "positive exact-head build manifest target is wrong");
console.log(
  `[web-identity-control] OK positive exact-head local build: `
    + `${expected.manifest.revision}/${expected.manifest.tree}`,
);

const baseUrl = "http://127.0.0.1:4173/";
const exactRecords = expected.manifest.assets.map((asset) => ({
  requestUrl: new URL(asset.path === "index.html" ? "" : asset.path, baseUrl).href,
  url: new URL(asset.path === "index.html" ? "" : asset.path, baseUrl).href,
  redirects: [],
  resourceType: asset.path === "index.html" ? "document" : "verified-asset",
  method: "GET",
  status: 200,
  bytes: asset.bytes,
  sha256: asset.sha256,
}));
validateResponseRecords(expected.manifest, exactRecords, baseUrl, { requireAll: true });
assertExactManifestBytes(expected.bytes, expected.bytes);
assertNavigationIdentity({ requestedUrl: baseUrl, finalUrl: baseUrl, redirects: [] });

await expectFailure("correct label with wrong served bytes", () => {
  const wrong = structuredClone(exactRecords);
  wrong.find((record) => record.resourceType === "document").sha256 = "0".repeat(64);
  validateBuildManifest(expected.manifest, root, {
    revision: expected.manifest.revision,
    tree: expected.manifest.tree,
    target: expected.manifest.target,
  });
  validateResponseRecords(expected.manifest, wrong, baseUrl, { requireAll: true });
}, /loaded asset mismatch for index\.html/);

await expectFailure("stale served manifest", () => {
  const stale = structuredClone(expected.manifest);
  stale.assets[0].sha256 = "1".repeat(64);
  assertExactManifestBytes(
    expected.bytes,
    Buffer.from(`${JSON.stringify(stale, null, 2)}\n`, "utf8"),
  );
}, /served build manifest digest/);

await expectFailure("mixed asset set", () => {
  const mixed = structuredClone(exactRecords);
  const asset = mixed.find((record) => record.resourceType !== "document");
  asset.sha256 = "2".repeat(64);
  validateResponseRecords(expected.manifest, mixed, baseUrl, { requireAll: true });
}, /loaded asset mismatch/);

for (const [field, value, pattern] of [
  ["revision", "0".repeat(40), /revision is not present|revision\/tree disagreement/],
  ["tree", "0".repeat(40), /revision\/tree disagreement/],
  ["target", "desktop", /target is desktop, expected web/],
]) {
  await expectFailure(`altered served ${field}`, () => {
    const altered = structuredClone(expected.manifest);
    altered[field] = value;
    validateBuildManifest(altered, root);
  }, pattern);
}

for (const [field, value, pattern] of [
  ["revision", "0".repeat(40), /caller revision/],
  ["tree", "0".repeat(40), /caller tree/],
  ["target", "desktop", /caller target/],
]) {
  await expectFailure(`altered caller ${field}`, () => {
    validateBuildManifest(expected.manifest, root, { [field]: value });
  }, pattern);
}

await expectFailure("missing identity data", () => {
  const missing = structuredClone(expected.manifest);
  delete missing.revision;
  validateBuildManifest(missing, root);
}, /revision is missing/);

await expectFailure("redirect to unintended target", () => {
  assertNavigationIdentity({
    requestedUrl: baseUrl,
    finalUrl: "http://127.0.0.1:4174/",
    redirects: [baseUrl],
  });
}, /redirected unexpectedly/);

console.log(`[web-identity-control] OK: ${checks} assertions passed`);
