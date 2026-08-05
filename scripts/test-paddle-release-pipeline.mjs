#!/usr/bin/env node

import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { chmod, cp, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validatePaddleReleaseArtifact } from "./paddle-release-contract.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const canonical = path.join(root, "dist", "paddle-web");
const temporary = await mkdtemp(path.join(root, "dist", ".paddle-pipeline-control."));
const fakeBin = path.join(temporary, "bin");
const statePath = path.join(temporary, "state.json");
const flyLog = path.join(temporary, "fly.json");
const imageId = `sha256:${"1".repeat(64)}`;
const remoteDigest = `sha256:${"2".repeat(64)}`;
let checks = 0;
function assert(value, message) { checks += 1; if (!value) throw new Error(message); }
function sha256(bytes) { return createHash("sha256").update(bytes).digest("hex"); }

const fakeDocker = `#!/usr/bin/env node
const fs=require("node:fs"), path=require("node:path");
const statePath=process.env.CALLACK_FAKE_DOCKER_STATE;
const state=JSON.parse(fs.readFileSync(statePath,"utf8"));
const args=process.argv.slice(2), command=args.shift();
const save=()=>fs.writeFileSync(statePath,JSON.stringify(state));
if(command==="info") process.exit(0);
if(command==="build") {
  state.builds=(state.builds||0)+1;
  const labels={}; for(let i=0;i<args.length;i++) if(args[i]==="--label") { const [k,...v]=args[++i].split("="); labels[k]=v.join("="); }
  state.labels=labels;
  const index=path.join(state.canonical,"index.html"), manifestPath=path.join(state.canonical,"callack-build-manifest.json");
  fs.appendFileSync(index,"\\n<!-- POST_PREFLIGHT_REPLACEMENT -->\\n");
  const bytes=fs.readFileSync(index), manifest=JSON.parse(fs.readFileSync(manifestPath));
  const record=manifest.assets.find(x=>x.path==="index.html"); record.bytes=bytes.length; record.sha256=require("node:crypto").createHash("sha256").update(bytes).digest("hex");
  manifest.assetSetSha256=require("node:crypto").createHash("sha256").update(JSON.stringify(manifest.assets)).digest("hex");
  fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+"\\n");
  fs.rmSync(state.imageRoot,{recursive:true,force:true}); fs.cpSync(state.canonical,state.imageRoot,{recursive:true}); save(); process.exit(0);
}
if(command==="image"&&args[0]==="inspect") {
  const format=args[2]||""; if(format.includes(".Id")) console.log(state.imageId); else { const m=format.match(/Labels \\\"([^\\\"]+)/); console.log(state.labels[m?.[1]]||""); } process.exit(0);
}
if(command==="create") { console.log("fake-container"); process.exit(0); }
if(command==="cp") { const dest=args[1]; fs.mkdirSync(dest,{recursive:true}); fs.cpSync(state.imageRoot,dest,{recursive:true}); process.exit(0); }
if(command==="rm") process.exit(0);
if(command==="tag") { state.tagRetargeted=true; save(); process.exit(0); }
if(command==="push") { fs.appendFileSync(path.join(state.canonical,"index.html"),"\\n<!-- POST_IMAGE_VALIDATION_EDIT -->\\n"); console.log("pushed digest: "+state.remoteDigest+" size: 1"); process.exit(0); }
if(command==="manifest"&&args[0]==="inspect") { console.log(JSON.stringify({schemaVersion:2,config:{digest:state.remoteConfig||state.imageId}})); process.exit(0); }
console.error("unexpected fake docker command",command,args); process.exit(91);
`;
const fakeFly = `#!/usr/bin/env node
require("node:fs").writeFileSync(process.env.CALLACK_FAKE_FLY_LOG,JSON.stringify(process.argv.slice(2)));`;

await mkdir(fakeBin);
await writeFile(path.join(fakeBin, "docker"), fakeDocker);
await writeFile(path.join(fakeBin, "flyctl"), fakeFly);
await chmod(path.join(fakeBin, "docker"), 0o755); await chmod(path.join(fakeBin, "flyctl"), 0o755);

