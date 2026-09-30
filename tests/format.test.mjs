/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { load } from "./load.mjs";

const fmt = load("contents/ui/js/format.js");

test("money formats with currency symbols", () => {
    assert.equal(fmt.money(7.78, "USD"), "$7.78");
    assert.equal(fmt.money("7.78", "USD"), "$7.78");
    // CLDR tells CNY and JPY apart in English, and uses the code for some
    // currencies; a bare code is spaced off the digits with a no-break space.
    assert.equal(fmt.money(110, "CNY"), "CN\u00A5110.00");
    assert.equal(fmt.money(110, "CNY", "zh_CN"), "\u00A5110.00");
    // The symbol list wins over ICU's English habit of spelling out the code.
    assert.equal(fmt.money(1, "SEK"), "kr\u00A01.00");
    assert.equal(fmt.money(1, "RUB"), "\u20BD1.00");
    assert.equal(fmt.money(1, "XYZ"), "XYZ\u00A01.00");
    assert.equal(fmt.money(1, ""), "1.00");
});

test("money uses more precision for small amounts", () => {
    assert.equal(fmt.money(0.0001, "USD"), "$0.0001");
    assert.equal(fmt.money(0.0123, "USD"), "$0.012");
    assert.equal(fmt.money(0.5, "USD"), "$0.500");
});

test("money handles invalid input", () => {
    assert.equal(fmt.money(NaN, "USD"), "\u2014");
    assert.equal(fmt.money("nope", "USD"), "\u2014");
});

test("compactNumber scales and trims", () => {
    assert.equal(fmt.compactNumber(0), "0");
    assert.equal(fmt.compactNumber(999), "999");
    assert.equal(fmt.compactNumber(1000), "1K");
    assert.equal(fmt.compactNumber(1234), "1.2K");
    assert.equal(fmt.compactNumber(1500000), "1.5M");
    assert.equal(fmt.compactNumber(2000000000), "2B");
    assert.equal(fmt.tokens(80441344), "80.4M");
});

test("daysLeft guards against non-positive burn", () => {
    assert.equal(fmt.daysLeft(10, 0), null);
    assert.equal(fmt.daysLeft(10, -1), null);
    assert.equal(fmt.daysLeft(10, NaN), null);
    assert.equal(fmt.daysLeft(10, 2), 5);
});

test("daysLeftText renders coarse buckets", () => {
    assert.equal(fmt.daysLeftText(10, 0), "\u2014");
    assert.equal(fmt.daysLeftText(400, 1), ">1y");
    assert.equal(fmt.daysLeftText(20, 1), "20d");
    assert.equal(fmt.daysLeftText(2.5, 1), "2.5d");
});

test("hideable masks values in privacy mode", () => {
    assert.equal(fmt.hideable("$3.20", false), "$3.20");
    assert.equal(fmt.hideable("$3.20", true), "\u2022\u2022\u2022");
});

test("percent and shortDay", () => {
    assert.equal(fmt.percent(1, 4), "25%");
    assert.equal(fmt.percent(1, 0), "\u2014");
    assert.match(fmt.shortDay(1790305200), /^\d\d-\d\d$/);
});

const metricValues = {
    currency: "USD",
    balance: 7.78,
    todayCost: 0.42,
    todayTokens: 1500000,
    periodCost: 2.2,
    lifetimeCost: 12.5,
    hasLifetime: true,
    hidden: false
};

test("metricText selects the configured panel value", () => {
    assert.equal(fmt.metricText(fmt.METRIC_BALANCE, metricValues), "$7.78");
    assert.equal(fmt.metricText(fmt.METRIC_TODAY_COST, metricValues), "$0.420");
    assert.equal(fmt.metricText(fmt.METRIC_TODAY_TOKENS, metricValues), "1.5M");
    assert.equal(fmt.metricText(fmt.METRIC_PERIOD_COST, metricValues), "$2.20");
    assert.equal(fmt.metricText(fmt.METRIC_LIFETIME_COST, metricValues), "$12.50");
});

test("metricText falls back to balance and marks missing lifetime data", () => {
    assert.equal(fmt.metricText(undefined, metricValues), "$7.78");
    assert.equal(fmt.metricText(fmt.METRIC_LIFETIME_COST, { currency: "USD", hasLifetime: false }), "\u2014");
});

