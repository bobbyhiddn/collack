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

const spliceRecordKeys = [
  "label",
  "stage",
  "order",
  "recipeId",
  "battleSeed",
  "eventType",
  "eventId",
  "triggerCollisionEventId",
  "preventionCollisionEventId",
  "tick",
  "ruleId",
  "sourceRuleSetId",
  "abilityId",
  "sourceUid",
  "targetUid",
  "amount",
  "unit",
  "magnitude",
  "cadenceUnit",
  "cadenceInterval",
  "durationTicks",
  "expiresTick",
  "appliedCount",
  "expiredCount",
  "requestedDamage",
  "appliedDamage",
  "integrityBefore",
  "integrityAfter",
  "visualFrameTick",
  "visualGuardCount",
  "reason",
  "screenshot",
];

function validateSpliceGuardEvidence(evidence) {
  assert(Array.isArray(evidence.spliceGuardEvidence)
      && evidence.spliceGuardEvidence.length === 8,
    `generated evidence must contain eight Splice Guard records, got ${
      evidence.spliceGuardEvidence?.length
    }`);
  const semanticByViewport = {};
  for (const label of ["phone", "desktop"]) {
    const records = evidence.spliceGuardEvidence.filter((record) => record.label === label);
    assert(records.length === 4,
      `${label} evidence must contain four Splice Guard stages, got ${records.length}`);
    const stages = ["triggered", "applied", "prevented", "expired"];
    const types = ["splice_triggered", "guard_applied", "guard_prevented", "guard_expired"];
    records.forEach((record, index) => {
      exactKeys(record, spliceRecordKeys, `${label} Splice Guard record ${index + 1}`);
      exactKeys(record.screenshot, ["name", "sha256", "width", "height"],
        `${label} Splice Guard screenshot binding ${index + 1}`);
      assert(record.order === index + 1
          && record.stage === stages[index]
          && record.eventType === types[index],
        `${label} Splice Guard stages are missing or out of order`);
      assert(record.recipeId === "glass_cannon"
          && record.battleSeed === 9125
          && record.ruleId === "brick.splice.guard"
          && record.sourceRuleSetId === "brick.splice_node"
          && record.abilityId === "splice_guard"
          && record.magnitude === 1
          && record.cadenceUnit === "exchange"
          && record.cadenceInterval === 1
          && record.durationTicks === 120
          && record.appliedCount === 3
          && record.expiredCount === 2
          && record.visualGuardCount === 2,
        `${label} Splice Guard identity/rule semantics changed`);
      const expectedViewport = evidence.viewports[label];
      assert(record.screenshot.name === `${label}-splice-guard.png`
          && record.screenshot.sha256 === evidence.screenshotHashes[record.screenshot.name]
          && record.screenshot.width === expectedViewport.width
          && record.screenshot.height === expectedViewport.height,
        `${label} Splice Guard record lost its exact screenshot/viewport binding`);
      const screenshotRecord = evidence.screenshotRecords.find(
        (candidate) => candidate.name === record.screenshot.name
      );
      assert(screenshotRecord
          && screenshotRecord.label === label
          && screenshotRecord.surface === "splice-guard"
          && screenshotRecord.sha256 === record.screenshot.sha256,
        `${label} Splice Guard semantic screenshot record is missing or stale`);
    });
    assert(records[0].reason === "hostile_collision"
        && records[0].amount === 1
        && records[0].unit === "damage"
        && records[0].targetUid === "none",
      `${label} Splice did not originate from the packaged hostile collision`);
    assert(records[1].amount === 1
        && records[1].unit === "damage"
        && records[1].expiresTick === records[3].tick
        && records[1].targetUid !== "none"
        && records[1].reason === "adjacent_allied_guard",
      `${label} Splice did not apply bounded Guard to an adjacent ally`);
    assert(records[2].amount === 1
        && records[2].requestedDamage === 2
        && records[2].appliedDamage === 1
        && records[2].integrityBefore - records[2].integrityAfter === 1
        && records[2].targetUid !== "none"
        && records[2].reason === "hostile_damage",
      `${label} Splice Guard did not prevent exactly one hostile damage`);
    assert(records[3].amount === 1
        && records[3].unit === "damage"
        && records[3].reason === "duration"
        && records[3].expiresTick === records[3].tick
        && records[3].tick - records[0].tick === 120
        && records[3].targetUid !== records[2].targetUid,
      `${label} untouched Splice Guard did not expire after 120 canonical ticks`);
    assert(Number(records[0].triggerCollisionEventId) < Number(records[0].eventId)
        && Number(records[1].eventId) < Number(records[0].preventionCollisionEventId)
        && Number(records[0].preventionCollisionEventId) < Number(records[2].eventId)
        && records[0].visualFrameTick === records[2].tick
        && records.every((record, index) =>
          record.triggerCollisionEventId === records[0].triggerCollisionEventId
            && record.preventionCollisionEventId
              === records[0].preventionCollisionEventId
            && record.visualFrameTick === records[0].visualFrameTick
            && record.visualGuardCount === records[0].visualGuardCount
            && record.sourceUid === records[0].sourceUid
            && (index === 0 || Number(record.eventId) > Number(records[index - 1].eventId))
        ),
      `${label} Splice Guard events lost their physical roots or visible frame binding`);
    semanticByViewport[label] = records.map(({ label: _label, screenshot: _screenshot, ...record }) =>
      record
    );
  }
  assert(JSON.stringify(semanticByViewport.phone) === JSON.stringify(semanticByViewport.desktop),
    "phone and desktop Splice Guard evidence diverged for the same build and seed");
}

