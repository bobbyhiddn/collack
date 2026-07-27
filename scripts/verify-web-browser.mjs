#!/usr/bin/env node

import { createReadStream } from "node:fs";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const webRoot = path.join(root, "dist", "web");
const verificationRoot = path.join(root, "dist", "verification");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".data": "application/octet-stream",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".png": "image/png",
  ".wasm": "application/wasm",
};

const server = createServer(async (request, response) => {
  try {
    const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
    const pathname = decodeURIComponent(requestUrl.pathname);
    const relative = pathname === "/" ? "index.html" : pathname.slice(1);
    const requestedPath = path.resolve(webRoot, relative);
    if (requestedPath !== webRoot && !requestedPath.startsWith(`${webRoot}${path.sep}`)) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    const info = await stat(requestedPath);
    if (!info.isFile()) throw new Error("not a file");
    response.writeHead(200, {
      "Content-Type": contentTypes[path.extname(requestedPath)] ?? "application/octet-stream",
      "Content-Length": info.size,
      "Cache-Control": "no-store",
    });
    createReadStream(requestedPath).pipe(response);
  } catch {
    response.writeHead(404).end("Not found");
  }
});

let browser;
let serverListening = false;
const runtimeErrors = [];
const requestedAssets = [];
const physicsSamples = [];
const audioReady = new Set();
const settingSamples = [];
const guidanceSamples = [];
const inspectionSamples = [];
const canonicalSweeps = [];
const canonicalBlowbacks = [];

function observePage(page, label) {
  page.on("console", (message) => {
    const text = message.text();
    if (process.env.CALLACK_BROWSER_DEBUG === "1") {
      console.log(`[${label}:${message.type()}] ${text}`);
    }
    if (message.type() === "error") runtimeErrors.push(`${label} console: ${text}`);
    if (text.includes("CALLACK_AUDIO ready")) audioReady.add(label);
    if (text.includes("CALLACK_AUDIO unavailable")) {
      runtimeErrors.push(`${label}: procedural audio failed to initialize: ${text}`);
    }
    if (text.startsWith("CALLACK_GUIDANCE ")) {
      guidanceSamples.push({ label, text });
    }
    if (text.startsWith("CALLACK_INSPECTION ")) {
      inspectionSamples.push({ label, text });
    }
    const sweep = text.match(
      /CALLACK_CANONICAL_SWEEP kind=(\S+) speed=(-?\d+\.\d+) toi=(-?\d+\.\d+) reflected=(true|false) tunneled=(true|false) substeps=(\d+) iterations=(\d+)/
    );
    if (sweep) {
      canonicalSweeps.push({
        label,
        kind: sweep[1],
        speed: Number(sweep[2]),
        toi: Number(sweep[3]),
        reflected: sweep[4] === "true",
        tunneled: sweep[5] === "true",
        substeps: Number(sweep[6]),
        iterations: Number(sweep[7]),
      });
    }
    const blowback = text.match(
      /CALLACK_CANONICAL_BLOWBACK allied=(true|false) enemy=(true|false) affected=(\d+) ally_dx=(-?\d+\.\d+) enemy_dx=(-?\d+\.\d+) substeps=(\d+) iterations=(\d+) tick=(\d+)/
    );
    if (blowback) {
      canonicalBlowbacks.push({
        label,
        allied: blowback[1] === "true",
        enemy: blowback[2] === "true",
        affected: Number(blowback[3]),
        allyDx: Number(blowback[4]),
        enemyDx: Number(blowback[5]),
        substeps: Number(blowback[6]),
        iterations: Number(blowback[7]),
        tick: Number(blowback[8]),
      });
    }
    const setting = text.match(
      /CALLACK_SETTING muted=(true|false) reduced_motion=(true|false) source=(\S+)/
    );
    if (setting) {
      settingSamples.push({
        label,
        muted: setting[1] === "true",
        reducedMotion: setting[2] === "true",
        source: setting[3],
      });
    }
    const match = text.match(
      /CALLACK_PHYSICS tick=(\d+) entity=(\S+) x=(-?\d+\.\d+) y=(-?\d+\.\d+)/
    );
    if (match) {
      physicsSamples.push({
        label,
        tick: Number(match[1]),
        entity: match[2],
        x: Number(match[3]),
        y: Number(match[4]),
      });
    }
  });
  page.on("pageerror", (error) => runtimeErrors.push(`${label} pageerror: ${error.message}`));
  page.on("requestfailed", (request) => {
    runtimeErrors.push(
      `${label} requestfailed: ${request.url()} (${request.failure()?.errorText ?? "unknown"})`
    );
  });
  page.on("request", (request) => requestedAssets.push(new URL(request.url()).pathname));
}

