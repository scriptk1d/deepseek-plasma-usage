/*
    SPDX-FileCopyrightText: 2026 scriptk1d
    SPDX-License-Identifier: GPL-2.0-or-later

    A provider section header for the popup: the brand icon at its optical
    size beside the provider's name, larger and bolder than the table text so
    the popup reads as three sections rather than one flat list. The icon's
    dark-theme variant is picked here; the caller passes the PROVIDER_ICONS
    entry.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "js/format.js" as Fmt

RowLayout {
    id: header

    property string title: ""
    property var icon: null

    // Light theme text is dark and vice versa: a light text colour means a
    // dark background — the case the white glyph variants exist for.
    readonly property bool darkBackground: {
        var c = Kirigami.Theme.textColor;
        return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 > 0.5;
    }

    spacing: Kirigami.Units.smallSpacing

    Image {
        visible: header.icon !== null
        source: header.icon !== null ? Fmt.iconVariant(header.icon, header.darkBackground) : ""
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: header.icon !== null ? Fmt.iconHeight(header.icon, Kirigami.Units.iconSizes.small) : 0
        Layout.preferredHeight: Layout.preferredWidth
        fillMode: Image.PreserveAspectFit
        // A broken or missing file renders as nothing rather than breaking
        // the header.
        asynchronous: true
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: header.title
        elide: Text.ElideRight
        font.bold: true
        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.1)
    }
}
