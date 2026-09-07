#!/usr/bin/env node

import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildManifestName, readBuildManifest, sourceIdentity, validateLocalBuild,
} from "./web-build-identity.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
if (Object.hasOwn(process.env, "CALLACK_EXPECTED_BUILD_MANIFEST")) {
  throw new Error("Autobattler identity comes from the checked-out candidate, not an external manifest");
}
const claims = await sourceIdentity(root);
const webRoot = path.join(root, "dist/web");
const expected = await readBuildManifest(path.join(webRoot, buildManifestName), root, claims);
const packageRoot = path.resolve(process.argv[2] ?? webRoot);
await validateLocalBuild(packageRoot, expected.manifest, {
  allowExtraFiles: process.argv.includes("--allow-extra-files"),
});
console.log(`[autobattler-package] OK: ${packageRoot} carries ${claims.revision} target=web`);
