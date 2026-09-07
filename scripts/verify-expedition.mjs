#!/usr/bin/env node
// Exercise the actual player entry point: no canonical-verification flag,
// injected engine state, forced outcomes, or accelerated test clock.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createWebServer } from "./serve-web.mjs";

const output = fileURLToPath(new URL("../dist/expedition-verification/", import.meta.url));
const saveKey = "collack.expedition.v1";
const preferencesKey = "collack.preferences.v1";
const errors = [], checks = [];
const server = createWebServer();
let browser;
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const check = (value, label) => {
  assert(value, label); checks.push(label); console.log(`[expedition] ${label}`);
};

async function until(page, predicate, label, timeout = 180_000) {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeout) throw new Error(`Timed out: ${label}`);
    await page.waitForTimeout(50);
  }
}

async function boot(context, url) {
  const page = await context.newPage();
  const logs = [];
  page.on("console", (message) => {
    const line = message.text(); logs.push(line);
    if (message.type() === "error" && !line.includes("404")) errors.push(line);
  });
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url);
  await until(page, () => logs.some((line) => line.startsWith("CALLACK_ACTION ready")), "game boots");
  return { page, logs };
}

async function input(runtime, operation, expected) {
  const start = runtime.logs.length;
  await operation();
  if (expected) await until(runtime.page,
    () => runtime.logs.slice(start).some((line) => line.includes(expected)), expected, 15_000);
  await runtime.page.waitForTimeout(150);
}

async function reload(runtime) {
  await input(runtime, () => runtime.page.reload(), "CALLACK_ACTION ready");
}

async function screenshot(runtime, name) {
  await runtime.page.screenshot({ path: `${output}/${name}.png` });
}