function assertResealedSemanticMutationRejected(evidence, label, mutate) {
  const changed = deepClone(evidence);
  mutate(changed);
  const resealed = sealEvidence(payloadWithoutDigest(changed));
  validatePayloadDigest(resealed);
  let rejected = false;
  try {
    validateSpliceGuardEvidence(resealed);
  } catch {
    rejected = true;
  }
  assert(rejected, `Splice Guard semantic validation accepted resealed ${label}`);
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
  assertPayloadMutationRejected(evidence, "missing linked-cost evidence", (changed) => {
    changed.linkedCostEvidence.pop();
  });
  assertPayloadMutationRejected(evidence, "crossed viewport evidence", (changed) => {
    changed.screenshotRecords[0].label =
      changed.screenshotRecords[0].label === "phone" ? "desktop" : "phone";
  });
  assertPayloadMutationRejected(evidence, "tampered screenshot binding", (changed) => {
    changed.screenshotRecords[0].sha256 = "0".repeat(64);
  });
  const spliceMutationControls = [
    ["stage removal", (changed) => changed.spliceGuardEvidence.splice(2, 1)],
    ["stage order", (changed) => {
      [changed.spliceGuardEvidence[1], changed.spliceGuardEvidence[2]] =
        [changed.spliceGuardEvidence[2], changed.spliceGuardEvidence[1]];
    }],
    ["event type", (changed) => { changed.spliceGuardEvidence[0].eventType = "guard_applied"; }],
    ["recipe", (changed) => { changed.spliceGuardEvidence[0].recipeId = "forged_recipe"; }],
    ["seed", (changed) => { changed.spliceGuardEvidence[0].battleSeed = 7; }],
    ["rule", (changed) => { changed.spliceGuardEvidence[0].ruleId = "forged.rule"; }],
    ["source", (changed) => { changed.spliceGuardEvidence[0].sourceUid = "forged-source"; }],
    ["magnitude", (changed) => { changed.spliceGuardEvidence[1].magnitude = 99; }],
    ["cadence", (changed) => { changed.spliceGuardEvidence[1].cadenceInterval = 2; }],
    ["duration", (changed) => { changed.spliceGuardEvidence[3].durationTicks = 121; }],
    ["visible frame tick", (changed) => {
      changed.spliceGuardEvidence[0].visualFrameTick += 1;
    }],
    ["visible Guard count", (changed) => {
      changed.spliceGuardEvidence[0].visualGuardCount = 1;
    }],
    ["prevention", (changed) => { changed.spliceGuardEvidence[2].appliedDamage = 2; }],
    ["expiry", (changed) => { changed.spliceGuardEvidence[3].reason = "forged"; }],
    ["target", (changed) => {
      changed.spliceGuardEvidence[3].targetUid = changed.spliceGuardEvidence[2].targetUid;
    }],
    ["viewport", (changed) => { changed.spliceGuardEvidence[0].label = "desktop"; }],
    ["screenshot removal", (changed) => { delete changed.spliceGuardEvidence[0].screenshot; }],
    ["screenshot hash", (changed) => {
      changed.spliceGuardEvidence[0].screenshot.sha256 = "0".repeat(64);
    }],
    ["screenshot dimensions", (changed) => {
      changed.spliceGuardEvidence[0].screenshot.width = 1280;
    }],
  ];
  for (const [label, mutate] of spliceMutationControls) {
    assertResealedSemanticMutationRejected(evidence, label, mutate);
  }

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
  "linkedCostEvidence",
  "spliceGuardEvidence",
  "settings",
  "screenshotHashes",
  "screenshotRecords",
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
assert(screenshotEntries.length === 40,
  `generated evidence must bind all 40 screenshots, got ${screenshotEntries.length}`);
for (const [name, expected] of screenshotEntries) {
  assert(/^(phone|desktop)-[a-z0-9-]+\.png$/.test(name),
    `generated evidence contains an unexpected screenshot path: ${name}`);
  const bytes = await evidenceFile(`dist/verification/${name}`);
  const actual = sha256(bytes);
  assert(actual === expected,
    `stale generated screenshot ${name}: ${actual}, expected ${expected}`);
}
assert(evidence.screenshotRecords?.length === 40,
  "generated evidence must carry one semantic record per screenshot");
for (const record of evidence.screenshotRecords) {
  const expectedViewport = evidence.viewports[record.label];
  assert(expectedViewport
      && record.name.startsWith(`${record.label}-`)
      && record.width === expectedViewport.width
      && record.height === expectedViewport.height
      && record.sha256 === evidence.screenshotHashes[record.name],
    `missing, crossed, stale, or tampered screenshot record: ${JSON.stringify(record)}`);
}
for (const label of ["phone", "desktop"]) {
  const linked = evidence.linkedCostEvidence?.filter((sample) => sample.label === label) ?? [];
  assert(linked.length === 1 && linked[0].text.includes("ordered=true")
      && linked[0].text.includes("cost=1")
      && linked[0].text.includes("payoff=2"),
    `${label} linked-cost evidence is missing or incorrect`);
}
validateSpliceGuardEvidence(evidence);

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
    + `${evidence.spliceGuardEvidence.length} ordered Splice Guard records; `
    + `${screenshotEntries.length} bound screenshots; `
    + `${evidence.executableEvidence.webFiles.length + 1} executable files; `
    + `aa5bf74 + direct tamper controls rejected`
    + `${compareTracked ? "; fresh bytes equal tracked evidence" : ""}`
);
