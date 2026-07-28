#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { evidenceSourceDigest } from "./evidence-source-digest.mjs";
import {
  checksumName,
  evidenceSchemaVersion,
  executableEvidence,
  expectedEvidenceProvenance,
  manifestName,
  sealEvidence,
  sha256,
  validatePayloadDigest,
  validateRawChecksum,
} from "./evidence-integrity.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const workingTree = process.argv.includes("--working-tree");
const compareTracked = process.argv.includes("--compare-tracked");
const inheritedStaleCommit = "aa5bf74226049be1d38d6912c952429132af59cf";

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

function exactKeys(value, expected, label) {
  assert(value && typeof value === "object" && !Array.isArray(value),
    `${label} must be an object`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  assert(JSON.stringify(actual) === JSON.stringify(wanted),
    `${label} fields changed: ${actual.join(",")}; expected ${wanted.join(",")}`);
}

function validateFreshness(evidence, expectedSourceDigest, provenance) {
  assert(evidence.schemaVersion === evidenceSchemaVersion,
    `generated evidence schema must be ${evidenceSchemaVersion}, got ${evidence.schemaVersion}`);
  assert(/^[0-9a-f]{64}$/.test(evidence.sourceDigest ?? ""),
    "generated evidence is missing its exact source digest");
  assert(evidence.sourceDigest === expectedSourceDigest,
    `stale generated evidence: source ${evidence.sourceDigest}, expected ${expectedSourceDigest}`);
  assert(evidence.sourceCommit === provenance.sourceCommit,
    `stale generated evidence commit: ${evidence.sourceCommit}, expected ${provenance.sourceCommit}`);
  assert(evidence.sourceTree === provenance.sourceTree,
    `stale generated evidence tree: ${evidence.sourceTree}, expected ${provenance.sourceTree}`);
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function payloadWithoutDigest(evidence) {
  const { evidenceDigest: _discarded, ...payload } = evidence;
  return payload;
}

function assertPayloadMutationRejected(evidence, label, mutate) {
  const changed = deepClone(evidence);
  mutate(changed);
  let rejected = false;
  try {
    validatePayloadDigest(changed);
  } catch {
    rejected = true;
  }
  assert(rejected, `evidence integrity accepted ${label}`);
}

function runMutationControls(evidence, manifestBytes, checksumBytes, expectedDigest, provenance) {
  const text = manifestBytes.toString("utf8");
  assert(text.includes("magnitude=3"),
    "direct callout tamper control needs the canonical magnitude=3 sample");
  const tamperedBytes = Buffer.from(text.replace("magnitude=3", "magnitude=999"), "utf8");
  let rawRejected = false;
  try {
    validateRawChecksum(tamperedBytes, checksumBytes);
  } catch {
    rawRejected = true;
  }
  assert(rawRejected, "raw evidence checksum accepted the reported 3-to-999 callout tamper");

  assertPayloadMutationRejected(evidence, "the reported 3-to-999 callout tamper", (changed) => {
    const callout = changed.ruleCallouts.find((item) => item.text.includes("magnitude=3"));
    callout.text = callout.text.replace("magnitude=3", "magnitude=999");
  });
  assertPayloadMutationRejected(evidence, "a changed callout source", (changed) => {
    changed.ruleCallouts[0].text = changed.ruleCallouts[0].text.replace(
      /source=\S+/,
      "source=tampered"
    );
  });
  assertPayloadMutationRejected(evidence, "an added telemetry field", (changed) => {
    changed.ruleCallouts[0].hidden = 999;
  });
  assertPayloadMutationRejected(evidence, "a deleted telemetry field", (changed) => {
    delete changed.ruleCallouts[0].label;
  });
  assertPayloadMutationRejected(evidence, "changed telemetry order", (changed) => {
    [changed.ruleCallouts[0], changed.ruleCallouts[1]] =
      [changed.ruleCallouts[1], changed.ruleCallouts[0]];
  });
  assertPayloadMutationRejected(evidence, "a changed schema", (changed) => {
    changed.schemaVersion += 1;
  });
  assertPayloadMutationRejected(evidence, "a changed source digest", (changed) => {
    changed.sourceDigest = "0".repeat(64);
  });
  assertPayloadMutationRejected(evidence, "a changed source commit", (changed) => {
    changed.sourceCommit = inheritedStaleCommit;
  });
  assertPayloadMutationRejected(evidence, "a changed source tree", (changed) => {
    changed.sourceTree = "0".repeat(40);
  });
  assertPayloadMutationRejected(evidence, "changed executable bytes", (changed) => {
    changed.executableEvidence.archive.sha256 = "0".repeat(64);
  });

  // Preserve the inherited aa5bf74 stale-evidence control even if all of its
  // internal integrity fields are honestly recomputed.
  const inherited = sealEvidence({
    ...payloadWithoutDigest(evidence),
    sourceCommit: inheritedStaleCommit,
  });
  let inheritedRejected = false;
  try {
    validateFreshness(inherited, expectedDigest, provenance);
  } catch {
    inheritedRejected = true;
  }
  assert(inheritedRejected,
    "freshness guard accepted internally consistent inherited-aa5bf74 evidence");
}

assert(!compareTracked || workingTree,
  "--compare-tracked requires freshly generated --working-tree evidence");

const expectedSourceDigest = await evidenceSourceDigest(root);
const provenance = expectedEvidenceProvenance(root);
const manifestBytes = await evidenceFile(manifestName);
const checksumBytes = await evidenceFile(checksumName);
const evidence = JSON.parse(manifestBytes.toString("utf8"));

exactKeys(evidence, [
  "schemaVersion",
  "sourceDigest",
  "sourceCommit",
  "sourceTree",
  "viewports",
  "executableEvidence",
  "canonicalSweeps",
  "canonicalBlowbacks",
  "motionEvidence",
  "guidance",
  "inspections",
  "ruleCallouts",
  "settings",
  "screenshotHashes",
  "evidenceDigest",
], "generated evidence");
validateRawChecksum(manifestBytes, checksumBytes);
validatePayloadDigest(evidence);
validateFreshness(evidence, expectedSourceDigest, provenance);

const currentExecutables = await executableEvidence(root);
assert(JSON.stringify(evidence.executableEvidence) === JSON.stringify(currentExecutables),
  "generated evidence executable bytes do not match the exact packaged archive/web build");
assert(evidence.executableEvidence.webFiles.length > 0,
  "generated evidence did not bind the packaged web files");

assert(evidence.viewports?.phone?.width === 390
    && evidence.viewports.phone.height === 844
    && evidence.viewports.phone.touch === true,
  "generated evidence is missing the canonical 390x844 touch viewport");
assert(evidence.viewports?.desktop?.width === 1280
    && evidence.viewports.desktop.height === 800
    && evidence.viewports.desktop.touch === false,
  "generated evidence is missing the canonical desktop mouse viewport");
assert(evidence.ruleCallouts?.length === 62,
  `generated evidence must match the 62-callout telemetry, got ${evidence.ruleCallouts?.length}`);
for (const label of ["phone", "desktop"]) {
  const callouts = evidence.ruleCallouts.filter((sample) => sample.label === label);
  assert(callouts.length === 31,
    `${label} evidence must contain 31 callouts, got ${callouts.length}`);
}

const screenshotEntries = Object.entries(evidence.screenshotHashes ?? {});
assert(screenshotEntries.length === 38,
  `generated evidence must bind all 38 screenshots, got ${screenshotEntries.length}`);
for (const [name, expected] of screenshotEntries) {
  assert(/^(phone|desktop)-[a-z0-9-]+\.png$/.test(name),
    `generated evidence contains an unexpected screenshot path: ${name}`);
  const bytes = await evidenceFile(`dist/verification/${name}`);
  const actual = sha256(bytes);
  assert(actual === expected,
    `stale generated screenshot ${name}: ${actual}, expected ${expected}`);
}

runMutationControls(
  evidence,
  manifestBytes,
  checksumBytes,
  expectedSourceDigest,
  provenance
);

if (compareTracked) {
  const trackedManifest = trackedFile(manifestName);
  const trackedChecksum = trackedFile(checksumName);
  assert(manifestBytes.equals(trackedManifest),
    "fresh canonical telemetry differs byte-for-byte from tracked evidence");
  assert(checksumBytes.equals(trackedChecksum),
    "fresh canonical evidence checksum differs byte-for-byte from tracked evidence");
  for (const [name] of screenshotEntries) {
    const fresh = await readFile(path.join(root, "dist", "verification", name));
    assert(fresh.equals(trackedFile(`dist/verification/${name}`)),
      `fresh canonical screenshot differs byte-for-byte from tracked evidence: ${name}`);
  }
}

console.log(
  `[generated-evidence] OK: ${workingTree ? "working tree" : "tracked HEAD"} `
    + `${expectedSourceDigest}; payload ${evidence.evidenceDigest}; `
    + `${evidence.ruleCallouts.length} ordered callouts; `
    + `${screenshotEntries.length} bound screenshots; `
    + `${evidence.executableEvidence.webFiles.length + 1} executable files; `
    + `aa5bf74 + direct tamper controls rejected`
    + `${compareTracked ? "; fresh bytes equal tracked evidence" : ""}`
);