async function waitForConsole(page, fragment, timeout = 20_000) {
  return page.waitForEvent("console", {
    predicate: (message) => message.text().includes(fragment),
    timeout,
  });
}

async function bootPage(context, url, expected, label) {
  const page = await context.newPage();
  observePage(page, label);
  const ready = waitForConsole(page, "CALLACK_ACTION ready seed=9125 phase=setup", 60_000);
  await page.goto(url, { waitUntil: "networkidle", timeout: 60_000 });
  await ready;
  await page.waitForFunction(() => {
    const canvas = document.querySelector("#canvas");
    return canvas && getComputedStyle(canvas).visibility === "visible";
  }, null, { timeout: 60_000 });
  const canvas = page.locator("#canvas");
  const bounds = await canvas.boundingBox();
  assert(bounds, `${label}: #canvas has no visible bounding box`);
  assert(Math.abs(bounds.x) < 0.5 && Math.abs(bounds.y) < 0.5,
    `${label}: #canvas is offset at ${bounds.x},${bounds.y}`);
  assert(Math.abs(bounds.width - expected.width) < 0.5,
    `${label}: #canvas width is ${bounds.width}, expected ${expected.width}`);
  assert(Math.abs(bounds.height - expected.height) < 0.5,
    `${label}: #canvas height is ${bounds.height}, expected ${expected.height}`);
  return { page, canvas, bounds };
}

async function touchAction(runtime, x, y, action, timeout = 20_000) {
  const handled = waitForConsole(runtime.page, `CALLACK_ACTION ${action}`, timeout);
  await runtime.page.touchscreen.tap(runtime.bounds.x + x, runtime.bounds.y + y);
  await handled;
}

async function mouseAction(runtime, x, y, action, timeout = 20_000) {
  const handled = waitForConsole(runtime.page, `CALLACK_ACTION ${action}`, timeout);
  await runtime.page.mouse.click(runtime.bounds.x + x, runtime.bounds.y + y);
  await handled;
}

async function inspectAction(runtime, pointer, x, y, action, type, timeout = 20_000) {
  const handled = waitForConsole(runtime.page, `CALLACK_ACTION ${action}`, timeout);
  const inspected = waitForConsole(
    runtime.page,
    `CALLACK_INSPECTION type=${type}`,
    timeout
  );
  if (pointer === "touch") {
    await runtime.page.touchscreen.tap(runtime.bounds.x + x, runtime.bounds.y + y);
  } else {
    await runtime.page.mouse.click(runtime.bounds.x + x, runtime.bounds.y + y);
  }
  const detail = (await inspected).text();
  await handled;
  assert(/name=[^ ]+/.test(detail), `${type} inspection did not expose a readable name: ${detail}`);
  if (type === "choice") {
    assert(/mechanics=[1-9]\d*/.test(detail),
      `choice inspection did not expose mechanics: ${detail}`);
    assert(!detail.includes("counters=none links=none adds=none"),
      `choice inspection did not expose meaningful synergy: ${detail}`);
  } else {
    assert(/owner=[^ ]+/.test(detail) && !detail.includes("mechanic=none"),
      `entity inspection did not expose owner/mechanic detail: ${detail}`);
  }
  return detail;
}

async function screenshot(runtime, name, options = {}) {
  await runtime.page.screenshot({
    path: path.join(verificationRoot, name),
    animations: "disabled",
    ...options,
  });
}