test("metricText renders the Kimi quota metrics", () => {
    const kimi = Object.assign({}, metricValues, {
        hasKimi: true,
        kimiWeeklyUsed: 18934776,
        kimiWeeklyLimit: 51200000
    });
    assert.equal(fmt.metricText(fmt.METRIC_KIMI_WEEKLY_USED, kimi), "37%");
    assert.equal(fmt.metricText(fmt.METRIC_KIMI_QUOTA_LEFT, kimi), "32.3M");
    // No quota behind the metric: a dash, not a zero.
    assert.equal(fmt.metricText(fmt.METRIC_KIMI_WEEKLY_USED, { hasKimi: false }), "\u2014");
    assert.equal(fmt.metricText(fmt.METRIC_KIMI_QUOTA_LEFT, { hasKimi: false }), "\u2014");
    assert.equal(
        fmt.metricText(fmt.METRIC_KIMI_WEEKLY_USED, { hasKimi: true, kimiWeeklyUsed: 1, kimiWeeklyLimit: 0 }),
        "\u2014"
    );
});

test("metricText renders the Z.ai percent metrics", () => {
    const zai = Object.assign({}, metricValues, { hasZai: true, zaiPercent: 27 });
    assert.equal(fmt.metricText(fmt.METRIC_ZAI_WINDOW_USED, zai), "27%");
    assert.equal(fmt.metricText(fmt.METRIC_ZAI_QUOTA_LEFT, zai), "73%");
    // No quota behind the metric: a dash, not a zero.
    assert.equal(fmt.metricText(fmt.METRIC_ZAI_WINDOW_USED, { hasZai: false }), "\u2014");
    assert.equal(fmt.metricText(fmt.METRIC_ZAI_QUOTA_LEFT, { hasZai: false }), "\u2014");
    // A fraction rounds, and the left-over share can never go below zero.
    assert.equal(fmt.metricText(fmt.METRIC_ZAI_WINDOW_USED, { hasZai: true, zaiPercent: 27.4 }), "27%");
    assert.equal(fmt.metricText(fmt.METRIC_ZAI_QUOTA_LEFT, { hasZai: true, zaiPercent: 99.6 }), "0%");
});

/*
    The two sentinels are not settings entries any more: 9 was the fixed
    "all providers" mode the checkbox list replaces, and 10 is what an
    unchecked list stores ("icon only"), so an explicit empty choice survives
    a restart. Their numbers are load-bearing either way — they must stay
    behind every per-provider metric, and the config entry that stores the
    composition must exist beside them.
*/
test("the composition sentinels sit after every per-provider metric", () => {
    assert.equal(fmt.METRIC_ALL_PROVIDERS, 9);
    assert.equal(fmt.METRIC_ICON_ONLY, 10);
    assert.ok(fmt.METRIC_ALL_PROVIDERS > fmt.METRIC_ZAI_QUOTA_LEFT);
    assert.ok(fmt.METRIC_ICON_ONLY > fmt.METRIC_ALL_PROVIDERS);

    // One value, three homes again: the StringList the settings write, the
    // legacy Int they fall back to, and the constants both interpret.
    const xml = readFileSync(new URL("../contents/config/main.xml", import.meta.url), "utf8");
    assert.match(xml, /<entry name="panelMetrics" type="StringList">/, "main.xml has the panelMetrics StringList");
    assert.match(xml, /<entry name="panelMetric" type="Int">/, "main.xml keeps the legacy panelMetric Int");
});

