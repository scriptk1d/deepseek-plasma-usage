/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure request-building / response-parsing logic for the Z.ai (GLM Coding
    Plan) usage endpoints. No Qt APIs are used here so the file can be
    unit-tested with node:test (see tests/zai.test.mjs).

    Three GETs under {base}/api/monitor/usage/…, each optional individually
    (the reference tracker collects them with allSettled and keeps whatever
    answered), all behind the {code,msg,data,success} envelope:

      quota/limit                              the quota rows (verified live,
                                               2026-09-30: two TOKENS_LIMIT
                                               rows that carry only a
                                               percentage and a reset time —
                                               no absolute token counts — plus
                                               a TIME_LIMIT row whose `usage`
                                               IS the limit and whose
                                               `currentValue` is the used
                                               count; `level` names the plan)
      model-usage?startTime=&endTime=          hourly series plus a
                                               totalUsage object; asked twice,
                                               for 7 and 30 days

    Authentication is tried as a bare key first ("Authorization: <key>", what
    the coding-plan CLI sends; verified live) and retried as a Bearer header
    on 401, because the endpoint has accepted both at different times.
*/

var DEFAULT_BASE = "https://api.z.ai";

/*
    The quota rows name their window with a unit enum times a multiplier:
    {unit:3, number:5} is the 5-hour prompt window, {unit:6, number:1} the
    weekly quota, {unit:5, number:1} the monthly tool quota — inferred from
    the recorded live probe (their reset times were hours, days and ~9 days
    out), because the enum itself is not documented. An unknown unit renders
    as a plain ordinal row rather than a guessed label.
*/
var UNIT_SPANS = { 3: "h", 6: "w", 5: "mo" };

/* ------------------------------------------------------------------ urls */

// Same repair as kimi.js: empty means "not configured" and takes the default,
// and a trailing slash would 404 every route.
function normalizeBaseUrl(raw) {
    var value = raw === undefined || raw === null ? "" : String(raw).trim();
    if (!value) {
        return DEFAULT_BASE;
    }
    return value.replace(/\/+$/, "");
}

function quotaUrl(baseUrl) {
    return normalizeBaseUrl(baseUrl) + "/api/monitor/usage/quota/limit";
}