async function waitForPhysics(label, minimum, timeout = 30_000) {
  const started = Date.now();
  while (physicsSamples.filter((sample) => sample.label === label).length < minimum) {
    if (Date.now() - started > timeout) {
      throw new Error(`${label}: did not emit ${minimum} moving-physics samples`);
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const samples = physicsSamples.filter((sample) => sample.label === label);
  const first = samples[0];
  const moved = samples.some((sample) =>
    sample.tick !== first.tick
      && (Math.abs(sample.x - first.x) > 0.01 || Math.abs(sample.y - first.y) > 0.01)
  );
  assert(moved, `${label}: canonical physics samples did not change position`);
}

async function waitForNewPhysics(label, priorCount, timeout = 30_000) {
  const started = Date.now();
  while (physicsSamples.filter((sample) => sample.label === label).length <= priorCount) {
    if (Date.now() - started > timeout) {
      throw new Error(`${label}: battle did not emit a new moving-physics sample`);
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return physicsSamples.filter((sample) => sample.label === label).at(-1);
}

function digest(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

async function completeMobile(runtime) {
  await screenshot(runtime, "phone-setup-start.png");
  const setupDetail = guidanceSamples.find((sample) =>
    sample.label === "phone" && sample.text.includes("screen=setup")
  )?.text ?? "";
  assert(/scout=(?!none)[^ ]+/.test(setupDetail) && /build=(?!none)[^ ]+/.test(setupDetail),
    `phone setup guidance is not meaningful: ${setupDetail}`);

  await touchAction(runtime, 59, 548, "marble:");
  await touchAction(runtime, 350, 608, "slot:tail");
  // Exercise both directions of the ordered bag, then restore the recommended
  // Chalk → Quartz opener before the deterministic tutorial route.
  await touchAction(runtime, 148, 548, "marble:");
  await touchAction(runtime, 40, 608, "slot:");
  const bench = [
    [60, 386], [149, 386], [238, 386],
  ];
  const cells = [
    [93, 180], [191, 180], [289, 180],
  ];
  for (let index = 0; index < bench.length; index += 1) {
    await touchAction(runtime, bench[index][0], bench[index][1], "brick:");
    await touchAction(runtime, cells[index][0], cells[index][1], "cell:");
  }
  await screenshot(runtime, "phone-setup.png");

  const battleReached = waitForConsole(runtime.page, "CALLACK_ACTION phase_battle", 20_000);
  const firstRefitReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_draft",
    120_000
  );
  await touchAction(runtime, 195, 800, "lock_setup");
  await battleReached;
  await firstRefitReached;
  await screenshot(runtime, "phone-refit-1.png");
  await inspectAction(runtime, "touch", 195, 180, "offer:", "choice");
  await screenshot(runtime, "phone-refit-inspection.png");
  await touchAction(runtime, 195, 732, "select:");
  const secondSetupReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_setup",
    20_000
  );
  await touchAction(runtime, 195, 800, "confirm_offer");
  await secondSetupReached;

  const secondBattleReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_battle",
    20_000
  );
  const secondRefitReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_draft",
    120_000
  );
  const secondPhysicsBaseline =
    physicsSamples.filter((sample) => sample.label === "phone").length;
  await touchAction(runtime, 195, 800, "lock_setup");
  await secondBattleReached;
  await waitForNewPhysics("phone", secondPhysicsBaseline);
  await touchAction(runtime, 57, 796, "battle_pause");
  await inspectAction(
    runtime,
    "touch",
    107,
    557,
    "entity:",
    "entity"
  );
  await screenshot(runtime, "phone-battle-inspection.png");
  await touchAction(runtime, 57, 796, "battle_pause");
  await touchAction(runtime, 147, 796, "battle_speed");
  await waitForPhysics("phone", 2);
  const firstBattle = await runtime.canvas.screenshot();
  await screenshot(runtime, "phone-battle.png");
  await runtime.page.waitForTimeout(650);
  const secondBattle = await runtime.canvas.screenshot();
  assert(digest(firstBattle) !== digest(secondBattle),
    "phone: battle canvas did not visually change while canonical physics advanced");
  await touchAction(runtime, 330, 796, "battle_motion");
  await touchAction(runtime, 237, 796, "battle_mute");
  await runtime.page.waitForTimeout(1_500);
  const phoneSettings = settingSamples.filter((sample) => sample.label === "phone");
  const finalSettings = phoneSettings[phoneSettings.length - 1];
  assert(finalSettings?.muted && finalSettings?.reducedMotion,
    `phone: touch settings did not remain enabled: ${JSON.stringify(phoneSettings)}`);
  await screenshot(runtime, "phone-battle-settings.png");
  await secondRefitReached;
  await screenshot(runtime, "phone-refit-2.png");
  await touchAction(runtime, 195, 180, "offer:");
  await touchAction(runtime, 195, 732, "select:");
  const thirdSetupReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_setup",
    20_000
  );
  await touchAction(runtime, 195, 800, "confirm_offer");
  await thirdSetupReached;

  // The recommended second reward adds one new brick.  Persistent casualties
  // leave exactly three active bricks, so the new third bench card must be
  // placed before the terminal setup can lock.
  await touchAction(runtime, 238, 386, "brick:");
  await touchAction(runtime, 191, 180, "cell:");
  await screenshot(runtime, "phone-setup-terminal.png");
  const thirdBattleReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_battle",
    20_000
  );
  const resultReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_result",
    120_000
  );
  await touchAction(runtime, 195, 800, "lock_setup");
  await thirdBattleReached;
  await resultReached;
  await screenshot(runtime, "phone-result.png");

  await touchAction(runtime, 103, 788, "review_battle");
  await runtime.page.waitForTimeout(450);
  await touchAction(runtime, 103, 788, "review_battle");
  await touchAction(runtime, 287, 788, "replay_battle");
  await runtime.page.waitForTimeout(450);
  await touchAction(runtime, 287, 788, "replay_close");
  await runtime.page.waitForTimeout(450);
  await touchAction(runtime, 195, 720, "new_run");
  await runtime.page.waitForTimeout(1_400);
  await mouseAction(runtime, 60, 386, "brick:");
}