const originalIndex = await readFile(path.join(canonical, "index.html"));
const originalManifest = await readFile(path.join(canonical, "callack-build-manifest.json"));
try {
  const release = await validatePaddleReleaseArtifact(canonical);
  const tool = release.releaseFiles.find((entry) => entry.path === "callack-toolchain-identity.json");
  const labels = {
    "io.callack.release.target": "paddle-web",
    "io.callack.release.artifact-path": "dist/paddle-web",
    "org.opencontainers.image.revision": release.manifest.revision,
    "io.callack.release.source-tree": release.manifest.tree,
    "io.callack.release.manifest-sha256": release.manifestSha256,
    "io.callack.release.asset-set-sha256": release.manifest.assetSetSha256,
    "io.callack.release.file-set-sha256": release.releaseFileSetSha256,
    "io.callack.release.archive-sha256": release.manifest.toolchain.candidateArchive.sha256,
    "io.callack.release.toolchain-sha256": tool.sha256,
  };
  const imageRoot = path.join(temporary, "image-root"); await cp(canonical, imageRoot, { recursive: true });
  const state = { canonical, imageRoot, imageId, remoteDigest, labels, builds: 0 };
  await writeFile(statePath, JSON.stringify(state));
  const env = { ...process.env, PATH: `${fakeBin}:${process.env.PATH}`, CALLACK_CONTAINER_ENGINE: "docker", CALLACK_FAKE_DOCKER_STATE: statePath, CALLACK_FAKE_FLY_LOG: flyLog };

  const racedBuild = spawnSync("bash", [path.join(root, "scripts", "build-paddle-release-image.sh"), "fake:race"], { cwd: root, env, encoding: "utf8" });
  assert(racedBuild.status !== 0, "post-preflight artifact replacement silently became the image candidate");
  assert(JSON.parse(await readFile(statePath, "utf8")).builds === 1,
    `race control did not cross the preflight/build boundary exactly once: ${racedBuild.stderr}`);

  await writeFile(path.join(canonical, "index.html"), originalIndex); await writeFile(path.join(canonical, "callack-build-manifest.json"), originalManifest);
  await rm(imageRoot, { recursive: true, force: true }); await cp(canonical, imageRoot, { recursive: true });
  await writeFile(statePath, JSON.stringify({ ...state, imageRoot, builds: 0 }));
  const released = spawnSync("bash", [path.join(root, "scripts", "release-paddle-fly.sh"), "--deploy", "--image", imageId], { cwd: root, env, encoding: "utf8" });
  assert(released.status === 0, `mocked immutable release failed: ${released.stderr}`);
  const flyArgs = JSON.parse(await readFile(flyLog, "utf8"));
  const expectedRef = `registry.fly.io/collack-spike@${remoteDigest}`;
  assert(flyArgs.includes("--image") && flyArgs.includes(expectedRef), "Fly did not receive the returned digest-qualified reference");
  assert(!flyArgs.some((arg) => arg.includes(":candidate-")), "Fly received a mutable staging tag");
  assert(!flyArgs.includes("--dockerfile") && !flyArgs.some((arg) => arg.includes("dist/paddle-web")), "release command reread or rebuilt working-tree artifacts");
  assert(JSON.parse(await readFile(statePath, "utf8")).tagRetargeted, "mutable-tag retarget control did not execute");
  assert(sha256(await readFile(path.join(canonical, "index.html"))) !== sha256(originalIndex), "post-validation edit control did not execute");
  console.log(`[paddle-pipeline-control] OK: ${checks} assertions; validated=${imageId} deployed=${expectedRef}`);
} finally {
  await writeFile(path.join(canonical, "index.html"), originalIndex).catch(() => {});
  await writeFile(path.join(canonical, "callack-build-manifest.json"), originalManifest).catch(() => {});
  await rm(temporary, { recursive: true, force: true });
}
