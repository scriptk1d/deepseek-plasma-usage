/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    Dev-only mock of the DeepSeek platform API: serves the payload shapes
    recorded in docs/state/api-contract.md so the widget's rich mode can be
    exercised, and its README screenshots taken, without live credentials.

        node tests/mock-platform-server.mjs [port] [--echo-auth]

    Point `PLATFORM_BASE` in contents/ui/js/api.js at it (translate/build.sh's
    sibling, tests/capture-screenshots.sh, does this and restores it).

    `--echo-auth` reports the shape of the authorization header of every request. The
    mock accepts any token, so nothing else can show whether a credential was
    normalised on the way out -- which is the difference between a working session
    token and "Authorization Failed (invalid token)". It describes the header rather
    than printing it, so a token never lands in a log.

    The numbers are **invented, on purpose**. An earlier revision of this file was a
    snapshot of a real account's usage page, which meant the committed screenshots
    published that account's balance, its spend and the names of its API keys. Nothing
    here belongs to anyone:

      balance (topped up)        $12.48       no bonus credit
      lifetime / last-30-day     $4.62
      last-30-day requests       910          863 flash + 47 v4-pro
      last-30-day tokens         159,098,619  152,884,031 flash + 6,214,588 v4-pro
      daily cost                 0.42 + (0.69 + 1.25) + 0.95 + 1.31 = 4.62

    Four of the thirty days have activity, which is what makes the sparkline sparse
    and the "Today" row meaningful. The key names are placeholders for the same
    reason the figures are.

    `--check` recomputes every total from the same tables and prints them, so the
    arithmetic above is verified rather than asserted in a comment.
*/
import http from "node:http";
import { pathToFileURL } from "node:url";

// True only when this file is the process entry point. The payload builders are
// exported so api.test.mjs can push them through the widget's own pipeline;
// importing must not start a server.
function isMain() {
    return !!process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url;
}

const port = Number(process.argv[2] || 8731);
const echoAuth = process.argv.includes("--echo-auth");

const DAYS = 30;

// One entry per day with activity: `back` days before today, split by model.
const ACTIVE_DAYS = [
    { back: 4, flash: 0.42, pro: 0 },
    { back: 2, flash: 0.69, pro: 1.25 },
    { back: 1, flash: 0.95, pro: 0 },
    { back: 0, flash: 1.31, pro: 0 }
];

// 30-day totals, split across the keys the account has. The shares are applied
// with distribute() below, so the per-key figures always sum to these exactly.
// `pro` marks the one key that has used the larger model; it is a flag rather
// than a name comparison so that renaming a placeholder key cannot silently
// change which model's usage it is given.
const KEYS = [
    {
        tracking_id: "00000000-0000-4000-8000-000000000001",
        name: "laptop",
        sensitive_id: "sk-11111***********************1111",
        flashShare: 0.35
    },
    {
        tracking_id: "00000000-0000-4000-8000-000000000002",
        name: "ci-runner",
        sensitive_id: "sk-22222***********************2222",
        flashShare: 0.5,
        pro: true
    },
    {
        tracking_id: "00000000-0000-4000-8000-000000000003",
        name: "sandbox",
        sensitive_id: "sk-33333***********************3333",
        flashShare: 0.15
    }
];

const MODELS = {
    "deepseek-flash": { tokens: 152884031, requests: 863 },
    "deepseek-v4-pro": { tokens: 6214588, requests: 47 }
};

const BALANCE = "12.4800000000000000";
const BONUS = "0";
const LIFETIME_COST = "4.6200000000000000";

/*
    Kimi Code (Coding Plan) usage, served under /coding/v1/usages. The shape
    is the one the live endpoint answers (verified 2026-09-30, with a real
    key): a `usage` summary plus a `limits` array, amounts as strings,
    TIME_UNIT_* enums and ISO timestamps with microseconds — plus `usages`
    ratio objects the widget does not read but must tolerate. Numbers are
    invented like everything else here: a weekly quota at 30%.
*/
const KIMI_QUOTA_LIMIT = 120;
const KIMI_QUOTA_USED = 36;

