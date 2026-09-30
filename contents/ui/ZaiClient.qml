/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    Fetches Z.ai (GLM Coding Plan) usage: the quota rows from
    /api/monitor/usage/quota/limit and the 7/30-day totals from
    /api/monitor/usage/model-usage (see js/zai.js for the endpoint contract).

    The key is tried as a bare Authorization value first and retried as a
    Bearer header on 401. Each of the three requests is optional on its own —
    the widget shows whatever answered, like the reference tracker — and the
    whole refresh only fails when nothing did.
*/
import QtQuick
import "js/zai.js" as Zai

QtObject {
    id: client

    // ------------------------------------------------------------ inputs
    property string apiKey: ""
    property string baseUrl: ""

    // ------------------------------------------------------------- state
    property bool loading: false
    property string errorText: ""
    property bool hasData: false
    property date lastUpdated: new Date(0)

    // parsed (Zai.parseQuotaLimit / parseModelUsage); quotaRows is null until
    // the quota endpoint answers. The object literals are parenthesised
    // because a bare `{` after the binding's colon parses as a statement
    // block, which is a QML error rather than an object.
    property var quotaRows: null
    property var sevenDay: ({ prompts: 0, tokens: 0 })
    property var thirtyDay: ({ prompts: 0, tokens: 0 })

    readonly property bool hasApiKey: apiKey.length > 0
    readonly property bool configured: hasApiKey

    // The row the panel shows: the quota that resets soonest, i.e. the
    // shortest window (parseQuotaLimit sorts that way).
    readonly property var headline: quotaRows !== null && quotaRows.length > 0 ? quotaRows[0] : null
    readonly property bool zaiOk: hasData && headline !== null
    readonly property real headlinePercent: headline !== null ? headline.percent : 0

    // ----------------------------------------------------------- fetching
    // The endpoint's refusals are terse; say what a user can do about the
    // ones we know, and keep the HTTP status for the rest.
    function zaiFailure(status) {
        var kind = Zai.failureKind(status)
        if (kind === "auth") {
            return i18n("The Z.ai API rejected the key. Check that it is a Z.ai Coding Plan API key.")
        }
        if (kind === "forbidden") {
            return i18n("The Z.ai API denied access (403) for this key.")
        }
        if (kind === "rate-limited") {
            return i18n("The Z.ai API is rate-limiting requests. Try again later.")
        }
        return i18n("HTTP error %1", String(status))
    }

    function refresh() {
        if (loading || !configured) {
            return
        }
        loading = true
        errorText = ""
        var windows = Zai.usageWindows(new Date())
        // Three requests, each settling exactly once — a 401 with the first
        // Authorization spelling retries only itself with the other — and all
        // counters meeting in _done().
        var state = { answered: 0, failures: [] }
        _fetch(Zai.quotaUrl(baseUrl), state, function (status, text) {
            if (status >= 200 && status < 300) {
                client.quotaRows = Zai.parseQuotaLimit(text)
            }
        })
        _fetch(Zai.modelUsageUrl(baseUrl, windows.start7, windows.end), state, function (status, text) {
            if (status >= 200 && status < 300) {
                client.sevenDay = Zai.parseModelUsage(text)
            }
        })
        _fetch(Zai.modelUsageUrl(baseUrl, windows.start30, windows.end), state, function (status, text) {
            if (status >= 200 && status < 300) {
                client.thirtyDay = Zai.parseModelUsage(text)
            }
        })
    }

    function _done(state) {
        if (state.answered + state.failures.length < 3) {
            return
        }
        loading = false
        if (state.answered > 0) {
            hasData = true
            lastUpdated = new Date()
            errorText = ""
            return
        }
        // Nothing answered: the first recorded failure names the problem.
        errorText = state.failures.length > 0
            ? state.failures[0]
            : i18n("Could not read the Z.ai usage data — check the API key and base URL.")
    }

    function _fetch(url, state, accept) {
        _fetchVariant(url, 0, state, accept)
    }

    function _fetchVariant(url, variant, state, accept) {
        _get(url, Zai.authVariants(apiKey)[variant], function (netErr, status, text) {
            if (netErr) {
                state.failures.push(netErr)
                _done(state)
                return
            }
            if (status === 401 && variant === 0) {
                // The other Authorization spelling gets its chance before
                // this counts as a refusal; the retry itself is final.
                _fetchVariant(url, 1, state, accept)
                return
            }
            if (status >= 200 && status < 300) {
                state.answered += 1
                accept(status, text)
            } else {
                state.failures.push(zaiFailure(status))
            }
            _done(state)
        })
    }

    function _get(url, headers, callback) {
        var xhr = new XMLHttpRequest()
        var settled = false
        function finish(err, status, text) {
            if (settled) {
                return
            }
            settled = true
            callback(err, status, text)
        }
        xhr.open("GET", url, true)
        xhr.timeout = 20000
        for (var name in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, name)) {
                xhr.setRequestHeader(name, headers[name])
            }
        }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4) {
                return
            }
            finish("", xhr.status, xhr.responseText || "")
        }
        xhr.ontimeout = function () {
            finish(i18n("Request timed out"), 0, "")
        }
        xhr.onerror = function () {
            finish(i18n("Network error"), 0, "")
        }
        xhr.send()
    }

    // --------------------------------------------------------- presentation
    function updatedLabel() {
        if (!hasData) {
            return i18n("never")
        }
        var seconds = Math.max(0, (new Date().getTime() - lastUpdated.getTime()) / 1000)
        if (seconds < 60) {
            return i18n("just now")
        }
        if (seconds < 3600) {
            return i18ncp("minutes ago", "%1 minute ago", "%1 minutes ago", Math.floor(seconds / 60))
        }
        return i18ncp("hours ago", "%1 hour ago", "%1 hours ago", Math.floor(seconds / 3600))
    }
}
