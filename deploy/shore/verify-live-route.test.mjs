import assert from "node:assert/strict";
import test from "node:test";
import {
  assertMatchingReplayFrames,
  assertSupportedReplayTranscript,
  createActionObserver,
  drivePlayerInteraction,
  parseActionMessage,
} from "./verify-live-route.mjs";

const action = (name, seed, phase) =>
  `CALLACK_ACTION ${name} seed=${seed} phase=${phase}`;
const nextTurn = () => new Promise((resolve) => setImmediate(resolve));

function observerAt(phase, seed = 9125) {
  const observer = createActionObserver();
  observer.observe(action(`phase_${phase}`, seed, phase));
  return observer;
}

const supportedTranscript = [
  action("phase_setup", 9125, "setup"),
  action("ready", 9125, "setup"),
  action("phase_battle", 9125, "battle"),
  action("lock_setup", 9125, "battle"),
  action("battle_speed", 9125, "battle"),
  action("phase_draft", 9125, "draft"),
  action("offer:first", 9125, "draft"),
  action("select:first", 9125, "draft"),
  action("phase_setup", 9125, "setup"),
  action("confirm_offer", 9125, "setup"),
  action("phase_battle", 9125, "battle"),
  action("lock_setup", 9125, "battle"),
  action("battle_speed", 9125, "battle"),
  action("phase_draft", 9125, "draft"),
  action("offer:second", 9125, "draft"),
  action("select:second", 9125, "draft"),
  action("phase_setup", 9125, "setup"),
  action("confirm_offer", 9125, "setup"),
  action("phase_battle", 9125, "battle"),
  action("lock_setup", 9125, "battle"),
  action("battle_speed", 9125, "battle"),
  action("phase_result", 9125, "result"),
  action("phase_replay", 9125, "replay"),
  action("replay_battle", 9125, "replay"),
  action("phase_result", 9125, "result"),
  action("replay_close", 9125, "result"),
  action("phase_replay", 9125, "replay"),
  action("replay_battle", 9125, "replay"),
  action("phase_result", 9125, "result"),
  action("replay_close", 9125, "result"),
  action("phase_setup", 9126, "setup"),
  action("new_run", 9126, "setup"),
];

test("accepts the supported three-fight, repeated-replay, new-run transcript", () => {
  assert.equal(assertSupportedReplayTranscript(supportedTranscript).length,
    supportedTranscript.length);
  assert.deepEqual(parseActionMessage(supportedTranscript.at(-1)), {
    action: "new_run",
    seed: 9126,
    phase: "setup",
    text: supportedTranscript.at(-1),
  });
});

test("rejects the stale boot-to-result shortcut that missed on setup", () => {
  const staleTranscript = [
    action("phase_setup", 9125, "setup"),
    action("ready", 9125, "setup"),
  ];
  assert.throws(
    () => assertSupportedReplayTranscript(staleTranscript),
    /expected 3 lock_setup action\(s\), got 0/,
  );
});

test("rejects a replay that changes seed", () => {
  const wrongSeed = [...supportedTranscript];
  const index = wrongSeed.lastIndexOf(action("replay_battle", 9125, "replay"));
  wrongSeed[index] = action("replay_battle", 9126, "replay");
  assert.throws(
    () => assertSupportedReplayTranscript(wrongSeed),
    /missing the repeated seed-9125 replay/,
  );
  assert.equal(assertSupportedReplayTranscript(supportedTranscript).length,
    supportedTranscript.length);
});

test("rejects missing replay state, replay action, and setup/result phase confusion", () => {
  const missingState = supportedTranscript.filter((entry) =>
    entry !== action("phase_replay", 9125, "replay"));
  assert.throws(
    () => assertSupportedReplayTranscript(missingState),
    /expected 2 phase_replay action\(s\), got 0/,
  );

  const missedClose = [...supportedTranscript];
  missedClose.splice(missedClose.indexOf(action("replay_close", 9125, "result")), 1);
  assert.throws(
    () => assertSupportedReplayTranscript(missedClose),
    /expected 2 replay_close action\(s\), got 1/,
  );

  const confused = [...supportedTranscript];
  const resultIndex = confused.indexOf(action("phase_result", 9125, "result"));
  confused[resultIndex] = action("phase_setup", 9125, "setup");
  assert.throws(
    () => assertSupportedReplayTranscript(confused),
    /expected 3 phase_result action\(s\), got 2/,
  );

  assert.equal(assertSupportedReplayTranscript(supportedTranscript).length,
    supportedTranscript.length);
});