function kimiUsagesPayload() {
    const iso = ms => new Date(Date.now() + ms).toISOString();
    return {
        usage: {
            limit: String(KIMI_QUOTA_LIMIT),
            used: String(KIMI_QUOTA_USED),
            remaining: String(KIMI_QUOTA_LIMIT - KIMI_QUOTA_USED),
            resetTime: iso(2 * 86400 * 1000 + 3 * 3600 * 1000 + 15 * 60 * 1000)
        },
        limits: [
            {
                window: { duration: 300, timeUnit: "TIME_UNIT_MINUTE" },
                detail: {
                    limit: "120",
                    remaining: "115",
                    resetTime: iso(45 * 60 * 1000)
                }
            }
        ],
        usages: {
            limit_5h: { used_ratio: 0.041, reset_time: iso(45 * 60 * 1000) },
            limit_7d: { used_ratio: 0.3, reset_time: iso(2 * 86400 * 1000) }
        }
    };
}

/*
    Z.ai (GLM Coding Plan) monitor endpoints, under /api/monitor/usage/. The
    quota shape is the one recorded live (2026-09-30): TOKENS_LIMIT rows carry
    only a percentage and a reset time, the TIME_LIMIT row carries counts
    where `usage` IS the limit. Numbers invented as usual.
*/
const ZAI_QUOTA_5H = 27;
const ZAI_QUOTA_WEEKLY = 6;
const ZAI_MONTHLY_LIMIT = 1000;
const ZAI_MONTHLY_USED = 120;
const ZAI_SEVEN = { prompts: 412, tokens: 68204551 };
const ZAI_THIRTY = { prompts: 1730, tokens: 291882016 };

function zaiEnvelope(data) {
    return { code: 200, msg: "Operation successful", data: data, success: true };
}

function zaiQuotaPayload() {
    const ms = Date.now();
    return zaiEnvelope({
        limits: [
            { type: "TOKENS_LIMIT", unit: 3, number: 5, percentage: ZAI_QUOTA_5H, nextResetTime: ms + 2 * 3600 * 1000 },
            {
                type: "TOKENS_LIMIT",
                unit: 6,
                number: 1,
                percentage: ZAI_QUOTA_WEEKLY,
                nextResetTime: ms + 19 * 3600 * 1000
            },
            {
                type: "TIME_LIMIT",
                unit: 5,
                number: 1,
                usage: ZAI_MONTHLY_LIMIT,
                currentValue: ZAI_MONTHLY_USED,
                remaining: ZAI_MONTHLY_LIMIT - ZAI_MONTHLY_USED,
                percentage: 12,
                nextResetTime: ms + 9 * 86400 * 1000
            }
        ],
        level: "pro"
    });
}

function zaiModelUsagePayload(rawUrl) {
    // Distinguish the two windows by the startTime the widget asked for: 7
    // days back is the weekly payload, anything longer the monthly one.
    let days = 30;
    try {
        const start = new URL(rawUrl, "http://localhost").searchParams.get("startTime") || "";
        const parsed = Date.parse(start.replace(" ", "T"));
        if (!isNaN(parsed)) {
            days = Math.round((Date.now() - parsed) / 86400000);
        }
    } catch (e) {
        // keep the 30-day default
    }
    const totals = days <= 8 ? ZAI_SEVEN : ZAI_THIRTY;
    return zaiEnvelope({
        totalUsage: {
            totalModelCallCount: totals.prompts,
            totalTokensUsage: totals.tokens
        },
        granularity: "hourly"
    });
}

// Fractions of a bucket's tokens: completions, then cached vs missed prompt.
const RESPONSE_SHARE = 0.005;
const CACHE_HIT_SHARE = 0.98;

// Split `total` into whole numbers proportional to `weights`, summing to
// `total` exactly (largest-remainder, so no rounding drift).
function distribute(total, weights) {
    const sum = weights.reduce((a, b) => a + b, 0);
    if (total <= 0 || sum <= 0) {
        return weights.map(() => 0);
    }
    const exact = weights.map(w => (total * w) / sum);
    const out = exact.map(Math.floor);
    const residual = total - out.reduce((a, b) => a + b, 0);
    const order = exact.map((v, i) => ({ i, frac: v - Math.floor(v) })).sort((a, b) => b.frac - a.frac);
    for (let k = 0; k < residual; k++) {
        out[order[k % order.length].i] += 1;
    }
    return out;
}

function localMidnight(daysBack) {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - daysBack);
    return Math.floor(d.getTime() / 1000);
}