try {
  await mkdir(output, { recursive: true });
  await new Promise((resolve, reject) => {
    server.once("error", reject); server.listen(0, "127.0.0.1", resolve);
  });
  const url = `http://127.0.0.1:${server.address().port}/?seed=9125`;
  browser = await chromium.launch({ headless: true,
    executablePath: process.env.CALLACK_BROWSER_EXECUTABLE || undefined,
    args: ["--enable-unsafe-swiftshader"] });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 },
    deviceScaleFactor: 1, hasTouch: true, isMobile: true });
  const phone = await boot(context, url), p = phone.page;
  const tap = (x, y, action) => input(phone, () => p.touchscreen.tap(x, y), action);
  const saved = () => p.evaluate((key) => localStorage.getItem(key), saveKey);
  await screenshot(phone, "phone-home");
  check(!(await saved()), "Fresh launch does not create or replace an expedition");
  await tap(195, 600, "COLLACK_MENU help");
  await screenshot(phone, "phone-help");
  await tap(195, 650, "COLLACK_MENU back");
  await tap(195, 532, "COLLACK_MENU new");
  await tap(280, 322, "CALLACK_ACTION quick_arrange");
  check(phone.logs.some((line) => /screen=setup .*active_links=[1-9]/.test(line)),
    "Quick arrange creates a legal, linked defensive formation");
  const checkpoint = await saved();
  check(checkpoint?.startsWith("C1:"), "Formation is saved in browser storage");
  await screenshot(phone, "phone-setup");
  await reload(phone);
  await screenshot(phone, "phone-continue");
  check(await saved() === checkpoint, "Reload preserves the exact saved expedition");
  await tap(195, 532, "COLLACK_MENU resume");
  check((await p.title()).includes("SETUP | Seed 9125"), "Continue returns to the saved formation");
  await tap(195, 796, "CALLACK_ACTION lock_setup");
  await tap(57, 796, "CALLACK_ACTION battle_pause");
  check(await saved() === checkpoint, "An active battle retains its pre-battle checkpoint");
  await tap(330, 796, "CALLACK_ACTION battle_motion");
  await tap(237, 796, "CALLACK_ACTION battle_mute");
  const preferences = await p.evaluate((key) => JSON.parse(localStorage.getItem(key)), preferencesKey);
  check(preferences.muted && preferences.reduced, "Touch settings persist mute and reduced motion");
  await screenshot(phone, "phone-battle-paused");
  await tap(340, 38);
  await screenshot(phone, "phone-menu-mid-battle");
  await reload(phone);
  await tap(195, 532, "COLLACK_MENU resume");
  check((await p.title()).includes("SETUP"), "Reloading mid-battle safely resumes the last formation");
  const battleStart = phone.logs.length;
  await tap(195, 796, "CALLACK_ACTION lock_setup");
  const beforeMotion = digest(await p.locator("#canvas").screenshot());
  await p.waitForTimeout(800);
  const afterMotion = digest(await p.locator("#canvas").screenshot());
  check(beforeMotion !== afterMotion, "Marbles visibly move during the normal autobattle");
  await screenshot(phone, "phone-battle");
  await until(p, () => phone.logs.slice(battleStart).some((line) => line.includes("CALLACK_ACTION phase_draft")),
    "first victory opens refit");
  check(phone.logs.slice(battleStart).some((line) => line.includes("collision.chip.damage")),
    "Normal play produces canonical marble-to-brick damage");
  await screenshot(phone, "phone-refit");
  const refitSave = await saved();
  check(refitSave !== checkpoint, "Victory creates a new refit checkpoint");
  await reload(phone); await tap(195, 532, "COLLACK_MENU resume");
  check((await p.title()).includes("DRAFT"), "The refit survives a browser restart");

  for (let fight = 2; fight <= 3; fight += 1) {
    await tap(195, 180, "CALLACK_ACTION offer:");
    await screenshot(phone, `phone-reward-${fight - 1}`);
    await tap(195, 732, "CALLACK_ACTION select:");
    await tap(195, 796, "CALLACK_ACTION confirm_offer");
    await tap(280, 322, "CALLACK_ACTION quick_arrange");
    await screenshot(phone, `phone-setup-${fight}`);
    const start = phone.logs.length;
    await tap(195, 796, "CALLACK_ACTION lock_setup");
    await until(p, () => phone.logs.slice(start).some((line) =>
      /CALLACK_ACTION phase_(draft|result)/.test(line)), `fight ${fight} resolves`);
    check((await p.title()).includes(fight === 3 ? "RESULT" : "DRAFT"),
      `Fight ${fight} completes the expected expedition step`);
  }
  await screenshot(phone, "phone-result");
  const terminalSave = await saved();
  await reload(phone); await tap(195, 532, "COLLACK_MENU resume");
  check((await p.title()).includes("RESULT"), "Terminal result and recording survive reload");
  await tap(287, 788, "CALLACK_ACTION replay_battle");
  await screenshot(phone, "phone-replay");
  await tap(103, 788, "CALLACK_ACTION replay_next");
  await tap(287, 788, "CALLACK_ACTION replay_close");
  check(await saved() === terminalSave, "Watching the recorded replay does not alter the run");

  // A damaged compressed payload must never reach native decompression.
  await p.evaluate((key) => localStorage.setItem(key, "C1:00000000:bm90LXpsaWI="), saveKey);
  await reload(phone);
  await screenshot(phone, "phone-damaged-save");
  await tap(195, 532, "COLLACK_MENU new");
  check((await saved())?.startsWith("C1:"), "A damaged save can be replaced by a playable new run");
  await context.close();

  const desktopContext = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const desktop = await boot(desktopContext, url), d = desktop.page;
  await screenshot(desktop, "desktop-home");
  const key = (name, expected) => input(desktop, () => d.keyboard.press(name), expected);
  await key("Tab"); await key("Enter", "COLLACK_MENU help");
  await screenshot(desktop, "desktop-help");
  await key("Enter", "COLLACK_MENU back");
  await key("Enter", "COLLACK_MENU new");
  await input(desktop, () => d.mouse.click(160, 618), "CALLACK_ACTION quick_arrange");
  await screenshot(desktop, "desktop-setup");
  await key("Escape");
  await key("Tab"); await key("Enter", "COLLACK_MENU new");
  await screenshot(desktop, "desktop-confirm-new");
  await key("Enter", "COLLACK_MENU back");
  await key("Enter", "COLLACK_MENU resume");
  check((await d.title()).includes("SETUP | Seed 9125"), "Keyboard confirmation preserves an ongoing run");
  await key("m", "CALLACK_ACTION toggle_mute");
  await key("v", "CALLACK_ACTION toggle_reduced_motion");
  await input(desktop, () => d.mouse.click(1122, 732), "CALLACK_ACTION lock_setup");
  // Reduced motion deliberately disables trail telemetry, not the physics.
  // Verify the rendered world still advances with that preference enabled.
  const desktopBefore = digest(await d.locator("#canvas").screenshot());
  await d.waitForTimeout(800);
  check(desktopBefore !== digest(await d.locator("#canvas").screenshot()),
    "Desktop marbles visibly move with reduced motion enabled");
  await key("Space", "CALLACK_ACTION battle_pause");
  await screenshot(desktop, "desktop-battle");
  await desktopContext.close();

  // Storage-restricted browsers still play and display an honest save warning.
  const privateContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  await privateContext.addInitScript(() => {
    Storage.prototype.setItem = () => { throw new DOMException("Storage blocked", "QuotaExceededError"); };
  });
  const privatePage = await boot(privateContext, url);
  await input(privatePage, () => privatePage.page.mouse.click(195, 532), "COLLACK_MENU new");
  check(await privatePage.page.locator("#save-warning").isVisible(), "Unavailable storage is visible and does not block play");
  await privateContext.close();
  check(errors.length === 0, `No browser runtime errors (${errors.join("; ")})`);
  await writeFile(`${output}/report.json`, JSON.stringify({ passed: true, checks, errors }, null, 2) + "\n");
  console.log(`OK: ${checks.length} normal expedition browser checks passed`);
} catch (error) {
  await writeFile(`${output}/report.json`, JSON.stringify({ passed: false, checks, errors, error: error.message }, null, 2) + "\n");
  throw error;
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}
