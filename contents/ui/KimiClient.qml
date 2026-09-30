/*
    SPDX-FileCopyrightText: 2026 cassidy
    SPDX-License-Identifier: GPL-2.0-or-later

    Fetches Kimi Code (Coding Plan) usage: the weekly quota summary and the
    per-model limits, from GET {base}/usages with a /usage fallback
    (see js/kimi.js for the endpoint contract).

    A Kimi Code key (sk-kimi-…) is required; Moonshot Open Platform keys
    (api.moonshot.cn) are answered with 401. Failures are classified from the
    HTTP status, unlike the DeepSeek platform API.
*/
import QtQuick
import "js/kimi.js" as Kimi

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

    // parsed rows (Kimi.parseUsagePayload); summary is null when the payload
    // only carries per-model limits.
    property var summary: null
    property var limits: []

    readonly property bool hasApiKey: apiKey.length > 0
    readonly property bool configured: hasApiKey

    // The number a panel metric shows: the weekly quota when the payload has
    // one, else the first per-model limit.
    readonly property var headline: summary !== null ? summary : (limits.length > 0 ? limits[0] : null)
    readonly property bool kimiOk: hasData && headline !== null
    readonly property real headlineUsed: headline !== null ? headline.used : 0
    readonly property real headlineLimit: headline !== null ? headline.limit : 0

    // ----------------------------------------------------------- fetching
    // The endpoint's refusals are terse; say what a user can do about the
    // ones we know, and keep the HTTP status for the rest.
    function kimiFailure(status) {
        var kind = Kimi.failureKind(status)
        if (kind === "auth") {
            return i18n("The Kimi API rejected the key. Use a Kimi Code (Coding Plan) key (sk-kimi-…); keys from the Kimi Open Platform (api.moonshot.cn) do not work.")
        }
        if (kind === "forbidden") {
            return i18n("The Kimi API denied access (403) for this key.")
        }
        if (kind === "rate-limited") {
            return i18n("The Kimi API is rate-limiting requests. Try again later.")
        }
        return i18n("HTTP error %1", String(status))
    }

    function refresh() {
        if (loading || !configured) {
            return
        }
        loading = true
        errorText = ""
        _fetch(Kimi.usageUrl(baseUrl), false)
    }

    function _fetch(url, isFallback) {
        _get(url, function (netErr, status, text) {
            if (netErr) {
                loading = false
                errorText = netErr
                return
            }
            if (status === 404 && !isFallback) {
                _fetch(Kimi.fallbackUrl(baseUrl), true)
                return
            }
            loading = false
            if (status < 200 || status >= 300) {
                errorText = status === 404
                    ? i18n("The Kimi usage endpoint was not found. Check the Kimi base URL in the widget settings.")
                    : kimiFailure(status)
                return
            }
            var parsed = Kimi.parseUsagePayload(text)
            if (!parsed.ok) {
                errorText = i18n("Could not read the Kimi usage data — check the API key and base URL.")
                return
            }
            summary = parsed.summary
            limits = parsed.limits
            hasData = true
            lastUpdated = new Date()
        })
    }

    function _get(url, callback) {
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
        var headers = Kimi.authHeaders(apiKey)
        for (var name in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, name)) {
                xhr.setRequestHeader(name, headers[name])
            }
        }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4) {
                return
            }
            if (xhr.status >= 200 && xhr.status < 300) {
                finish("", xhr.status, xhr.responseText)
            } else {
                // The 401 body is JSON, but the status alone says everything
                // the user can act on, so it is classified from the status.
                finish("", xhr.status, xhr.responseText || "")
            }
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
