/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure decision logic for the weekly-quota reminder: whether a quota is
    close enough to its reset (and unused enough) to be worth a desktop
    notification, and the per-day pace that would spend the rest in time.
    No Qt APIs are used here so the file can be unit-tested with node:test
    (see tests/reminder.test.mjs); the caller sends the notification and
    remembers that it did.

    The two thresholds are the product decision this module exists to keep
    in one place:

      BEFORE_RESET_MS        "about to reset" — the last day of the window
      MIN_REMAINING_PERCENT  "worth mentioning" — a few leftover points are
                             not, a fifth of the quota is
*/

var BEFORE_RESET_MS = 24 * 3600 * 1000;
var MIN_REMAINING_PERCENT = 20;

// "1d 6h 20m" — the same compact form kimi.js renders (duplicated here
// because the plain-script js/ modules cannot import each other).
function countdownText(msLeft) {
    var total = Math.max(0, Math.floor(msLeft / 1000));
    var days = Math.floor(total / 86400);
    var hours = Math.floor((total % 86400) / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    var parts = [];
    if (days > 0) {
        parts.push(days + "d");
    }
    if (hours > 0) {
        parts.push(hours + "h");
    }
    parts.push(minutes + "m");
    return parts.join(" ");
}

/*
    Everything the notification shows, or null when the inputs cannot
    support one (no reset time known, or a nonsense percentage). Returns
    { msLeft, remainingPercent, msLeftText, perDayPercent }.

    perDayPercent is the pace that spends the remainder exactly on time:
    remaining / daysLeft. With less than a day left the division would
    invent a quota-and-a-half to burn through, so it caps at "all of it
    today" instead.
*/
function verdict(usedPercent, resetAtMs, nowMs) {
    if (!(resetAtMs > 0)) {
        return null;
    }
    var used = typeof usedPercent === "number" ? usedPercent : parseFloat(usedPercent);
    if (!isFinite(used) || used < 0 || used > 100) {
        return null;
    }
    var msLeft = resetAtMs - (nowMs === undefined ? Date.now() : nowMs);
    if (msLeft <= 0) {
        return null;
    }
    var remaining = 100 - Math.round(used);
    var daysLeft = msLeft / 86400000;
    var perDay = daysLeft < 1 ? remaining : Math.round(remaining / daysLeft);
    return {
        msLeft: msLeft,
        remainingPercent: remaining,
        msLeftText: countdownText(msLeft),
        perDayPercent: perDay
    };
}

// A UTC day number, the "notify at most once a day" stamp.
function epochDay(ms) {
    return Math.floor(ms / 86400000);
}

/*
    Whether the reminder should fire now: inside the last day of the window,
    with more than MIN_REMAINING_PERCENT unused, and not already sent this
    day (the caller stores the day the last one went out).
*/
function due(v, lastNotifiedDay, nowMs) {
    if (v === null) {
        return false;
    }
    if (v.remainingPercent <= MIN_REMAINING_PERCENT) {
        return false;
    }
    if (v.msLeft > BEFORE_RESET_MS) {
        return false;
    }
    return epochDay(nowMs) !== lastNotifiedDay;
}
