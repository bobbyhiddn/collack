#!/usr/bin/env node

import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const webRoot = path.join(root, "dist", "web");
const expectedViewport = { width: 390, height: 844 };

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

try {
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  serverListening = true;
  const address = server.address();
  assert(address && typeof address !== "string", "static server did not bind a TCP port");

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
    runtimeErrors.push(`requestfailed: ${request.url()} (${request.failure()?.errorText ?? "unknown"})`);
  });
  page.on("request", (request) => requestedAssets.push(new URL(request.url()).pathname));

  const readyMessage = page.waitForEvent("console", {
    predicate: (message) => message.text().includes(
      "CALLACK_ACTION ready seed=9125 phase=draft"
    ),
    timeout: 60_000,
  });
  await page.goto(`http://127.0.0.1:${address.port}/`, {
    waitUntil: "networkidle",
    timeout: 60_000,
  });
  await readyMessage;
  await page.waitForFunction(() => {
    const canvas = document.querySelector("#canvas");
    return canvas && getComputedStyle(canvas).visibility === "visible";
  }, null, { timeout: 60_000 });

  const canvas = page.locator("#canvas");
  const bounds = await canvas.boundingBox();
  assert(bounds, "#canvas has no visible bounding box");
  assert(Math.abs(bounds.x) < 0.5 && Math.abs(bounds.y) < 0.5,
    `#canvas is offset at ${bounds.x},${bounds.y}`);
  assert(Math.abs(bounds.width - expectedViewport.width) < 0.5,
    `#canvas width is ${bounds.width}, expected ${expectedViewport.width}`);
  assert(Math.abs(bounds.height - expectedViewport.height) < 0.5,
    `#canvas height is ${bounds.height}, expected ${expectedViewport.height}`);

  const tapAction = async (x, y, action, timeout = 15_000) => {
    const handled = page.waitForEvent("console", {
      predicate: (message) => message.text().includes(`CALLACK_ACTION ${action}`),
      timeout,
    });
    await page.touchscreen.tap(bounds.x + x, bounds.y + y);
    await handled;
  };

  // Complete all nine inspect → select → confirm decisions through touch.
  for (let offer = 0; offer < 9; offer += 1) {
    await tapAction(195, 180, "offer:");
    await tapAction(195, 732, "select:");
    await tapAction(195, 800, "confirm_offer");
  }

  // Place the eight independently drafted bricks into legal cells.
  const bench = [
    [60, 386], [149, 386], [238, 386], [327, 386],
    [60, 446], [149, 446], [238, 446], [327, 446],
  ];
  const cells = [
    [44, 180], [93, 180], [142, 180], [191, 180],
    [240, 180], [289, 180], [338, 180], [44, 229],
  ];
  for (let index = 0; index < bench.length; index += 1) {
    await tapAction(bench[index][0], bench[index][1], "brick:");
    await tapAction(cells[index][0], cells[index][1], "cell:");
  }

  const resultReached = page.waitForEvent("console", {
    predicate: (message) => message.text().includes(
      "CALLACK_ACTION phase_result seed=9125 phase=result"
    ),
    timeout: 120_000,
  });
  await tapAction(195, 800, "lock_setup");
  await resultReached;

  await tapAction(103, 788, "replay_battle");
  await tapAction(103, 788, "replay_next");
  await tapAction(287, 788, "replay_close");
  await tapAction(287, 788, "new_run");

  // Synthetic mouse and touch use the same semantic action route.
  await page.waitForTimeout(1_100);
  const mouseHandled = page.waitForEvent("console", {
    predicate: (message) => message.text().includes(
      "CALLACK_ACTION offer:"
    ) && message.text().includes("seed=9126 phase=draft"),
    timeout: 15_000,
  });
  await page.mouse.click(bounds.x + 195, bounds.y + 180);
  await mouseHandled;

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
  assert(runtimeErrors.length === 0, runtimeErrors.join("\n"));

  console.log(
    "[web-browser] OK: 390x844 full touch run; canonical result/replay/new run; mouse parity; hashed runtime requests"
  );
} finally {
  if (browser) await browser.close();
  if (serverListening) {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}
