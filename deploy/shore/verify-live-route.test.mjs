import assert from "node:assert/strict";
import test from "node:test";
import {
  assertMatchingReplayFrames,
  assertSupportedReplayTranscript,
  parseActionMessage,
} from "./verify-live-route.mjs";

const action = (name, seed, phase) =>
  `CALLACK_ACTION ${name} seed=${seed} phase=${phase}`;

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
});

test("requires byte-identical rendered replay frames", () => {
  const frame = Buffer.from("seed-9125-recorded-frame-1");
  assert.match(assertMatchingReplayFrames(frame, Buffer.from(frame)), /^[0-9a-f]{64}$/);
  assert.throws(
    () => assertMatchingReplayFrames(frame, Buffer.from("changed-frame")),
    /replay frame changed/,
  );
});
