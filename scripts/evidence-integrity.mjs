import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";

export const manifestName =
  "dist/verification/packaged-runtime-evidence.json";
export const checksumName =
  "dist/verification/packaged-runtime-evidence.sha256";
export const evidenceSchemaVersion = 6;

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function gitText(root, args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

function commitRecord(root, revision) {
  let ancestry;
  try {
    ancestry = gitText(root, ["rev-list", "--parents", "-n", "1", `${revision}^{commit}`])
      .split(" ");
  } catch {
    throw new Error(`evidence provenance cannot resolve commit ${revision}`);
  }
  const [commit, ...parents] = ancestry;
  return {
    commit,
    parents,
    tree: gitText(root, ["rev-parse", `${commit}^{tree}`]),
  };
}

function changedPaths(root, parent, commit) {
  const output = gitText(root, [
    "diff-tree",
    "--no-commit-id",
    "--name-only",
    "--no-renames",
    "-r",
    parent,
    commit,
  ]);
  return output === "" ? [] : output.split("\n");
}

function isAncestor(root, ancestor, descendant) {
  try {
    execFileSync("git", ["merge-base", "--is-ancestor", ancestor, descendant], {
      cwd: root,
      stdio: "ignore",
    });
    return true;
  } catch (error) {
    if (error?.status === 1) return false;
    throw new Error(
      `evidence provenance could not compare ${ancestor} with ${descendant}`
    );
  }
}

function sourceBelowEvidence(root, reviewedCommit) {
  let source = commitRecord(root, reviewedCommit);
  const evidenceCommits = [];
  while (true) {
    if (source.parents.length !== 1) break;
    const [parent] = source.parents;
    const changed = changedPaths(root, parent, source.commit);
    if (changed.length === 0
      || !changed.every((name) => name.startsWith("dist/verification/"))) {
      break;
    }
    evidenceCommits.push(source.commit);
    source = commitRecord(root, parent);
  }
  return { source, evidenceCommits };
}

// The manifest names the exact source/build commit immediately below any
// evidence-only commits. The final reviewed tree cannot name its own commit or
// tree without becoming self-referential, so derive that identity from Git.
// A release merge is valid only when its bytes are exactly its reviewed second
// parent's bytes; its first and second parents remain part of the returned,
// cryptographically resolved provenance.
export function expectedEvidenceProvenance(root, revision = "HEAD") {
  const candidate = commitRecord(root, revision);
  if (candidate.parents.length > 2) {
    throw new Error(
      `release evidence rejects octopus merge ${candidate.commit}: `
        + `expected at most two parents, got ${candidate.parents.length}`
    );
  }

  let reviewed = candidate;
  let mergeCommit = null;
  let mergeTree = null;
  let mergeParents = [];
  if (candidate.parents.length === 2) {
    const [baseParent, reviewedParent] = candidate.parents;
    if (baseParent === reviewedParent) {
      throw new Error(
        `release merge ${candidate.commit} repeats parent ${baseParent}; `
          + "reviewed provenance is ambiguous"
      );
    }
    reviewed = commitRecord(root, reviewedParent);
    if (candidate.tree !== reviewed.tree) {
      throw new Error(
        `release merge tree mismatch: merge ${candidate.commit} tree ${candidate.tree} `
          + `does not match reviewed parent ${reviewed.commit} tree ${reviewed.tree}; `
          + "the merge introduced unreviewed bytes"
      );
    }
    if (isAncestor(root, reviewedParent, baseParent)) {
      throw new Error(
        `release merge ${candidate.commit} has invalid reviewed parent ${reviewedParent}: `
          + `it is already contained in base parent ${baseParent}`
      );
    }
    mergeCommit = candidate.commit;
    mergeTree = candidate.tree;
    mergeParents = [...candidate.parents];
  }

  const { source, evidenceCommits } = sourceBelowEvidence(root, reviewed.commit);
  return {
    sourceCommit: source.commit,
    sourceTree: source.tree,
    reviewedCommit: reviewed.commit,
    reviewedTree: reviewed.tree,
    evidenceCommits,
    mergeCommit,
    mergeTree,
    mergeParents,
  };
}

export function validateEvidenceFreshness(evidence, expectedSourceDigest, provenance) {
  if (evidence.schemaVersion !== evidenceSchemaVersion) {
    throw new Error(
      `generated evidence schema must be ${evidenceSchemaVersion}, got ${evidence.schemaVersion}`
    );
  }
  if (!/^[0-9a-f]{64}$/.test(evidence.sourceDigest ?? "")) {
    throw new Error("generated evidence is missing its exact source digest");
  }
  if (evidence.sourceDigest !== expectedSourceDigest) {
    throw new Error(
      `stale generated evidence source digest: ${evidence.sourceDigest}, `
        + `expected ${expectedSourceDigest}`
    );
  }
  const lineage = provenance.mergeCommit
    ? `reviewed parent ${provenance.reviewedCommit} of merge ${provenance.mergeCommit}`
    : `reviewed commit ${provenance.reviewedCommit}`;
  if (evidence.sourceCommit !== provenance.sourceCommit) {
    throw new Error(
      `stale generated evidence commit: ${evidence.sourceCommit}, `
        + `expected ${provenance.sourceCommit} from ${lineage} evidence-only lineage`
    );
  }
  if (evidence.sourceTree !== provenance.sourceTree) {
    throw new Error(
      `stale generated evidence tree: ${evidence.sourceTree}, `
        + `expected ${provenance.sourceTree} from source commit ${provenance.sourceCommit}`
    );
  }
}

export function assertSourceWorkingTreeClean(root) {
  // Porcelain's leading two status columns are significant; do not pass this
  // output through gitText(), whose trim would erase a leading worktree space.
  const status = execFileSync("git", [
    "status",
    "--porcelain=v1",
    "--untracked-files=all",
  ], {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trimEnd();
  const outsideEvidence = status === ""
    ? []
    : status.split("\n").filter(Boolean).filter((line) => {
      const raw = line.slice(3);
      const name = raw.includes(" -> ") ? raw.split(" -> ").at(-1) : raw;
      return !name.startsWith("dist/verification/");
    });
  if (outsideEvidence.length > 0) {
    throw new Error(
      "generated evidence requires a clean exact source tree; found "
        + outsideEvidence.join(", ")
    );
  }
}

async function fileRecord(root, name) {
  const bytes = await readFile(path.join(root, name));
  const info = await stat(path.join(root, name));
  if (!info.isFile()) throw new Error(`executable evidence is not a file: ${name}`);
  return { path: name, size: bytes.length, sha256: sha256(bytes) };
}

async function filesBelow(root, relativeDirectory) {
  const absolute = path.join(root, relativeDirectory);
  const entries = await readdir(absolute, { withFileTypes: true });
  const names = [];
  for (const entry of entries) {
    const relative = path.posix.join(relativeDirectory, entry.name);
    if (entry.isDirectory()) {
      names.push(...await filesBelow(root, relative));
    } else if (entry.isFile()) {
      names.push(relative);
    } else {
      throw new Error(`executable evidence contains a non-file entry: ${relative}`);
    }
  }
  return names.sort();
}

export async function executableEvidence(root) {
  const archive = await fileRecord(root, "dist/collack-spike.love");
  const webFiles = [];
  for (const name of await filesBelow(root, "dist/web")) {
    webFiles.push(await fileRecord(root, name));
  }
  const aggregateDigest = sha256(
    Buffer.from(JSON.stringify([archive, ...webFiles]), "utf8")
  );
  return { archive, webFiles, aggregateDigest };
}

export function evidencePayloadDigest(evidence) {
  const { evidenceDigest: _discarded, ...payload } = evidence;
  return sha256(Buffer.from(JSON.stringify(payload), "utf8"));
}

export function sealEvidence(payload) {
  const evidence = { ...payload };
  evidence.evidenceDigest = evidencePayloadDigest(evidence);
  return evidence;
}

export function serializeEvidence(evidence) {
  return Buffer.from(`${JSON.stringify(evidence, null, 2)}\n`, "utf8");
}

export function checksumLine(manifestBytes) {
  return Buffer.from(
    `${sha256(manifestBytes)}  ${path.posix.basename(manifestName)}\n`,
    "utf8"
  );
}

export function validateRawChecksum(manifestBytes, checksumBytes) {
  const expected = checksumLine(manifestBytes);
  if (!Buffer.from(checksumBytes).equals(expected)) {
    throw new Error(
      `generated evidence byte checksum mismatch: expected ${expected.toString("utf8").trim()}`
    );
  }
}

export function validatePayloadDigest(evidence) {
  const expected = evidencePayloadDigest(evidence);
  if (!/^[0-9a-f]{64}$/.test(evidence.evidenceDigest ?? "")
    || evidence.evidenceDigest !== expected) {
    throw new Error(
      `generated evidence payload digest mismatch: ${evidence.evidenceDigest}, expected ${expected}`
    );
  }
}