async function completeDesktop(runtime) {
  await screenshot(runtime, "desktop-setup-start.png");
  const setupDetail = guidanceSamples.find((sample) =>
    sample.label === "desktop" && sample.text.includes("screen=setup")
  )?.text ?? "";
  assert(/scout=(?!none)[^ ]+/.test(setupDetail) && /build=(?!none)[^ ]+/.test(setupDetail),
    `desktop setup guidance is not meaningful: ${setupDetail}`);

  await mouseAction(runtime, 1100, 190, "marble:");
  await mouseAction(runtime, 1204, 556, "slot:tail");
  await mouseAction(runtime, 1100, 282, "marble:");
  await mouseAction(runtime, 1204, 196, "slot:");
  const bench = [
    [96, 180], [224, 180], [96, 292],
  ];
  const cells = [
    [472, 256], [632, 256], [792, 256],
  ];
  for (let index = 0; index < bench.length; index += 1) {
    await mouseAction(runtime, bench[index][0], bench[index][1], "brick:");
    await mouseAction(runtime, cells[index][0], cells[index][1], "cell:");
  }
  await screenshot(runtime, "desktop-setup.png");

  const battleReached = waitForConsole(runtime.page, "CALLACK_ACTION phase_battle", 20_000);
  const firstRefitReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_draft",
    120_000
  );
  await mouseAction(runtime, 1122, 732, "lock_setup");
  await battleReached;
  await firstRefitReached;
  await screenshot(runtime, "desktop-refit-1.png");
  await inspectAction(runtime, "mouse", 456, 348, "offer:", "choice");
  await screenshot(runtime, "desktop-refit-inspection.png");
  await mouseAction(runtime, 880, 732, "select:");
  const secondSetupReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_setup",
    20_000
  );
  await mouseAction(runtime, 1122, 732, "confirm_offer");
  await secondSetupReached;

  const secondBattleReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_battle",
    20_000
  );
  const secondRefitReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_draft",
    120_000
  );
  const secondPhysicsBaseline =
    physicsSamples.filter((sample) => sample.label === "desktop").length;
  await mouseAction(runtime, 1122, 732, "lock_setup");
  await secondBattleReached;
  await waitForNewPhysics("desktop", secondPhysicsBaseline);
  await mouseAction(runtime, 816, 732, "battle_pause");
  await inspectAction(
    runtime,
    "mouse",
    930,
    242,
    "entity:",
    "entity"
  );
  await screenshot(runtime, "desktop-battle-inspection.png");
  await mouseAction(runtime, 816, 732, "battle_pause");
  await mouseAction(runtime, 940, 732, "battle_speed");
  await waitForPhysics("desktop", 2);
  const firstBattle = await runtime.canvas.screenshot();
  await screenshot(runtime, "desktop-battle.png");
  await runtime.page.waitForTimeout(650);
  const secondBattle = await runtime.canvas.screenshot();
  assert(digest(firstBattle) !== digest(secondBattle),
    "desktop: battle canvas did not visually change while canonical physics advanced");
  await secondRefitReached;
  await screenshot(runtime, "desktop-refit-2.png");
  await mouseAction(runtime, 456, 348, "offer:");
  await mouseAction(runtime, 880, 732, "select:");
  const thirdSetupReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_setup",
    20_000
  );
  await mouseAction(runtime, 1122, 732, "confirm_offer");
  await thirdSetupReached;
  await mouseAction(runtime, 96, 292, "brick:");
  await mouseAction(runtime, 632, 256, "cell:");
  await screenshot(runtime, "desktop-setup-terminal.png");

  const thirdBattleReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_battle",
    20_000
  );
  const resultReached = waitForConsole(
    runtime.page,
    "CALLACK_ACTION phase_result",
    120_000
  );
  await mouseAction(runtime, 1122, 732, "lock_setup");
  await thirdBattleReached;
  await resultReached;
  await screenshot(runtime, "desktop-result.png");

  await mouseAction(runtime, 818, 732, "review_battle");
  await runtime.page.waitForTimeout(450);
  await mouseAction(runtime, 818, 732, "review_battle");
  await mouseAction(runtime, 944, 732, "replay_battle");
  await runtime.page.waitForTimeout(450);
  await mouseAction(runtime, 1194, 732, "replay_close");
  await runtime.page.waitForTimeout(450);
  await mouseAction(runtime, 1122, 732, "new_run");
}