// tokens/requests per (key, model): per-key split of the model total, then that
// key's own split across the days it was active, weighted by its cost.
function seriesFor(key, model) {
    const total = MODELS[model];
    const isFlash = model === "deepseek-flash";

    const keyTokens = isFlash
        ? distribute(
              total.tokens,
              KEYS.map(k => k.flashShare)
          )[KEYS.indexOf(key)]
        : total.tokens; // v4-pro belongs to a single key
    const keyRequests = isFlash
        ? distribute(
              total.requests,
              KEYS.map(k => k.flashShare)
          )[KEYS.indexOf(key)]
        : total.requests;

    // The model is only used on the days this key spent money on it.
    const days = ACTIVE_DAYS.filter(d => (isFlash ? d.flash : d.pro) > 0);
    const weights = days.map(d => (isFlash ? d.flash : d.pro) * (isFlash ? key.flashShare : 1));
    const tokensPerDay = distribute(keyTokens, weights);
    const requestsPerDay = distribute(keyRequests, weights);

    const buckets = [];
    for (let back = DAYS - 1; back >= 0; back--) {
        const at = days.findIndex(d => d.back === back);
        const tokens = at < 0 ? 0 : tokensPerDay[at];
        const requests = at < 0 ? 0 : requestsPerDay[at];
        const response = Math.round(tokens * RESPONSE_SHARE);
        const input = tokens - response;
        const cacheHit = Math.round(input * CACHE_HIT_SHARE);
        buckets.push({
            time: localMidnight(back),
            tokens,
            requests,
            usage: {
                RESPONSE_TOKEN: response,
                REQUEST: requests,
                PROMPT_CACHE_HIT_TOKEN: cacheHit,
                PROMPT_CACHE_MISS_TOKEN: input - cacheHit
            }
        });
    }
    return { buckets, keyTokens, keyRequests };
}

// Cost per (key, model): the day's cost times the key's share.
function costBucketsFor(key, model) {
    const isFlash = model === "deepseek-flash";
    const buckets = [];
    for (let back = DAYS - 1; back >= 0; back--) {
        const day = ACTIVE_DAYS.find(d => d.back === back);
        const dayCost = day ? (isFlash ? day.flash : day.pro) : 0;
        const share = isFlash ? key.flashShare : key.pro ? 1 : 0;
        buckets.push({ time: localMidnight(back), cost: (dayCost * share).toFixed(16) });
    }
    return buckets;
}

function apiKey(key) {
    return {
        tracking_id: key.tracking_id,
        name: key.name,
        sensitive_id: key.sensitive_id,
        valid: true,
        key_type: "NORMAL"
    };
}

function modelsFor(key) {
    return Object.keys(MODELS).filter(m => m === "deepseek-flash" || key.pro);
}

function costPayload() {
    const data = [];
    for (const key of KEYS) {
        for (const model of modelsFor(key)) {
            data.push({
                currency: "USD",
                series: [{ api_key: apiKey(key), model, buckets: costBucketsFor(key, model) }]
            });
        }
    }
    return {
        code: 0,
        msg: "",
        data: {
            biz_code: 0,
            biz_msg: "",
            biz_data: {
                start: localMidnight(DAYS - 1),
                end: localMidnight(-1),
                bucket: 86400,
                models: Object.keys(MODELS),
                data
            }
        }
    };
}

function amountPayload() {
    const series = [];
    for (const key of KEYS) {
        for (const model of modelsFor(key)) {
            series.push({
                api_key: apiKey(key),
                model,
                buckets: seriesFor(key, model).buckets.map(b => ({
                    time: b.time,
                    usage: b.usage
                }))
            });
        }
    }
    return {
        code: 0,
        msg: "",
        data: {
            biz_code: 0,
            biz_msg: "",
            biz_data: {
                start: localMidnight(DAYS - 1),
                end: localMidnight(-1),
                bucket: 86400,
                models: Object.keys(MODELS),
                series
            }
        }
    };
}

function summaryPayload() {
    return {
        code: 0,
        msg: "",
        data: {
            biz_code: 0,
            biz_msg: "",
            biz_data: {
                normal_wallets: [{ currency: "USD", balance: BALANCE, token_estimation: "0" }],
                bonus_wallets: [{ currency: "USD", balance: BONUS, token_estimation: "0" }],
                total_costs: [{ currency: "USD", amount: LIFETIME_COST }]
            }
        }
    };
}

