#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  appendFile,
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  unlink,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { verifyPaddleRelease } from "./verify-paddle-release.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const paddleRoot = path.join(root, "dist", "paddle-web");
const webRoot = path.join(root, "dist", "web");
const baseRevision = "0187c7da16df8518955ec1c68a3add1695981843";
const baseTree = "7afc7892da41f0ef6987b7a1b9c4b8a22eddd674";
let checks = 0;

function assert(condition, message) {
  checks += 1;
  if (!condition) throw new Error(message);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function expectFailure(name, operation, pattern) {
  let error;
  try {
    await operation();
  } catch (caught) {
    error = caught;
  }
  assert(error, `${name}: negative control unexpectedly passed`);
  assert(pattern.test(error.message),
    `${name}: wrong failure '${error.message}', expected ${pattern}`);
  console.log(`[paddle-release-control] OK rejected ${name}: ${error.message}`);
}

async function readManifest(artifactRoot) {
  return JSON.parse(await readFile(
    path.join(artifactRoot, "callack-build-manifest.json"),
    "utf8",
  ));
}

async function writeManifest(artifactRoot, manifest) {
  await writeFile(
    path.join(artifactRoot, "callack-build-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

async function fixtureControl(name, mutate, pattern) {
  const temporaryRoot = await mkdtemp(path.join(root, "dist", ".paddle-release-control."));
  const artifactRoot = path.join(temporaryRoot, "dist", "paddle-web");
  await mkdir(path.dirname(artifactRoot), { recursive: true });
  try {
    await cp(paddleRoot, artifactRoot, { recursive: true, errorOnExist: true });
    await mutate(artifactRoot);
    await expectFailure(name, () => verifyPaddleRelease(root, {
      artifactRoot,
      enforceCanonicalPath: false,
      quiet: true,
    }), pattern);
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
}

const legacyHashes = Object.freeze({
  ".dockerignore": "85b8d5ea6dd29b094ab95420931e7facf996aa9aef08dae7c1df59bff9aac9ed",
  "deploy/fly/Dockerfile": "3287f38978cb78972285b58e3049aff814516918aaabcb703eb0ef91136679fc",
  "deploy/fly/fly.toml": "5c20329a1f543f6344653076232487389d6a5c110f8bcca3f292859f0a54a31c",
  "deploy/fly/nginx.conf": "5d9833dfe29c19c445b9e448da15cb33faa7b95ea6bbc0b5e53eefa958c2513b",
  "scripts/verify-release-container.sh": "110cf7f6c55c00e7c08d52eac48ddd8333b8fefe227b91474e8687f24d5af01b",
});
for (const [relative, expected] of Object.entries(legacyHashes)) {
  assert(sha256(await readFile(path.join(root, relative))) === expected,
    `existing auto-battler release path changed: ${relative}`);
}

const dockerfile = await readFile(path.join(root, "deploy/fly/Dockerfile.paddle"), "utf8");
const dockerignore = await readFile(
  path.join(root, "deploy/fly/Dockerfile.paddle.dockerignore"),
  "utf8",
);
const flyConfig = await readFile(path.join(root, "deploy/fly/paddle.fly.toml"), "utf8");
const imageBuilder = await readFile(
  path.join(root, "scripts/build-paddle-release-image.sh"),
  "utf8",
);
assert(dockerfile.includes("COPY dist/paddle-web/ dist/paddle-web/"),
  "dedicated Dockerfile does not consume canonical dist/paddle-web");
assert(!dockerfile.includes("dist/web"),
  "dedicated Dockerfile can consume dist/web");
assert(dockerfile.includes("RUN node scripts/paddle-release-contract.mjs"),
  "dedicated Dockerfile does not fail closed through its in-image contract gate");
assert(dockerfile.includes("io.callack.release.target=\"paddle-web\""),
  "dedicated image target label is missing");
assert(dockerignore.includes("!dist/paddle-web/**"),
  "dedicated build context does not admit canonical paddle assets");
assert(!dockerignore.includes("!dist/web"),
  "dedicated build context admits dist/web substitution");
assert(flyConfig.includes('app = "collack-spike"')
    && flyConfig.includes('CALLACK_RELEASE_TARGET = "paddle-web"'),
"dedicated Fly config does not identify the service and target together");
assert(imageBuilder.indexOf("verify-paddle-release.mjs")
    < imageBuilder.indexOf("container build"),
"image build can run before the exact-source release gate");

const exact = await verifyPaddleRelease(root, { quiet: true });
assert(exact.manifest.target === "paddle-web", "positive release target is not paddle-web");
assert(exact.manifest.outputPath === "dist/paddle-web",
  "positive release output path is not canonical");
assert(exact.releaseFileSetSha256 === exact.independentReleaseFileSetSha256,
  "positive release does not equal the independent exact-source rebuild");

const currentPaddleManifest = await readManifest(paddleRoot);
const currentWebManifest = await readManifest(webRoot);
assert(currentPaddleManifest.assetSetSha256
    === "bf1c77c2efb56c1a73635d0d6894855d4d49da9a6dd0ecf1261eec4e528b15dc",
"paddle generated runtime bytes changed from the merged candidate");
assert(currentWebManifest.assetSetSha256
    === "7262b3e75a481d092e8ba28bc05fbd028de5f8e164d594467240d63f229ab2bc",
"auto-battler generated runtime bytes changed from the merged candidate");

await expectFailure("dist/web artifact-path substitution", () => verifyPaddleRelease(root, {
  artifactRoot: webRoot,
  quiet: true,
}), /artifact substitution is forbidden/);

await fixtureControl("dist/web bytes relabeled at paddle path", async (artifactRoot) => {
  await rm(artifactRoot, { recursive: true, force: true });
  await cp(webRoot, artifactRoot, { recursive: true });
}, /caller target|source set disagrees|runtime path|candidate archive path/);

await fixtureControl("missing release manifest", async (artifactRoot) => {
  await unlink(path.join(artifactRoot, "callack-build-manifest.json"));
}, /manifest is missing|expected build manifest is missing/);

await fixtureControl("stale paddle revision and tree", async (artifactRoot) => {
  const manifest = await readManifest(artifactRoot);
  manifest.revision = baseRevision;
  manifest.tree = baseTree;
  await writeManifest(artifactRoot, manifest);
}, /caller revision|source set disagrees|recipe mismatch/);

await fixtureControl("mismatched manifest tree", async (artifactRoot) => {
  const manifest = await readManifest(artifactRoot);
  manifest.tree = "0".repeat(40);
  await writeManifest(artifactRoot, manifest);
}, /revision\/tree disagreement/);

await fixtureControl("mismatched manifest target", async (artifactRoot) => {
  const manifest = await readManifest(artifactRoot);
  manifest.target = "web";
  manifest.outputPath = "dist/web";
  manifest.runtimePath = "src";
  manifest.shellPath = "web-shell/index.html";
  manifest.recipe.path = "scripts/build-web.sh";
  await writeManifest(artifactRoot, manifest);
}, /source is outside target inputs|source set disagrees|recipe mismatch|caller target/);

await fixtureControl("mixed auto-battler asset", async (artifactRoot) => {
  const webManifest = await readManifest(webRoot);
  const webAsset = webManifest.assets.find((asset) => asset.path.endsWith(".data"));
  await cp(
    path.join(webRoot, webAsset.path),
    path.join(artifactRoot, "auto-battler-substitution.data"),
  );
}, /asset set disagrees|file set disagrees/);

await fixtureControl("mutated paddle asset", async (artifactRoot) => {
  await appendFile(path.join(artifactRoot, "index.html"), "\n<!-- stale -->\n");
}, /asset mismatch for index\.html/);

await fixtureControl("missing paddle asset", async (artifactRoot) => {
  const manifest = await readManifest(artifactRoot);
  const hashed = manifest.assets.find((asset) => /\.[0-9a-f]{16}\.wasm$/.test(asset.path));
  await unlink(path.join(artifactRoot, hashed.path));
}, /asset set disagrees|file set disagrees/);

await fixtureControl("symbolic paddle asset", async (artifactRoot) => {
  const themePath = path.join(artifactRoot, "theme", "bg.png");
  await unlink(themePath);
  await symlink("../index.html", themePath);
}, /non-file entry|not a regular file/);

await fixtureControl("self-consistent caller-rewritten manifest", async (artifactRoot) => {
  const indexPath = path.join(artifactRoot, "index.html");
  await appendFile(indexPath, "\n<!-- caller rewrite -->\n");
  const indexBytes = await readFile(indexPath);
  const manifest = await readManifest(artifactRoot);
  const indexRecord = manifest.assets.find((asset) => asset.path === "index.html");
  indexRecord.bytes = indexBytes.length;
  indexRecord.sha256 = sha256(indexBytes);
  manifest.assetSetSha256 = sha256(Buffer.from(JSON.stringify(manifest.assets), "utf8"));
  await writeManifest(artifactRoot, manifest);
}, /served build manifest digest|independent exact-source rebuild/);

await expectFailure("caller-selected target label", () => verifyPaddleRelease(root, {
  environment: { ...process.env, CALLACK_TARGET_NAME: "web" },
  quiet: true,
}), /caller target/);

await expectFailure("caller-selected manifest identity", () => verifyPaddleRelease(root, {
  environment: {
    ...process.env,
    CALLACK_EXPECTED_BUILD_MANIFEST: path.join(webRoot, "callack-build-manifest.json"),
  },
  quiet: true,
}), /CALLACK_EXPECTED_BUILD_MANIFEST is forbidden/);

console.log(
  `[paddle-release-control] OK: ${checks} assertions; exact files=${exact.releaseFiles.length} `
    + `manifest=${exact.manifestSha256} fileSet=${exact.releaseFileSetSha256}`,
);
