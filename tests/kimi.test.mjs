/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { load } from "./load.mjs";
import { kimiUsagesPayload, KIMI_QUOTA_USED, KIMI_QUOTA_LIMIT } from "./mock-platform-server.mjs";

const kimi = load("contents/ui/js/kimi.js");
const wallet = load("contents/ui/js/wallet.js");

// Reset times are formatted in the local zone (clockStamp), so pin it like
// tests/api.test.mjs pins its own.
process.env.TZ = "Etc/GMT+3";

// Fixed "now" for the countdown assertions; nothing here is a real timestamp.
const NOW = new Date("2026-09-30T12:00:00-03:00").getTime();

test("urls: the default base, a configured base, and the trailing-slash repair", () => {
    assert.equal(kimi.usageUrl(""), "https://api.kimi.com/coding/v1/usages");
    assert.equal(kimi.usageUrl(undefined), "https://api.kimi.com/coding/v1/usages");
    assert.equal(kimi.usageUrl("  "), "https://api.kimi.com/coding/v1/usages");
    assert.equal(kimi.usageUrl("https://api.kimi.com/coding/v1/"), "https://api.kimi.com/coding/v1/usages");
    assert.equal(kimi.usageUrl("https://proxy.example/coding/v1///"), "https://proxy.example/coding/v1/usages");
    assert.equal(kimi.fallbackUrl(""), "https://api.kimi.com/coding/v1/usage");
});

test("authHeaders carries one bare Bearer key", () => {
    const header = raw => kimi.authHeaders(raw).Authorization;
    assert.equal(header("sk-kimi-test"), "Bearer sk-kimi-test");
    assert.equal(header("  sk-kimi-test \n"), "Bearer sk-kimi-test");
    // The one paste mistake with a known repair: a whole header line.
    assert.equal(header("Bearer sk-kimi-test"), "Bearer sk-kimi-test");
    // Anything else is sent as-is: mangling a real key would be worse.
    assert.equal(header("sk-kimi with spaces"), "Bearer sk-kimi with spaces");
    assert.equal(header(undefined), "Bearer ");
});

test("windowText folds a limit window into a span", () => {
    assert.equal(kimi.windowText({ duration: 300, timeUnit: "MINUTES" }), "5h");
    assert.equal(kimi.windowText({ duration: 45, timeUnit: "MINUTE" }), "45m");
    assert.equal(kimi.windowText({ duration: 5, timeUnit: "HOURS" }), "5h");
    assert.equal(kimi.windowText({ duration: 7, timeUnit: "DAY" }), "7d");
    assert.equal(kimi.windowText({ duration: 1, timeUnit: "MONTH" }), "1mo");
    assert.equal(kimi.windowText({ duration: 90, time_unit: "SECONDS" }), "90s");
    assert.equal(kimi.windowText({ timeUnit: "DAY" }), "");
    assert.equal(kimi.windowText(null), "");
});

test("usageAmounts reads used/limit and reconstructs used from remaining", () => {
    assert.equal(kimi.usageAmounts({ used: 10, limit: 100 }).used, 10);
    assert.equal(kimi.usageAmounts({ used: 10, limit: 100 }).limit, 100);
    assert.equal(kimi.usageAmounts({ used_amount: "10", limit_amount: "100" }).used, 10);
    assert.equal(kimi.usageAmounts({ remaining: 30, limit: 100 }).used, 70);
    assert.deepEqual([kimi.usageAmounts({ used: 7 }).used, kimi.usageAmounts({ used: 7 }).limit], [7, 0]);
    assert.equal(kimi.usageAmounts({}), null);
    assert.equal(kimi.usageAmounts(null), null);
});

test("resetInfo handles timestamps, ISO strings and reset_in seconds", () => {
    const epochSec = (NOW + 2 * 86400 * 1000 + 3 * 3600 * 1000 + 15 * 60 * 1000) / 1000;
    // Compared field by field: the rows come from a vm realm, so a deep
    // equality would compare realms rather than values (see api.test.mjs).
    const fromEpoch = kimi.resetInfo({ resetTime: epochSec }, NOW);
    assert.equal(fromEpoch.resetAtText, "10-02 15:15");
    assert.equal(fromEpoch.countdown, "2d 3h 15m");

    const fromIso = kimi.resetInfo({ reset_at: "2026-10-02T15:15:00-03:00" }, NOW);
    assert.equal(fromIso.resetAtText, "10-02 15:15");
    assert.equal(fromIso.countdown, "2d 3h 15m");

    // Microsecond fractions are what the live endpoint stamps (verified
    // 2026-09-30); truncating to milliseconds must not fail the parse.
    const fromMicro = kimi.resetInfo({ reset_time: "2026-10-02T15:15:00.670345-03:00" }, NOW);
    assert.equal(fromMicro.resetAtText, "10-02 15:15");
    assert.equal(fromMicro.countdown, "2d 3h 15m");

    const fromMs = kimi.resetInfo({ reset_time: epochSec * 1000 }, NOW);
    assert.equal(fromMs.resetAtText, "10-02 15:15");
    assert.equal(fromMs.countdown, "2d 3h 15m");

    const fromDuration = kimi.resetInfo({ reset_in: 3600 }, NOW);
    assert.equal(fromDuration.resetAtText, "09-30 13:00");
    assert.equal(fromDuration.countdown, "1h 0m");

    // Already past: honest "0m" rather than a negative countdown (the
    // reference CLI shows the same).
    const past = kimi.resetInfo({ reset_in: -5 }, NOW);
    assert.equal(past.countdown, "0m");
    // An unparseable timestamp is not a reset; nor is an entry without one.
    assert.equal(kimi.resetInfo({ resetTime: "not a date" }, NOW), null);
    assert.equal(kimi.resetInfo({}, NOW), null);
    assert.equal(kimi.resetInfo(null, NOW), null);
});