try {
  await mkdir(verificationRoot, { recursive: true });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  serverListening = true;
  const address = server.address();
  assert(address && typeof address !== "string", "static server did not bind a TCP port");
  const url = `http://127.0.0.1:${address.port}/`;

  browser = await chromium.launch({ headless: true });
  const phoneContext = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 1,
    hasTouch: true,
    isMobile: true,
  });
  const verificationUrl = `${url}?verify=canonical`;
  const phone = await bootPage(
    phoneContext,
    verificationUrl,
    { width: 390, height: 844 },
    "phone"
  );
  await completeMobile(phone);
  await phoneContext.close();

  const desktopContext = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 1,
  });
  const desktop = await bootPage(
    desktopContext,
    verificationUrl,
    { width: 1280, height: 800 },
    "desktop"
  );
  await completeDesktop(desktop);
  await desktopContext.close();

  const fixedRuntimeUrls = new Set(["/game.js", "/game.data", "/love.js", "/love.wasm"]);
  assert(!requestedAssets.some((asset) => fixedRuntimeUrls.has(asset)),
    `browser requested a stale fixed runtime URL: ${requestedAssets.join(", ")}`);
  assert(requestedAssets.some((asset) => /^\/game\.[0-9a-f]{16}\.js$/.test(asset)),
    "browser did not request a hashed game loader");
  assert(requestedAssets.some((asset) => /^\/game\.[0-9a-f]{16}\.data$/.test(asset)),
    "browser did not request hashed game data");
  assert(requestedAssets.some((asset) => /^\/love\.[0-9a-f]{16}\.js$/.test(asset)),
    "browser did not request a hashed LÖVE loader");
  assert(requestedAssets.some((asset) => /^\/love\.[0-9a-f]{16}\.wasm$/.test(asset)),
    "browser did not request hashed WebAssembly");
  assert(audioReady.has("phone") && audioReady.has("desktop"),
    "procedural audio did not initialize in both browser layouts");
  for (const label of ["phone", "desktop"]) {
    const guidance = guidanceSamples.filter((sample) => sample.label === label);
    assert(guidance.some((sample) =>
      /screen=draft .*scout=(?!none)[^ ]+ .*mechanic_cards=3/.test(sample.text)),
    `${label}: refit did not publish next-scout and canonical mechanic guidance`);
    assert(guidance.some((sample) =>
      /screen=setup .*scout=(?!none)[^ ]+ .*build=(?!none)[^ ]+/.test(sample.text)),
    `${label}: setup did not publish scout and build synergy guidance`);
    const inspections = inspectionSamples.filter((sample) => sample.label === label);
    assert(inspections.some((sample) =>
      sample.text.includes("type=choice")
        && !sample.text.includes("operation=none")
        && sample.text.includes("cause=post_battle_choice")),
    `${label}: typed causal refit inspection was not exercised`);
    assert(inspections.some((sample) => sample.text.includes("type=entity")),
      `${label}: entity inspection regression was not exercised`);
    const sweep = canonicalSweeps.find((sample) => sample.label === label);
    assert(sweep?.kind === "box_collision"
      && sweep.speed >= 240
      && sweep.toi > 0
      && sweep.toi < 1 / 120
      && sweep.reflected
      && !sweep.tunneled
      && sweep.substeps === 1
      && sweep.iterations === 1,
    `${label}: packaged canonical sweep evidence is incomplete: ${JSON.stringify(sweep)}`);
    const blowback = canonicalBlowbacks.find((sample) => sample.label === label);
    assert(blowback?.allied
      && blowback.enemy
      && blowback.affected >= 2
      && blowback.allyDx < 0
      && blowback.enemyDx > 0
      && blowback.substeps === 1
      && blowback.iterations >= 1,
    `${label}: packaged allied/enemy blowback evidence is incomplete: ${JSON.stringify(blowback)}`);
  }
  assert(runtimeErrors.length === 0, runtimeErrors.join("\n"));

  const motionEvidence = {};
  for (const label of ["phone", "desktop"]) {
    const samples = physicsSamples.filter((sample) => sample.label === label);
    const first = samples[0];
    const moved = samples.find((sample) =>
      sample.tick !== first.tick
        && (Math.abs(sample.x - first.x) > 0.01 || Math.abs(sample.y - first.y) > 0.01)
    );
    motionEvidence[label] = { first, moved };
  }
  const screenshotNames = [
    "phone-refit-inspection.png",
    "phone-setup.png",
    "phone-setup-terminal.png",
    "phone-battle-inspection.png",
    "phone-battle.png",
    "desktop-refit-inspection.png",
    "desktop-setup.png",
    "desktop-setup-terminal.png",
    "desktop-battle-inspection.png",
    "desktop-battle.png",
  ];
  const screenshotHashes = {};
  for (const name of screenshotNames) {
    screenshotHashes[name] = digest(await readFile(path.join(verificationRoot, name)));
  }
  await writeFile(
    path.join(verificationRoot, "packaged-runtime-evidence.json"),
    `${JSON.stringify({
      schemaVersion: 1,
      viewports: {
        phone: { width: 390, height: 844, touch: true },
        desktop: { width: 1280, height: 800, touch: false },
      },
      canonicalSweeps,
      canonicalBlowbacks,
      motionEvidence,
      guidance: guidanceSamples,
      inspections: inspectionSamples,
      screenshotHashes,
    }, null, 2)}\n`
  );

  console.log(
    `[web-browser] OK: phone + desktop sparse setup, three battles, two causal refits, `
      + `attrition, terminal result, replay, settings, and new-run; `
      + `${physicsSamples.length} canonical moving-physics samples; swept TOI + allied/enemy `
      + `blowback; screenshots and evidence manifest in dist/verification`
  );
} finally {
  if (browser) await browser.close();
  if (serverListening) {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}
