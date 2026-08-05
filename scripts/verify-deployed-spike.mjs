#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { PNG } from "pngjs";
import {
  assertExactManifestBytes,
  assertNavigationIdentity,
  buildManifestName,
  readBuildManifest,
  sha256 as bytesSha256,
  validateBuildManifest,
  validateLocalBuild,
  validateResponseRecords,
} from "./web-build-identity.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const evidenceRoot = path.join(root, "dist", "deployed-verification");
const deployedUrl = process.env.CALLACK_DEPLOYED_URL ?? "https://collack-spike.fly.dev/";
const expectedManifestPath = path.resolve(
  process.env.CALLACK_EXPECTED_BUILD_MANIFEST
    ?? path.join(root, "dist", "web", buildManifestName),
);
const identityReportOnly = process.env.CALLACK_IDENTITY_REPORT_ONLY === "1";
const callerClaims = {
  revision: process.env.CALLACK_TARGET_SOURCE_COMMIT ?? null,
  tree: process.env.CALLACK_TARGET_SOURCE_TREE ?? null,
  target: process.env.CALLACK_TARGET_NAME ?? null,
};

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
  const error = new Error(`${description}; last state: ${JSON.stringify(state)}`);
  error.lastState = state;
  throw error;
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

async function canvasPoint(page, logicalX, logicalY) {
  const canvas = page.locator("#canvas");
  const [box, surface] = await Promise.all([
    canvas.boundingBox(),
    canvas.evaluate((element) => ({ width: element.width, height: element.height })),
  ]);
  assert(box, "canvas does not have a browser-space bounding box");
  return {
    x: box.x + logicalX / surface.width * box.width,
    y: box.y + logicalY / surface.height * box.height,
  };
}

async function dragTouch(page, from, to, steps = 8) {
  const session = await page.context().newCDPSession(page);
  const point = (x, y) => ({
    x,
    y,
    id: 1,
    radiusX: 1,
    radiusY: 1,
    force: 1,
  });
  try {
    await session.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [point(from.x, from.y)],
    });
    for (let step = 1; step <= steps; step += 1) {
      const progress = step / steps;
      await session.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [point(
          from.x + (to.x - from.x) * progress,
          from.y + (to.y - from.y) * progress,
        )],
      });
      await page.waitForTimeout(25);
    }
    await session.send("Input.dispatchTouchEvent", {
      type: "touchEnd",
      touchPoints: [],
    });
  } finally {
    await session.detach();
  }
}

async function readInputEvidence(page) {
  return page.evaluate(() => window.__callackInputEvidence);
}

async function installInputEvidence(context) {
  await context.addInitScript(() => {
    const evidence = {
      keydown: 0,
      keyup: 0,
      touchstart: 0,
      touchmove: 0,
      touchend: 0,
      touchcancel: 0,
      trustedTouchstart: 0,
      trustedTouchmove: 0,
      trustedTouchend: 0,
      trustedTouchcancel: 0,
      touchTrace: [],
    };
    window.__callackInputEvidence = evidence;
    for (const type of ["keydown", "keyup"]) {
      window.addEventListener(type, () => { evidence[type] += 1; }, true);
    }
    for (const type of ["touchstart", "touchmove", "touchend", "touchcancel"]) {
      window.addEventListener(type, (event) => {
        evidence[type] += 1;
        if (event.isTrusted) {
          const key = `trusted${type[0].toUpperCase()}${type.slice(1)}`;
          evidence[key] += 1;
        }
        const touch = event.touches[0] ?? event.changedTouches[0];
        if (evidence.touchTrace.length < 24) {
          evidence.touchTrace.push({
            type,
            target: event.target?.id ?? event.target?.tagName ?? null,
            clientX: touch?.clientX ?? null,
            clientY: touch?.clientY ?? null,
            trusted: event.isTrusted,
          });
        }
      }, true);
    }
  });
}

function requestRedirects(request) {
  const redirects = [];
  let prior = request.redirectedFrom();
  while (prior) {
    redirects.unshift(prior.url());
    prior = prior.redirectedFrom();
  }
  return redirects;
}

async function responseRecord(response) {
  const request = response.request();
  let body;
  try {
    body = await response.body();
  } catch {
    body = Buffer.alloc(0);
  }
  return {
    requestUrl: request.url(),
    url: response.url(),
    redirects: requestRedirects(request),
    resourceType: request.resourceType(),
    method: request.method(),
    status: response.status(),
    etag: response.headers().etag ?? null,
    lastModified: response.headers()["last-modified"] ?? null,
    bytes: body.length,
    sha256: bytesSha256(body),
  };
}