// The endpoint takes "YYYY-MM-DD HH:mm:ss" in the server's local reading, so
// the widget sends its own local time — same as the tracker does.
function modelUsageUrl(baseUrl, startSec, endSec) {
    return (
        normalizeBaseUrl(baseUrl) +
        "/api/monitor/usage/model-usage?startTime=" +
        encodeURIComponent(dateTimeParam(startSec)) +
        "&endTime=" +
        encodeURIComponent(dateTimeParam(endSec))
    );
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// 1787886000 -> "2026-08-28 00:00:00", in the machine's local zone.
function dateTimeParam(epochSec) {
    var d = new Date(epochSec * 1000);
    return (
        d.getFullYear() +
        "-" +
        pad2(d.getMonth() + 1) +
        "-" +
        pad2(d.getDate()) +
        " " +
        pad2(d.getHours()) +
        ":" +
        pad2(d.getMinutes()) +
        ":" +
        pad2(d.getSeconds())
    );
}

/*
    The two windows the tracker asks for, both ending at the end of today:
    7 whole days back, and "same day last month". Derived from local midnight
    so both ends stay on the zone's own day boundaries.
*/
function usageWindows(now) {
    var end = midnight(now) + 86400 - 1;
    var d7 = new Date(now);
    d7.setHours(0, 0, 0, 0);
    d7.setDate(d7.getDate() - 7);
    var d30 = new Date(now);
    d30.setHours(0, 0, 0, 0);
    d30.setMonth(d30.getMonth() - 1);
    return {
        end: end,
        start7: Math.floor(d7.getTime() / 1000),
        start30: Math.floor(d30.getTime() / 1000)
    };
}

function midnight(dateObj) {
    var d = new Date(dateObj);
    d.setHours(0, 0, 0, 0);
    return Math.floor(d.getTime() / 1000);
}

/* -------------------------------------------------------------- credentials */

// Trims and peels a pasted "Bearer <key>" header; anything else is sent
// as-is, because mangling a real key would be worse than rejecting it.
function normalizeApiKey(raw) {
    var value = raw === undefined || raw === null ? "" : String(raw).trim();
    var bearer = /^Bearer[ \t]+/i.exec(value);
    if (bearer) {
        value = value.slice(bearer[0].length).trim();
    }
    return value;
}

// The two Authorization header values to try, in order: a bare key first
// (verified live), Bearer on retry. Returns an array of single-key header
// objects.
function authVariants(apiKey) {
    var key = normalizeApiKey(apiKey);
    return [{ Authorization: key }, { Authorization: "Bearer " + key }];
}

/* ---------------------------------------------------------- parse helpers */

function toNumber(value) {
    if (value === undefined || value === null || value === "") {
        return 0;
    }
    var n = typeof value === "number" ? value : parseFloat(value);
    return isNaN(n) ? 0 : n;
}

// Everything answers the {code,msg,data,success} envelope; older deployments
// skipped it, so an unwrapped payload is accepted too (`data.data || data`,
// what the tracker unwraps with).
function unwrapPayload(text) {
    var obj;
    try {
        obj = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!obj || typeof obj !== "object") {
        return null;
    }
    return obj.data !== undefined && obj.data !== null ? obj.data : obj;
}

// "MM-DD HH:mm" and "2d 3h 15m", the same compact forms kimi.js renders
// (duplicated here because the plain-script js/ modules cannot import each
// other; `nowMs` is injectable for the tests).
function clockStamp(dateObj) {
    return (
        pad2(dateObj.getMonth() + 1) +
        "-" +
        pad2(dateObj.getDate()) +
        " " +
        pad2(dateObj.getHours()) +
        ":" +
        pad2(dateObj.getMinutes())
    );
}

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

function resetInfo(entry, nowMs) {
    var ms = toNumber(entry.nextResetTime);
    if (!ms) {
        return { resetAtMs: 0, resetAtText: "", countdown: "" };
    }
    // The stamp is epoch milliseconds (verified live: 13-digit values), and a
    // seconds-scale value is folded the same way kimi.js folds timestamps.
    var at = ms < 1e12 ? ms * 1000 : ms;
    return {
        resetAtMs: at,
        resetAtText: clockStamp(new Date(at)),
        countdown: countdownText(at - nowMs)
    };
}

function quotaSpan(entry) {
    var suffix = UNIT_SPANS[entry.unit];
    if (!suffix) {
        return "";
    }
    var number = toNumber(entry.number);
    return (number > 0 ? number : 1) + suffix;
}

/*
    The quota rows, one per entry of limits[]:

      { span: "5h", kind, percent, hasAmounts, used, limit,
        resetAtText, countdown, resetAtMs }

    TOKENS_LIMIT carries only a percentage today; the absolute fields
    (currentValue = used, usage = limit, `limit` preferred when present) are
    read when they exist, because that is what older deployments and the
    reference tracker read. Rows sort by reset time so the shortest window —
    the one the panel shows — comes first.

    Returns null when the payload carries no limits array.
*/
function parseQuotaLimit(text, nowMs) {
    var payload = unwrapPayload(text);
    if (!payload || !Array.isArray(payload.limits)) {
        return null;
    }
    var now = nowMs === undefined ? Date.now() : nowMs;
    var rows = [];
    for (var i = 0; i < payload.limits.length; i++) {
        var entry = payload.limits[i];
        if (!entry || typeof entry !== "object") {
            continue;
        }
        var hasLimitField = entry.limit !== undefined && entry.limit !== null;
        var hasAmounts = hasLimitField || entry.currentValue !== undefined || entry.usage !== undefined;
        var reset = resetInfo(entry, now);
        rows.push({
            span: quotaSpan(entry),
            kind: entry.type || "",
            percent: Math.round(toNumber(entry.percentage)),
            hasAmounts: hasAmounts,
            used: entry.currentValue !== undefined ? toNumber(entry.currentValue) : 0,
            limit: hasLimitField ? toNumber(entry.limit) : toNumber(entry.usage),
            resetAtText: reset.resetAtText,
            countdown: reset.countdown,
            resetAtMs: reset.resetAtMs
        });
    }
    if (rows.length === 0) {
        return null;
    }
    rows.sort(function (x, y) {
        // A row without a reset time sorts last; between two such rows the
        // payload's own order is kept (sort stability).
        if (!x.resetAtMs) {
            return y.resetAtMs ? 1 : 0;
        }
        if (!y.resetAtMs) {
            return -1;
        }
        return x.resetAtMs - y.resetAtMs;
    });
    return rows;
}

// Totals for one window: { prompts, tokens }. A payload without totalUsage is
// not an error — the window is simply empty.
function parseModelUsage(text) {
    var payload = unwrapPayload(text);
    var total = payload && payload.totalUsage && typeof payload.totalUsage === "object" ? payload.totalUsage : null;
    return {
        prompts: total ? toNumber(total.totalModelCallCount) : 0,
        tokens: total ? toNumber(total.totalTokensUsage) : 0
    };
}

/*
    Failures are classified from the HTTP status. A 401 after both auth
    variants means the key itself is not accepted; anything else keeps its
    status in the generic "HTTP error %1" so a bug report still carries it.
*/
function failureKind(status) {
    if (status === 401) {
        return "auth";
    }
    if (status === 403) {
        return "forbidden";
    }
    if (status === 429) {
        return "rate-limited";
    }
    return "";
}
