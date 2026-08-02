#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { PNG } from "pngjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const evidenceRoot = path.join(root, "dist", "deployed-verification");
const deployedUrl = process.env.CALLACK_DEPLOYED_URL ?? "https://collack-spike.fly.dev/";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForState(page, description, predicate, timeout = 15_000) {
  const started = Date.now();
  let state;
  while (Date.now() - started < timeout) {
    state = await readCanvasState(page);
    if (predicate(state)) return state;
    await page.waitForTimeout(100);
  }
  throw new Error(`${description}; last state: ${JSON.stringify(state)}`);
}

async function readCanvasState(page) {
  const canvas = page.locator("#canvas");
  const surface = await canvas.evaluate((element) => ({
    width: element.width,
    height: element.height,
  }));
  const image = PNG.sync.read(await canvas.screenshot({ animations: "disabled" }));
  const { width, height, data: pixels } = image;
  const frameHash = createHash("sha256").update(pixels).digest("hex");
  const scaleX = width / surface.width;
  const scaleY = height / surface.height;
  const areaScale = scaleX * scaleY;
  const channel = (x, y, offset) => pixels[(y * width + x) * 4 + offset];
  const logicalY = (value) => Math.max(0, Math.min(height - 1, Math.round(value * scaleY)));
  const logicalX = (value) => Math.max(0, Math.min(width - 1, Math.round(value * scaleX)));

    let paddleMin = width;
    let paddleMax = -1;
    let paddlePixels = 0;
    for (let y = logicalY(545); y <= logicalY(580); y += 1) {
      for (let x = 0; x < width; x += 1) {
        const red = channel(x, y, 0);
        const green = channel(x, y, 1);
        const blue = channel(x, y, 2);
        if (red >= 205 && red <= 230
          && green >= 218 && green <= 242
          && blue >= 232 && blue <= 255
          && red < green && green < blue) {
          paddleMin = Math.min(paddleMin, x);
          paddleMax = Math.max(paddleMax, x);
          paddlePixels += 1;
        }
      }
    }

    let brickPixels = 0;
    for (let y = logicalY(50); y <= logicalY(155); y += 1) {
      for (let x = 0; x < width; x += 1) {
        const red = channel(x, y, 0);
        const green = channel(x, y, 1);
        const blue = channel(x, y, 2);
        const redBrick = red > 205 && green >= 55 && green <= 135 && blue >= 55 && blue <= 135;
        const yellowBrick = red > 205 && green >= 150 && green <= 220 && blue >= 35 && blue <= 115;
        const greenBrick = red >= 65 && red <= 150 && green > 175 && blue >= 75 && blue <= 180;
        if (redBrick || yellowBrick || greenBrick) brickPixels += 1;
      }
    }

    let hudHash = 2166136261;
    for (let y = 0; y <= logicalY(52); y += 1) {
      for (let x = 0; x <= logicalX(180); x += 1) {
        for (let offset = 0; offset < 3; offset += 1) {
          hudHash = Math.imul(hudHash ^ channel(x, y, offset), 16777619);
        }
      }
    }

    let centerBrightPixels = 0;
    for (let y = logicalY(265); y <= logicalY(325); y += 1) {
      for (let x = 0; x < width; x += 1) {
        if (channel(x, y, 0) > 190
          && channel(x, y, 1) > 190
          && channel(x, y, 2) > 190) {
          centerBrightPixels += 1;
        }
      }
    }

    return {
      width: surface.width,
      height: surface.height,
      captureWidth: width,
      captureHeight: height,
      frameHash,
      paddleCenter: paddleMax >= paddleMin
        ? ((paddleMin + paddleMax) / 2) / scaleX
        : null,
      paddlePixels: Math.round(paddlePixels / areaScale),
      brickPixels: Math.round(brickPixels / areaScale),
      hudHash: (hudHash >>> 0).toString(16).padStart(8, "0"),
      centerBrightPixels: Math.round(centerBrightPixels / areaScale),
    };
}

async function boot(context, label) {
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(`${label} page: ${error.message}`));
  page.on("requestfailed", (request) =>
    errors.push(`${label} request: ${request.url()} ${request.failure()?.errorText ?? "failed"}`));
  const response = await page.goto(deployedUrl, { waitUntil: "domcontentloaded", timeout: 30_000 });
  assert(response?.ok(), `${label}: deployed URL returned ${response?.status() ?? "no response"}`);
  await page.waitForFunction(() => {
    const canvas = document.querySelector("#canvas");
    const loader = document.querySelector("#loading");
    return canvas instanceof HTMLCanvasElement
      && canvas.style.visibility === "visible"
      && loader?.classList.contains("hidden");
  }, undefined, { timeout: 30_000 });
  await page.waitForTimeout(250);
  const state = await readCanvasState(page);
  assert(state.width === 800 && state.height === 600,
    `${label}: expected an 800x600 LÖVE surface, got ${state.width}x${state.height}`);
  assert(state.brickPixels > 35_000, `${label}: brick field did not render: ${state.brickPixels}`);
  assert(state.paddlePixels > 900 && state.paddleCenter !== null,
    `${label}: paddle did not render: ${JSON.stringify(state)}`);
  return {
    page,
    errors,
    response: {
      status: response.status(),
      etag: response.headers()["etag"] ?? null,
      lastModified: response.headers()["last-modified"] ?? null,
    },
    initial: state,
  };
}

