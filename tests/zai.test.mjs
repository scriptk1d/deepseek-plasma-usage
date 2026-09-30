/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { load } from "./load.mjs";
import {
    zaiQuotaPayload,
    zaiModelUsagePayload,
    ZAI_QUOTA_5H,
    ZAI_QUOTA_WEEKLY,
    ZAI_MONTHLY_LIMIT,
    ZAI_MONTHLY_USED,
    ZAI_SEVEN,
    ZAI_THIRTY
} from "./mock-platform-server.mjs";

const zai = load("contents/ui/js/zai.js");
const wallet = load("contents/ui/js/wallet.js");

// The window helpers and reset stamps work in the local zone; pin it like the
// other suites do.
process.env.TZ = "Etc/GMT+3";

// Fixed "now" for the deterministic assertions; nothing here is a real
// timestamp.
const NOW = new Date("2026-09-30T12:00:00-03:00").getTime();

test("urls: default base, trailing-slash repair, encoded window params", () => {
    assert.equal(zai.quotaUrl(""), "https://api.z.ai/api/monitor/usage/quota/limit");
    assert.equal(zai.quotaUrl("https://api.z.ai/"), "https://api.z.ai/api/monitor/usage/quota/limit");
    assert.equal(zai.quotaUrl("  "), "https://api.z.ai/api/monitor/usage/quota/limit");
    assert.equal(
        zai.quotaUrl("https://proxy.example") && zai.modelUsageUrl("https://proxy.example/", 1787886000, 1790478000),
        "https://proxy.example/api/monitor/usage/model-usage" +
            "?startTime=" +
            encodeURIComponent("2026-08-28 00:00:00") +
            "&endTime=" +
            encodeURIComponent("2026-09-27 00:00:00")
    );
});

test("usageWindows asks for 7 days back and same-day-last-month, both local", () => {
    const now = new Date("2026-09-30T18:12:43-03:00");
    const w = zai.usageWindows(now);
    assert.equal(zai.dateTimeParam(w.start7), "2026-09-23 00:00:00");
    assert.equal(zai.dateTimeParam(w.start30), "2026-08-30 00:00:00");
    assert.equal(zai.dateTimeParam(w.end), "2026-09-30 23:59:59");
});

test("authVariants tries the bare key first, Bearer second", () => {
    const variants = zai.authVariants(" test.key \n");
    assert.equal(variants.length, 2);
    assert.equal(variants[0].Authorization, "test.key");
    assert.equal(variants[1].Authorization, "Bearer test.key");
    // A pasted header line is peeled before either variant is built.
    assert.equal(zai.authVariants("Bearer test.key")[0].Authorization, "test.key");
});

/*
    The recorded live probe (2026-09-30, api.z.ai, real key): HTTP 200 with
    two TOKENS_LIMIT rows that carry only a percentage and a reset time, plus
    a TIME_LIMIT row whose `usage` IS the limit and whose `currentValue` is
    the used count. The account's own numbers are replaced; the shapes and
    the unit enums are as answered.
*/
test("parseQuotaLimit reproduces the recorded live probe", () => {
    const live = `{
        "code": 200, "msg": "Operation successful", "success": true,
        "data": {"limits": [
            {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 27,
             "nextResetTime": ${NOW + 2 * 3600 * 1000}},
            {"type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 6,
             "nextResetTime": ${NOW + 19 * 3600 * 1000}},
            {"type": "TIME_LIMIT", "unit": 5, "number": 1, "usage": 1000,
             "currentValue": 120, "remaining": 880, "percentage": 12,
             "nextResetTime": ${NOW + 9 * 86400 * 1000}}
        ], "level": "pro"}
    }`;
    const rows = zai.parseQuotaLimit(live, NOW);
    assert.ok(rows, "parses");
    // Sorted by reset time: the 5-hour window first — the panel's headline.
    assert.equal(rows.length, 3);
    assert.equal(rows[0].span, "5h");
    assert.equal(rows[0].percent, 27);
    assert.equal(rows[0].hasAmounts, false);
    assert.equal(rows[0].resetAtText, "09-30 14:00");
    assert.equal(rows[0].countdown, "2h 0m");
    assert.equal(rows[1].span, "1w");
    assert.equal(rows[1].percent, 6);
    // TIME_LIMIT: counts exist, `usage` is the limit.
    assert.equal(rows[2].span, "1mo");
    assert.equal(rows[2].hasAmounts, true);
    assert.equal(rows[2].used, 120);
    assert.equal(rows[2].limit, 1000);
    assert.equal(rows[2].percent, 12);
});

