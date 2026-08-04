#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  evidenceSchemaVersion,
  expectedEvidenceProvenance,
  validateEvidenceFreshness,
} from "./evidence-integrity.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const sandbox = await mkdtemp(path.join(root, ".evidence-provenance-test-"));
let controls = 0;

function git(args) {
  return execFileSync("git", args, {
    cwd: sandbox,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

async function trackedFile(name, contents) {
  const absolute = path.join(sandbox, name);
  await mkdir(path.dirname(absolute), { recursive: true });
  await writeFile(absolute, contents);
  git(["add", "--", name]);
}

function commit(message) {
  git(["commit", "-q", "-m", message]);
  return git(["rev-parse", "HEAD"]);
}

function commitTree(tree, parents, message) {
  const args = ["commit-tree", tree];
  for (const parent of parents) args.push("-p", parent);
  args.push("-m", message);
  return git(args);
}

function control(label, check) {
  check();
  controls += 1;
  return label;
}

function rejects(label, check, diagnostic) {
  let error = null;
  try {
    check();
  } catch (caught) {
    error = caught;
  }
  assert(error, `${label} was accepted`);
  assert.match(error.message, diagnostic, `${label} used an imprecise diagnostic`);
  controls += 1;
}

try {
  git(["init", "-q", "--initial-branch", "common"]);
  git(["config", "user.name", "Evidence Provenance Test"]);
  git(["config", "user.email", "evidence-provenance@example.invalid"]);

  await trackedFile("common.txt", "common\n");
  const common = commit("common ancestor");

  git(["switch", "-q", "-c", "base"]);
  await trackedFile("base.txt", "base\n");
  const base = commit("base parent");

  git(["switch", "-q", "--detach", common]);
  await trackedFile("game.txt", "reviewed source bytes\n");
  await trackedFile("dist/collack-spike.love", "packaged bytes\n");
  const source = commit("source and build");
  const sourceTree = git(["rev-parse", `${source}^{tree}`]);

  await trackedFile("dist/verification/evidence.json", "sealed evidence\n");
  const reviewed = commit("canonical evidence");
  const reviewedTree = git(["rev-parse", `${reviewed}^{tree}`]);
  const merge = commitTree(reviewedTree, [base, reviewed], "reviewed merge");

  const prProvenance = expectedEvidenceProvenance(sandbox, reviewed);
  control("reviewed head", () => {
    assert.equal(prProvenance.sourceCommit, source);
    assert.equal(prProvenance.sourceTree, sourceTree);
    assert.equal(prProvenance.reviewedCommit, reviewed);
    assert.equal(prProvenance.reviewedTree, reviewedTree);
    assert.deepEqual(prProvenance.evidenceCommits, [reviewed]);
    assert.equal(prProvenance.mergeCommit, null);
  });

  const mergeProvenance = expectedEvidenceProvenance(sandbox, merge);
  control("reviewed-head-to-merge equivalence", () => {
    assert.equal(mergeProvenance.sourceCommit, source);
    assert.equal(mergeProvenance.sourceTree, sourceTree);
    assert.equal(mergeProvenance.reviewedCommit, reviewed);
    assert.equal(mergeProvenance.reviewedTree, reviewedTree);
    assert.equal(mergeProvenance.mergeCommit, merge);
    assert.equal(mergeProvenance.mergeTree, reviewedTree);
    assert.deepEqual(mergeProvenance.mergeParents, [base, reviewed]);
  });

  const digest = "a".repeat(64);
  const evidence = {
    schemaVersion: evidenceSchemaVersion,
    sourceDigest: digest,
    sourceCommit: source,
    sourceTree,
  };
  control("fresh merge evidence", () => {
    validateEvidenceFreshness(evidence, digest, mergeProvenance);
  });

  const baseTree = git(["rev-parse", `${base}^{tree}`]);
  const wrongTreeMerge = commitTree(baseTree, [base, reviewed], "merge-added bytes");
  rejects(
    "wrong-tree merge",
    () => expectedEvidenceProvenance(sandbox, wrongTreeMerge),
    /merge tree mismatch.*introduced unreviewed bytes/
  );

  const wrongParent = commitTree(reviewedTree, [common], "same bytes, wrong lineage");
  const wrongParentMerge = commitTree(reviewedTree, [base, wrongParent], "wrong parent merge");
  const wrongParentProvenance = expectedEvidenceProvenance(sandbox, wrongParentMerge);
  rejects(
    "wrong reviewed parent",
    () => validateEvidenceFreshness(evidence, digest, wrongParentProvenance),
    /expected .* from reviewed parent .* evidence-only lineage/
  );

  const ancestorParentMerge = commitTree(
    git(["rev-parse", `${common}^{tree}`]),
    [base, common],
    "ancestor as reviewed parent"
  );
  rejects(
    "reviewed parent already in base",
    () => expectedEvidenceProvenance(sandbox, ancestorParentMerge),
    /already contained in base parent/
  );

  const octopus = commitTree(reviewedTree, [base, reviewed, common], "octopus");
  rejects(
    "octopus provenance",
    () => expectedEvidenceProvenance(sandbox, octopus),
    /rejects octopus merge/
  );

  rejects(
    "stale source digest",
    () => validateEvidenceFreshness(evidence, "b".repeat(64), mergeProvenance),
    /stale generated evidence source digest/
  );
  rejects(
    "stale source commit",
    () => validateEvidenceFreshness({ ...evidence, sourceCommit: common }, digest, mergeProvenance),
    /stale generated evidence commit/
  );
  rejects(
    "wrong source tree",
    () => validateEvidenceFreshness({ ...evidence, sourceTree: "0".repeat(40) }, digest,
      mergeProvenance),
    /stale generated evidence tree/
  );

  console.log(
    `[evidence-provenance] OK: ${controls} reviewed-head/merge positive and `
      + "wrong-tree/wrong-parent/stale identity controls"
  );
} finally {
  await rm(sandbox, { recursive: true, force: true });
}