async function sha256(file) {
  return createHash("sha256").update(await readFile(file)).digest("hex");
}

let browser;
try {
  await mkdir(evidenceRoot, { recursive: true });
  browser = await chromium.launch({ headless: true });

  const phoneContext = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 1,
    hasTouch: true,
    isMobile: true,
  });
  const phone = await boot(phoneContext, "phone");
  await phone.page.screenshot({ path: path.join(evidenceRoot, "phone-render.png") });

  // Park the paddle left. The deterministic opening shot hits a brick on its
  // first ascent, then misses the left-parked paddle and reaches loss.
  await phone.page.keyboard.down("ArrowLeft");
  await phone.page.waitForTimeout(850);
  await phone.page.keyboard.up("ArrowLeft");
  const parked = await readCanvasState(phone.page);
  assert(parked.paddleCenter < 80,
    `phone: could not park the paddle for the loss journey: ${parked.paddleCenter}`);
  const collided = await waitForState(
    phone.page,
    "phone: no deployed brick collision/score change",
    (state) => state.brickPixels < phone.initial.brickPixels - 900
      && state.hudHash !== phone.initial.hudHash,
    10_000,
  );
  await phone.page.screenshot({ path: path.join(evidenceRoot, "phone-scored.png") });

  let priorLossFrame;
  let stableLossFrames = 0;
  const lost = await waitForState(
    phone.page,
    "phone: deployed journey did not reach loss",
    (state) => {
      if (state.centerBrightPixels < 100) {
        priorLossFrame = state.frameHash;
        stableLossFrames = 0;
        return false;
      }
      stableLossFrames = state.frameHash === priorLossFrame ? stableLossFrames + 1 : 0;
      priorLossFrame = state.frameHash;
      return stableLossFrames >= 3;
    },
    10_000,
  );
  await phone.page.screenshot({ path: path.join(evidenceRoot, "phone-loss.png") });
  assert(phone.errors.length === 0, phone.errors.join("\n"));
  await phoneContext.close();

  const desktopContext = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 1,
  });
  const desktop = await boot(desktopContext, "desktop");
  await desktop.page.keyboard.down("ArrowLeft");
  await desktop.page.waitForTimeout(350);
  await desktop.page.keyboard.up("ArrowLeft");
  const keyboardLeft = await readCanvasState(desktop.page);
  await desktop.page.keyboard.down("ArrowRight");
  await desktop.page.waitForTimeout(650);
  await desktop.page.keyboard.up("ArrowRight");
  const keyboardRight = await readCanvasState(desktop.page);
  assert(keyboardLeft.paddleCenter < desktop.initial.paddleCenter - 80,
    `desktop: ArrowLeft did not move paddle: ${desktop.initial.paddleCenter} -> ${keyboardLeft.paddleCenter}`);
  assert(keyboardRight.paddleCenter > keyboardLeft.paddleCenter + 160,
    `desktop: ArrowRight did not move paddle: ${keyboardLeft.paddleCenter} -> ${keyboardRight.paddleCenter}`);
  await desktop.page.screenshot({ path: path.join(evidenceRoot, "desktop-keyboard.png") });
  assert(desktop.errors.length === 0, desktop.errors.join("\n"));
  await desktopContext.close();

  const screenshotNames = [
    "desktop-keyboard.png",
    "phone-loss.png",
    "phone-render.png",
    "phone-scored.png",
  ];
  const screenshotHashes = Object.fromEntries(await Promise.all(
    screenshotNames.map(async (name) => [name, await sha256(path.join(evidenceRoot, name))]),
  ));
  const sourceCommit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
  const sourceTree = execFileSync("git", ["rev-parse", "HEAD^{tree}"], { cwd: root, encoding: "utf8" }).trim();
  const evidence = {
    schema: "callack-deployed-spike-v1",
    sourceCommit,
    sourceTree,
    deployedUrl,
    browser: await browser.version(),
    response: phone.response,
    phone390x844: {
      initial: phone.initial,
      paddleParked: parked,
      collisionAndScore: collided,
      loss: lost,
    },
    desktop1280x800: {
      initial: desktop.initial,
      keyboardLeft,
      keyboardRight,
    },
    screenshotHashes,
  };
  await writeFile(
    path.join(evidenceRoot, "evidence.json"),
    `${JSON.stringify(evidence, null, 2)}\n`,
  );
  console.log(
    `[deployed-spike] OK: 390x844 render + brick collision + score change + loss; `
      + `desktop Left/Right at ${deployedUrl}`,
  );
} finally {
  if (browser) await browser.close();
}
