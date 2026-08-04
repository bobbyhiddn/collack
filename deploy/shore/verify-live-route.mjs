#!/usr/bin/env node

import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { chromium } from "playwright";

export const expectedViewport = { width: 390, height: 844 };
export const expectedSeed = 9125;
const nextSeed = expectedSeed + 1;
const battleTimeout = 180_000;
const actionTimeout = 20_000;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export function parseActionMessage(text) {
  const match = /^CALLACK_ACTION (\S+) seed=(\d+) phase=(\S+)$/.exec(text);
  if (!match) return null;
  return { action: match[1], seed: Number(match[2]), phase: match[3], text };
}

function actionCount(events, action) {
  return events.filter((event) => event.action === action).length;
}

function requiredEvent(events, start, label, predicate) {
  const offset = events.slice(start + 1).findIndex(predicate);
  assert(offset >= 0, `live replay transcript is missing ${label}`);
  return start + 1 + offset;
}

export function assertSupportedReplayTranscript(messages) {
  const events = messages.map((message) => {
    const event = typeof message === "string" ? parseActionMessage(message) : message;
    assert(event, `malformed CALLACK_ACTION transcript entry: ${message}`);
    return event;
  });
  assert(events.length > 0, "live replay transcript is empty");
  assert(!events.some((event) => event.action.startsWith("rejected_")),
    "live replay transcript contains a rejected player action");

  for (const [action, count] of [
    ["lock_setup", 3],
    ["confirm_offer", 2],
    ["phase_battle", 3],
    ["phase_draft", 2],
    ["phase_replay", 2],
    ["phase_result", 3],
    ["replay_battle", 2],
    ["replay_close", 2],
    ["new_run", 1],
  ]) {
    assert(actionCount(events, action) === count,
      `live replay transcript expected ${count} ${action} action(s), got ${actionCount(events, action)}`);
  }

  let cursor = -1;
  const require = (label, predicate) => {
    cursor = requiredEvent(events, cursor, label, predicate);
  };
  const exact = (action, seed, phase) => (event) =>
    event.action === action && event.seed === seed && event.phase === phase;
  const prefixed = (prefix, seed, phase) => (event) =>
    event.action.startsWith(prefix) && event.seed === seed && event.phase === phase;

  require("the seed-9125 setup boot", exact("ready", expectedSeed, "setup"));
  require("the first supported setup lock", exact("lock_setup", expectedSeed, "battle"));
  require("the first post-battle draft", exact("phase_draft", expectedSeed, "draft"));
  require("the first visible draft offer", prefixed("offer:", expectedSeed, "draft"));
  require("the first visible draft selection", prefixed("select:", expectedSeed, "draft"));
  require("the first reward confirmation", exact("confirm_offer", expectedSeed, "setup"));
  require("the second supported setup lock", exact("lock_setup", expectedSeed, "battle"));
  require("the second post-battle draft", exact("phase_draft", expectedSeed, "draft"));
  require("the second visible draft offer", prefixed("offer:", expectedSeed, "draft"));
  require("the second visible draft selection", prefixed("select:", expectedSeed, "draft"));
  require("the second reward confirmation", exact("confirm_offer", expectedSeed, "setup"));
  require("the terminal supported setup lock", exact("lock_setup", expectedSeed, "battle"));
  require("the terminal result", exact("phase_result", expectedSeed, "result"));
  require("the first seed-9125 replay", exact("replay_battle", expectedSeed, "replay"));
  require("the first replay return", exact("replay_close", expectedSeed, "result"));
  require("the repeated seed-9125 replay", exact("replay_battle", expectedSeed, "replay"));
  require("the repeated replay return", exact("replay_close", expectedSeed, "result"));
  require("the supported seed-9126 new run", exact("new_run", nextSeed, "setup"));
  return events;
}

export function assertMatchingReplayFrames(first, second) {
  assert(first?.byteLength > 0 && second?.byteLength > 0,
    "live replay did not produce two rendered frames");
  const firstHash = createHash("sha256").update(first).digest("hex");
  const secondHash = createHash("sha256").update(second).digest("hex");
  assert(firstHash === secondHash,
    `seed ${expectedSeed} replay frame changed: ${firstHash} != ${secondHash}`);
  return firstHash;
}

function actionMatches(actual, expected) {
  return expected.endsWith(":") ? actual.startsWith(expected) : actual === expected;
}

async function waitForAction(page, expected, {
  seed = expectedSeed,
  phase,
  timeout = actionTimeout,
} = {}) {
  try {
    const message = await page.waitForEvent("console", {
      predicate: (candidate) => {
        const event = parseActionMessage(candidate.text());
        return event
          && actionMatches(event.action, expected)
          && event.seed === seed
          && (!phase || event.phase === phase);
      },
      timeout,
    });
    return parseActionMessage(message.text());
  } catch (error) {
    const title = await page.title().catch(() => "unavailable");
    throw new Error(
      `timed out waiting for ${expected} seed=${seed}${phase ? ` phase=${phase}` : ""}; title=${title}`,
      { cause: error },
    );
  }
}