test("scopes rejected actions to their exact required interaction epoch", () => {
  const firstReplay = supportedTranscript.indexOf(action("replay_battle", 9125, "replay"));
  const firstClose = supportedTranscript.indexOf(action("replay_close", 9125, "result"));
  const postTransition = [
    ...supportedTranscript,
    action("rejected_replay_close", 9125, "result"),
  ];
  const replayEpochs = [
    { action: "replay_battle", startSequence: firstReplay - 1, endSequence: firstReplay + 1 },
    { action: "replay_close", startSequence: firstClose - 1, endSequence: firstClose + 1 },
  ];
  assert.equal(assertSupportedReplayTranscript(postTransition, {
    interactionEpochs: replayEpochs,
  }).length, postTransition.length);
  assert.throws(
    () => assertSupportedReplayTranscript(postTransition),
    /contains a rejected player action/,
  );

  const requiredRejection = [...supportedTranscript];
  requiredRejection.splice(
    firstReplay,
    0,
    action("rejected_replay_battle", 9125, "result"),
  );
  assert.throws(
    () => assertSupportedReplayTranscript(requiredRejection, {
      interactionEpochs: [{
        action: "replay_battle",
        startSequence: firstReplay,
        endSequence: firstReplay + 2,
      }],
    }),
    /contains a rejected player action/,
  );

  assert.equal(assertSupportedReplayTranscript(supportedTranscript).length,
    supportedTranscript.length);
});

test("recreates the rejected shared-coordinate replay toggle schedule", () => {
  const timeline = [];
  let phase = "result";
  const sharedReplayCoordinate = () => {
    if (phase === "result") {
      phase = "replay";
      timeline.push("phase_replay", "replay_battle");
    } else {
      phase = "result";
      timeline.push("phase_result", "replay_close");
    }
  };

  sharedReplayCoordinate(); // required open
  sharedReplayCoordinate(); // delayed duplicate closes the new replay
  const intendedCloseStart = timeline.length;
  sharedReplayCoordinate(); // intended close now reopens replay

  assert.equal(phase, "replay");
  assert.deepEqual(timeline.slice(intendedCloseStart), ["phase_replay", "replay_battle"]);
  assert(!timeline.slice(intendedCloseStart).includes("replay_close"));
});

test("immediate replay transitions send one open and one close with no stale click", async () => {
  const observer = observerAt("result");
  const sent = [];
  const opened = await drivePlayerInteraction({
    observer,
    action: "replay_battle",
    fromPhase: "result",
    actionPhase: "replay",
    transition: "replay",
    timeout: 100,
    retryInterval: 1,
    send: async () => {
      sent.push("replay_battle");
      observer.observe(action("phase_replay", 9125, "replay"));
      observer.observe(action("replay_battle", 9125, "replay"));
    },
  });
  const closed = await drivePlayerInteraction({
    observer,
    action: "replay_close",
    fromPhase: "replay",
    actionPhase: "result",
    transition: "result",
    timeout: 100,
    retryInterval: 1,
    send: async () => {
      sent.push("replay_close");
      observer.observe(action("phase_result", 9125, "result"));
      observer.observe(action("replay_close", 9125, "result"));
    },
  });

  assert.deepEqual(sent, ["replay_battle", "replay_close"]);
  assert.equal(opened.attempts, 1);
  assert.equal(closed.attempts, 1);
  assert.equal(observer.phase, "result");
});

test("delayed replay action stops retries at the observable phase transition", async () => {
  const observer = observerAt("result");
  const sent = [];
  const driven = drivePlayerInteraction({
    observer,
    action: "replay_battle",
    fromPhase: "result",
    actionPhase: "replay",
    transition: "replay",
    timeout: 500,
    retryInterval: 100,
    send: async () => sent.push("replay_battle"),
  });

  await nextTurn();
  observer.observe(action("phase_replay", 9125, "replay"));
  await nextTurn();
  assert.deepEqual(sent, ["replay_battle"]);
  observer.observe(action("replay_battle", 9125, "replay"));
  const epoch = await driven;
  assert.equal(epoch.attempts, 1);
  assert.deepEqual(sent, ["replay_battle"]);
});

