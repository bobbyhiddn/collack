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
const interactionRetryInterval = 125;

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

export function assertSupportedReplayTranscript(messages, { interactionEpochs = null } = {}) {
  const events = messages.map((message, sequence) => {
    const event = typeof message === "string" ? parseActionMessage(message) : message;
    assert(event, `malformed CALLACK_ACTION transcript entry: ${message}`);
    return {
      ...event,
      sequence: Number.isInteger(event.sequence) ? event.sequence : sequence,
    };
  });
  assert(events.length > 0, "live replay transcript is empty");
  const rejectedInRequiredEpoch = (event) => {
    if (!event.action.startsWith("rejected_")) return false;
    if (interactionEpochs === null) return true;
    const rejectedAction = event.action.slice("rejected_".length);
    return interactionEpochs.some((epoch) =>
      event.sequence >= epoch.startSequence
        && event.sequence < epoch.endSequence
        && actionMatches(rejectedAction, epoch.action));
  };
  assert(!events.some(rejectedInRequiredEpoch),
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

function rejectedActionMatches(actual, expected) {
  return actual.startsWith("rejected_")
    && actionMatches(actual.slice("rejected_".length), expected);
}

export function createActionObserver() {
  const events = [];
  const waiters = new Set();
  let phase = null;
  let seed = null;

  return {
    events,
    get length() {
      return events.length;
    },
    get phase() {
      return phase;
    },
    get seed() {
      return seed;
    },
    observe(message) {
      const parsed = typeof message === "string" ? parseActionMessage(message) : message;
      if (!parsed) return null;
      const event = { ...parsed, sequence: events.length };
      events.push(event);
      if (event.action === "ready" || event.action.startsWith("phase_")) {
        phase = event.phase;
        seed = event.seed;
      }
      for (const wake of [...waiters]) wake(true);
      return event;
    },
    waitForChange(after, timeout) {
      if (events.length > after) return Promise.resolve(true);
      return new Promise((resolve) => {
        let timer;
        const wake = (changed) => {
          clearTimeout(timer);
          waiters.delete(wake);
          resolve(changed);
        };
        waiters.add(wake);
        timer = setTimeout(() => wake(false), timeout);
      });
    },
  };
}

async function waitForObservedAction(observer, expected, {
  seed = expectedSeed,
  phase,
  after = observer.length,
  timeout = actionTimeout,
} = {}) {
  const deadline = Date.now() + timeout;
  let cursor = after;
  while (Date.now() < deadline) {
    for (const event of observer.events.slice(cursor)) {
      if (actionMatches(event.action, expected)
        && event.seed === seed
        && (!phase || event.phase === phase)) return event;
    }
    cursor = observer.length;
    const remaining = deadline - Date.now();
    if (remaining <= 0 || !await observer.waitForChange(cursor, remaining)) break;
  }
  throw new Error(
    `timed out waiting for ${expected} seed=${seed}${phase ? ` phase=${phase}` : ""}; `
      + `observed phase=${observer.phase ?? "none"} seed=${observer.seed ?? "none"}`,
  );
}

async function settleRuntime(page) {
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
}

export async function drivePlayerInteraction({
  observer,
  send,
  settle = async () => {},
  action,
  fromPhase,
  fromSeed = expectedSeed,
  seed = expectedSeed,
  actionPhase = fromPhase,
  transition,
  retryInterval = interactionRetryInterval,
  timeout = actionTimeout,
}) {
  assert(observer.phase === fromPhase && observer.seed === fromSeed,
    `${action} is not valid in observed phase=${observer.phase ?? "none"} `
      + `seed=${observer.seed ?? "none"}; expected phase=${fromPhase} seed=${fromSeed}`);

  const startSequence = observer.length;
  const deadline = Date.now() + timeout;
  let cursor = startSequence;
  let accepted = null;
  let transitioned = transition ? null : true;
  let attempts = 0;
  let phaseDeparted = false;

  while (Date.now() < deadline) {
    for (const event of observer.events.slice(cursor)) {
      cursor = event.sequence + 1;
      if (event.action.startsWith("phase_")
        && (event.phase !== fromPhase || event.seed !== fromSeed)) {
        phaseDeparted = true;
        if (transition
          && event.action === `phase_${transition}`
          && event.phase === transition
          && event.seed === seed) {
          transitioned = event;
        } else {
          throw new Error(
            `${action} left phase=${fromPhase} for unexpected ${event.action} `
              + `seed=${event.seed} phase=${event.phase}`,
          );
        }
      }
      if (rejectedActionMatches(event.action, action)) {
        throw new Error(
          `${action} was rejected during its required interaction epoch `
            + `(seed=${event.seed} phase=${event.phase})`,
        );
      }
      if (actionMatches(event.action, action)
        && event.seed === seed
        && event.phase === actionPhase) {
        accepted = event;
      }
      if (accepted && transitioned) {
        return {
          action,
          attempts,
          event: accepted,
          startSequence,
          endSequence: event.sequence + 1,
        };
      }
    }

    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    if (accepted || phaseDeparted) {
      if (!await observer.waitForChange(cursor, remaining)) break;
      continue;
    }

    // No asynchronous observer callback can run between this state check and
    // starting the interaction. Once a phase event arrives, later attempts
    // are cancelled even if the accepted action message is still in flight.
    if (observer.phase !== fromPhase || observer.seed !== fromSeed) {
      phaseDeparted = true;
      continue;
    }
    attempts += 1;
    await send();
    await settle();
    const retryWait = Math.min(retryInterval, Math.max(0, deadline - Date.now()));
    if (retryWait > 0) await observer.waitForChange(cursor, retryWait);
  }

  const timeline = observer.events.slice(startSequence)
    .map((event) => `${event.action}@${event.phase}:${event.seed}`).join(", ");
  throw new Error(
    `timed out driving ${action} from phase=${fromPhase}; `
      + `observed phase=${observer.phase ?? "none"} seed=${observer.seed ?? "none"}; `
      + `epoch=[${timeline}]`,
  );
}

async function clickAction(runtime, x, y, action, options) {
  const epoch = await drivePlayerInteraction({
    observer: runtime.observer,
    // Use one ordinary pointer source. Chromium touchscreen taps can enqueue
    // a delayed synthetic mouse click after the canvas has changed phase.
    send: () => runtime.page.mouse.click(runtime.bounds.x + x, runtime.bounds.y + y),
    settle: () => settleRuntime(runtime.page),
    action,
    ...options,
  });
  runtime.interactionEpochs.push(epoch);
  return epoch.event;
}

async function waitForRenderedPhase(runtime, phase, seed = expectedSeed) {
  await runtime.page.waitForFunction(
    ({ expectedPhase, expectedSeedValue }) =>
      document.title.includes(expectedPhase.toUpperCase())
        && document.title.includes(`Seed ${expectedSeedValue}`),
    { expectedPhase: phase, expectedSeedValue: seed },
    { timeout: actionTimeout },
  );
  assert(runtime.observer.phase === phase && runtime.observer.seed === seed,
    `rendered ${phase}:${seed} disagrees with observed `
      + `${runtime.observer.phase ?? "none"}:${runtime.observer.seed ?? "none"}`);
  await settleRuntime(runtime.page);
}

async function captureStableReplayFrame(runtime) {
  await waitForRenderedPhase(runtime, "replay");
  const deadline = Date.now() + actionTimeout;
  let previous = null;
  let previousHash = null;
  while (Date.now() < deadline) {
    assert(runtime.observer.phase === "replay" && runtime.observer.seed === expectedSeed,
      "replay phase changed while waiting for a stable rendered frame");
    const frame = await runtime.canvas.screenshot();
    const hash = createHash("sha256").update(frame).digest("hex");
    if (hash === previousHash) return previous;
    previous = frame;
    previousHash = hash;
    await settleRuntime(runtime.page);
  }
  throw new Error("live replay frame did not become visually stable");
}

async function completeSupportedRun(runtime) {
  await clickAction(runtime, 59, 548, "marble:", { fromPhase: "setup" });
  await clickAction(runtime, 350, 608, "slot:tail", { fromPhase: "setup" });
  await clickAction(runtime, 148, 548, "marble:", { fromPhase: "setup" });
  await clickAction(runtime, 40, 608, "slot:", { fromPhase: "setup" });
  const bench = [[60, 386], [149, 386], [238, 386]];
  const cells = [[93, 180], [191, 180], [289, 180]];
  for (let index = 0; index < bench.length; index += 1) {
    await clickAction(runtime, bench[index][0], bench[index][1], "brick:", {
      fromPhase: "setup",
    });
    await clickAction(runtime, cells[index][0], cells[index][1], "cell:", {
      fromPhase: "setup",
    });
  }

  const firstBattleStart = runtime.observer.length;
  await clickAction(runtime, 195, 800, "lock_setup", {
    fromPhase: "setup",
    actionPhase: "battle",
    transition: "battle",
  });
  await clickAction(runtime, 147, 796, "battle_speed", { fromPhase: "battle" });
  await waitForObservedAction(runtime.observer, "phase_draft", {
    phase: "draft",
    after: firstBattleStart,
    timeout: battleTimeout,
  });

  await clickAction(runtime, 195, 180, "offer:", { fromPhase: "draft" });
  await clickAction(runtime, 195, 732, "select:", { fromPhase: "draft" });
  await clickAction(runtime, 195, 800, "confirm_offer", {
    fromPhase: "draft",
    actionPhase: "setup",
    transition: "setup",
  });

  const secondBattleStart = runtime.observer.length;
  await clickAction(runtime, 195, 800, "lock_setup", {
    fromPhase: "setup",
    actionPhase: "battle",
    transition: "battle",
  });
  await clickAction(runtime, 147, 796, "battle_speed", { fromPhase: "battle" });
  await waitForObservedAction(runtime.observer, "phase_draft", {
    phase: "draft",
    after: secondBattleStart,
    timeout: battleTimeout,
  });

  await clickAction(runtime, 195, 180, "offer:", { fromPhase: "draft" });
  await clickAction(runtime, 195, 732, "select:", { fromPhase: "draft" });
  await clickAction(runtime, 195, 800, "confirm_offer", {
    fromPhase: "draft",
    actionPhase: "setup",
    transition: "setup",
  });
  await clickAction(runtime, 238, 386, "brick:", { fromPhase: "setup" });
  await clickAction(runtime, 191, 180, "cell:", { fromPhase: "setup" });

  const terminalBattleStart = runtime.observer.length;
  await clickAction(runtime, 195, 800, "lock_setup", {
    fromPhase: "setup",
    actionPhase: "battle",
    transition: "battle",
  });
  await clickAction(runtime, 147, 796, "battle_speed", { fromPhase: "battle" });
  await waitForObservedAction(runtime.observer, "phase_result", {
    phase: "result",
    after: terminalBattleStart,
    timeout: battleTimeout,
  });
  await waitForRenderedPhase(runtime, "result");

  await clickAction(runtime, 287, 788, "replay_battle", {
    fromPhase: "result",
    actionPhase: "replay",
    transition: "replay",
  });
  const firstReplayFrame = await captureStableReplayFrame(runtime);
  await clickAction(runtime, 287, 788, "replay_close", {
    fromPhase: "replay",
    actionPhase: "result",
    transition: "result",
  });

  await clickAction(runtime, 287, 788, "replay_battle", {
    fromPhase: "result",
    actionPhase: "replay",
    transition: "replay",
  });
  const secondReplayFrame = await captureStableReplayFrame(runtime);
  const replayHash = assertMatchingReplayFrames(firstReplayFrame, secondReplayFrame);
  await clickAction(runtime, 287, 788, "replay_close", {
    fromPhase: "replay",
    actionPhase: "result",
    transition: "result",
  });

  await clickAction(runtime, 195, 720, "new_run", {
    fromPhase: "result",
    fromSeed: expectedSeed,
    seed: nextSeed,
    actionPhase: "setup",
    transition: "setup",
  });
  await waitForRenderedPhase(runtime, "setup", nextSeed);
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
  const actionObserver = createActionObserver();
  const interactionEpochs = [];
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
      actionObserver.observe(text);
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

    const ready = waitForObservedAction(actionObserver, "ready", {
      seed: expectedSeed,
      phase: "setup",
      after: 0,
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

    const replayHash = await completeSupportedRun({
      page,
      canvas,
      bounds,
      observer: actionObserver,
      interactionEpochs,
    });
    const transcript = assertSupportedReplayTranscript(actionObserver.events, {
      interactionEpochs,
    });

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
      `[shore-browser] OK: ${routeUrl} normal 390x844 player flow; `
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