async function settleRuntime(page) {
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
}

async function touchAction(runtime, x, y, action, {
  seed = expectedSeed,
  phase,
  transition,
  timeout = actionTimeout,
} = {}) {
  const handled = waitForAction(runtime.page, action, { seed, phase, timeout });
  const transitioned = transition
    ? waitForAction(runtime.page, `phase_${transition}`, {
        seed,
        phase: transition,
        timeout,
      })
    : null;
  await runtime.page.touchscreen.tap(runtime.bounds.x + x, runtime.bounds.y + y);
  await settleRuntime(runtime.page);
  const [event] = await Promise.all([handled, transitioned].filter(Boolean));
  return event;
}

async function completeSupportedRun(runtime) {
  await touchAction(runtime, 59, 548, "marble:", { phase: "setup" });
  await touchAction(runtime, 350, 608, "slot:tail", { phase: "setup" });
  await touchAction(runtime, 148, 548, "marble:", { phase: "setup" });
  await touchAction(runtime, 40, 608, "slot:", { phase: "setup" });
  const bench = [[60, 386], [149, 386], [238, 386]];
  const cells = [[93, 180], [191, 180], [289, 180]];
  for (let index = 0; index < bench.length; index += 1) {
    await touchAction(runtime, bench[index][0], bench[index][1], "brick:", { phase: "setup" });
    await touchAction(runtime, cells[index][0], cells[index][1], "cell:", { phase: "setup" });
  }

  const firstDraft = waitForAction(runtime.page, "phase_draft", {
    phase: "draft",
    timeout: battleTimeout,
  });
  await touchAction(runtime, 195, 800, "lock_setup", {
    phase: "battle",
    transition: "battle",
  });
  await touchAction(runtime, 147, 796, "battle_speed", { phase: "battle" });
  await firstDraft;

  await touchAction(runtime, 195, 180, "offer:", { phase: "draft" });
  await touchAction(runtime, 195, 732, "select:", { phase: "draft" });
  await touchAction(runtime, 195, 800, "confirm_offer", {
    phase: "setup",
    transition: "setup",
  });

  const secondDraft = waitForAction(runtime.page, "phase_draft", {
    phase: "draft",
    timeout: battleTimeout,
  });
  await touchAction(runtime, 195, 800, "lock_setup", {
    phase: "battle",
    transition: "battle",
  });
  await touchAction(runtime, 147, 796, "battle_speed", { phase: "battle" });
  await secondDraft;

  await touchAction(runtime, 195, 180, "offer:", { phase: "draft" });
  await touchAction(runtime, 195, 732, "select:", { phase: "draft" });
  await touchAction(runtime, 195, 800, "confirm_offer", {
    phase: "setup",
    transition: "setup",
  });
  await touchAction(runtime, 238, 386, "brick:", { phase: "setup" });
  await touchAction(runtime, 191, 180, "cell:", { phase: "setup" });

  const result = waitForAction(runtime.page, "phase_result", {
    phase: "result",
    timeout: battleTimeout,
  });
  await touchAction(runtime, 195, 800, "lock_setup", {
    phase: "battle",
    transition: "battle",
  });
  await touchAction(runtime, 147, 796, "battle_speed", { phase: "battle" });
  await result;
  await runtime.page.waitForFunction(() => document.title.includes("RESULT"));

  await touchAction(runtime, 287, 788, "replay_battle", {
    phase: "replay",
    transition: "replay",
  });
  // This is the same result-to-replay interaction settle used by the canonical
  // packaged-browser flow. It lets the visible 420 ms result motion finish;
  // battle completion still has its independent, state-based timeout above.
  await runtime.page.waitForTimeout(450);
  const firstReplayFrame = await runtime.canvas.screenshot();
  await touchAction(runtime, 287, 788, "replay_close", {
    phase: "result",
    transition: "result",
  });
  await runtime.page.waitForTimeout(1_000);

  await touchAction(runtime, 287, 788, "replay_battle", {
    phase: "replay",
    transition: "replay",
  });
  await runtime.page.waitForTimeout(450);
  const secondReplayFrame = await runtime.canvas.screenshot();
  const replayHash = assertMatchingReplayFrames(firstReplayFrame, secondReplayFrame);
  await touchAction(runtime, 287, 788, "replay_close", {
    phase: "result",
    transition: "result",
  });
  await runtime.page.waitForTimeout(1_000);

  await touchAction(runtime, 195, 720, "new_run", {
    seed: nextSeed,
    phase: "setup",
    transition: "setup",
  });
  await runtime.page.waitForFunction(
    (seed) => document.title.includes("SETUP") && document.title.includes(`Seed ${seed}`),
    nextSeed,
    { timeout: actionTimeout },
  );
  return replayHash;
}

function escapedRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export async function verifyLiveRoute({
  routeUrl = process.env.CALLACK_URL ?? "http://127.0.0.1:7778/collack/",
  browserType = chromium,
} = {}) {
  const route = new URL(routeUrl);
  const routePath = route.pathname.endsWith("/") ? route.pathname : `${route.pathname}/`;
  const runtimePattern = new RegExp(
    `^${escapedRegExp(routePath)}(?:game|love)\\.[0-9a-f]{16}\\.(?:js|data|wasm)$`,
  );
  const actionMessages = [];
  const runtimeErrors = [];
  const requestedAssets = [];
  const runtimeResponses = [];
  let browser;

  try {
    browser = await browserType.launch({ headless: true });
    const context = await browser.newContext({
      viewport: expectedViewport,
      deviceScaleFactor: 1,
      hasTouch: true,
      isMobile: true,
    });
    const page = await context.newPage();

    page.on("console", (message) => {
      const text = message.text();
      if (text.startsWith("CALLACK_ACTION ")) actionMessages.push(text);
      if (message.type() === "error") runtimeErrors.push(`console: ${text}`);
    });
    page.on("pageerror", (error) => runtimeErrors.push(`pageerror: ${error.message}`));
    page.on("requestfailed", (request) => {
      runtimeErrors.push(
        `requestfailed: ${request.url()} (${request.failure()?.errorText ?? "unknown"})`,
      );
    });
    page.on("request", (request) => requestedAssets.push(new URL(request.url()).pathname));
    page.on("response", (response) => {
      const pathname = new URL(response.url()).pathname;
      if (response.status() >= 400) {
        runtimeErrors.push(`response: ${response.status()} ${response.url()}`);
      }
      if (runtimePattern.test(pathname)) {
        runtimeResponses.push(response.body().then((body) => ({
          pathname,
          bytes: body.byteLength,
          sha256: createHash("sha256").update(body).digest("hex"),
        })));
      }
    });

    const ready = waitForAction(page, "ready", {
      seed: expectedSeed,
      phase: "setup",
      timeout: 60_000,
    });
    const response = await page.goto(routeUrl, {
      waitUntil: "networkidle",
      timeout: 60_000,
    });
    assert(response?.ok(), `route navigation returned HTTP ${response?.status() ?? "unknown"}`);
    await ready;
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

    const replayHash = await completeSupportedRun({ page, canvas, bounds });
    const transcript = assertSupportedReplayTranscript(actionMessages);

    const fixedRuntimeUrls = new Set([
      `${routePath}game.js`,
      `${routePath}game.data`,
      `${routePath}love.js`,
      `${routePath}love.wasm`,
    ]);
    assert(
      !requestedAssets.some((asset) => fixedRuntimeUrls.has(asset)),
      `browser requested a stale fixed runtime URL: ${requestedAssets.join(", ")}`,
    );
    for (const [label, extension] of [
      ["game loader", "game\\.[0-9a-f]{16}\\.js"],
      ["game data", "game\\.[0-9a-f]{16}\\.data"],
      ["LÖVE loader", "love\\.[0-9a-f]{16}\\.js"],
      ["WebAssembly", "love\\.[0-9a-f]{16}\\.wasm"],
    ]) {
      const pattern = new RegExp(`^${escapedRegExp(routePath)}${extension}$`);
      assert(requestedAssets.some((asset) => pattern.test(asset)),
        `browser did not request hashed ${label} through Shore`);
    }

    const identities = await Promise.all(runtimeResponses);
    assert(identities.length === 4,
      `browser received ${identities.length} hashed runtime assets, expected 4`);
    for (const identity of identities) {
      const embedded = identity.pathname.match(/\.([0-9a-f]{16})\.(?:js|data|wasm)$/)?.[1];
      assert(embedded === identity.sha256.slice(0, 16),
        `served asset identity mismatch for ${identity.pathname}: ${identity.sha256}`);
    }
    assert(runtimeErrors.length === 0, runtimeErrors.join("\n"));

    console.log(
      `[shore-browser] OK: ${routeUrl} normal 390x844 touch flow; `
        + `three battles and two drafts; seed ${expectedSeed} replayed twice at frame `
        + `${replayHash}; new run seed ${nextSeed}; ${identities.length} hashed runtime assets`,
    );
    return { replayHash, transcript, identities };
  } finally {
    if (browser) await browser.close();
  }
}

const directRun = process.argv[1]
  && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (directRun) {
  try {
    await verifyLiveRoute();
  } catch (error) {
    console.error(`[shore-browser] FAIL: ${error.stack ?? error}`);
    process.exitCode = 1;
  }
}
