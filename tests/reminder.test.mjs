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