function collectTargetResponses(page) {
  const targetOrigin = new URL(deployedUrl).origin;
  const pending = [];
  page.on("response", (response) => {
    if (new URL(response.url()).origin === targetOrigin) {
      pending.push(responseRecord(response));
    }
  });
  return async () => Promise.all(pending);
}

async function boot(context, label) {
  const page = await context.newPage();
  const collectedResponses = collectTargetResponses(page);
  const errors = [];
  page.on("pageerror", (error) => errors.push(`${label} page: ${error.message}`));
  page.on("requestfailed", (request) =>
    errors.push(`${label} request: ${request.url()} ${request.failure()?.errorText ?? "failed"}`));
  const response = await page.goto(deployedUrl, { waitUntil: "domcontentloaded", timeout: 30_000 });
  assert(response?.ok(), `${label}: deployed URL returned ${response?.status() ?? "no response"}`);
  const indexBody = await response.body();
  await page.waitForFunction(() => {
    const canvas = document.querySelector("#canvas");
    const loader = document.querySelector("#loading");
    return canvas instanceof HTMLCanvasElement
      && canvas.style.visibility === "visible"
      && loader?.classList.contains("hidden");
  }, undefined, { timeout: 30_000 });
  await page.waitForTimeout(250);
  const loadedResponses = await collectedResponses();
  const state = await readCanvasState(page);
  const viewport = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    devicePixelRatio: window.devicePixelRatio,
    visualWidth: window.visualViewport?.width ?? null,
    visualHeight: window.visualViewport?.height ?? null,
    visualScale: window.visualViewport?.scale ?? null,
  }));
  assert(state.width === 800 && state.height === 600,
    `${label}: expected an 800x600 LÖVE surface, got ${state.width}x${state.height}`);
  assert(state.brickPixels > 35_000, `${label}: brick field did not render: ${state.brickPixels}`);
  assert(state.paddlePixels > 900 && state.paddleCenter !== null,
    `${label}: paddle did not render: ${JSON.stringify(state)}`);
  return {
    page,
    errors,
    response: {
      requestedUrl: new URL(deployedUrl).href,
      url: response.url(),
      redirects: requestRedirects(response.request()),
      status: response.status(),
      etag: response.headers()["etag"] ?? null,
      lastModified: response.headers()["last-modified"] ?? null,
      bytes: indexBody.length,
      sha256: createHash("sha256").update(indexBody).digest("hex"),
    },
    loadedResponses,
    viewport,
    initial: state,
  };
}

async function fetchExact(page, url, resourceType) {
  const response = await page.context().request.get(url, {
    maxRedirects: 0,
    timeout: 30_000,
  });
  const body = await response.body();
  return {
    record: {
      requestUrl: url,
      url: response.url(),
      redirects: [],
      resourceType,
      method: "GET",
      status: response.status(),
      etag: response.headers().etag ?? null,
      lastModified: response.headers()["last-modified"] ?? null,
      bytes: body.length,
      sha256: bytesSha256(body),
    },
    body,
  };
}

async function verifyLoadedSession(booted, expectedManifest) {
  assertNavigationIdentity({
    requestedUrl: booted.response.requestedUrl,
    finalUrl: booted.response.url,
    redirects: booted.response.redirects,
  });
  return validateResponseRecords(
    expectedManifest,
    booted.loadedResponses,
    booted.response.url,
  );
}

