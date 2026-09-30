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
import org.kde.plasma.plasma5support as P5Support
import org.kde.coreaddons as KCoreAddons
import "js/wallet.js" as WalletJs
import "js/format.js" as Fmt
import "js/peak.js" as Peak
import "js/reminder.js" as Reminder

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

    Component.onCompleted: root.reloadSecrets()

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
    }

    function refreshAll() {
        apiClient.refresh()
        kimiClient.refresh()
        zaiClient.refresh()
    }

    // --- the weekly-quota reminder --------------------------------------
    // Sends at most one notification per provider per day, only inside the
    // last day of a weekly quota's window and only when more than a fifth of
    // it is still unused (js/reminder.js owns the thresholds). The
    // notification itself goes through notify-send — the one binary this
    // adds, and its absence just means no reminder, never a broken widget.
    property int _notifySeq: 0

    readonly property P5Support.DataSource _notifySource: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => _notifySource.disconnectSource(sourceName)
    }

    function sendReminder(title, body) {
        _notifySeq += 1;
        // The unique trailing comment makes repeated sends a fresh source,
        // exactly like the wallet bridge's commands.
        var command = "notify-send -t 60000 -a " + WalletJs.shellQuote(i18n("AI Usage")) +
            " -i office-chart-bar " + WalletJs.shellQuote(title) + " " + WalletJs.shellQuote(body) +
            " # " + _notifySeq;
        _notifySource.connectedSources = [command];
    }

    // The Z.ai weekly row: the quota whose span is measured in weeks ("1w").
    function zaiWeeklyRow() {
        var rows = zaiClient.quotaRows;
        if (rows === null) {
            return null;
        }
        for (var i = 0; i < rows.length; i++) {
            if (/w$/.test(rows[i].span)) {
                return rows[i];
            }
        }
        return null;
    }

    function checkReminders() {
        var now = Date.now();
        var offsetMs = -new Date().getTimezoneOffset() * 60000;
        var day = Reminder.localDay(now, offsetMs);
        var resetOpts = {
            beforeMs: Math.max(1, Plasmoid.configuration.resetReminderHours) * 3600 * 1000,
            minRemaining: Plasmoid.configuration.resetReminderPercent,
            offsetMs: offsetMs
        };

        if (Plasmoid.configuration.resetReminderEnabled) {
            if (kimiClient.kimiOk && kimiClient.headline !== null) {
                var used = kimiClient.headlineLimit > 0
                    ? (kimiClient.headlineUsed / kimiClient.headlineLimit) * 100
                    : NaN;
                var v = Reminder.verdict(used, kimiClient.headline.resetAtMs, now);
                if (Reminder.due(v, Plasmoid.configuration.kimiReminderDay, now, resetOpts)) {
                    sendReminder(i18n("Kimi weekly quota is about to reset"),
                        i18n("%1 of the weekly quota is unused and it resets in %2 — about %3 per day would use it up.",
                             v.remainingPercent + "%", v.msLeftText, v.perDayPercent + "%"));
                    Plasmoid.configuration.kimiReminderDay = day;
                }
            }

            var zaiRow = zaiClient.zaiOk ? zaiWeeklyRow() : null;
            if (zaiRow !== null) {
                var vz = Reminder.verdict(zaiRow.percent, zaiRow.resetAtMs, now);
                if (Reminder.due(vz, Plasmoid.configuration.zaiReminderDay, now, resetOpts)) {
                    sendReminder(i18n("Z.ai weekly quota is about to reset"),
                        i18n("%1 of the weekly quota is unused and it resets in %2 — about %3 per day would use it up.",
                             vz.remainingPercent + "%", vz.msLeftText, vz.perDayPercent + "%"));
                    Plasmoid.configuration.zaiReminderDay = day;
                }
            }
        }

        if (Plasmoid.configuration.dailyDigestEnabled) {
            checkDigest(now, offsetMs);
        }
    }

    // The twice-daily usage digest. A slot with nothing to say (no provider
    // data yet) is not stamped, so it fires later in the day when the data
    // arrives rather than being silently skipped.
    function checkDigest(now, offsetMs) {
        var slots = [
            { minutes: Reminder.parseClock(Plasmoid.configuration.digestTime1), stamp: "digestDay1" },
            { minutes: Reminder.parseClock(Plasmoid.configuration.digestTime2), stamp: "digestDay2" }
        ];
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            if (!Reminder.digestDue(slot.minutes, now, offsetMs, Plasmoid.configuration[slot.stamp])) {
                continue;
            }
            var lines = [];
            if (kimiClient.kimiOk && kimiClient.headline !== null && kimiClient.headlineLimit > 0) {
                var pct = Math.round((kimiClient.headlineUsed / kimiClient.headlineLimit) * 100);
                lines.push(i18n("Kimi weekly quota: %1 used", pct + "%"));
            }
            var zRow = zaiClient.zaiOk ? zaiWeeklyRow() : null;
            if (zRow !== null) {
                lines.push(i18n("Z.ai weekly quota: %1 used", zRow.percent + "%"));
            }
            if (lines.length === 0) {
                return;
            }
            sendReminder(i18n("Today's usage"), lines.join("\n"));
            Plasmoid.configuration[slot.stamp] = Reminder.localDay(now, offsetMs);
        }
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

    Timer {
        // The reminder check polls every minute and decides for itself when
        // there is something to do (Reminder's thresholds and stamps), so
        // the timer stays a cheap poll.
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.checkReminders()
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
