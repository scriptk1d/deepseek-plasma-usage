/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    A percent-over-time line for the quota trend: 0% at the bottom edge,
    100% at a hairline under the top, points placed by their timestamp
    across the recorded span. Used by the Kimi and Z.ai sections of the
    popup with the series js/history.js builds (points where that provider
    had data).
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Canvas {
    id: canvas

    property var series: []

    readonly property color lineColor: Kirigami.Theme.highlightColor
    readonly property color axisColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                               Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b,
                                               0.3)

    Layout.preferredHeight: Kirigami.Units.gridUnit * 2

    onSeriesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColorChanged: requestPaint()
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

        var list = series || [];
        if (list.length < 2) {
            return;
        }
        var t0 = list[0].t;
        var t1 = list[list.length - 1].t;
        var span = t1 - t0;
        if (span <= 0) {
            span = 1;
        }
        // The 100% ceiling is a hairline, so a full quota reads as touching
        // it rather than being clipped at the canvas edge.
        ctx.strokeStyle = Qt.rgba(axisColor.r, axisColor.g, axisColor.b, 0.6);
        ctx.beginPath();
        ctx.moveTo(0, 1.5);
        ctx.lineTo(width, 1.5);
        ctx.stroke();

        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2;
        ctx.beginPath();
        for (var i = 0; i < list.length; i++) {
            var x = 1 + ((list[i].t - t0) / span) * (width - 2);
            var y = (height - 2) * (1 - Math.max(0, Math.min(100, list[i].v)) / 100) + 1;
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        }
        ctx.stroke();
    }
}