// Recompute every headline figure straight from the tables above.
function reconcile() {
    let cost = 0;
    let requests = 0;
    let tokens = 0;
    for (const key of KEYS) {
        for (const model of modelsFor(key)) {
            for (const b of costBucketsFor(key, model)) {
                cost += parseFloat(b.cost);
            }
            const s = seriesFor(key, model);
            for (const b of s.buckets) {
                requests += b.usage.REQUEST;
                tokens += b.usage.RESPONSE_TOKEN + b.usage.PROMPT_CACHE_HIT_TOKEN + b.usage.PROMPT_CACHE_MISS_TOKEN;
            }
        }
    }
    return { cost, requests, tokens };
}

if (isMain() && process.argv.includes("--check")) {
    const { cost, requests, tokens } = reconcile();
    const ok = Math.abs(cost - 4.62) < 1e-9 && requests === 910 && tokens === 159098619;
    console.log(`cost     ${cost.toFixed(4)}  (want 4.6200)`);
    console.log(`requests ${requests}     (want 910)`);
    console.log(`tokens   ${tokens}  (want 159098619)`);
    console.log(ok ? "mock-platform-server: consistent" : "mock-platform-server: NOT consistent");
    process.exit(ok ? 0 : 1);
}

const routes = {
    "/api/v0/users/get_user_summary": summaryPayload,
    "/api/v0/usage/by_api_key/cost": costPayload,
    "/api/v0/usage/by_api_key/amount": amountPayload,
    // Kimi Code usage; the singular /coding/v1/usage is deliberately absent,
    // like on the live endpoint, so the fallback path is exercised only
    // against a base URL that serves it.
    "/coding/v1/usages": kimiUsagesPayload,
    // Z.ai monitor endpoints; model-usage answers by the window asked.
    "/api/monitor/usage/quota/limit": zaiQuotaPayload,
    "/api/monitor/usage/model-usage": zaiModelUsagePayload
};

// Everything below is described rather than echoed, for two reasons. CodeQL's
// log-injection query is right that the request line and the authorization header are
// attacker-controlled and that echoing them into a log is an injection sink; and a
// session token does not belong in a log file that people paste into bug reports
// anyway. The question this feature exists to answer is whether the credential was
// normalised on the way out, and that is a question about its *shape*.
//
// Every string returned here is a constant, so nothing request-derived reaches the
// log. A route is reported only if it is one of the known ones.
function routeLabel(rawUrl) {
    const path = new URL(rawUrl, "http://localhost").pathname;
    for (const known of Object.keys(routes)) {
        if (known === path) {
            return known;
        }
    }
    return "(unknown route)";
}

function describeAuthorization(header) {
    const value = header === undefined || header === null ? "" : String(header).trim();
    if (!value) {
        return "(absent)";
    }
    if (!/^Bearer[ \t]+/i.test(value)) {
        return "present, but not a Bearer header";
    }
    const token = value.replace(/^Bearer[ \t]+/i, "");
    if (token.startsWith("{")) {
        return "Bearer <a JSON wrapper, not a token -- unwrapping is broken>";
    }
    if (token.length < 16) {
        return "Bearer <suspiciously short>";
    }
    return "Bearer <a bare token>";
}

const server = http.createServer((req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (echoAuth) {
        console.log(routeLabel(req.url));
        console.log(`  authorization: ${describeAuthorization(req.headers.authorization)}`);
    }
    const handler = routes[path];
    if (!handler) {
        res.writeHead(404, { "content-type": "application/json" });
        res.end(JSON.stringify({ detail: "Not Found" }));
        return;
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(handler(req.url)));
});

if (isMain()) {
    server.listen(port, "127.0.0.1", () => {
        console.log("mock platform API on http://127.0.0.1:" + port);
    });
}

export {
    costPayload,
    amountPayload,
    summaryPayload,
    kimiUsagesPayload,
    zaiQuotaPayload,
    zaiModelUsagePayload,
    reconcile,
    MODELS,
    BALANCE,
    BONUS,
    LIFETIME_COST,
    KIMI_QUOTA_USED,
    KIMI_QUOTA_LIMIT,
    ZAI_QUOTA_5H,
    ZAI_QUOTA_WEEKLY,
    ZAI_MONTHLY_LIMIT,
    ZAI_MONTHLY_USED,
    ZAI_SEVEN,
    ZAI_THIRTY
};