test("parseQuotaLimit handles the older absolute-counts shape and junk", () => {
    // What the reference tracker reads: currentValue = used, and the limit in
    // `usage` (a plain `limit` field wins when both exist).
    const older = zai.parseQuotaLimit(
        JSON.stringify({
            data: {
                limits: [{ type: "TOKENS_LIMIT", percentage: 42, currentValue: 840, usage: 2000, limit: 4000 }]
            }
        }),
        NOW
    );
    assert.equal(older[0].used, 840);
    assert.equal(older[0].limit, 4000, "an explicit `limit` beats the `usage` spelling");

    const usageOnly = zai.parseQuotaLimit(
        JSON.stringify({ limits: [{ type: "TOKENS_LIMIT", percentage: 42, currentValue: 840, usage: 2000 }] }),
        NOW
    );
    assert.equal(usageOnly[0].limit, 2000, "the `usage` spelling is the fallback");

    // No reset time: the row sorts last and carries no stamp.
    assert.equal(older[0].resetAtText, "");
    assert.equal(older[0].resetAtMs, 0);

    assert.equal(zai.parseQuotaLimit("not json", NOW), null);
    assert.equal(zai.parseQuotaLimit("{}", NOW), null);
    assert.equal(zai.parseQuotaLimit('{"limits":[]}', NOW), null);
    // An unknown unit enum renders as no span rather than a guessed label.
    const unknown = zai.parseQuotaLimit(
        JSON.stringify({ limits: [{ type: "TOKENS_LIMIT", unit: 9, number: 2, percentage: 5 }] }),
        NOW
    );
    assert.equal(unknown[0].span, "");
    // A seconds-scale nextResetTime is folded, like kimi.js folds timestamps.
    const seconds = zai.parseQuotaLimit(
        JSON.stringify({
            limits: [{ type: "TOKENS_LIMIT", percentage: 1, nextResetTime: (NOW + 3600 * 1000) / 1000 }]
        }),
        NOW
    );
    assert.equal(seconds[0].countdown, "1h 0m");
});

test("parseModelUsage reads totals and tolerates their absence", () => {
    // Compared field by field: results come from a vm realm (see api.test.mjs).
    const full = zai.parseModelUsage(
        JSON.stringify({ data: { totalUsage: { totalModelCallCount: "412", totalTokensUsage: 68204551 } } })
    );
    assert.equal(full.prompts, 412);
    assert.equal(full.tokens, 68204551);
    // An unwrapped payload (no `data` envelope) is accepted too.
    const plain = zai.parseModelUsage(JSON.stringify({ totalUsage: { totalModelCallCount: 5, totalTokensUsage: 6 } }));
    assert.equal(plain.prompts, 5);
    assert.equal(plain.tokens, 6);
    const empty = zai.parseModelUsage(JSON.stringify({ data: {} }));
    assert.equal(empty.prompts, 0);
    assert.equal(empty.tokens, 0);
    const broken = zai.parseModelUsage("not json");
    assert.equal(broken.prompts, 0);
    assert.equal(broken.tokens, 0);
});

test("failureKind names the statuses a user can act on", () => {
    assert.equal(zai.failureKind(401), "auth");
    assert.equal(zai.failureKind(403), "forbidden");
    assert.equal(zai.failureKind(429), "rate-limited");
    assert.equal(zai.failureKind(404), "");
    assert.equal(zai.failureKind(500), "");
});

/*
    End to end against the development fixture: the widget's own parsing has
    to reproduce the numbers the mock declares (see api.test.mjs for the same
    idea on the DeepSeek side).
*/
test("the pipeline reproduces the mock's own totals", () => {
    const rows = zai.parseQuotaLimit(JSON.stringify(zaiQuotaPayload()), NOW);
    assert.ok(rows);
    assert.equal(rows.length, 3);
    assert.equal(rows[0].percent, ZAI_QUOTA_5H);
    assert.equal(rows[0].span, "5h");
    assert.equal(rows[1].percent, ZAI_QUOTA_WEEKLY);
    assert.equal(rows[2].used, ZAI_MONTHLY_USED);
    assert.equal(rows[2].limit, ZAI_MONTHLY_LIMIT);

    const seven = zai.parseModelUsage(
        JSON.stringify(zaiModelUsagePayload("?startTime=" + zai.dateTimeParam(zai.usageWindows(new Date(NOW)).start7)))
    );
    assert.equal(seven.prompts, ZAI_SEVEN.prompts);
    assert.equal(seven.tokens, ZAI_SEVEN.tokens);
    const thirty = zai.parseModelUsage(
        JSON.stringify(zaiModelUsagePayload("?startTime=" + zai.dateTimeParam(zai.usageWindows(new Date(NOW)).start30)))
    );
    assert.equal(thirty.prompts, ZAI_THIRTY.prompts);
    assert.equal(thirty.tokens, ZAI_THIRTY.tokens);
});

test("the zai wallet entry is distinct from the others", () => {
    assert.equal(wallet.ZAI_API_KEY_ENTRY, "zai-api-key");
    assert.notEqual(wallet.ZAI_API_KEY_ENTRY, wallet.API_KEY_ENTRY);
    assert.notEqual(wallet.ZAI_API_KEY_ENTRY, wallet.KIMI_API_KEY_ENTRY);
});

/*
    One value, two homes: the base URL default the widget falls back to
    (zai.js) and the KConfigXT default the settings page stages.
*/
test("the settings default base URL is the one the request falls back to", () => {
    const xml = readFileSync(new URL("../contents/config/main.xml", import.meta.url), "utf8");
    const entry = /<entry name="zaiBaseUrl"[^>]*>([\s\S]*?)<\/entry>/.exec(xml);
    assert.ok(entry, "contents/config/main.xml has a zaiBaseUrl entry");
    const def = /<default>([^<]*)<\/default>/.exec(entry[1]);
    assert.ok(def, "zaiBaseUrl has a default");
    assert.equal(def[1].trim(), zai.DEFAULT_BASE, "KConfigXT zaiBaseUrl default");
});