test("countdownText always shows at least one unit", () => {
    assert.equal(kimi.countdownText(0), "0m");
    assert.equal(kimi.countdownText(45 * 60 * 1000), "45m");
    assert.equal(kimi.countdownText(5 * 3600 * 1000), "5h 0m");
    assert.equal(kimi.countdownText((2 * 86400 + 3 * 3600 + 5 * 60) * 1000), "2d 3h 5m");
});

/*
    Both payload shapes the endpoint has shipped. The rows are asserted field
    by field because they come from a vm realm.
*/
test("parseUsagePayload reads the current data[] shape", () => {
    const r = kimi.parseUsagePayload(
        JSON.stringify({
            data: [
                { model_name: "all", used: 100, limit: 400, reset_in: 7200 },
                { model_name: "kimi-k2", name: "kimi-k2-turbo", used: 50, limit: 100 },
                { model_name: "kimi-latest", used: 25, limit: 100, resetTime: "2026-10-02T00:00:00-03:00" },
                "not an object"
            ]
        }),
        NOW
    );
    assert.equal(r.ok, true);
    assert.equal(r.summary.kind, "summary");
    // The summary's own name is dropped: the UI localizes that label itself.
    assert.equal(r.summary.name, null);
    assert.equal(r.summary.used, 100);
    assert.equal(r.summary.limit, 400);
    assert.equal(r.summary.countdown, "2h 0m");

    assert.equal(r.limits.length, 2);
    assert.equal(r.limits[0].name, "kimi-k2-turbo");
    assert.equal(r.limits[0].used, 50);
    // model_name is only a fallback name, so it labels the row too.
    assert.equal(r.limits[1].name, "kimi-latest");
    assert.equal(r.limits[1].used, 25);
    assert.equal(r.limits[1].resetAtText, "10-02 00:00");
});

test("parseUsagePayload reads the older usage/limits shape", () => {
    const r = kimi.parseUsagePayload(
        JSON.stringify({
            usage: { used: 100, limit: 400, remaining: 300 },
            limits: [
                {
                    // Reset info sits inside `detail`, beside the numbers, the
                    // way the reference CLI reads it.
                    detail: { used: 50, limit: 100, resetTime: "2026-10-02T15:15:00-03:00" },
                    window: { duration: 300, timeUnit: "MINUTES" }
                },
                { detail: { used: 10, limit: 20 } }
            ]
        }),
        NOW
    );
    assert.equal(r.ok, true);
    assert.equal(r.summary.used, 100);
    assert.equal(r.summary.limit, 400);
    assert.equal(r.limits.length, 2);
    assert.equal(r.limits[0].window, "5h");
    assert.equal(r.limits[0].countdown, "2d 3h 15m");
    // A limit with numbers directly on it (no `detail` wrapper) still reads.
    assert.equal(r.limits[1].used, 10);
});

test("parseUsagePayload refuses what is not a usage payload", () => {
    // The 401 body the live endpoint returns (verified 2026-09-30) is JSON,
    // but not a usage payload — and the client never parses it, because the
    // status has already said everything.
    assert.equal(kimi.parseUsagePayload('{"error":{"message":"Invalid Authentication"}}').ok, false);
    assert.equal(kimi.parseUsagePayload("not json").error, "invalid-json");
    assert.equal(kimi.parseUsagePayload("{}").error, "empty");
    assert.equal(kimi.parseUsagePayload('{"data":[]}').error, "empty");
    assert.equal(kimi.parseUsagePayload('{"data":["nope"]}').error, "empty");
});

