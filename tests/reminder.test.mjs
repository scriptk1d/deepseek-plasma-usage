/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const reminder = load("contents/ui/js/reminder.js");

const NOW = new Date("2026-09-30T12:00:00Z").getTime();
const DAY = 86400 * 1000;

test("verdict computes the remainder and the per-day pace", () => {
    // 40% used, resets in exactly 2 days: 60% left, 30% a day.
    const v = reminder.verdict(40, NOW + 2 * DAY, NOW);
    assert.equal(v.remainingPercent, 60);
    assert.equal(v.perDayPercent, 30);
    assert.equal(v.msLeftText, "2d 0m");
});

test("verdict caps the pace at the whole remainder under the last day", () => {
    // 12 hours left, 50% unused: burning 100%/day to "finish on time" would
    // be advice to spam, so the suggestion is simply the rest of it, today.
    const v = reminder.verdict(50, NOW + DAY / 2, NOW);
    assert.equal(v.perDayPercent, 50);
});

test("verdict refuses what cannot support a reminder", () => {
    assert.equal(reminder.verdict(40, 0, NOW), null, "no reset time known");
    assert.equal(reminder.verdict(NaN, NOW + DAY, NOW), null, "no usable percentage");
    assert.equal(reminder.verdict(-1, NOW + DAY, NOW), null);
    assert.equal(reminder.verdict(101, NOW + DAY, NOW), null);
    assert.equal(reminder.verdict(40, NOW, NOW), null, "already past the reset");
});

test("due fires only in the last day, with more than a fifth unused, once a day", () => {
    const today = reminder.epochDay(NOW);

    // 26h out: not yet "about to reset".
    let v = reminder.verdict(50, NOW + 26 * 3600 * 1000, NOW);
    assert.equal(reminder.due(v, 0, NOW), false);

    // 23h out and 60% unused: yes.
    v = reminder.verdict(40, NOW + 23 * 3600 * 1000, NOW);
    assert.equal(reminder.due(v, 0, NOW), true);

    // Barely anything left: not worth a notification.
    v = reminder.verdict(95, NOW + 23 * 3600 * 1000, NOW);
    assert.equal(reminder.due(v, 0, NOW), false, "5% unused is below the bar");

    // Exactly 20% unused is not "more than 20%".
    v = reminder.verdict(80, NOW + 23 * 3600 * 1000, NOW);
    assert.equal(reminder.due(v, 0, NOW), false);

    // Already reminded today: no, whatever the quota looks like.
    v = reminder.verdict(40, NOW + 23 * 3600 * 1000, NOW);
    assert.equal(reminder.due(v, today, NOW), false);
    // And a day later it may fire again.
    assert.equal(reminder.due(v, today, NOW + DAY), true);

    assert.equal(reminder.due(null, 0, NOW), false, "no verdict, no reminder");
});

test("epochDay moves at UTC midnight", () => {
    const midnight = new Date("2026-09-30T00:00:00Z").getTime();
    assert.equal(reminder.epochDay(midnight - 1), reminder.epochDay(midnight) - 1);
    assert.equal(reminder.epochDay(midnight), reminder.epochDay(midnight + DAY - 1));
});

/*
    The two thresholds are the product decision this module exists to keep
    in one place; pin them so a change is a decision, not an accident.
*/
test("the reminder thresholds are pinned", () => {
    assert.equal(reminder.BEFORE_RESET_MS, 24 * 3600 * 1000);
    assert.equal(reminder.MIN_REMAINING_PERCENT, 20);
});

test("due honours the settings' overrides", () => {
    // 30h out with the default 24h window: not due; a wider window is.
    const v = reminder.verdict(40, NOW + 30 * 3600 * 1000, NOW);
    assert.equal(reminder.due(v, 0, NOW), false);
    assert.equal(reminder.due(v, 0, NOW, { beforeMs: 36 * 3600 * 1000 }), true);

    // The minimum-unused bar moves the same way: 25% unused with the bar at
    // 20 is due, with the bar at 30 it is not.
    const w = reminder.verdict(75, NOW + 10 * 3600 * 1000, NOW);
    assert.equal(reminder.due(w, 0, NOW), true);
    assert.equal(reminder.due(w, 0, NOW, { minRemaining: 30 }), false);
});

test("parseClock accepts clocks and refuses the rest", () => {
    assert.equal(reminder.parseClock("09:00"), 9 * 60);
    assert.equal(reminder.parseClock("9:5"), 9 * 60 + 5);
    assert.equal(reminder.parseClock("  23:59  "), 23 * 60 + 59);
    assert.equal(reminder.parseClock("24:00"), null);
    assert.equal(reminder.parseClock("12:60"), null);
    assert.equal(reminder.parseClock(""), null);
    assert.equal(reminder.parseClock(undefined), null);
    assert.equal(reminder.parseClock("whenever"), null);
});

test("localDay and minutesOfDay follow the shifted clock", () => {
    // UTC+3: the local day flips at 21:00 UTC, not at UTC midnight.
    const plus3 = 3 * 3600 * 1000;
    const localMidnight = new Date("2026-09-29T21:00:00Z").getTime();
    assert.equal(reminder.localDay(localMidnight - 1, plus3), reminder.localDay(localMidnight, plus3) - 1);
    assert.equal(reminder.minutesOfDay(new Date("2026-09-30T21:15:00Z").getTime(), plus3), 15);
    assert.equal(reminder.minutesOfDay(new Date("2026-09-30T18:00:00Z").getTime(), plus3), 21 * 60);
    // Offset 0 is the UTC behaviour the reset reminder's tests pin.
    const utcMidnight = new Date("2026-09-30T00:00:00Z").getTime();
    assert.equal(reminder.localDay(utcMidnight, 0), reminder.epochDay(utcMidnight));
});

test("digestDue fires once per local day per slot, only past its time", () => {
    const plus8 = 8 * 3600 * 1000;
    // 10:00 local (02:00 UTC) with the slot at 09:00: due, unless stamped.
    const at1000 = new Date("2026-09-30T02:00:00Z").getTime();
    assert.equal(reminder.digestDue(9 * 60, at1000, plus8, 0), true);
    const today = reminder.localDay(at1000, plus8);
    assert.equal(reminder.digestDue(9 * 60, at1000, plus8, today), false, "already sent this slot today");
    // Still the same local day five hours later: still suppressed.
    assert.equal(reminder.digestDue(9 * 60, at1000 + 5 * 3600 * 1000, plus8, today), false);
    // Next local day, same clock: due again.
    assert.equal(reminder.digestDue(9 * 60, at1000 + DAY, plus8, today), true);
    // Before the slot's time: not yet.
    const at0800 = new Date("2026-09-30T00:00:00Z").getTime();
    assert.equal(reminder.digestDue(9 * 60, at0800, plus8, 0), false);
    // An unparsable slot time never fires (the settings may hold junk).
    assert.equal(reminder.digestDue(null, at1000, plus8, 0), false);
});