async function verifyTargetIdentity(page, booted, expectedBuild) {
  const loaded = await verifyLoadedSession(booted, expectedBuild.manifest);
  const baseUrl = new URL("./", booted.response.url).href;
  const manifestUrl = new URL(buildManifestName, baseUrl).href;
  const servedManifest = await fetchExact(page, manifestUrl, "manifest");
  assert(servedManifest.record.status >= 200 && servedManifest.record.status < 300,
    `served build manifest is missing or failed with HTTP ${servedManifest.record.status}: ${manifestUrl}`);
  assert(servedManifest.record.requestUrl === servedManifest.record.url,
    `served build manifest redirected to unintended URL ${servedManifest.record.url}; requested ${manifestUrl}`);
  assertExactManifestBytes(expectedBuild.bytes, servedManifest.body);

  let parsedManifest;
  try {
    parsedManifest = JSON.parse(servedManifest.body.toString("utf8"));
  } catch (error) {
    throw new Error(`served build manifest is invalid JSON: ${error.message}`);
  }
  validateBuildManifest(parsedManifest, root, callerClaims);

  const verifiedAssets = [];
  for (const asset of expectedBuild.manifest.assets) {
    const assetUrl = new URL(asset.path, baseUrl).href;
    const fetched = await fetchExact(page, assetUrl, "verified-asset");
    verifiedAssets.push(fetched.record);
  }
  const complete = validateResponseRecords(
    expectedBuild.manifest,
    verifiedAssets,
    booted.response.url,
    { requireAll: true },
  );

  return {
    outcome: "PASS",
    derivedIdentity: {
      revision: expectedBuild.manifest.revision,
      tree: expectedBuild.manifest.tree,
      target: expectedBuild.manifest.target,
    },
    requestedUrl: booted.response.requestedUrl,
    finalUrl: booted.response.url,
    redirects: booted.response.redirects,
    expectedManifest: {
      path: expectedBuild.path,
      sha256: expectedBuild.sha256,
      bytes: expectedBuild.bytes.length,
      assetSetSha256: expectedBuild.manifest.assetSetSha256,
    },
    servedManifest: {
      url: manifestUrl,
      sha256: servedManifest.record.sha256,
      bytes: servedManifest.record.bytes,
      status: servedManifest.record.status,
    },
    loaded,
    completeAssetSet: complete,
  };
}

async function waitForLoss(page, label, timeout = 10_000) {
  let priorFrame;
  let stableFrames = 0;
  return waitForState(
    page,
    `${label}: deployed journey did not reach a stable loss`,
    (state) => {
      if (state.centerBrightPixels < 50) {
        priorFrame = state.frameHash;
        stableFrames = 0;
        return false;
      }
      stableFrames = state.frameHash === priorFrame ? stableFrames + 1 : 0;
      priorFrame = state.frameHash;
      return stableFrames >= 3;
    },
    timeout,
  );
}

async function sha256(file) {
  return createHash("sha256").update(await readFile(file)).digest("hex");
}

const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
const screenshotNames = [];
const evidence = {
  schema: "callack-deployed-spike-v3",
  outcome: "RUNNING",
  verifier: {
    commit: git("rev-parse", "HEAD"),
    tree: git("rev-parse", "HEAD^{tree}"),
    trackedStatus: git("status", "--porcelain", "--untracked-files=no"),
    scriptSha256: await sha256(fileURLToPath(import.meta.url)),
  },
  target: {
    requestedUrl: new URL(deployedUrl).href,
    expectedManifestPath,
    callerClaims,
    identityPolicy: identityReportOnly ? "report-only" : "strict",
  },
  viewport: {
    phone: { width: 390, height: 844, deviceScaleFactor: 1, hasTouch: true, isMobile: true },
    desktop: { width: 1280, height: 800, deviceScaleFactor: 1 },
  },
};

async function capture(page, name) {
  await page.screenshot({ path: path.join(evidenceRoot, name) });
  screenshotNames.push(name);
}

async function persistEvidence() {
  evidence.screenshotHashes = Object.fromEntries(await Promise.all(
    screenshotNames.map(async (name) => [name, await sha256(path.join(evidenceRoot, name))]),
  ));
  await writeFile(
    path.join(evidenceRoot, "evidence.json"),
    `${JSON.stringify(evidence, null, 2)}\n`,
  );
}

