/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    Settings page. The credentials are written to KWallet, never to the applet
    config; the rest is staged in `cfg_*` properties and applied in saveConfig()
    by the Plasma configuration framework.

    Layout order is usage order: Panel first (the part people change), then the
    data window, then the three providers' credentials. Every control that
    changes the configuration emits `configurationChanged`, so the dialog's
    Apply/OK enablement tracks the page's own edits.
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "js/wallet.js" as WalletJs
import "js/format.js" as Fmt
import "js/api.js" as Api
import "js/reminder.js" as Reminder

KCM.SimpleKCM {
    id: page

    title: i18n("General")

    signal configurationChanged

    // Staged configuration; the framework fills these in from the applet config
    // and reads them back when the user applies the dialog.
    property int cfg_refreshInterval: 300
    property int cfg_panelMetric: 0
    property var cfg_panelMetrics: []
    property int cfg_costPeriodDays: 30
    property bool cfg_hideAmounts: false
    property bool cfg_showProviderIcons: false
    property string cfg_kimiBaseUrl: ""
    property string cfg_zaiBaseUrl: ""
    property bool cfg_resetReminderEnabled: true
    property int cfg_resetReminderHours: 24
    property int cfg_resetReminderPercent: 20
    property bool cfg_dailyDigestEnabled: true
    property string cfg_digestTime1: "09:00"
    property string cfg_digestTime2: "21:00"
    property int cfg_secretsRevision: 0

    property bool apiKeySet: false
    property bool sessionTokenSet: false
    property bool kimiKeySet: false
    property bool zaiKeySet: false
    property string statusText: ""

    // The composition the panel shows: metric ids in display order. A plain
    // property filled once in Component.onCompleted rather than a binding on
    // cfg_panelMetrics — after Apply the framework echoes the cfg_* values
    // back, and a live binding would fight the edits made in the list.
    property var stagedMetrics: []

    Wallet {
        id: wallet
    }

    Timer {
        id: statusTimer

        interval: 5000
        onTriggered: page.statusText = ""
    }

    // The saved composition when there is one, else the legacy single metric.
    // The "icon only" sentinel (10) is not a list entry by design.
    function initialMetrics() {
        var raw = cfg_panelMetrics;
        if (raw && raw.length > 0) {
            var ids = [];
            for (var i = 0; i < raw.length; i++) {
                var n = parseInt(raw[i], 10);
                if (!isNaN(n) && n >= Fmt.METRIC_BALANCE && n <= Fmt.METRIC_ZAI_QUOTA_LEFT) {
                    ids.push(n);
                }
            }
            return ids;
        }
        return [cfg_panelMetric];
    }

    // The provider a metric belongs to, for the picker's submenus and the
    // list's row labels. The brand names are existing catalogue entries;
    // composing them here adds no new strings.
    function providerLabelForMetric(id) {
        if (id <= Fmt.METRIC_LIFETIME_COST) {
            return i18n("DeepSeek");
        }
        if (id <= Fmt.METRIC_KIMI_QUOTA_LEFT) {
            return i18n("Kimi Code");
        }
        return i18n("Z.ai");
    }

    // What one provider's submenu offers: the metrics of its id range that
    // are not in the list yet, each carrying its own add action so menu
    // delegates need nothing from the outer scope (the same reason
    // removeCallback exists).
    function addCallback(metricId) {
        return function () {
            page.addMetric(metricId);
            page.configurationChanged();
        };
    }

    function availableMetricsFor(providerIndex) {
        var first = [Fmt.METRIC_BALANCE, Fmt.METRIC_KIMI_WEEKLY_USED, Fmt.METRIC_ZAI_WINDOW_USED][providerIndex];
        var last = [Fmt.METRIC_LIFETIME_COST, Fmt.METRIC_KIMI_QUOTA_LEFT, Fmt.METRIC_ZAI_QUOTA_LEFT][providerIndex];
        var labels = metricLabels();
        var out = [];
        for (var i = first; i <= last; i++) {
            if (stagedMetrics.indexOf(i) < 0) {
                out.push({ id: i, label: labels[i], add: addCallback(i) });
            }
        }
        return out;
    }

    function removeCallback(metricId) {
        return function () {
            page.removeMetric(metricId);
            page.configurationChanged();
        };
    }

    // One entry per row of the composition list: the provider name plus the
    // metric, and the action, so the delegate needs nothing from the outer
    // scope.
    function compositionEntries() {
        var labels = metricLabels();
        var entries = [];
        for (var i = 0; i < stagedMetrics.length; i++) {
            var id = stagedMetrics[i];
            entries.push({
                id: id,
                label: providerLabelForMetric(id) + " — " + labels[id],
                remove: removeCallback(id)
            });
        }
        return entries;
    }

    function addMetric(id) {
        if (stagedMetrics.indexOf(id) >= 0) {
            return;
        }
        var ids = stagedMetrics.slice();
        ids.push(id);
        stagedMetrics = ids;
    }

    function removeMetric(id) {
        stagedMetrics = stagedMetrics.filter(function (x) { return x !== id; });
    }

    function saveConfig() {
        Plasmoid.configuration.refreshInterval = cfg_refreshInterval
        // Sync the staged value too: the framework echoes cfg_* back on
        // apply, and a stale echo would overwrite what is written directly.
        cfg_panelMetrics = stagedMetrics.length === 0
            ? [String(Fmt.METRIC_ICON_ONLY)]
            : stagedMetrics.map(function (x) { return String(x); })
        Plasmoid.configuration.panelMetrics = cfg_panelMetrics
        Plasmoid.configuration.panelMetric = cfg_panelMetric
        Plasmoid.configuration.costPeriodDays = cfg_costPeriodDays
        Plasmoid.configuration.hideAmounts = cfg_hideAmounts
        Plasmoid.configuration.showProviderIcons = cfg_showProviderIcons
        Plasmoid.configuration.kimiBaseUrl = cfg_kimiBaseUrl.trim()
        Plasmoid.configuration.zaiBaseUrl = cfg_zaiBaseUrl.trim()
        Plasmoid.configuration.resetReminderEnabled = cfg_resetReminderEnabled
        Plasmoid.configuration.resetReminderHours = cfg_resetReminderHours
        Plasmoid.configuration.resetReminderPercent = cfg_resetReminderPercent
        Plasmoid.configuration.dailyDigestEnabled = cfg_dailyDigestEnabled
        // Normalised by parse-on-save: a hand-typed "9:5" that parses
        // becomes "09:05", and an unparsable time falls back to the default
        // rather than storing something the digest can never match.
        cfg_digestTime1 = Reminder.parseClock(cfg_digestTime1) === null ? "09:00" : normalizedClock(cfg_digestTime1)
        cfg_digestTime2 = Reminder.parseClock(cfg_digestTime2) === null ? "21:00" : normalizedClock(cfg_digestTime2)
        Plasmoid.configuration.digestTime1 = cfg_digestTime1
        Plasmoid.configuration.digestTime2 = cfg_digestTime2
    }

    function normalizedClock(text) {
        var minutes = Reminder.parseClock(text);
        var h = Math.floor(minutes / 60);
        var m = minutes % 60;
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }

    // Bumping the revision makes the running applet re-read the wallet. The
    // staged value is bumped too so the configuration framework cannot echo a
    // stale revision back over it.
    function bumpSecretsRevision() {
        const next = cfg_secretsRevision + 1
        cfg_secretsRevision = next
        Plasmoid.configuration.secretsRevision = next
        page.configurationChanged()
    }

    function setStatus(text) {
        statusText = text
        statusTimer.restart()
    }

    function writeSecret(entry, value) {
        if (value.length === 0) {
            setStatus(i18n("Enter a value first."))
            return
        }
        wallet.write(entry, value)
    }

    function metricLabels() {
        return [
            i18n("Balance"),
            i18n("Today's spend"),
            i18n("Today's tokens"),
            i18ncp("trailing period for a cost", "Spend, last %1 day", "Spend, last %1 days", page.cfg_costPeriodDays),
            i18n("Lifetime spend"),
            i18n("Kimi weekly usage"),
            i18n("Kimi quota left"),
            i18n("Z.ai 5-hour usage"),
            i18n("Z.ai quota left")
        ]
    }

    Component.onCompleted: {
        stagedMetrics = initialMetrics();
        // The bridge runs commands one at a time, so all the reads can be
        // queued.
        wallet.read(WalletJs.API_KEY_ENTRY)
        wallet.read(WalletJs.SESSION_TOKEN_ENTRY)
        wallet.read(WalletJs.KIMI_API_KEY_ENTRY)
        wallet.read(WalletJs.ZAI_API_KEY_ENTRY)
    }

    Connections {
        target: wallet

        function onReadFinished(entry, secret) {
            if (entry === WalletJs.API_KEY_ENTRY) {
                page.apiKeySet = secret.length > 0
            } else if (entry === WalletJs.SESSION_TOKEN_ENTRY) {
                page.sessionTokenSet = secret.length > 0
            } else if (entry === WalletJs.KIMI_API_KEY_ENTRY) {
                page.kimiKeySet = secret.length > 0
            } else if (entry === WalletJs.ZAI_API_KEY_ENTRY) {
                page.zaiKeySet = secret.length > 0
            }
        }

        function onWriteFinished(entry, ok) {
            if (!ok) {
                page.setStatus(i18n("Could not write to KWallet."))
                return
            }
            if (entry === WalletJs.API_KEY_ENTRY) {
                page.apiKeySet = true
                apiKeyField.text = ""
            } else if (entry === WalletJs.SESSION_TOKEN_ENTRY) {
                page.sessionTokenSet = true
                sessionField.text = ""
            } else if (entry === WalletJs.KIMI_API_KEY_ENTRY) {
                page.kimiKeySet = true
                kimiKeyField.text = ""
            } else if (entry === WalletJs.ZAI_API_KEY_ENTRY) {
                page.zaiKeySet = true
                zaiKeyField.text = ""
            }
            page.bumpSecretsRevision()
            page.setStatus(i18n("Saved to KWallet."))
        }
    }

    Kirigami.FormLayout {
        // ------------------------------------------------------------- panel
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Panel")
        }

        // Add-style composition: pick a number, press Add to append it, remove
        // rows with the button on each. The list's order is the panel's order.
        // A provider without credentials or still loading is skipped on the
        // chip rather than shown as a dash.
        ColumnLayout {
            Kirigami.FormData.label: i18n("Panel shows:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // A button with a per-provider submenu: the provider name is the
            // group, so every offered number says whose it is. The submenu
            // items carry their own add actions (modelData), the same reason
            // the list's remove buttons do.
            QQC2.Button {
                id: addButton

                Layout.fillWidth: true
                text: i18n("Add")
                icon.name: "list-add"
                enabled: page.availableMetricsFor(0).length + page.availableMetricsFor(1).length + page.availableMetricsFor(2).length > 0
                onClicked: addMenu.popup(addButton, 0, addButton.height)
            }

            // A sibling of the button, NOT a child: a Control's default
            // property is its content, so a Menu declared inside the button
            // would become its face and never open (verified live: the button
            // rendered empty and nothing showed).
            QQC2.Menu {
                id: addMenu

                QQC2.Menu {
                    title: i18n("DeepSeek")

                    Instantiator {
                        model: page.availableMetricsFor(0)
                        delegate: QQC2.MenuItem {
                            required property var modelData
                            text: modelData.label
                            onTriggered: modelData.add()
                        }
                    }
                }

                QQC2.Menu {
                    title: i18n("Kimi Code")

                    Instantiator {
                        model: page.availableMetricsFor(1)
                        delegate: QQC2.MenuItem {
                            required property var modelData
                            text: modelData.label
                            onTriggered: modelData.add()
                        }
                    }
                }

                QQC2.Menu {
                    title: i18n("Z.ai")

                    Instantiator {
                        model: page.availableMetricsFor(2)
                        delegate: QQC2.MenuItem {
                            required property var modelData
                            text: modelData.label
                            onTriggered: modelData.add()
                        }
                    }
                }
            }

            Repeater {
                model: page.compositionEntries()

                delegate: RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: modelData.label
                        elide: Text.ElideRight
                    }

                    QQC2.ToolButton {
                        icon.name: "list-remove"
                        onClicked: modelData.remove()

                        QQC2.ToolTip.text: i18n("Remove")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: page.stagedMetrics.length === 0
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("Nothing selected, the panel shows the icon only.")
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Panel icons:")
            text: i18n("Show each number's provider icon")
            checked: page.cfg_showProviderIcons
            onToggled: {
                page.cfg_showProviderIcons = checked;
                page.configurationChanged();
            }
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Refresh interval (seconds):")
            from: 30
            to: 86400
            stepSize: 30
            value: page.cfg_refreshInterval
            onValueModified: {
                page.cfg_refreshInterval = value;
                page.configurationChanged();
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Privacy:")
            text: i18n("Hide all amounts")
            checked: page.cfg_hideAmounts
            onToggled: {
                page.cfg_hideAmounts = checked;
                page.configurationChanged();
            }
        }

        // -------------------------------------------------------------- data
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Data")
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Cost period (days):")
            from: 1
            // The platform refuses a window longer than this (Api.MAX_USAGE_DAYS),
            // so offering a bigger number would offer a broken widget.
            to: Api.MAX_USAGE_DAYS
            value: page.cfg_costPeriodDays
            onValueModified: {
                page.cfg_costPeriodDays = value;
                page.configurationChanged();
            }
        }

        // ------------------------------------------------------- credentials
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Credentials")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("All keys are stored in KWallet and never in the widget's configuration file.")
        }

        // --------------------------------------------------------- deepseek
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("DeepSeek")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("API key:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: apiKeyField

                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: page.apiKeySet
                    ? i18n("Stored in KWallet — enter a new key to replace it")
                    : i18n("sk-…")
            }

            QQC2.Button {
                text: i18nc("store the entered credential in KWallet", "Save")
                icon.name: "document-save"
                enabled: apiKeyField.text.length > 0
                onClicked: page.writeSecret(WalletJs.API_KEY_ENTRY, apiKeyField.text)
            }

            QQC2.Button {
                text: i18nc("discard the stored credential", "Clear")
                icon.name: "edit-clear"
                enabled: page.apiKeySet
                onClicked: {
                    apiKeyField.text = ""
                    wallet.write(WalletJs.API_KEY_ENTRY, "")
                }
            }
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("API key status:")
            text: page.apiKeySet ? i18n("Stored in KWallet") : i18n("Not set")
            opacity: 0.7
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Session token (optional)")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("The session token is the value the DeepSeek platform site keeps after you log in. It grants full access to your account — including creating and deleting API keys — so treat it like a password. Only token usage, cost history and the per-key breakdown need it; the API key alone is enough for the balance.")
        }

        // The token only exists inside the browser, so the settings page can do two
        // things and no more: say where it is, and open the site that holds it. It
        // cannot read the token for the user -- that would need the browser's own
        // storage or the login endpoint, and the login endpoint is behind a bot
        // check no non-browser client can pass.
        RowLayout {
            Kirigami.FormData.label: i18n("How to get it:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Log in at platform.deepseek.com, open Developer Tools (F12), then copy the value of the “userToken” entry under Application → Local Storage (in Firefox, Storage → Local Storage).")
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignTop
                text: i18nc("opens the DeepSeek platform site in the browser so a token can be copied", "Open platform.deepseek.com")
                icon.name: "internet-services"
                onClicked: Qt.openUrlExternally("https://platform.deepseek.com/")
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Session token:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: sessionField

                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: page.sessionTokenSet
                    ? i18n("Stored in KWallet — enter a new token to replace it")
                    : i18n("Paste the token from platform.deepseek.com")
            }

            QQC2.Button {
                text: i18nc("store the entered credential in KWallet", "Save")
                icon.name: "document-save"
                enabled: sessionField.text.length > 0
                // Peeled on the way in as well as on the way out, so the wallet holds
                // the token rather than whatever wrapper it was copied inside.
                onClicked: page.writeSecret(WalletJs.SESSION_TOKEN_ENTRY, Api.normalizeSessionToken(sessionField.text))
            }

            QQC2.Button {
                text: i18nc("discard the stored credential", "Clear")
                icon.name: "edit-clear"
                enabled: page.sessionTokenSet
                onClicked: {
                    sessionField.text = ""
                    wallet.write(WalletJs.SESSION_TOKEN_ENTRY, "")
                }
            }
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Session status:")
            text: page.sessionTokenSet ? i18n("Stored in KWallet") : i18n("Not set")
            opacity: 0.7
        }

        // ------------------------------------------------------ kimi code
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Kimi Code (optional)")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("A Kimi Code (Coding Plan) key adds the weekly quota and per-model limits to the popup. Use a key that starts with sk-kimi- and the Kimi Code base URL — keys and addresses from the Kimi Open Platform (api.moonshot.cn) do not work here.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Kimi API key:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: kimiKeyField

                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: page.kimiKeySet
                    ? i18n("Stored in KWallet — enter a new key to replace it")
                    : i18n("sk-kimi-…")
            }

            QQC2.Button {
                text: i18nc("store the entered credential in KWallet", "Save")
                icon.name: "document-save"
                enabled: kimiKeyField.text.length > 0
                onClicked: page.writeSecret(WalletJs.KIMI_API_KEY_ENTRY, kimiKeyField.text.trim())
            }

            QQC2.Button {
                text: i18nc("discard the stored credential", "Clear")
                icon.name: "edit-clear"
                enabled: page.kimiKeySet
                onClicked: {
                    kimiKeyField.text = ""
                    wallet.write(WalletJs.KIMI_API_KEY_ENTRY, "")
                }
            }
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Kimi API key status:")
            text: page.kimiKeySet ? i18n("Stored in KWallet") : i18n("Not set")
            opacity: 0.7
        }

        // Not a secret, so unlike the keys it is stored in the widget's
        // configuration file rather than KWallet.
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Kimi base URL:")
            Layout.fillWidth: true
            placeholderText: "https://api.kimi.com/coding/v1"
            text: page.cfg_kimiBaseUrl
            onEditingFinished: {
                page.cfg_kimiBaseUrl = text.trim();
                page.configurationChanged();
            }
        }

        // --------------------------------------------------------- z.ai
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Z.ai (optional)")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("A Z.ai Coding Plan key adds the quota windows (5-hour, weekly, monthly) and the last 7 and 30 days of usage to the popup.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Z.ai API key:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: zaiKeyField

                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: page.zaiKeySet
                    ? i18n("Stored in KWallet — enter a new key to replace it")
                    : i18n("Paste the Z.ai API key")
            }

            QQC2.Button {
                text: i18nc("store the entered credential in KWallet", "Save")
                icon.name: "document-save"
                enabled: zaiKeyField.text.length > 0
                onClicked: page.writeSecret(WalletJs.ZAI_API_KEY_ENTRY, zaiKeyField.text.trim())
            }

            QQC2.Button {
                text: i18nc("discard the stored credential", "Clear")
                icon.name: "edit-clear"
                enabled: page.zaiKeySet
                onClicked: {
                    zaiKeyField.text = ""
                    wallet.write(WalletJs.ZAI_API_KEY_ENTRY, "")
                }
            }
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Z.ai API key status:")
            text: page.zaiKeySet ? i18n("Stored in KWallet") : i18n("Not set")
            opacity: 0.7
        }

        // Not a secret either; same deal as the Kimi base URL.
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Z.ai base URL:")
            Layout.fillWidth: true
            placeholderText: "https://api.z.ai"
            text: page.cfg_zaiBaseUrl
            onEditingFinished: {
                page.cfg_zaiBaseUrl = text.trim();
                page.configurationChanged();
            }
        }

        // --------------------------------------------------------- reminders
        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Reminders")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Reset reminder:")
            text: i18n("Warn when a weekly quota is about to reset with much of it unused")
            checked: page.cfg_resetReminderEnabled
            onToggled: {
                page.cfg_resetReminderEnabled = checked;
                page.configurationChanged();
            }
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Hours before reset:")
            from: 1
            to: 72
            value: page.cfg_resetReminderHours
            onValueModified: {
                page.cfg_resetReminderHours = value;
                page.configurationChanged();
            }
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Minimum unused (%):")
            from: 0
            to: 90
            value: page.cfg_resetReminderPercent
            onValueModified: {
                page.cfg_resetReminderPercent = value;
                page.configurationChanged();
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Daily digest:")
            text: i18n("Summarize today's quota usage twice a day")
            checked: page.cfg_dailyDigestEnabled
            onToggled: {
                page.cfg_dailyDigestEnabled = checked;
                page.configurationChanged();
            }
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("First reminder time:")
            Layout.fillWidth: true
            placeholderText: "09:00"
            text: page.cfg_digestTime1
            inputMask: "00:00"
            onEditingFinished: {
                page.cfg_digestTime1 = text.trim();
                page.configurationChanged();
            }
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Second reminder time:")
            Layout.fillWidth: true
            placeholderText: "21:00"
            text: page.cfg_digestTime2
            inputMask: "00:00"
            onEditingFinished: {
                page.cfg_digestTime2 = text.trim();
                page.configurationChanged();
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: page.statusText.length > 0
            wrapMode: Text.Wrap
            color: Kirigami.Theme.positiveTextColor
            text: page.statusText
        }
    }
}
