/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure decision logic for the quota reminders: whether a weekly quota is
    close enough to its reset (and unused enough) to be worth a desktop
    notification, and when the twice-daily usage digest is due. The caller
    sends the notifications and remembers that it did. No Qt APIs are used
    here so the file can be unit-tested with node:test
    (see tests/reminder.test.mjs).

    The two thresholds are the defaults the settings offer to change, kept
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
    The same stamp on the user's clock: offsetMs is the zone's offset east of
    UTC (the caller passes -new Date().getTimezoneOffset() * 60000), so a
    digest due "once a day" fires once per local day, not once per UTC day.
    With offset 0 this is epochDay.
*/
function localDay(ms, offsetMs) {
    return Math.floor((ms + (offsetMs || 0)) / 86400000);
}

// Minutes since local midnight for the same shifted clock.
function minutesOfDay(ms, offsetMs) {
    var local = new Date(ms + (offsetMs || 0));
    return local.getUTCHours() * 60 + local.getUTCMinutes();
}

// "09:05" -> 545; anything unparsable is null and the slot simply never
// fires (a reminder at no time is off, which the settings can also say).
function parseClock(text) {
    var match = /^(\d{1,2}):(\d{1,2})$/.exec(String(text === undefined || text === null ? "" : text).trim());
    if (!match) {
        return null;
    }
    var hours = parseInt(match[1], 10);
    var minutes = parseInt(match[2], 10);
    if (hours > 23 || minutes > 59) {
        return null;
    }
    return hours * 60 + minutes;
}

/*
    Whether the daily digest's slot has come due: the local time is past it
    and no digest went out for that slot this local day. The stamp is per
    slot, so the two times are independent reminders.
*/
function digestDue(slotMinutes, nowMs, offsetMs, stampedDay) {
    if (slotMinutes === null || slotMinutes === undefined) {
        return false;
    }
    if (minutesOfDay(nowMs, offsetMs) < slotMinutes) {
        return false;
    }
    return localDay(nowMs, offsetMs) !== stampedDay;
}

/*
    Whether the reminder should fire now: inside the window before the reset
    (BEFORE_RESET_MS, or opts.beforeMs), with more than the minimum unused
    (MIN_REMAINING_PERCENT, or opts.minRemaining), and not already sent this
    local day (the caller stores the day the last one went out; opts.offsetMs
    is the zone offset, 0 meaning UTC like the tests use).
*/
function due(v, lastNotifiedDay, nowMs, opts) {
    if (v === null) {
        return false;
    }
    var minRemaining = opts && opts.minRemaining !== undefined ? opts.minRemaining : MIN_REMAINING_PERCENT;
    var beforeMs = opts && opts.beforeMs !== undefined ? opts.beforeMs : BEFORE_RESET_MS;
    var offsetMs = opts && opts.offsetMs !== undefined ? opts.offsetMs : 0;
    if (v.remainingPercent <= minRemaining) {
        return false;
    }
    if (v.msLeft > beforeMs) {
        return false;
    }
    return localDay(nowMs, offsetMs) !== lastNotifiedDay;
}
