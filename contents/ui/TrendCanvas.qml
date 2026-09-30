/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    The quota trend, drawn the way the popup's DeepSeek daily-spend chart is:
    one bar per time slot on a bottom axis, the freshest observation in each
    slot (js/history.js chartBars), the height the percentage against a full
    quota. Used by the Kimi and Z.ai sections with the series the recorded
    history builds.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "js/history.js" as History

Canvas {
    id: canvas

    property var series: []
    // The density cap the bars are bucketed to; 40 matches the DeepSeek
    // chart's look at the popup's width.
    property int maxSlots: 40

    readonly property color barColor: Kirigami.Theme.highlightColor
    readonly property color axisColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                               Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b,
                                               0.3)

    Layout.preferredHeight: Kirigami.Units.gridUnit * 2

    onSeriesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onBarColorChanged: requestPaint()
    onAxisColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        ctx.strokeStyle = axisColor;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(0, height - 0.5);
        ctx.lineTo(width, height - 0.5);
        ctx.stroke();

        var chart = History.chartBars(series, maxSlots);
        var bars = chart.bars;
        if (bars.length === 0) {
            return;
        }
        // One slot per bucket across the recorded span, each bar placed by
        // its bucket's offset from the first — the DeepSeek chart's geometry,
        // so time gaps between observations survive instead of collapsing.
        var totalSlots = Math.max(1, Math.round((bars[bars.length - 1].t - bars[0].t) / chart.bucketSec) + 1);
        var slot = width / totalSlots;
        var barWidth = Math.max(1, slot * 0.7);
        ctx.fillStyle = barColor;
        for (var i = 0; i < bars.length; i++) {
            if (bars[i].v === 0) {
                continue;
            }
            var index = Math.round((bars[i].t - bars[0].t) / chart.bucketSec);
            var barHeight = Math.max(1, Math.round((height - 2) * (Math.max(0, Math.min(100, bars[i].v)) / 100)));
            var x = index * slot + (slot - barWidth) / 2;
            ctx.fillRect(x, height - 1 - barHeight, barWidth, barHeight);
        }
    }
}
