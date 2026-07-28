import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";

function trackedSourcePaths(root) {
  const output = execFileSync("git", ["ls-files", "-z"], {
    cwd: root,
    encoding: "buffer",
  });
  return output.toString("utf8")
    .split("\0")
    .filter(Boolean)
    .filter((name) => !name.startsWith("dist/"))
    .sort();
}

export async function evidenceSourceDigest(root) {
  const hash = createHash("sha256");
  for (const name of trackedSourcePaths(root)) {
    hash.update(name);
    hash.update("\0");
    hash.update(await readFile(path.join(root, name)));
    hash.update("\0");
  }
  return hash.digest("hex");
}