/*
    Each provider icon ships as two files — a black glyph for light themes and
    a "-dark" white one — because currentColor resolves to plain black in a
    QML Image and would vanish on a dark panel. The names, the variant picker
    and the per-brand optical scale are pinned here: swapping art must not
    require touching QML, a renamed file would silently render as nothing,
    and the full-width Z.ai diagonal needs a smaller box than the solid
    letterforms to read as the same weight.
*/
test("provider icon names are pinned, both variants exist, and the picker is total", () => {
    // Field by field: the table comes from a vm realm (see api.test.mjs).
    assert.equal(fmt.PROVIDER_ICONS.deepseek.path, "../icons/deepseek.svg");
    assert.equal(fmt.PROVIDER_ICONS.kimi.path, "../icons/kimi.svg");
    assert.equal(fmt.PROVIDER_ICONS.zai.path, "../icons/zai.svg");
    assert.equal(Object.keys(fmt.PROVIDER_ICONS).length, 3, "no unnamed provider icons");

    // Every scale is a sane multiplier, and the wide diagonal scales down.
    for (const name of Object.keys(fmt.PROVIDER_ICONS)) {
        const scale = fmt.PROVIDER_ICONS[name].scale;
        assert.ok(scale >= 0.5 && scale <= 1.5, `${name} scale ${scale} is sane`);
    }
    assert.ok(fmt.PROVIDER_ICONS.zai.scale < 1, "the full-width Z.ai diagonal scales down");

    const kimi = fmt.PROVIDER_ICONS.kimi;
    assert.equal(fmt.iconVariant(kimi, false), "../icons/kimi.svg");
    assert.equal(fmt.iconVariant(kimi, true), "../icons/kimi-dark.svg");
    assert.equal(fmt.iconVariant(kimi, undefined), "../icons/kimi.svg");
    assert.equal(fmt.iconVariant(null, true), "", "no entry, no variant to break");
    assert.equal(fmt.iconHeight(kimi, 16), 16);
    assert.equal(
        fmt.iconHeight(fmt.PROVIDER_ICONS.zai, 16),
        Math.round(16 * fmt.PROVIDER_ICONS.zai.scale),
        "the Z.ai box is its scaled height"
    );
    assert.equal(fmt.iconHeight(null, 16), 16, "no entry, no scaling");

    for (const name of ["deepseek", "kimi", "zai"]) {
        for (const variant of ["", "-dark"]) {
            const file = new URL("../contents/icons/" + name + variant + ".svg", import.meta.url);
            assert.ok(existsSync(file), name + variant + ".svg exists");
            assert.match(readFileSync(file, "utf8"), /<svg[\s\S]*<\/svg>/, name + variant + ".svg is an SVG");
        }
    }
});

test("metricText honours privacy mode", () => {
    const hidden = Object.assign({}, metricValues, { hidden: true });
    assert.equal(fmt.metricText(fmt.METRIC_BALANCE, hidden), "\u2022\u2022\u2022");
    assert.equal(fmt.metricText(fmt.METRIC_TODAY_TOKENS, hidden), "\u2022\u2022\u2022");
    assert.equal(
        fmt.metricText(
            fmt.METRIC_KIMI_WEEKLY_USED,
            Object.assign({}, hidden, { hasKimi: true, kimiWeeklyUsed: 1, kimiWeeklyLimit: 4 })
        ),
        "\u2022\u2022\u2022"
    );
});

// The popup shows exact counts so its figures can be reconciled with the
// platform's own page; compactNumber() remains the panel's form.
test("grouped renders exact counts with thousands separators", () => {
    assert.equal(fmt.grouped(0), "0");
    assert.equal(fmt.grouped(7), "7");
    assert.equal(fmt.grouped(999), "999");
    assert.equal(fmt.grouped(1000), "1,000");
    assert.equal(fmt.grouped(1325), "1,325");
    assert.equal(fmt.grouped(297270684), "297,270,684");
    assert.equal(fmt.grouped(1234567890123), "1,234,567,890,123");
    assert.equal(fmt.grouped(1234.6), "1,235"); // rounds, never truncates
    assert.equal(fmt.grouped("-1234"), "-1,234");
    assert.equal(fmt.grouped("297270684"), "297,270,684"); // API values are strings
    assert.equal(fmt.grouped(NaN), "\u2014");
    assert.equal(fmt.grouped("nonsense"), "\u2014");
});

