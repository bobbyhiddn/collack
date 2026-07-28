#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { evidenceSourceDigest } from "./evidence-source-digest.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const workingTree = process.argv.includes("--working-tree");
const manifestName = "dist/verification/packaged-runtime-evidence.json";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function trackedFile(name) {
  return execFileSync("git", ["show", `HEAD:${name}`], {
    cwd: root,
    encoding: "buffer",
  });
}

async function evidenceFile(name) {
  return workingTree ? readFile(path.join(root, name)) : trackedFile(name);
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function validateFreshness(evidence, expectedSourceDigest) {
  assert(evidence.schemaVersion === 2,
    `generated evidence schema must be 2, got ${evidence.schemaVersion}`);
  assert(/^[0-9a-f]{64}$/.test(evidence.sourceDigest ?? ""),
    "generated evidence is missing its exact source digest");
  assert(evidence.sourceDigest === expectedSourceDigest,
    `stale generated evidence: source ${evidence.sourceDigest}, expected ${expectedSourceDigest}`);
}

const expectedSourceDigest = await evidenceSourceDigest(root);
const evidence = JSON.parse((await evidenceFile(manifestName)).toString("utf8"));

let staleControlRejected = false;
try {
  validateFreshness(
    { ...evidence, sourceDigest: "0".repeat(64) },
    expectedSourceDigest
  );
} catch {
  staleControlRejected = true;
}
assert(staleControlRejected, "freshness guard failed its stale-evidence negative control");
validateFreshness(evidence, expectedSourceDigest);

assert(evidence.viewports?.phone?.width === 390
    && evidence.viewports.phone.height === 844
    && evidence.viewports.phone.touch === true,
  "tracked evidence is missing the canonical 390x844 touch viewport");
assert(evidence.viewports?.desktop?.width === 1280
    && evidence.viewports.desktop.height === 800
    && evidence.viewports.desktop.touch === false,
  "tracked evidence is missing the canonical desktop mouse viewport");
assert(evidence.ruleCallouts?.length === 62,
  `tracked evidence must match the 62-callout telemetry, got ${evidence.ruleCallouts?.length}`);
for (const label of ["phone", "desktop"]) {
  const callouts = evidence.ruleCallouts.filter((sample) => sample.label === label);
  assert(callouts.length === 31,
    `${label} evidence must contain 31 callouts, got ${callouts.length}`);
}

const screenshotEntries = Object.entries(evidence.screenshotHashes ?? {});
assert(screenshotEntries.length === 10,
  `tracked evidence must bind ten canonical screenshots, got ${screenshotEntries.length}`);
for (const [name, expected] of screenshotEntries) {
  const bytes = await evidenceFile(`dist/verification/${name}`);
  const actual = digest(bytes);
  assert(actual === expected,
    `stale generated screenshot ${name}: ${actual}, expected ${expected}`);
}

console.log(
  `[generated-evidence] OK: ${workingTree ? "working tree" : "tracked HEAD"} `
    + `${expectedSourceDigest}; 62 callouts; 10 bound screenshots; stale negative control rejected`
);