test("failureKind names the statuses a user can act on", () => {
    assert.equal(kimi.failureKind(401), "auth");
    assert.equal(kimi.failureKind(403), "forbidden");
    assert.equal(kimi.failureKind(429), "rate-limited");
    assert.equal(kimi.failureKind(404), "");
    assert.equal(kimi.failureKind(500), "");
    assert.equal(kimi.failureKind(0), "");
});

/*
    End to end against the development fixture, like api.test.mjs does for the
    DeepSeek mock: the widget's own parsing has to reproduce the numbers the
    mock declares, so the two halves cannot drift apart. The fixture mirrors
    the shape the live endpoint answers (verified with a real key, 2026-09-30).
*/
test("the pipeline reproduces the mock's own totals", () => {
    const r = kimi.parseUsagePayload(JSON.stringify(kimiUsagesPayload()), NOW);
    assert.equal(r.ok, true);
    assert.equal(r.summary.used, KIMI_QUOTA_USED);
    assert.equal(r.summary.limit, KIMI_QUOTA_LIMIT);
    assert.ok(r.summary.countdown.length > 0);
    // The limit row carries only `remaining`; used is derived from it.
    assert.equal(r.limits.length, 1);
    assert.equal(r.limits[0].window, "5h");
    assert.equal(r.limits[0].used, 5);
    assert.equal(r.limits[0].limit, 120);
    for (const row of [r.summary].concat(r.limits)) {
        assert.ok(row.used <= row.limit, "used exceeds limit");
    }
});

/*
    The recorded live probe (2026-09-30, api.kimi.com, real key): HTTP 200
    with the usage/limits shape, string amounts, TIME_UNIT_* enum and
    microsecond ISO stamps. The wallet object the payload also carries is
    dropped here — it holds account ids — and must not be needed for parsing.
    Numbers kept as answered; they are quota units, not tokens.
*/
test("parseUsagePayload reproduces the recorded live probe", () => {
    const live = `{
        "usage": {"limit": "100", "used": "3", "remaining": "97",
                  "resetTime": "2026-10-02T05:03:43.670345Z"},
        "limits": [{"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                    "detail": {"limit": "100", "remaining": "100",
                               "resetTime": "2026-09-30T04:03:43.670345Z"}}],
        "usages": {"limit_5h": {"used_ratio": 0, "reset_time": "2026-09-30T04:03:43Z"},
                   "limit_7d": {"used_ratio": 0.034605, "reset_time": "2026-10-02T05:03:42Z"}}
    }`;
    const probe = new Date("2026-09-30T04:15:00Z").getTime();
    const r = kimi.parseUsagePayload(live, probe);
    assert.equal(r.ok, true);
    assert.equal(r.summary.used, 3);
    assert.equal(r.summary.limit, 100);
    // 05:03:43Z is 02:03:43 at the fixed GMT-3 this file pins; from 04:15Z
    // that is two days and 48 minutes away (a zero hour count is omitted).
    assert.equal(r.summary.resetAtText, "10-02 02:03");
    assert.equal(r.summary.countdown, "2d 48m");
    // The raw reset time the weekly-quota reminder decides on.
    assert.ok(r.summary.resetAtMs > NOW, "resetAtMs is the future moment");
    assert.equal(r.limits.length, 1);
    assert.equal(r.limits[0].window, "5h");
    // detail carries only `remaining`: used is 100 - 100.
    assert.equal(r.limits[0].used, 0);
    assert.equal(r.limits[0].resetAtText, "09-30 01:03");
    assert.equal(r.limits[0].resetAtMs, Date.parse("2026-09-30T04:03:43.670Z"), "resetAtMs parsed from the payload");
});

test("the kimi wallet entry is distinct from the deepseek ones", () => {
    assert.equal(wallet.KIMI_API_KEY_ENTRY, "kimi-api-key");
    assert.notEqual(wallet.KIMI_API_KEY_ENTRY, wallet.API_KEY_ENTRY);
    assert.notEqual(wallet.KIMI_API_KEY_ENTRY, wallet.SESSION_TOKEN_ENTRY);
});

/*
    One value, two homes: the base URL default the widget falls back to
    (kimi.js) and the KConfigXT default the settings page stages. Changing one
    alone ships a settings page that offers a URL the widget would not use.
*/
test("the settings default base URL is the one the request falls back to", () => {
    const xml = readFileSync(new URL("../contents/config/main.xml", import.meta.url), "utf8");
    const entry = /<entry name="kimiBaseUrl"[^>]*>([\s\S]*?)<\/entry>/.exec(xml);
    assert.ok(entry, "contents/config/main.xml has a kimiBaseUrl entry");
    const def = /<default>([^<]*)<\/default>/.exec(entry[1]);
    assert.ok(def, "kimiBaseUrl has a default");
    assert.equal(def[1].trim(), kimi.DEFAULT_BASE, "KConfigXT kimiBaseUrl default");
});
