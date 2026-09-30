/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const history = load("contents/ui/js/history.js");

// Field-by-field comparison: the points come from a vm realm, so a deep
// equality would compare realms rather than values (see api.test.mjs).
function point(points, i) {
    return [points[i][0], points[i][1], points[i][2]];
}

test("parse tolerates nothing, garbage and shape drift", () => {
    assert.equal(history.parse("").length, 0);
    assert.equal(history.parse(undefined).length, 0);
    assert.equal(history.parse("not json").length, 0);
    assert.equal(history.parse('{"a":1}').length, 0);
    assert.equal(history.parse("[1,2]").length, 0);
    assert.equal(history.parse("[[100,5]]").length, 0, "short rows are dropped");
    assert.equal(history.parse('[["t",5,6]]').length, 0, "non-numeric time is dropped");
    // Out-of-order input is sorted: the recording is append-only, but a
    // hand-edited entry must not draw a line back in time.
    const sorted = history.parse("[[200,1,1],[100,2,2]]");
    assert.equal(sorted.length, 2);
    assert.equal(sorted[0][0], 100);
});

test("serialize and parse round-trip", () => {
    const r1 = history.append([], 1000, 37, 27);
    const r2 = history.append(r1.points, 2000, 40, null);
    const back = history.parse(history.serialize(r2.points));
    assert.equal(back.length, 2);
    assert.deepEqual(point(back, 1), [2000, 40, null]);
});

test("append replaces a too-close point and keeps an unchanged one", () => {
    const first = history.append([], 1000, 10, 20);
    // Within MIN_SPACING_SEC: the fresher reading replaces, not stacks.
    const replaced = history.append(first.points, 1000 + history.MIN_SPACING_SEC - 1, 11, 21);
    assert.equal(replaced.points.length, 1);
    assert.deepEqual(point(replaced.points, 0), [1000 + history.MIN_SPACING_SEC - 1, 11, 21]);
    assert.equal(replaced.changed, true);

    // The same observation twice changes nothing, so the caller skips the
    // config write.
    const again = history.append(replaced.points, 1000 + history.MIN_SPACING_SEC - 1, 11, 21);
    assert.equal(again.changed, false);
    assert.equal(again.points.length, 1);

    const pushed = history.append(replaced.points, 1000 + 2 * history.MIN_SPACING_SEC, 12, 22);
    assert.equal(pushed.points.length, 2, "a point past the spacing appends");
});

test("append clamps and drops non-finite values", () => {
    const r = history.append([], 1000, 140, -3);
    assert.deepEqual(point(r.points, 0), [1000, 100, 0]);
    const r2 = history.append(r.points, 1000 + history.MIN_SPACING_SEC, NaN, undefined);
    assert.deepEqual(point(r2.points, 1), [1000 + history.MIN_SPACING_SEC, null, null]);
});

test("append caps the buffer at MAX_POINTS, dropping the front", () => {
    const spacing = history.MIN_SPACING_SEC;
    let points = [];
    for (let i = 0; i < history.MAX_POINTS + 10; i++) {
        points = history.append(points, i * spacing, i % 101, 100 - (i % 101)).points;
    }
    assert.equal(points.length, history.MAX_POINTS);
    assert.equal(points[0][0], 10 * spacing, "the oldest ten fell off");
    assert.equal(points[points.length - 1][0], (history.MAX_POINTS + 9) * spacing);
});

test("series picks one provider and skips its gaps", () => {
    const spacing = history.MIN_SPACING_SEC;
    const points = [
        [1000, 30, 27],
        [1000 + spacing, null, null],
        [1000 + 2 * spacing, null, 29],
        [1000 + 3 * spacing, 41, 31]
    ];
    const kimi = history.series(points, "kimi");
    assert.equal(kimi.length, 2);
    assert.deepEqual([kimi[0].t, kimi[0].v], [1000, 30]);
    assert.deepEqual([kimi[1].t, kimi[1].v], [1000 + 3 * spacing, 41]);

    const zai = history.series(points, "zai");
    assert.equal(zai.length, 3);
    assert.equal(zai[1].v, 29);

    assert.equal(history.series(points, "deepseek").length, 0, "no column for other names");
    assert.equal(history.series(null, "kimi").length, 0);
});

/*
    The recording cadence and the buffer ceiling are the two numbers that
    decide how much of the config file this feature owns; pin them so a
    change is a decision, not an accident.
*/
test("the cadence and the ceiling are pinned", () => {
    assert.equal(history.MIN_SPACING_SEC, 600);
    assert.equal(history.MAX_POINTS, 512);
});

test("dailyDelta measures since local midnight and clamps resets", () => {
    const midnight = 100000;
    const spacing = history.MIN_SPACING_SEC;
    const points = [
        [midnight - spacing, 10, 5],
        [midnight, 12, 6],
        [midnight + spacing, 15, null],
        [midnight + 2 * spacing, 20, 9]
    ];
    assert.equal(history.dailyDelta(points, "kimi", midnight, 30), 18, "the value at midnight itself is the base");
    // zai skips its gap: base 6, now 9.
    assert.equal(history.dailyDelta(points, "zai", midnight, 9), 3);
    // A mid-day reset drops the percentage: not negative usage.
    assert.equal(history.dailyDelta(points, "kimi", midnight, 8), 0, "clamped, not -7");
    // Nothing recorded today for kimi → unknown; a bad now value too.
    assert.equal(history.dailyDelta([[midnight - spacing, 1, 1]], "kimi", midnight, 5), null);
    assert.equal(history.dailyDelta(points, "kimi", midnight, NaN), null);
    assert.equal(history.dailyDelta(points, "deepseek", midnight, 5), null);
});
