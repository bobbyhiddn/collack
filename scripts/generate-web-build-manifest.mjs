#!/usr/bin/env node

import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildManifestName,
  generateBuildManifest,
  validateLocalBuild,
} from "./web-build-identity.mjs";

const scriptRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const webRoot = path.resolve(process.argv[2] ?? path.join(scriptRoot, "dist", "web"));
const sourceRoot = path.resolve(process.argv[3] ?? scriptRoot);
const profileName = process.argv[4] ?? "web";
const { manifest } = await generateBuildManifest(webRoot, sourceRoot, profileName);
await validateLocalBuild(webRoot, manifest);
console.log(
  `[web-manifest] OK: ${buildManifestName} binds ${manifest.assets.length} assets `
    + `to ${manifest.revision}/${manifest.tree} target=${manifest.target}`,
);
