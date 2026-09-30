/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    Expanded representation (D2 — as much data as the configured credentials
    allow). Balance, today/period/lifetime spend, token breakdown, a daily
    spend sparkline and a per-key breakdown.

    Costs and the days-left estimate are *derived* from the platform usage API
    (undocumented, may change); the view says so.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "js/format.js" as Fmt
import "js/history.js" as History

Item {
    id: root

    property QtObject api
    property QtObject kimi
    property QtObject zai
    property bool hideAmounts: false
    property bool hasSession: false
    property string periodLabel: ""
    // Set by main.qml (Qt.locale().name).
    property string numberLocale: "en_US"

    // Peak / off-peak pricing state, computed centrally in main.qml so both
    // representations and the tooltip agree.
    property bool peakRates: false
    property bool peakKnown: true
    property string peakStateText: ""
    property string peakRemainingText: ""

    // The quota trend's recorded points (main.qml / js/history.js).
    property var history: []

    signal refreshRequested()

    readonly property string currency: api ? api.displayCurrency : ""
    readonly property bool hasUsage: api ? api.hasUsage : false
    readonly property bool isPlatform: api ? api.platformOk : false
    readonly property string noData: "\u2014"

    // Light theme text is dark and vice versa: a light text colour means a
    // dark background, the case the white glyph variants exist for.
    readonly property bool darkBackground: {
        var c = Kirigami.Theme.textColor;
        return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 > 0.5;
    }

    function providerIcon(entry) {
        return Fmt.iconVariant(entry, root.darkBackground);
    }

    readonly property real peakCost: {
        var list = api ? api.perDay : [];
        var max = 0;
        for (var i = 0; i < list.length; i++) {
            if (list[i].cost > max) {
                max = list[i].cost;
            }
        }
        return max;
    }

    readonly property var figures: {
        var a = api;
        return [
            {
                label: i18n("Today"),
                value: (a && a.hasUsage) ? root.money(a.todayTotals.cost) : root.noData
            },
            {
                label: root.periodLabel,
                value: (a && a.hasUsage) ? root.money(a.totals.cost) : root.noData
            },
            {
                label: i18n("Lifetime spend"),
                value: (a && a.platformOk) ? root.money(a.totalCost) : root.noData
            },
            {
                label: i18n("Estimated days left"),
                value: (a && a.platformOk) ? a.estimatedDaysLeftLabel : root.noData
            }
        ];
    }

    // Cells for ONE GridLayout rather than one layout per row. Separate per-row
    // layouts each size their own columns from their own contents, which is why
    // the columns did not line up.
    readonly property var tokenCells: {
        var a = api;
        var today = a ? a.todayTotals : null;
        var period = a ? a.totals : null;
        var rows = [
            ["", i18n("Today"), root.periodLabel],
            [i18nc("token usage table row", "Cost"),
                today ? root.money(today.cost) : root.noData,
                period ? root.money(period.cost) : root.noData],
            [i18nc("token usage table row: input tokens", "In"),
                today ? root.tokens(today.cacheHit + today.cacheMiss) : root.noData,
                period ? root.tokens(period.cacheHit + period.cacheMiss) : root.noData],
            [i18nc("token usage table row: output tokens", "Out"),
                today ? root.tokens(today.response) : root.noData,
                period ? root.tokens(period.response) : root.noData],
            [i18nc("token usage table row: cache-hit tokens", "Cached"),
                today ? root.tokens(today.cacheHit) : root.noData,
                period ? root.tokens(period.cacheHit) : root.noData],
            [i18nc("token usage table row: request count", "Requests"),
                today ? root.count(today.requests) : root.noData,
                period ? root.count(period.requests) : root.noData]
        ];
        var cells = [];
        for (var r = 0; r < rows.length; r++) {
            for (var c = 0; c < rows[r].length; c++) {
                cells.push({ text: rows[r][c], column: c, header: r === 0 });
            }
        }
        return cells;
    }

    // Same treatment for the per-key list so the figures line up down the
    // column. Only the key's name is shown; the masked key id is deliberately
    // not rendered anywhere.
    readonly property var perKeyCells: {
        var keys = api ? api.perKey : [];
        var cells = [];
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            cells.push({ text: key.name, column: 0, bold: true, dim: false });
            cells.push({
                text: root.tokens(key.cacheHit + key.cacheMiss + key.response),
                column: 1,
                bold: false,
                dim: true
            });
            cells.push({ text: root.money(key.cost), column: 2, bold: true, dim: false });
        }
        return cells;
    }

    // The Kimi quota table: one row per quota (the weekly summary plus each
    // per-model limit), sharing one GridLayout so the columns line up.
    // The quota trend's plottable series: percent of the headline quota over
    // time, one line per provider, points where that provider had data.
    readonly property var kimiTrend: History.series(history, "kimi")
    readonly property var zaiTrend: History.series(history, "zai")

    readonly property var kimiCells: {
        var cells = [];
        var k = kimi;
        if (!k) {
            return cells;
        }
        var rows = (k.summary ? [k.summary] : []).concat(k.limits || []);
        var headers = [i18n("Quota"), i18n("Used / Limit"), i18n("% used")];
        for (var h = 0; h < headers.length; h++) {
            cells.push({ text: headers[h], column: h, bold: true, dim: false });
        }
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            var label = root.kimiRowLabel(row, i);
            var reset = row.countdown.length > 0
                ? i18n("Resets %1 (in %2)", row.resetAtText, row.countdown)
                : (row.resetAtText.length > 0 ? i18n("Resets %1", row.resetAtText) : "");
            cells.push({
                // A newline gives a shared delegate a second, dimmer line for
                // the reset stamp under the quota's name.
                text: reset.length > 0 ? label + "\n" + reset : label,
                column: 0,
                bold: row.kind === "summary",
                dim: false
            });
            cells.push({
                text: root.tokens(row.used) + " / " + root.tokens(row.limit),
                column: 1,
                bold: false,
                dim: true
            });
            cells.push({ text: Fmt.percent(row.used, row.limit), column: 2, bold: row.kind === "summary", dim: false });
        }
        return cells;
    }

    // A quota's own name when the payload has one; else the window it runs on
    // ("5h limit"); else a plain ordinal so the row is still identifiable.
    function kimiRowLabel(row, idx) {
        if (row.kind === "summary") {
            return i18n("Weekly quota");
        }
        if (row.name && row.name.length > 0) {
            return row.name;
        }
        if (row.window && row.window.length > 0) {
            return i18nc("%1 is a time span like 5h or 7d", "%1 limit", row.window);
        }
        return i18n("Limit #%1", idx + 1);
    }

    /*
        The Z.ai tables. The quota rows mirror the Kimi table (span-named
        quotas, reset stamps); the window totals are label/value pairs over
        tokens and requests. Both share one cells builder each so the columns
        line up the same way the other tables do.
    */
    readonly property var zaiQuotaCells: {
        var cells = [];
        var z = zai;
        if (!z || z.quotaRows === null) {
            return cells;
        }
        var headers = [i18n("Quota"), i18n("Used / Limit"), i18n("% used")];
        for (var h = 0; h < headers.length; h++) {
            cells.push({ text: headers[h], column: h, bold: true, dim: false });
        }
        var rows = z.quotaRows;
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            var label = row.span.length > 0
                ? i18nc("%1 is a time span like 5h or 7d", "%1 limit", row.span)
                : i18n("Limit #%1", i + 1);
            var reset = row.countdown.length > 0
                ? i18n("Resets %1 (in %2)", row.resetAtText, row.countdown)
                : (row.resetAtText.length > 0 ? i18n("Resets %1", row.resetAtText) : "");
            cells.push({
                text: reset.length > 0 ? label + "\n" + reset : label,
                column: 0,
                bold: i === 0,
                dim: false
            });
            // TOKENS_LIMIT rows carry only a percentage today; the absolute
            // counts exist on TIME_LIMIT rows (and older deployments).
            cells.push({
                text: row.hasAmounts ? root.tokens(row.used) + " / " + root.tokens(row.limit) : root.noData,
                column: 1,
                bold: false,
                dim: true
            });
            cells.push({ text: row.percent + "%", column: 2, bold: i === 0, dim: false });
        }
        return cells;
    }

    readonly property var zaiWindowCells: {
        var cells = [];
        var z = zai;
        if (!z || !z.hasData) {
            return cells;
        }
        var headers = ["", i18n("Tokens"), i18n("Requests")];
        for (var h = 0; h < headers.length; h++) {
            cells.push({ text: headers[h], column: h, bold: true, dim: false });
        }
        var windows = [
            { label: i18n("Last 7 days"), data: z.sevenDay },
            { label: i18n("Last 30 days"), data: z.thirtyDay }
        ];
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i];
            cells.push({ text: w.label, column: 0, bold: false, dim: false });
            cells.push({ text: w.data ? root.tokens(w.data.tokens) : root.noData, column: 1, bold: true, dim: false });
            cells.push({
                text: w.data ? root.count(w.data.prompts) : root.noData,
                column: 2,
                bold: false,
                dim: true
            });
        }
        return cells;
    }

    function shown(text) {
        return Fmt.hideable(text, root.hideAmounts);
    }

    function money(value) {
        return shown(Fmt.money(value, root.currency, root.numberLocale));
    }

    // Exact, grouped counts in the popup, so the figures can be checked against
    // the platform's own. The panel chip keeps Fmt.tokens' compact form.
    function tokens(value) {
        return shown(Fmt.grouped(value, root.numberLocale));
    }

    function count(value) {
        return shown(Fmt.grouped(value, root.numberLocale));
    }

    implicitWidth: Kirigami.Units.gridUnit * 24
    readonly property real contentHeight: column.implicitHeight + Kirigami.Units.gridUnit * 2
    implicitHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 42)

    Flickable {
        id: scroll

        anchors.fill: parent
        contentWidth: width
        contentHeight: root.contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column

            // gridUnit gutters on both sides: the attached vertical scroll bar
            // is drawn over the Flickable's right edge, so right-aligned values
            // need room to stay readable.
            x: Kirigami.Units.gridUnit
            y: Kirigami.Units.gridUnit
            width: scroll.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.largeSpacing

            // ------------------------------------------------------- header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                // Provider icon, at the brand's optical size.
                Image {
                    visible: root.api ? root.api.configured : false
                    source: root.providerIcon(Fmt.PROVIDER_ICONS.deepseek)
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Fmt.iconHeight(Fmt.PROVIDER_ICONS.deepseek, Kirigami.Units.iconSizes.small)
                    Layout.preferredHeight: Fmt.iconHeight(Fmt.PROVIDER_ICONS.deepseek, Kirigami.Units.iconSizes.small)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: i18n("AI Usage")
                    elide: Text.ElideRight
                    font.bold: true
                }

                PlasmaComponents.Label {
                    visible: root.api ? root.api.hasData : false
                    text: root.api ? i18n("Updated %1", root.api.updatedLabel()) : ""
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: root.api ? (root.api.configured && !root.api.loading) : false
                    onClicked: root.refreshRequested()

                    PlasmaComponents.ToolTip.text: i18n("Refresh now")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // ------------------------------------------------------- errors
            Rectangle {
                Layout.fillWidth: true
                visible: root.api ? root.api.errorText.length > 0 : false
                implicitHeight: errorLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.cornerRadius
                color: Qt.rgba(Kirigami.Theme.negativeTextColor.r,
                               Kirigami.Theme.negativeTextColor.g,
                               Kirigami.Theme.negativeTextColor.b,
                               0.15)

                PlasmaComponents.Label {
                    id: errorLabel

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    text: root.api ? root.api.errorText : ""
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                }
            }

            // -------------------------------------------------- balance hero
            // DeepSeek's own blocks appear only when DeepSeek is configured;
            // a $0.00 hero above the Kimi and Z.ai sections is noise, not
            // information.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.api ? root.api.configured : false
                spacing: 0

                PlasmaComponents.Label {
                    text: i18n("Balance")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                PlasmaComponents.Label {
                    text: root.money(root.api ? root.api.displayBalance : 0)
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.4)
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    text: {
                        if (!root.api) {
                            return "";
                        }
                        if (root.api.platformOk) {
                            return root.api.bonus > 0
                                ? i18n("Includes %1 bonus credit", root.money(root.api.bonus))
                                : "";
                        }
                        if (root.api.officialOk) {
                            return i18n("Granted %1 · topped up %2",
                                        root.money(root.api.officialGranted),
                                        root.money(root.api.officialToppedUp));
                        }
                        return "";
                    }
                }
            }

            // -------------------------------------------------- key figures
            GridLayout {
                Layout.fillWidth: true
                visible: root.api ? root.api.configured : false
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.figures

                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: modelData.label
                            elide: Text.ElideRight
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: modelData.value
                            elide: Text.ElideRight
                            font.bold: true
                        }
                    }
                }
            }

            // ------------------------------------------------ peak / off-peak
            // DeepSeek pricing: meaningless without DeepSeek credentials.
            RowLayout {
                Layout.fillWidth: true
                visible: root.api ? root.api.configured : false
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    id: peakDot

                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.max(6, Math.round(Kirigami.Units.gridUnit * 0.4))
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: width / 2
                    color: !root.peakKnown
                        ? Kirigami.Theme.neutralTextColor
                        : root.peakRates ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                }

                PlasmaComponents.Label {
                    text: root.peakStateText
                    font.bold: true
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: root.peakRemainingText.length > 0
                    text: root.peakRemainingText.length > 0
                        ? i18n("Changes in %1", root.peakRemainingText)
                        : ""
                    elide: Text.ElideRight
                    opacity: 0.7
                }
            }

            // ---------------------------------------------------- sparkline
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.hasUsage
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: i18n("Daily spend, %1", root.periodLabel)
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }

                    PlasmaComponents.Label {
                        // Not "Peak": that word now means the peak-rate pricing state.
                        text: i18n("Highest %1", root.money(root.peakCost))
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }
                }

                Canvas {
                    id: chart

                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5

                    property var days: root.api ? root.api.perDay : []
                    // The requested window, so day buckets can be placed by date.
                    property int windowStart: root.api ? root.api.windowStart : 0
                    property int windowEnd: root.api ? root.api.windowEnd : 0
                    property color barColor: Kirigami.Theme.highlightColor
                    property color axisColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                                      Kirigami.Theme.textColor.g,
                                                      Kirigami.Theme.textColor.b,
                                                      0.3)

                    onDaysChanged: requestPaint()
                    onWindowStartChanged: requestPaint()
                    onWindowEndChanged: requestPaint()
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

                        var list = days || [];
                        if (list.length === 0) {
                            return;
                        }
                        var max = 0;
                        for (var i = 0; i < list.length; i++) {
                            if (list[i].cost > max) {
                                max = list[i].cost;
                            }
                        }
                        if (max <= 0) {
                            return;
                        }

                        // One slot per day of the whole period, not per day that
                        // happens to have spend. Buckets are local midnights, so
                        // a bucket's slot is its offset from the window start.
                        // Spacing the bars evenly by array index instead would
                        // draw a month of activity out of four recent days.
                        var slots = chart.windowEnd > chart.windowStart
                            ? Math.max(1, Math.round((chart.windowEnd - chart.windowStart) / 86400))
                            : list.length;
                        var slot = width / slots;
                        var barWidth = Math.max(1, slot * 0.7);
                        ctx.fillStyle = barColor;
                        for (var j = 0; j < list.length; j++) {
                            var index = Math.round((list[j].time - chart.windowStart) / 86400);
                            if (index < 0 || index >= slots) {
                                continue;
                            }
                            var barHeight = Math.max(1, Math.round((height - 2) * (list[j].cost / max)));
                            var x = index * slot + (slot - barWidth) / 2;
                            ctx.fillRect(x, height - 1 - barHeight, barWidth, barHeight);
                        }
                    }
                }
            }

            // -------------------------------------------------- token table
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.hasUsage
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18n("Tokens")
                    font.bold: true
                }

                // One GridLayout for the whole table, so the columns are shared
                // between every row and therefore line up. Per-row layouts each
                // sized their own columns, which misaligned the figures.
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.tokenCells

                        delegate: PlasmaComponents.Label {
                            text: modelData.text
                            elide: Text.ElideRight
                            opacity: modelData.header ? 0.7 : 1
                            font: modelData.header ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont
                            horizontalAlignment: modelData.column === 0 ? Text.AlignLeft : Text.AlignRight
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: modelData.column === 0 ? Kirigami.Units.gridUnit * 6 : -1
                            Layout.fillWidth: modelData.column !== 0
                        }
                    }
                }
            }

            // --------------------------------------------------- per key
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.api ? root.api.perKey.length > 0 : false
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18n("Per API key")
                    font.bold: true
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.perKeyCells

                        delegate: PlasmaComponents.Label {
                            text: modelData.text
                            elide: Text.ElideRight
                            // Only sub-properties of the font group here: assigning
                            // the whole group (`font: ...`) and then a
                            // sub-property is a QML error.
                            font.bold: modelData.bold
                            opacity: modelData.dim ? 0.55 : 1
                            horizontalAlignment: modelData.column === 0 ? Text.AlignLeft : Text.AlignRight
                            Layout.minimumWidth: 0
                            Layout.fillWidth: modelData.column === 0
                        }
                    }
                }
            }

            // ---------------------------------------------------- kimi code
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.kimi ? (root.kimi.configured || root.kimi.hasData) : false
                spacing: Kirigami.Units.smallSpacing

                // A rule between providers, so each section reads as its own
                // block; only drawn when there is something above to separate
                // from.
                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: root.api ? root.api.configured : false
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Image {
                        source: root.providerIcon(Fmt.PROVIDER_ICONS.kimi)
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: Fmt.iconHeight(Fmt.PROVIDER_ICONS.kimi, Kirigami.Units.iconSizes.small)
                        Layout.preferredHeight: Fmt.iconHeight(Fmt.PROVIDER_ICONS.kimi, Kirigami.Units.iconSizes.small)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    PlasmaComponents.Label {
                        text: i18n("Kimi Code")
                        font.bold: true
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.kimi ? root.kimi.errorText.length > 0 : false
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.negativeTextColor
                    font: Kirigami.Theme.smallFont
                    text: root.kimi ? root.kimi.errorText : ""
                }

                GridLayout {
                    Layout.fillWidth: true
                    visible: root.kimiCells.length > 0
                    columns: 3
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.kimiCells

                        delegate: PlasmaComponents.Label {
                            text: modelData.text
                            // A two-line quota label must wrap, not elide, or
                            // the reset stamp is cut off.
                            wrapMode: modelData.text.indexOf("\n") >= 0 ? Text.Wrap : Text.NoWrap
                            elide: modelData.text.indexOf("\n") >= 0 ? Text.ElideNone : Text.ElideRight
                            font.bold: modelData.bold
                            opacity: modelData.dim ? 0.55 : 1
                            horizontalAlignment: modelData.column === 0 ? Text.AlignLeft : Text.AlignRight
                            Layout.minimumWidth: 0
                            Layout.fillWidth: modelData.column === 0
                        }
                    }
                }

                // The recorded trend of the weekly quota's percentage. Two
                // points is a line; fewer are not a trend yet.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.kimiTrend.length >= 2
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: i18n("Quota trend")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }

                    TrendCanvas {
                        Layout.fillWidth: true
                        series: root.kimiTrend
                    }
                }
            }

            // ------------------------------------------------------- z.ai
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.zai ? (root.zai.configured || root.zai.hasData) : false
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: (root.api && root.api.configured)
                        || (root.kimi && (root.kimi.configured || root.kimi.hasData))
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Image {
                        source: root.providerIcon(Fmt.PROVIDER_ICONS.zai)
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: Fmt.iconHeight(Fmt.PROVIDER_ICONS.zai, Kirigami.Units.iconSizes.small)
                        Layout.preferredHeight: Fmt.iconHeight(Fmt.PROVIDER_ICONS.zai, Kirigami.Units.iconSizes.small)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    PlasmaComponents.Label {
                        text: i18n("Z.ai")
                        font.bold: true
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.zai ? root.zai.errorText.length > 0 : false
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.negativeTextColor
                    font: Kirigami.Theme.smallFont
                    text: root.zai ? root.zai.errorText : ""
                }

                GridLayout {
                    Layout.fillWidth: true
                    visible: root.zaiQuotaCells.length > 0
                    columns: 3
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.zaiQuotaCells

                        delegate: PlasmaComponents.Label {
                            text: modelData.text
                            // A two-line quota label must wrap, not elide, or
                            // the reset stamp is cut off.
                            wrapMode: modelData.text.indexOf("\n") >= 0 ? Text.Wrap : Text.NoWrap
                            elide: modelData.text.indexOf("\n") >= 0 ? Text.ElideNone : Text.ElideRight
                            font.bold: modelData.bold
                            opacity: modelData.dim ? 0.55 : 1
                            horizontalAlignment: modelData.column === 0 ? Text.AlignLeft : Text.AlignRight
                            Layout.minimumWidth: 0
                            Layout.fillWidth: modelData.column === 0
                        }
                    }
                }

                // The recorded trend of the 5-hour window's percentage — the
                // sawtooth of it filling and resetting is what the line shows.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.zaiTrend.length >= 2
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: i18n("Quota trend")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }

                    TrendCanvas {
                        Layout.fillWidth: true
                        series: root.zaiTrend
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    visible: root.zaiWindowCells.length > 0
                    columns: 3
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.zaiWindowCells

                        delegate: PlasmaComponents.Label {
                            text: modelData.text
                            elide: Text.ElideRight
                            font.bold: modelData.bold
                            opacity: modelData.dim ? 0.55 : 1
                            horizontalAlignment: modelData.column === 0 ? Text.AlignLeft : Text.AlignRight
                            Layout.minimumWidth: 0
                            Layout.fillWidth: modelData.column === 0
                        }
                    }
                }
            }

            // ------------------------------------------------------- notes
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.api ? (root.api.configured && !root.api.platformOk && !root.hasSession) : false
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("Balance-only mode. Add a platform session token in the settings to also see token usage, cost history and the per-key breakdown.")
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.hasUsage
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                text: i18n("Costs and the days-left estimate are derived from the platform usage API, which is undocumented and may change without notice.")
            }
        }
    }
}
