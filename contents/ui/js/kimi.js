/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure request-building / response-parsing logic for the Kimi Code
    (Coding Plan) usage endpoints, modelled on the contract the Kimi CLI
    tools use (https://github.com/Golden0Voyager/kimi-code-usage). No Qt APIs
    are used here so the file can be unit-tested with node:test
    (see tests/kimi.test.mjs).

    Unlike the DeepSeek platform API, this endpoint classifies failures with
    real HTTP status codes (verified live, 2026-09-30: no key answers
    HTTP 401 {"error":{"message":"Invalid Authentication",...}}), so callers
    branch on the status rather than on a code inside the JSON body.
*/

var DEFAULT_BASE = "https://api.kimi.com/coding/v1";

/* ------------------------------------------------------------------ urls */

// Empty or whitespace-only means "not configured" and takes the default, and a
// trailing slash is the one typo that silently turns "/v1/usages" into a 404,
// so both are fixed here rather than left for the request to discover.
function normalizeBaseUrl(raw) {
    var value = raw === undefined || raw === null ? "" : String(raw).trim();
    if (!value) {
        return DEFAULT_BASE;
    }
    return value.replace(/\/+$/, "");
}

function usageUrl(baseUrl) {
    return normalizeBaseUrl(baseUrl) + "/usages";
}

// Older deployments serve the singular form; the client falls back to it on a
// 404 (on the live endpoint the singular path itself answers 404).
function fallbackUrl(baseUrl) {
    return normalizeBaseUrl(baseUrl) + "/usage";
}

function normalizeApiKey(raw) {
    var value = raw === undefined || raw === null ? "" : String(raw).trim();
    // A whole `Bearer <key>` header pasted from somewhere. Nothing else is
    // peeled: a mangled key cannot be repaired, and mangling a real one would
    // be worse than sending it as-is.
    var bearer = /^Bearer[ \t]+/i.exec(value);
    if (bearer) {
        value = value.slice(bearer[0].length).trim();
    }
    return value;
}

// The one place the auth header is built. The CLI sends "User-Agent:
// KimiCLI/1.6" with these requests; a QML XMLHttpRequest cannot set
// User-Agent (Qt's forbidden header list), and the live endpoint answers
// 401 rather than 403 without it, so it is not required for these routes.
function authHeaders(apiKey) {
    return { Authorization: "Bearer " + normalizeApiKey(apiKey) };
}

/* ---------------------------------------------------------- parse helpers */

function toInt(value) {
    if (value === undefined || value === null || value === "") {
        return null;
    }
    var n = typeof value === "number" ? value : parseFloat(value);
    return isNaN(n) ? null : Math.round(n);
}

// Epoch seconds, epoch milliseconds (heuristic: 1e12 separates 2001 from
// 2001-in-ms is far past; seconds timestamps are below it until year 33658)
// or an ISO 8601 string. Returns a Date or null.
function parseDate(value) {
    if (typeof value === "number" && isFinite(value)) {
        return new Date(value < 1e12 ? value * 1000 : value);
    }
    if (typeof value === "string" && value) {
        // The live endpoint stamps microseconds ("…T05:03:43.670345Z",
        // verified 2026-09-30). V8 tolerates that; ECMA-262 only promises
        // three fraction digits, so truncate before parsing rather than trust
        // the engine to be lenient.
        var ms = Date.parse(value.replace(/(\.\d{3})\d+/, "$1"));
        return isNaN(ms) ? null : new Date(ms);
    }
    return null;
}

// "MM-DD HH:mm" — the same compact form the reference CLI prints. Deliberately
// not localized: it is a timestamp, and the popup's other compact stamps
// ("2.5d", "1.5M") keep Latin units too.
function clockStamp(dateObj) {
    function p2(n) {
        return (n < 10 ? "0" : "") + n;
    }
    return (
        p2(dateObj.getMonth() + 1) +
        "-" +
        p2(dateObj.getDate()) +
        " " +
        p2(dateObj.getHours()) +
        ":" +
        p2(dateObj.getMinutes())
    );
}

// "2d 3h", "3h 5m", "45m" — always at least one unit, so "0m" is honest about
// a quota that has just reset or is about to.
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
    Reset information, when the payload carries any: a moment the quota
    resets at (resetTime / reset_at / reset_time, as a timestamp or an ISO
    string) or a duration it resets in (reset_in, seconds). Returns
    { resetAtText, countdown } or null; `nowMs` is injectable for the tests.
*/
function resetInfo(data, nowMs) {
    if (!data || typeof data !== "object") {
        return null;
    }
    var now = nowMs === undefined ? Date.now() : nowMs;
    var resetAt =
        data.resetTime !== undefined && data.resetTime !== null && data.resetTime !== ""
            ? data.resetTime
            : data.reset_at !== undefined && data.reset_at !== null && data.reset_at !== ""
              ? data.reset_at
              : data.reset_time;
    if (resetAt !== undefined && resetAt !== null && resetAt !== "") {
        var dt = parseDate(resetAt);
        if (dt !== null && !isNaN(dt.getTime())) {
            return {
                resetAtText: clockStamp(dt),
                countdown: countdownText(dt.getTime() - now)
            };
        }
    }
    var resetIn = toInt(data.reset_in);
    if (resetIn !== null) {
        return {
            resetAtText: clockStamp(new Date(now + resetIn * 1000)),
            countdown: countdownText(resetIn * 1000)
        };
    }
    return null;
}

/*
    A limit window's span as "5h" / "45m" / "7d" / "1mo", so a limit without
    its own name still says what it bounds. Whole hours folded from minutes,
    because "300m limit" is how nobody reads a five-hour window. "" when the
    window is unknown; the UI then falls back to "Limit #%1".
*/
function windowText(window) {
    if (!window || typeof window !== "object") {
        return "";
    }
    var duration = toInt(window.duration);
    if (duration === null) {
        return "";
    }
    var unit = String(window.timeUnit || window.time_unit || "").toUpperCase();
    if (unit.indexOf("MINUTE") >= 0) {
        if (duration >= 60 && duration % 60 === 0) {
            return duration / 60 + "h";
        }
        return duration + "m";
    }
    if (unit.indexOf("HOUR") >= 0) {
        return duration + "h";
    }
    if (unit.indexOf("DAY") >= 0) {
        return duration + "d";
    }
    if (unit.indexOf("MONTH") >= 0) {
        return duration + "mo";
    }
    return duration + "s";
}

/*
    used / limit for one quota entry. `used` may arrive derived from
    `remaining` instead, in which case it is reconstructed; an entry with
    neither pair is not a quota at all and returns null.
*/
function usageAmounts(data) {
    if (!data || typeof data !== "object") {
        return null;
    }
    var limit = toInt(data.limit !== undefined ? data.limit : data.limit_amount);
    var used = toInt(data.used !== undefined ? data.used : data.used_amount);
    if (used === null) {
        var remaining = toInt(data.remaining);
        if (remaining !== null && limit !== null) {
            used = limit - remaining;
        }
    }
    if (used === null && limit === null) {
        return null;
    }
    return { used: used === null ? 0 : used, limit: limit === null ? 0 : limit };
}

function makeRow(kind, source, window, nowMs) {
    var amounts = usageAmounts(source);
    if (!amounts) {
        return null;
    }
    var reset = resetInfo(source, nowMs);
    var name =
        kind === "summary"
            ? null // the UI localizes the summary label itself
            : source.name || source.title || source.model_name || null;
    return {
        kind: kind,
        name: typeof name === "string" && name ? name : null,
        window: window,
        used: amounts.used,
        limit: amounts.limit,
        resetAtText: reset ? reset.resetAtText : "",
        countdown: reset ? reset.countdown : ""
    };
}

/*
    Both payload shapes the endpoint has shipped (verified live, 2026-09-30:
    api.kimi.com answers the second one):

      * usage/limits (live): { "usage": {…}, "limits": [ { detail: {…},
        window: {…} } ] } — one summary plus limits whose numbers sit in a
        `detail` object beside the `window` they run on; amounts arrive as
        strings, `timeUnit` as a "TIME_UNIT_MINUTE" enum, timestamps as
        ISO strings with microseconds;
      * data[] (the shape the reference CLI also reads): { "data": [
        { model_name: "all" | model, used, limit, resetTime | reset_in, … } ] }
        — the entry with model_name "all" is the weekly summary, the rest are
        per-model limits.

    Returns { ok: true, summary: row|null, limits: [row] } or
    { ok: false, error }, where error is "invalid-json" or "empty".
*/
function parseUsagePayload(text, nowMs) {
    var obj;
    try {
        obj = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "invalid-json" };
    }
    if (!obj || typeof obj !== "object") {
        return { ok: false, error: "invalid-json" };
    }

    var summary = null;
    var limits = [];

    if (Array.isArray(obj.data)) {
        for (var i = 0; i < obj.data.length; i++) {
            var item = obj.data[i];
            if (!item || typeof item !== "object") {
                continue;
            }
            if (String(item.model_name || "") === "all") {
                summary = makeRow("summary", item, "", nowMs) || summary;
            } else {
                var row = makeRow("limit", item, "", nowMs);
                if (row) {
                    limits.push(row);
                }
            }
        }
    } else if (obj.usage || Array.isArray(obj.limits)) {
        if (obj.usage && typeof obj.usage === "object") {
            summary = makeRow("summary", obj.usage, "", nowMs);
        }
        var rawLimits = Array.isArray(obj.limits) ? obj.limits : [];
        for (var l = 0; l < rawLimits.length; l++) {
            var entry = rawLimits[l];
            if (!entry || typeof entry !== "object") {
                continue;
            }
            var detail = entry.detail && typeof entry.detail === "object" ? entry.detail : entry;
            var limitRow = makeRow("limit", detail, windowText(entry.window), nowMs);
            if (limitRow) {
                limits.push(limitRow);
            }
        }
    } else {
        return { ok: false, error: "empty" };
    }

    if (!summary && limits.length === 0) {
        return { ok: false, error: "empty" };
    }
    return { ok: true, summary: summary, limits: limits };
}

/*
    A refused request, named so the UI can say something a user can act on.
    401 is the wrong-key case (a Moonshot Open Platform key looks like a key
    but is not accepted here); anything unrecognised keeps its HTTP status in
    the generic "HTTP error %1" message, so a bug report still carries it.
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
