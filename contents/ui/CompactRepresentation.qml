/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    Panel representation (D5): an icon plus one number, chosen in the settings
    (see `panelMetric`). The full detail lives in the popup
    (FullRepresentation.qml).
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "js/format.js" as Fmt

Item {
    id: root

    property QtObject api
    property QtObject kimi
    property QtObject zai
    // Legacy single metric (still the source when the composition list has
    // never been saved) and the add-style composition from the settings.
    property int metric: Fmt.METRIC_BALANCE
    property var metrics: []
    property bool metricsExplicit: false
    property bool hideAmounts: false
    // Optional provider icons on the chip (the "Panel icons" setting).
    property bool showProviderIcons: false
    property bool peakRates: false
    property bool peakKnown: true
    // Set by main.qml (Qt.locale().name).
    property string numberLocale: "en_US"

    signal toggleRequested()

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Light theme text is dark and vice versa, so a light text colour means a
    // dark background — the case the white glyph variants exist for.
    readonly property bool darkBackground: {
        var c = Kirigami.Theme.textColor;
        return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 > 0.5;
    }

    function providerIcon(entry) {
        return Fmt.iconVariant(entry, root.darkBackground);
    }

    function providerKeyForMetric(id) {
        if (id >= Fmt.METRIC_KIMI_WEEKLY_USED && id <= Fmt.METRIC_KIMI_QUOTA_LEFT) {
            return "kimi";
        }
        if (id >= Fmt.METRIC_ZAI_WINDOW_USED && id <= Fmt.METRIC_ZAI_QUOTA_LEFT) {
            return "zai";
        }
        return "deepseek";
    }

    function providerEntryForMetric(id) {
        return Fmt.PROVIDER_ICONS[providerKeyForMetric(id)];
    }

    readonly property bool kimiConfigured: kimi && kimi.configured
    readonly property bool zaiConfigured: zai && zai.configured
    readonly property bool anyConfigured: (api && api.configured) || kimiConfigured || zaiConfigured

    // The composition's "nothing checked" sentinel, and the legacy modes a
    // config saved between the two settings designs may still carry.
    readonly property bool iconOnly: metricsExplicit
        ? (metrics.length === 0 || (metrics.length === 1 && metrics[0] === Fmt.METRIC_ICON_ONLY))
        : metric === Fmt.METRIC_ICON_ONLY

    // True when at least one provider is configured but none has data — the
    // "everything is broken" case the warning icon stands for in the modes
    // that are not about one specific provider.
    readonly property bool allFailed: {
        var any = false;
        var anyOk = false;
        if (api && api.configured) {
            any = true;
            if (api.hasData) {
                anyOk = true;
            }
        }
        if (kimiConfigured) {
            any = true;
            if (kimi.hasData) {
                anyOk = true;
            }
        }
        if (zaiConfigured) {
            any = true;
            if (zai.hasData) {
                anyOk = true;
            }
        }
        return any && !anyOk;
    }

    // Whose number is on the panel in the legacy single-metric mode: the
    // provider the selected metric belongs to, or — when that one has no
    // credentials — whichever provider can speak at all, showing its headline.
    readonly property string shown: {
        if (root.metric >= Fmt.METRIC_ZAI_WINDOW_USED && root.metric <= Fmt.METRIC_ZAI_QUOTA_LEFT) {
            if (zaiConfigured) {
                return "zai";
            }
        } else if (root.metric >= Fmt.METRIC_KIMI_WEEKLY_USED && root.metric <= Fmt.METRIC_KIMI_QUOTA_LEFT) {
            if (kimiConfigured) {
                return "kimi";
            }
        } else if (api && api.configured) {
            return "deepseek";
        }
        if (api && api.configured) {
            return "deepseek";
        }
        if (kimiConfigured) {
            return "kimi";
        }
        if (zaiConfigured) {
            return "zai";
        }
        return api ? "deepseek" : "none";
    }

    readonly property bool failed: metricsExplicit || iconOnly || metric === Fmt.METRIC_ALL_PROVIDERS
        ? allFailed
        : shown === "zai"
          ? (zaiConfigured && zai.errorText.length > 0 && !zai.hasData)
          : shown === "kimi"
            ? (kimiConfigured && kimi.errorText.length > 0 && !kimi.hasData)
            : (api ? (api.errorText.length > 0 && !api.hasData) : false)

    // One text per metric id in the composition: the provider's own number
    // when it has data, "" when it does not (skipped rather than shown as a
    // dash — a dash in the middle of the chip reads like a value).
    function metricValueText(id) {
        if (api && api.configured && api.hasData && id >= Fmt.METRIC_BALANCE && id <= Fmt.METRIC_LIFETIME_COST) {
            return Fmt.metricText(id, {
                currency: api.displayCurrency,
                locale: root.numberLocale,
                balance: api.displayBalance,
                todayCost: api.todayTotals.cost,
                todayTokens: api.todayTokens,
                periodCost: api.totals.cost,
                lifetimeCost: api.totalCost,
                hasLifetime: api.platformOk,
                hidden: root.hideAmounts
            });
        }
        if (kimi && kimi.kimiOk && id >= Fmt.METRIC_KIMI_WEEKLY_USED && id <= Fmt.METRIC_KIMI_QUOTA_LEFT) {
            return Fmt.metricText(id, {
                locale: root.numberLocale,
                hasKimi: true,
                kimiWeeklyUsed: kimi.headlineUsed,
                kimiWeeklyLimit: kimi.headlineLimit,
                hidden: root.hideAmounts
            });
        }
        if (zai && zai.zaiOk && id >= Fmt.METRIC_ZAI_WINDOW_USED && id <= Fmt.METRIC_ZAI_QUOTA_LEFT) {
            return Fmt.metricText(id, {
                locale: root.numberLocale,
                hasZai: true,
                zaiPercent: zai.headlinePercent,
                hidden: root.hideAmounts
            });
        }
        return "";
    }

    // The composition the settings build: every checked metric that has data,
    // in the list's own order ("$7.78 · 30% · 27%"); the tooltip names each.
    readonly property string composedText: {
        var parts = [];
        for (var i = 0; i < metrics.length; i++) {
            var text = metricValueText(metrics[i]);
            if (text.length > 0) {
                parts.push(text);
            }
        }
        return parts.join(" \u00B7 ");
    }

    // One headline number per configured provider ("$7.78 · 37% · 27%");
    // the tooltip names each. Providers still loading or failing are skipped.
    readonly property string allProvidersText: {
        var parts = [];
        if (api && api.configured && api.hasData) {
            parts.push(Fmt.metricText(Fmt.METRIC_BALANCE, {
                currency: api.displayCurrency,
                locale: root.numberLocale,
                balance: api.displayBalance,
                hidden: root.hideAmounts
            }));
        }
        if (kimiConfigured && kimi.hasData && kimi.kimiOk) {
            parts.push(Fmt.percent(kimi.headlineUsed, kimi.headlineLimit));
        }
        if (zaiConfigured && zai.hasData && zai.zaiOk) {
            parts.push(Math.round(zai.headlinePercent) + "%");
        }
        return parts.join(" \u00B7 ");
    }

    readonly property string valueText: {
        if (!api) {
            return i18n("Set up");
        }
        if (metricsExplicit) {
            if (iconOnly) {
                return "";
            }
            if (composedText.length > 0) {
                return composedText;
            }
            if (!root.anyConfigured) {
                return i18n("Set up");
            }
            return failed ? i18n("Error") : "\u2026";
        }
        if (metric === Fmt.METRIC_ALL_PROVIDERS) {
            if (allProvidersText.length > 0) {
                return allProvidersText;
            }
            if (!root.anyConfigured) {
                return i18n("Set up");
            }
            return failed ? i18n("Error") : "\u2026";
        }
        if (iconOnly) {
            return "";
        }
        if (shown === "none") {
            return i18n("Set up");
        }
        if (shown === "zai") {
            if (!zai.hasData) {
                return failed ? i18n("Error") : "\u2026";
            }
            // A metric from another provider with only Z.ai configured falls
            // back to the headline rather than an empty panel.
            var zm = root.metric >= Fmt.METRIC_ZAI_WINDOW_USED && root.metric <= Fmt.METRIC_ZAI_QUOTA_LEFT
                ? root.metric
                : Fmt.METRIC_ZAI_WINDOW_USED;
            return Fmt.metricText(zm, {
                locale: root.numberLocale,
                hasZai: zai.zaiOk,
                zaiPercent: zai.headlinePercent,
                hidden: root.hideAmounts
            });
        }
        if (shown === "kimi") {
            if (!kimi.hasData) {
                return failed ? i18n("Error") : "\u2026";
            }
            var km = root.metric >= Fmt.METRIC_KIMI_WEEKLY_USED && root.metric <= Fmt.METRIC_KIMI_QUOTA_LEFT
                ? root.metric
                : Fmt.METRIC_KIMI_WEEKLY_USED;
            return Fmt.metricText(km, {
                locale: root.numberLocale,
                hasKimi: kimi.kimiOk,
                kimiWeeklyUsed: kimi.headlineUsed,
                kimiWeeklyLimit: kimi.headlineLimit,
                hidden: root.hideAmounts
            });
        }
        if (!api.hasData) {
            return failed ? i18n("Error") : "\u2026";
        }
        return Fmt.metricText(root.metric, {
            currency: api.displayCurrency,
            locale: root.numberLocale,
            balance: api.displayBalance,
            todayCost: api.todayTotals.cost,
            todayTokens: api.todayTokens,
            periodCost: api.totals.cost,
            lifetimeCost: api.totalCost,
            hasLifetime: api.platformOk,
            hidden: root.hideAmounts
        });
    }

    /*
        What the chip renders. With the "Panel icons" setting on, adjacent
        numbers from the same provider share one icon — the icon appears once,
        followed by that provider's figures ("[DS] ¥30.41 · 3% [K] 30%") —
        each at the brand's optical size (the thin-diagonal Z.ai mark scales
        down; see PROVIDER_ICONS). With the setting off — the default — the
        numbers stand alone. State texts ("Set up", "Error", "…") never carry
        a provider icon, and a missing or broken file renders as nothing
        rather than breaking the chip.
    */
    readonly property var chipParts: {
        if (iconOnly || valueText.length === 0) {
            return [];
        }
        if (!showProviderIcons || !showsNumbers) {
            return [{ icon: "", w: 0, h: 0, text: valueText }];
        }
        if (metricsExplicit) {
            var parts = [];
            for (var i = 0; i < metrics.length; i++) {
                var text = metricValueText(metrics[i]);
                if (text.length === 0) {
                    continue;
                }
                var key = providerKeyForMetric(metrics[i]);
                var last = parts.length > 0 ? parts[parts.length - 1] : null;
                if (last && last.provider === key) {
                    last.text = last.text + " \u00B7 " + text;
                    continue;
                }
                var entry = providerEntryForMetric(metrics[i]);
                var size = Fmt.iconHeight(entry, Kirigami.Units.iconSizes.small);
                parts.push({ provider: key, icon: providerIcon(entry), w: size, h: size, text: text });
            }
            return parts;
        }
        var fallback = metric === Fmt.METRIC_ALL_PROVIDERS
            ? null
            : shown === "kimi"
              ? Fmt.PROVIDER_ICONS.kimi
              : shown === "zai" ? Fmt.PROVIDER_ICONS.zai : Fmt.PROVIDER_ICONS.deepseek;
        var fallbackSize = fallback ? Fmt.iconHeight(fallback, Kirigami.Units.iconSizes.small) : 0;
        return [{
            provider: "",
            icon: fallback ? providerIcon(fallback) : "",
            w: fallbackSize,
            h: fallbackSize,
            text: valueText
        }];
    }

    /*
        Whether the chip is showing numbers (as opposed to "Set up", "Error",
        "…" or the icon-only mode). The generic widget icon steps aside for
        numbers; only the icon-only mode and the status texts keep it.
    */
    readonly property bool showsNumbers: {
        if (iconOnly) {
            return false;
        }
        if (metricsExplicit) {
            return composedText.length > 0;
        }
        if (metric === Fmt.METRIC_ALL_PROVIDERS) {
            return allProvidersText.length > 0;
        }
        if (shown === "none") {
            return false;
        }
        if (shown === "kimi") {
            return kimi ? kimi.hasData : false;
        }
        if (shown === "zai") {
            return zai ? zai.hasData : false;
        }
        return api ? api.hasData : false;
    }
    Layout.minimumWidth: content.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.minimumHeight: content.implicitHeight + Kirigami.Units.smallSpacing

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onClicked: root.toggleRequested()
    }

    GridLayout {
        id: content

        anchors.centerIn: parent
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? -1 : 1
        columns: root.vertical ? 1 : -1
        rowSpacing: 0
        columnSpacing: Kirigami.Units.smallSpacing

        // The widget's own icon, only where it is the whole point: the
        // icon-only mode and the status texts. Beside numbers it was noise.
        Kirigami.Icon {
            visible: !root.showsNumbers
            source: "office-chart-bar"
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        // The numbers, each with its provider's icon when the "Panel icons"
        // setting is on (chipParts carries empty icons otherwise).
        RowLayout {
            visible: !root.iconOnly && root.chipParts.length > 0
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: root.chipParts

                delegate: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Image {
                        visible: modelData.icon.length > 0
                        source: modelData.icon
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: modelData.w
                        Layout.preferredHeight: modelData.h
                        fillMode: Image.PreserveAspectFit
                        // A broken or missing file renders as nothing rather
                        // than breaking the chip.
                        asynchronous: true
                    }

                    PlasmaComponents.Label {
                        text: modelData.text
                        font.bold: true
                        color: root.failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    }
                }
            }
        }

        // Peak-rate state at a glance: green means the discounted off-peak rate
        // is in effect, red means full-price peak hours, and a muted dot means
        // the year's holiday list is not known so no claim is made either way.
        // The tooltip spells out the state and how long it lasts. Dropped in
        // icon-only mode, which the settings offer as "just the icon".
        Rectangle {
            visible: !root.iconOnly
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: Math.max(6, Math.round(Kirigami.Units.gridUnit * 0.4))
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: !root.peakKnown
                ? Kirigami.Theme.neutralTextColor
                : root.peakRates ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
        }
    }
}