let browser;
let expectedBuild;
let identityFailure;
try {
  await mkdir(evidenceRoot, { recursive: true });
  expectedBuild = await readBuildManifest(expectedManifestPath, root, callerClaims);
  await validateLocalBuild(path.dirname(expectedManifestPath), expectedBuild.manifest);
  evidence.target.expectedBuild = {
    revision: expectedBuild.manifest.revision,
    tree: expectedBuild.manifest.tree,
    target: expectedBuild.manifest.target,
    manifestSha256: expectedBuild.sha256,
    assetSetSha256: expectedBuild.manifest.assetSetSha256,
    assetCount: expectedBuild.manifest.assets.length,
  };
  browser = await chromium.launch({ headless: true });
  evidence.browser = await browser.version();

  const phoneContext = await browser.newContext({
    viewport: {
      width: evidence.viewport.phone.width,
      height: evidence.viewport.phone.height,
    },
    deviceScaleFactor: evidence.viewport.phone.deviceScaleFactor,
    hasTouch: evidence.viewport.phone.hasTouch,
    isMobile: evidence.viewport.phone.isMobile,
  });
  await installInputEvidence(phoneContext);
  const phone = await boot(phoneContext, "phone");
  evidence.target.response = phone.response;
  evidence.target.loadedResponses = phone.loadedResponses;
  evidence.phone390x844 = {
    browserViewport: phone.viewport,
    initial: phone.initial,
    inputBefore: await readInputEvidence(phone.page),
  };
  assert(phone.viewport.innerWidth === 390 && phone.viewport.innerHeight === 844,
    `phone: expected observed 390x844 viewport, got ${JSON.stringify(phone.viewport)}`);
  try {
    evidence.target.identity = await verifyTargetIdentity(phone.page, phone, expectedBuild);
  } catch (error) {
    identityFailure = error;
    evidence.target.identity = {
      outcome: "FAIL",
      message: error instanceof Error ? error.message : String(error),
      requestedUrl: phone.response.requestedUrl,
      finalUrl: phone.response.url,
      redirects: phone.response.redirects,
      loaded: phone.loadedResponses,
    };
    if (!identityReportOnly) throw error;
  }
  evidence.target.identitySessions = [];
  const verifySessionIdentity = async (label, booted) => {
    try {
      const loaded = await verifyLoadedSession(booted, expectedBuild.manifest);
      evidence.target.identitySessions.push({ label, outcome: "PASS", loaded });
    } catch (error) {
      identityFailure ??= error;
      evidence.target.identitySessions.push({
        label,
        outcome: "FAIL",
        message: error instanceof Error ? error.message : String(error),
        response: booted.response,
        loaded: booted.loadedResponses,
      });
      if (!identityReportOnly) throw error;
    }
  };
  await capture(phone.page, "phone-render.png");

  // Use only the browser's touch stream on the phone path. Starting at the
  // visible paddle and dragging left parks it away from the opening shot.
  const dragFrom = await canvasPoint(phone.page, phone.initial.paddleCenter, 565);
  const dragTo = await canvasPoint(phone.page, 30, 565);
  await dragTouch(phone.page, dragFrom, dragTo, 1);
  const inputAfterDrag = await readInputEvidence(phone.page);
  evidence.phone390x844.touchDrag = {
    fromBrowserCss: dragFrom,
    toBrowserCss: dragTo,
    inputAfter: inputAfterDrag,
  };
  assert(inputAfterDrag.keydown === 0 && inputAfterDrag.keyup === 0,
    `phone: keyboard input leaked into touch drag: ${JSON.stringify(inputAfterDrag)}`);
  assert(inputAfterDrag.trustedTouchstart >= 1
      && inputAfterDrag.trustedTouchmove >= 1
      && inputAfterDrag.trustedTouchend >= 1,
  `phone: drag did not deliver a trusted touch sequence: ${JSON.stringify(inputAfterDrag)}`);
  const parked = await waitForState(
    phone.page,
    "phone: genuine touch drag did not park the paddle",
    (state) => state.paddleCenter !== null && state.paddleCenter < 80,
    3_000,
  );
  evidence.phone390x844.touchDrag.paddleParked = parked;

  const collided = await waitForState(
    phone.page,
    "phone: no deployed brick collision/score change",
    (state) => state.brickPixels < phone.initial.brickPixels - 900
      && state.hudHash !== phone.initial.hudHash,
    10_000,
  );
  evidence.phone390x844.collisionAndScore = collided;
  await capture(phone.page, "phone-scored.png");

  const lost = await waitForLoss(phone.page, "phone");
  evidence.phone390x844.loss = lost;
  await capture(phone.page, "phone-loss.png");

  const inputAtLoss = await readInputEvidence(phone.page);
  assert(inputAtLoss.keydown === 0 && inputAtLoss.keyup === 0,
    `phone: keyboard input occurred before retry: ${JSON.stringify(inputAtLoss)}`);
  const retryPoint = await canvasPoint(phone.page, 400, 300);
  evidence.phone390x844.retryTap = {
    browserCss: retryPoint,
    inputBefore: inputAtLoss,
  };
  await phone.page.touchscreen.tap(retryPoint.x, retryPoint.y);
  evidence.phone390x844.retryTap.inputAfter = await readInputEvidence(phone.page);
  assert(evidence.phone390x844.retryTap.inputAfter.keydown === 0
      && evidence.phone390x844.retryTap.inputAfter.keyup === 0,
  `phone: retry sent a keyboard event: ${JSON.stringify(evidence.phone390x844.retryTap.inputAfter)}`);
  assert(evidence.phone390x844.retryTap.inputAfter.trustedTouchstart
      > inputAtLoss.trustedTouchstart
      && evidence.phone390x844.retryTap.inputAfter.trustedTouchend
      > inputAtLoss.trustedTouchend,
  `phone: retry was not a trusted touch tap: ${JSON.stringify(evidence.phone390x844.retryTap)}`);

  const restarted = await waitForState(
    phone.page,
    "phone: genuine touch tap after proven loss did not begin a fresh round",
    (state) => state.centerBrightPixels < 50
      && state.brickPixels >= phone.initial.brickPixels - 100
      && state.hudHash === phone.initial.hudHash
      && state.frameHash !== lost.frameHash,
    3_000,
  );
  await phone.page.waitForTimeout(250);
  const restartedProgress = await readCanvasState(phone.page);
  assert(restartedProgress.frameHash !== restarted.frameHash,
    "phone: the fresh round did not resume moving state");
  evidence.phone390x844.freshRound = restarted;
  evidence.phone390x844.freshRoundProgressed = restartedProgress;
  await capture(phone.page, "phone-restarted.png");
  assert(phone.errors.length === 0, phone.errors.join("\n"));
  await phoneContext.close();

  const desktopContext = await browser.newContext({
    viewport: {
      width: evidence.viewport.desktop.width,
      height: evidence.viewport.desktop.height,
    },
    deviceScaleFactor: evidence.viewport.desktop.deviceScaleFactor,
  });
  const desktop = await boot(desktopContext, "desktop");
  await verifySessionIdentity("desktop", desktop);
  assert(desktop.viewport.innerWidth === 1280 && desktop.viewport.innerHeight === 800,
    `desktop: expected observed 1280x800 viewport, got ${JSON.stringify(desktop.viewport)}`);
  assert(desktop.response.sha256 === phone.response.sha256,
    "desktop and phone did not receive the same target index bytes");
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
  evidence.desktop1280x800 = {
    browserViewport: desktop.viewport,
    initial: desktop.initial,
    keyboardLeft,
    keyboardRight,
  };
  await capture(desktop.page, "desktop-keyboard.png");
  assert(desktop.errors.length === 0, desktop.errors.join("\n"));
  await desktopContext.close();

  const desktopRetryContext = await browser.newContext({
    viewport: {
      width: evidence.viewport.desktop.width,
      height: evidence.viewport.desktop.height,
    },
    deviceScaleFactor: evidence.viewport.desktop.deviceScaleFactor,
  });
  const desktopRetry = await boot(desktopRetryContext, "desktop-retry");
  await verifySessionIdentity("desktop-retry", desktopRetry);
  await desktopRetry.page.keyboard.down("ArrowLeft");
  await desktopRetry.page.waitForTimeout(850);
  await desktopRetry.page.keyboard.up("ArrowLeft");
  const desktopParked = await readCanvasState(desktopRetry.page);
  assert(desktopParked.paddleCenter < 80,
    `desktop: could not park paddle for SPACE retry: ${desktopParked.paddleCenter}`);
  const desktopLost = await waitForLoss(desktopRetry.page, "desktop-retry");
  await capture(desktopRetry.page, "desktop-loss.png");
  await desktopRetry.page.keyboard.press("Space");
  const desktopRestarted = await waitForState(
    desktopRetry.page,
    "desktop: SPACE after loss did not begin a fresh round",
    (state) => state.centerBrightPixels < 50
      && state.brickPixels >= desktopRetry.initial.brickPixels - 100
      && state.hudHash === desktopRetry.initial.hudHash
      && state.frameHash !== desktopLost.frameHash,
    3_000,
  );
  evidence.desktop1280x800.spaceRetry = {
    paddleParked: desktopParked,
    loss: desktopLost,
    freshRound: desktopRestarted,
  };
  await capture(desktopRetry.page, "desktop-restarted.png");
  assert(desktopRetry.errors.length === 0, desktopRetry.errors.join("\n"));
  await desktopRetryContext.close();

  if (identityFailure) {
    throw new Error(
      `target identity rejected after behavior-only observation: ${identityFailure.message}`,
    );
  }
  evidence.outcome = "PASS";
  await persistEvidence();
  console.log(
    `[deployed-spike] OK: trusted 390x844 touch drag + loss + touch retry; `
      + `desktop Left/Right + SPACE retry; exact target `
      + `${expectedBuild.manifest.revision}/${expectedBuild.manifest.tree} at ${deployedUrl}`,
  );
} catch (error) {
  evidence.outcome = "FAIL";
  evidence.failure = {
    message: error instanceof Error ? error.message : String(error),
    lastState: error?.lastState ?? null,
  };
  await persistEvidence();
  throw error;
} finally {
  if (browser) await browser.close();
}
