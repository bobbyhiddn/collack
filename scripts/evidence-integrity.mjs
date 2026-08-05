import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";

export const manifestName =
  "dist/verification/packaged-runtime-evidence.json";
export const checksumName =
  "dist/verification/packaged-runtime-evidence.sha256";
export const evidenceSchemaVersion = 3;

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

function gitParent(root, commit) {
  try {
    return gitText(root, ["rev-parse", `${commit}^`]);
  } catch {
    return null;
  }
}

function changedPaths(root, commit) {
  const output = gitText(root, [
    "diff-tree",
    "--no-commit-id",
    "--name-only",
    "-r",
    commit,
  ]);
  return output === "" ? [] : output.split("\n");
}

// Evidence is committed immediately after the exact source/build commit.
// Peel any evidence-only commits so provenance never attempts to hash itself.
export function expectedEvidenceProvenance(root) {
  let sourceCommit = gitText(root, ["rev-parse", "HEAD"]);
  while (true) {
    const parent = gitParent(root, sourceCommit);
    const changed = changedPaths(root, sourceCommit);
    if (!parent
      || changed.length === 0
      || !changed.every((name) => name.startsWith("dist/verification/"))) {
      break;
    }
    sourceCommit = parent;
  }
  return {
    sourceCommit,
    sourceTree: gitText(root, ["rev-parse", `${sourceCommit}^{tree}`]),
  };
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
    // The build manifest names HEAD, so an evidence-only commit necessarily
    // changes its bytes. Seal the executable payload here and verify the
    // manifest independently against exact HEAD to avoid recursive evidence.
    if (name === "dist/web/callack-build-manifest.json") continue;
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
