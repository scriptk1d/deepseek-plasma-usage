/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    DeepSeek API balance + usage applet (D5: panel-first).

    Credentials live in KWallet only and are read through Wallet.qml. All
    request building and parsing happens in ApiClient.qml + js/, so the applet
    config never contains a secret.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.coreaddons as KCoreAddons
import "js/wallet.js" as WalletJs
import "js/format.js" as Fmt
import "js/peak.js" as Peak

PlasmoidItem {
    id: root

    readonly property int refreshInterval: Plasmoid.configuration.refreshInterval
    readonly property int metric: Plasmoid.configuration.panelMetric
    // The add-style composition: ids from the checked metrics in the
    // settings, and whether the user has made an explicit choice at all
    // (an unset list falls back to the legacy single metric).
    readonly property var panelMetricsRaw: Plasmoid.configuration.panelMetrics
    readonly property bool panelMetricsExplicit: panelMetricsRaw !== undefined && panelMetricsRaw.length > 0
    readonly property var panelMetricIds: {
        if (panelMetricsExplicit) {
            var ids = [];
            for (var i = 0; i < panelMetricsRaw.length; i++) {
                var n = parseInt(panelMetricsRaw[i], 10);
                if (!isNaN(n)) {
                    ids.push(n);
                }
            }
            return ids;
        }
        return [metric];
    }
    readonly property int periodDays: Plasmoid.configuration.costPeriodDays
    readonly property bool hideAmounts: Plasmoid.configuration.hideAmounts
    readonly property bool showProviderIcons: Plasmoid.configuration.showProviderIcons
    readonly property int secretsRevision: Plasmoid.configuration.secretsRevision
    // Not a secret, so it lives in the config; empty takes the default in
    // js/kimi.js.
    readonly property string kimiBaseUrl: Plasmoid.configuration.kimiBaseUrl !== undefined ? Plasmoid.configuration.kimiBaseUrl : ""
    // Same for the Z.ai base URL (default in js/zai.js).
    readonly property string zaiBaseUrl: Plasmoid.configuration.zaiBaseUrl !== undefined ? Plasmoid.configuration.zaiBaseUrl : ""

    readonly property string periodLabel: i18ncp("trailing period for a cost", "Last %1 day", "Last %1 days", root.periodDays)

    // Numbers follow the locale's own conventions -- thousands and decimal
    // separators, and where the currency sign goes -- which is locale data rather
    // than text, so it comes from Qt.locale() and not from the translation
    // catalogue. Defined once here and passed down to everything that formats.
    readonly property string numberLocale: Qt.locale().name

    // Peak / off-peak pricing. The schedule is defined to the minute, so a clock
    // tick keeps the state and the countdown honest between network refreshes.
    // See js/peak.js for the rule and its documented holiday caveat.
    property date now: new Date()
    readonly property string peakState: Peak.state(now.getTime())
    readonly property bool peakRates: peakState === Peak.PEAK
    // False when the holiday list for this year has not been published or added
    // yet. Reporting that beats reporting a wrong rate.
    readonly property bool peakKnown: peakState !== Peak.UNKNOWN
    readonly property string peakStateText: {
        switch (peakState) {
        case Peak.PEAK:
            return i18nc("DeepSeek is charging full-price peak rates", "Peak");
        case Peak.OFF_PEAK:
            return i18nc("DeepSeek is charging discounted off-peak rates", "Off-peak");
        default:
            return i18nc("DeepSeek's peak or off-peak rate cannot be determined", "Unknown");
        }
    }
    // Computed in one block on purpose: a `real` property would coerce a null
    // result to 0 and then render as "0 seconds" instead of no countdown.
    readonly property string peakRemainingText: {
        var remaining = Peak.msUntilChange(now.getTime());
        return remaining === null ? "" : KCoreAddons.Format.formatSpelloutDuration(remaining);
    }

    // Set once the KWallet round-trip has finished, so the "needs configuring"
    // overlay does not flash on every startup.
    property bool secretsLoaded: false
    property bool secretsInFlight: false
    property int loadedRevision: -1

    Wallet {
        id: wallet
    }

    ApiClient {
        id: apiClient

        periodDays: root.periodDays
        numberLocale: root.numberLocale
    }

    KimiClient {
        id: kimiClient

        baseUrl: root.kimiBaseUrl
    }

    ZaiClient {
        id: zaiClient

        baseUrl: root.zaiBaseUrl
    }

    // Any one provider alone is enough for the widget to have something to
    // show.
    readonly property bool anyConfigured: apiClient.configured || kimiClient.configured || zaiClient.configured

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation

    compactRepresentation: CompactRepresentation {
        api: apiClient
        kimi: kimiClient
        zai: zaiClient
        metric: root.metric
        metrics: root.panelMetricIds
        metricsExplicit: root.panelMetricsExplicit
        hideAmounts: root.hideAmounts
        showProviderIcons: root.showProviderIcons
        peakRates: root.peakRates
        peakKnown: root.peakKnown
        numberLocale: root.numberLocale

        onToggleRequested: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {
        api: apiClient
        kimi: kimiClient
        zai: zaiClient
        hideAmounts: root.hideAmounts
        hasSession: apiClient.hasSession
        periodLabel: root.periodLabel
        peakRates: root.peakRates
        peakKnown: root.peakKnown
        peakStateText: root.peakStateText
        peakRemainingText: root.peakRemainingText
        numberLocale: root.numberLocale

        onRefreshRequested: root.refreshAll()
    }

    function refreshAll() {
        apiClient.refresh()
        kimiClient.refresh()
        zaiClient.refresh()
    }

    Plasmoid.title: i18n("AI Usage")
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.busy: (apiClient.loading || kimiClient.loading || zaiClient.loading)
        && !(apiClient.hasData || kimiClient.hasData || zaiClient.hasData)
    Plasmoid.status: apiClient.loading || kimiClient.loading || zaiClient.loading ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    Plasmoid.configurationRequired: root.secretsLoaded && !root.anyConfigured

    toolTipMainText: i18n("AI Usage")
    toolTipSubText: root.toolTipText

    readonly property string kimiToolTipLine: kimiClient.kimiOk
        ? i18n("Kimi weekly usage: %1", Fmt.percent(kimiClient.headlineUsed, kimiClient.headlineLimit))
        : ""
    readonly property string zaiToolTipLine: zaiClient.zaiOk
        ? i18n("Z.ai 5-hour window: %1", Math.round(zaiClient.headlinePercent) + "%")
        : ""

    readonly property string toolTipText: {
        if (!root.anyConfigured) {
            return i18n("Add a DeepSeek API key in the widget settings.");
        }
        // Without DeepSeek credentials the tooltip belongs to whichever
        // providers can speak: their headline numbers, or the first error.
        if (!apiClient.configured) {
            var only = [];
            if (root.kimiToolTipLine.length > 0) {
                only.push(root.kimiToolTipLine);
            }
            if (root.zaiToolTipLine.length > 0) {
                only.push(root.zaiToolTipLine);
            }
            if (only.length > 0) {
                only.push(i18n("Updated %1", kimiClient.hasData ? kimiClient.updatedLabel() : zaiClient.updatedLabel()));
                return only.join("\n");
            }
            var firstError = kimiClient.configured && kimiClient.errorText.length > 0
                ? kimiClient.errorText
                : zaiClient.configured && zaiClient.errorText.length > 0 ? zaiClient.errorText : "";
            return firstError.length > 0 ? firstError : i18n("Loading…");
        }
        if (!apiClient.hasData) {
            return apiClient.errorText.length > 0 ? apiClient.errorText : i18n("Loading…");
        }
        var lines = [i18n("Balance: %1", root.shownMoney(apiClient.displayBalance))];
        if (apiClient.hasUsage) {
            lines.push(i18n("Today: %1", root.shownMoney(apiClient.todayTotals.cost)));
            lines.push(i18n("%1: %2", root.periodLabel, root.shownMoney(apiClient.totals.cost)));
        } else if (apiClient.platformOk) {
            lines.push(i18n("Lifetime spend: %1", root.shownMoney(apiClient.totalCost)));
        }
        lines.push(root.peakRemainingText.length > 0
            ? i18n("%1 · changes in %2", root.peakStateText, root.peakRemainingText)
            : root.peakStateText);
        if (root.kimiToolTipLine.length > 0) {
            lines.push(root.kimiToolTipLine);
        }
        if (root.zaiToolTipLine.length > 0) {
            lines.push(root.zaiToolTipLine);
        }
        lines.push(i18n("Updated %1", apiClient.updatedLabel()));
        return lines.join("\n");
    }

    Timer {
        // The peak state and its countdown are defined to the minute.
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            enabled: root.anyConfigured && !apiClient.loading && !kimiClient.loading && !zaiClient.loading
            onTriggered: root.refreshAll()
        }
    ]

    Timer {
        interval: Math.max(30, root.refreshInterval) * 1000
        repeat: true
        running: root.anyConfigured
        onTriggered: root.refreshAll()
    }

    Connections {
        target: wallet

        function onReadFinished(entry, secret) {
            root.handleSecret(entry, secret);
        }
    }

    onSecretsRevisionChanged: root.reloadSecrets()
    onPeriodDaysChanged: if (apiClient.configured) { apiClient.refresh() }
    onKimiBaseUrlChanged: if (kimiClient.configured) { kimiClient.refresh() }
    onZaiBaseUrlChanged: if (zaiClient.configured) { zaiClient.refresh() }

    Component.onCompleted: root.reloadSecrets()

    function shownMoney(value) {
        return Fmt.hideable(Fmt.money(value, apiClient.displayCurrency, root.numberLocale), root.hideAmounts);
    }

    // Reads every key the wallet bridge knows, one after the other: the
    // bridge queues commands, but a single read round-trip keeps the mapping
    // between request and reply obvious.
    function reloadSecrets() {
        if (secretsInFlight) {
            return;
        }
        if (secretsLoaded && root.loadedRevision === root.secretsRevision) {
            return;
        }
        secretsInFlight = true;
        root.loadedRevision = root.secretsRevision;
        apiClient.apiKey = "";
        apiClient.sessionToken = "";
        kimiClient.apiKey = "";
        zaiClient.apiKey = "";
        wallet.read(WalletJs.API_KEY_ENTRY);
    }

    function handleSecret(entry, secret) {
        if (entry === WalletJs.API_KEY_ENTRY) {
            apiClient.apiKey = secret;
            wallet.read(WalletJs.SESSION_TOKEN_ENTRY);
            return;
        }
        if (entry === WalletJs.SESSION_TOKEN_ENTRY) {
            apiClient.sessionToken = secret;
            wallet.read(WalletJs.KIMI_API_KEY_ENTRY);
            return;
        }
        if (entry === WalletJs.KIMI_API_KEY_ENTRY) {
            kimiClient.apiKey = secret;
            wallet.read(WalletJs.ZAI_API_KEY_ENTRY);
            return;
        }
        if (entry === WalletJs.ZAI_API_KEY_ENTRY) {
            zaiClient.apiKey = secret;
            secretsInFlight = false;
            secretsLoaded = true;
            root.refreshAll();
        }
    }
}
