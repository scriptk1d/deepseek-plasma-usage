/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure bookkeeping for the quota trend: appends one point per refresh of
    the Kimi and Z.ai data, keeps the buffer small, and hands the popup a
    plottable series. No Qt APIs are used here so the file can be
    unit-tested with node:test (see tests/history.test.mjs).

    The points live in the applet configuration as one compact JSON array,

        [[epochSeconds, kimiPercentOrNull, zaiPercentOrNull], ...]

    newest last. Percent is the comparable unit — used/limit for Kimi's
    headline quota, the reported percentage for Z.ai's — so the two
    providers can share one recording cadence and one canvas scale, and a
    quota that resets cannot make the history jump out of range.
*/

// ~3.5 days of 10-minute points; old points fall off the front.
var MAX_POINTS = 512;

// One point per refresh would be ~288 a day at the default interval, most of
// them indistinguishable from their neighbours; this keeps the buffer
// readable and the config entry small.
var MIN_SPACING_SEC = 600;

// Column of each provider's value inside a point.
var KEYS = { kimi: 1, zai: 2 };

function clampPercent(value) {
    var n = typeof value === "number" ? value : parseFloat(value);
    if (!isFinite(n)) {
        return null;
    }
    return Math.max(0, Math.min(100, Math.round(n)));
}

// Tolerant by design: an unreadable history is an empty one, not a broken
// widget — the recording simply starts again.
function parse(text) {
    if (!text) {
        return [];
    }
    var obj;
    try {
        obj = JSON.parse(text);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(obj)) {
        return [];
    }
    var points = [];
    for (var i = 0; i < obj.length; i++) {
        var p = obj[i];
        if (!Array.isArray(p) || p.length < 3 || typeof p[0] !== "number") {
            continue;
        }
        points.push([Math.floor(p[0]), clampPercent(p[1]), clampPercent(p[2])]);
    }
    points.sort(function (a, b) {
        return a[0] - b[0];
    });
    return points;
}

function serialize(points) {
    return JSON.stringify(points || []);
}

/*
    Record one observation. A point closer than MIN_SPACING_SEC to the last
    replaces it (the freshest reading wins), an older gap appends, and the
    buffer is capped by dropping the front. Values may be null when their
    provider had no data — a point is kept as long as either provider did.

    Returns { points, changed }, changed false only when nothing would have
    moved, so the caller can skip the config write.
*/
function append(points, tSec, kimiPercent, zaiPercent) {
    var base = Array.isArray(points) ? points : [];
    var t = Math.floor(tSec);
    var rec = [t, clampPercent(kimiPercent), clampPercent(zaiPercent)];
    var out;

    var last = base.length > 0 ? base[base.length - 1] : null;
    if (last && t - last[0] < MIN_SPACING_SEC) {
        if (last[0] === rec[0] && last[1] === rec[1] && last[2] === rec[2]) {
            return { points: base, changed: false };
        }
        out = base.slice(0, base.length - 1).concat([rec]);
    } else {
        out = base.concat([rec]);
    }
    if (out.length > MAX_POINTS) {
        out = out.slice(out.length - MAX_POINTS);
    }
    return { points: out, changed: true };
}

// Plottable [{t, v}] for one provider, skipping the observations where it
// had no data; oldest first.
function series(points, key) {
    var col = KEYS[key];
    if (!col || !Array.isArray(points)) {
        return [];
    }
    var out = [];
    for (var i = 0; i < points.length; i++) {
        if (points[i][col] !== null && points[i][col] !== undefined) {
            out.push({ t: points[i][0], v: points[i][col] });
        }
    }
    return out;
}

/*
    How much of the quota was spent since local midnight: the earliest
    recorded value at or after midnightSec against the value shown now.
    Null when the recording has nothing from today (the widget was not
    running, or the provider had no data), negative differences clamped to
    zero — a quota that reset mid-day is not "negative usage".
*/
function dailyDelta(points, key, midnightSec, nowValue) {
    var col = KEYS[key];
    if (!col || !Array.isArray(points) || typeof nowValue !== "number" || !isFinite(nowValue)) {
        return null;
    }
    var base = null;
    for (var i = 0; i < points.length; i++) {
        if (points[i][0] < midnightSec) {
            continue;
        }
        if (points[i][col] === null || points[i][col] === undefined) {
            continue;
        }
        base = points[i][col];
        break;
    }
    if (base === null) {
        return null;
    }
    return Math.max(0, Math.round(nowValue - base));
}