test("delayed replay close emits no stale post-transition click", async () => {
  const observer = observerAt("replay");
  const sent = [];
  const driven = drivePlayerInteraction({
    observer,
    action: "replay_close",
    fromPhase: "replay",
    actionPhase: "result",
    transition: "result",
    timeout: 500,
    retryInterval: 100,
    send: async () => sent.push("replay_close"),
  });

  await nextTurn();
  observer.observe(action("phase_result", 9125, "result"));
  await nextTurn();
  assert.deepEqual(sent, ["replay_close"]);
  observer.observe(action("replay_close", 9125, "result"));
  const epoch = await driven;
  assert.equal(epoch.attempts, 1);
  assert.deepEqual(sent, ["replay_close"]);
});

test("a missed replay click retries only while replay_battle remains valid", async () => {
  const observer = observerAt("result");
  const sent = [];
  const epoch = await drivePlayerInteraction({
    observer,
    action: "replay_battle",
    fromPhase: "result",
    actionPhase: "replay",
    transition: "replay",
    timeout: 100,
    retryInterval: 1,
    send: async () => {
      sent.push("replay_battle");
      if (sent.length === 2) {
        observer.observe(action("phase_replay", 9125, "replay"));
        observer.observe(action("replay_battle", 9125, "replay"));
      }
    },
  });
  assert.equal(epoch.attempts, 2);
  assert.deepEqual(sent, ["replay_battle", "replay_battle"]);
});

test("a replay click that keeps missing fails without inventing a transition", async () => {
  const observer = observerAt("result");
  let sends = 0;
  await assert.rejects(
    drivePlayerInteraction({
      observer,
      action: "replay_battle",
      fromPhase: "result",
      actionPhase: "replay",
      transition: "replay",
      timeout: 20,
      retryInterval: 1,
      send: async () => { sends += 1; },
    }),
    /timed out driving replay_battle from phase=result/,
  );
  assert(sends > 1);
  assert.equal(observer.phase, "result");
});

test("missing replay state and missing post-transition replay action fail without stale sends", async () => {
  const wrongPhase = observerAt("setup");
  let wrongPhaseSends = 0;
  await assert.rejects(
    drivePlayerInteraction({
      observer: wrongPhase,
      action: "replay_battle",
      fromPhase: "result",
      actionPhase: "replay",
      transition: "replay",
      timeout: 20,
      retryInterval: 1,
      send: async () => { wrongPhaseSends += 1; },
    }),
    /is not valid in observed phase=setup/,
  );
  assert.equal(wrongPhaseSends, 0);

  const missingAction = observerAt("result");
  const sent = [];
  await assert.rejects(
    drivePlayerInteraction({
      observer: missingAction,
      action: "replay_battle",
      fromPhase: "result",
      actionPhase: "replay",
      transition: "replay",
      timeout: 20,
      retryInterval: 1,
      send: async () => {
        sent.push("replay_battle");
        missingAction.observe(action("phase_replay", 9125, "replay"));
      },
    }),
    /timed out driving replay_battle/,
  );
  assert.deepEqual(sent, ["replay_battle"]);
});

test("an unavailable required replay action fails in its interaction epoch", async () => {
  const observer = observerAt("result");
  await assert.rejects(
    drivePlayerInteraction({
      observer,
      action: "replay_battle",
      fromPhase: "result",
      actionPhase: "replay",
      transition: "replay",
      timeout: 100,
      retryInterval: 1,
      send: async () => {
        observer.observe(action("rejected_replay_battle", 9125, "result"));
      },
    }),
    /rejected during its required interaction epoch/,
  );
});

test("an unexpected result-to-setup transition fails before a stale retry", async () => {
  const observer = observerAt("result");
  let sends = 0;
  await assert.rejects(
    drivePlayerInteraction({
      observer,
      action: "replay_battle",
      fromPhase: "result",
      actionPhase: "replay",
      transition: "replay",
      timeout: 100,
      retryInterval: 1,
      send: async () => {
        sends += 1;
        observer.observe(action("phase_setup", 9125, "setup"));
      },
    }),
    /left phase=result for unexpected phase_setup/,
  );
  assert.equal(sends, 1);
});

test("requires byte-identical rendered replay frames", () => {
  const frame = Buffer.from("seed-9125-recorded-frame-1");
  assert.match(assertMatchingReplayFrames(frame, Buffer.from(frame)), /^[0-9a-f]{64}$/);
  assert.throws(
    () => assertMatchingReplayFrames(frame, Buffer.from("changed-frame")),
    /replay frame changed/,
  );
});
