#!/usr/bin/env node

import path from "node:path";
import { fileURLToPath } from "node:url";

import { readBuildManifest, validateLocalBuild } from "./web-build-identity.mjs";
import { trustedPaddleBuild } from "./paddle-verification-policy.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const trusted = trustedPaddleBuild(root);
const packageRoot = path.resolve(process.argv[2] ?? path.dirname(trusted.manifestPath));
const allowExtraFiles = process.argv.includes("--allow-extra-files");
const expected = await readBuildManifest(trusted.manifestPath, root, trusted.claims);

await validateLocalBuild(packageRoot, expected.manifest, { allowExtraFiles });
console.log(
  `[paddle-package] OK: ${packageRoot} exactly carries `
    + `${expected.manifest.revision}/${expected.manifest.tree} `
    + `target=${expected.manifest.target} assets=${expected.manifest.assets.length}`,
);
