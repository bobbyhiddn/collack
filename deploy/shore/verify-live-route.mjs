#!/usr/bin/env node

import { chromium } from "playwright";

const expectedViewport = { width: 390, height: 844 };
const routeUrl = process.env.CALLACK_URL ?? "http://127.0.0.1:7778/collack/";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

let browser;
const runtimeErrors = [];
const requestedAssets = [];

try {
  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: expectedViewport,
    deviceScaleFactor: 1,
    hasTouch: true,
    isMobile: true,
  });
  const page = await context.newPage();

  page.on("console", (message) => {
    if (message.type() === "error") runtimeErrors.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => runtimeErrors.push(`pageerror: ${error.message}`));
  page.on("requestfailed", (request) => {
    runtimeErrors.push(
      `requestfailed: ${request.url()} (${request.failure()?.errorText ?? "unknown"})`,
    );
  });
  page.on("request", (request) => requestedAssets.push(new URL(request.url()).pathname));

  const readyMessage = page.waitForEvent("console", {
    predicate: (message) => message.text().includes("CALLACK_ACTION ready seed=9125"),
    timeout: 60_000,
  });
  const response = await page.goto(routeUrl, {
    waitUntil: "networkidle",
    timeout: 60_000,
  });
  assert(response?.ok(), `route navigation returned HTTP ${response?.status() ?? "unknown"}`);
  await readyMessage;
  await page.waitForFunction(() => {
    const canvas = document.querySelector("#canvas");
    return canvas && getComputedStyle(canvas).visibility === "visible";
  }, null, { timeout: 60_000 });

  const canvas = page.locator("#canvas");
  const bounds = await canvas.boundingBox();
  assert(bounds, "#canvas has no visible bounding box");
  assert(
    Math.abs(bounds.x) < 0.5 && Math.abs(bounds.y) < 0.5,
    `#canvas is offset at ${bounds.x},${bounds.y}`,
  );
  assert(
    Math.abs(bounds.width - expectedViewport.width) < 0.5,
    `#canvas width is ${bounds.width}, expected ${expectedViewport.width}`,
  );
  assert(
    Math.abs(bounds.height - expectedViewport.height) < 0.5,
    `#canvas height is ${bounds.height}, expected ${expectedViewport.height}`,
  );

  const replayHandled = page.waitForEvent("console", {
    predicate: (message) => message.text().includes("CALLACK_ACTION replay seed=9125"),
    timeout: 10_000,
  });
  await page.mouse.click(bounds.x + 100, bounds.y + 810);
  await replayHandled;

  await page.waitForTimeout(1_100);
  const newSeedHandled = page.waitForEvent("console", {
    predicate: (message) => message.text().includes("CALLACK_ACTION new_seed seed=9126"),
    timeout: 10_000,
  });
  await page.touchscreen.tap(bounds.x + 290, bounds.y + 810);
  await newSeedHandled;
  await page.waitForFunction(() => document.title.includes("Seed 9126"), null, {
    timeout: 10_000,
  });

  const fixedRuntimeUrls = new Set([
    "/collack/game.js",
    "/collack/game.data",
    "/collack/love.js",
    "/collack/love.wasm",
  ]);
  assert(
    !requestedAssets.some((asset) => fixedRuntimeUrls.has(asset)),
    `browser requested a stale fixed runtime URL: ${requestedAssets.join(", ")}`,
  );
  assert(
    requestedAssets.some((asset) => /^\/collack\/game\.[0-9a-f]{16}\.js$/.test(asset)),
    "browser did not request a hashed game loader through Shore",
  );
  assert(
    requestedAssets.some((asset) => /^\/collack\/game\.[0-9a-f]{16}\.data$/.test(asset)),
    "browser did not request hashed game data through Shore",
  );
  assert(
    requestedAssets.some((asset) => /^\/collack\/love\.[0-9a-f]{16}\.js$/.test(asset)),
    "browser did not request a hashed LÖVE loader through Shore",
  );
  assert(
    requestedAssets.some((asset) => /^\/collack\/love\.[0-9a-f]{16}\.wasm$/.test(asset)),
    "browser did not request hashed WebAssembly through Shore",
  );
  assert(runtimeErrors.length === 0, runtimeErrors.join("\n"));

  console.log(
    `[shore-browser] OK: ${routeUrl} 390x844 boot; mouse replay; touch new seed; hashed runtime requests`,
  );
} finally {
  if (browser) await browser.close();
}