/*
    Number and money rendering per locale, transcribed from CLDR through ICU.
    `node -e 'new Intl.NumberFormat("es-CL", {style:"currency",
    currency:"USD"}).format(1234567.89)'` prints the money column, which is how the
    table in format.js was written; these assertions are that same output, so a bad
    transcription fails here instead of only in a screenshot.
*/
const LOCALE_CASES = [
    // locale,      number for 1234567.89,   money for 1234567.89 USD
    ["en_US", "1,234,567.89", "$1,234,567.89"],
    ["en", "1,234,567.89", "$1,234,567.89"],
    ["en_IN", "12,34,567.89", "$12,34,567.89"], // Indian grouping: 2,2,3
    ["hi_IN", "12,34,567.89", "$12,34,567.89"],
    ["zh_CN", "1,234,567.89", "US$1,234,567.89"], // US$ so it is not read as \u00A5
    ["id_ID", "1.234.567,89", "US$1.234.567,89"],
    ["fr_FR", "1\u202F234\u202F567,89", "1\u202F234\u202F567,89\u00A0$US"],
    ["ru_RU", "1\u00A0234\u00A0567,89", "1\u00A0234\u00A0567,89\u00A0$"],
    ["ru_BY", "1\u00A0234\u00A0567,89", "1\u00A0234\u00A0567,89\u00A0$"],
    ["es_ES", "1.234.567,89", "1.234.567,89\u00A0US$"],
    ["es", "1.234.567,89", "1.234.567,89\u00A0US$"], // a bare "es" is Spain
    ["es_419", "1,234,567.89", "USD\u00A01,234,567.89"],
    ["es_CL", "1.234.567,89", "US$1.234.567,89"],
    ["es_AR", "1.234.567,89", "US$\u00A01.234.567,89"],
    ["es_MX", "1,234,567.89", "USD\u00A01,234,567.89"],
    ["es_CU", "1,234,567.89", "US$1,234,567.89"],
    // Unknown tags fall back to English rather than throwing.
    ["pt_PT", "1,234,567.89", "$1,234,567.89"],
    ["", "1,234,567.89", "$1,234,567.89"],
    ["zh_Hans_CN", "1,234,567.89", "US$1,234,567.89"]
];

test("numbers and money follow the locale", () => {
    for (const [locale, number, money] of LOCALE_CASES) {
        assert.equal(fmt.formatNumber(1234567.89, locale, 2), number, `number ${locale}`);
        assert.equal(fmt.money(1234567.89, "USD", locale, 2), money, `money ${locale}`);
    }
});

test("grouping only applies where CLDR says it does", () => {
    // Spain's minimumGroupingDigits is 2: one separator would leave a lone
    // leading digit, so 1000 has none while longer numbers still group.
    assert.equal(fmt.formatNumber(1000, "es_ES", 2), "1000,00");
    assert.equal(fmt.formatNumber(10000, "es_ES", 2), "10.000,00");
    assert.equal(fmt.formatNumber(1234567890, "es_ES", 2), "1.234.567.890,00");
    // Its Latin-American neighbours do group 1000.
    assert.equal(fmt.formatNumber(1000, "es_CL", 2), "1.000,00");
    assert.equal(fmt.formatNumber(1000, "es_MX", 2), "1,000.00");
    assert.equal(fmt.formatNumber(1000, "en_IN", 2), "1,000.00");
});

test("the compact panel form takes the locale's decimal separator", () => {
    // The K/M/B suffix stays Latin; see the note on compactNumber.
    assert.equal(fmt.compactNumber(1500000, "en_US"), "1.5M");
    assert.equal(fmt.compactNumber(1500000, "fr_FR"), "1,5M");
    assert.equal(fmt.compactNumber(1500000, "id_ID"), "1,5M");
    assert.equal(fmt.compactNumber(1500000, "zh_CN"), "1.5M");
    assert.equal(fmt.compactNumber(297270684, "fr_FR"), "297,3M");
});

test("days left and the panel metric take the locale too", () => {
    assert.equal(fmt.daysLeftText(2.5, 1, "en_US"), "2.5d");
    assert.equal(fmt.daysLeftText(2.5, 1, "fr_FR"), "2,5d");
    assert.equal(
        fmt.metricText(fmt.METRIC_BALANCE, Object.assign({}, metricValues, { locale: "fr_FR" })),
        "7,78\u00A0$US"
    );
    assert.equal(fmt.metricText(fmt.METRIC_TODAY_TOKENS, Object.assign({}, metricValues, { locale: "fr_FR" })), "1,5M");
});
