import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Notification center: an iPhone-lock-screen-style stack that expands into a
// scrollable list, plus live settings for the notification service.
Panel {
  id: root
  moduleName: "jovibe.notify-center"
  ipcTarget: "notify-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool settingsOpen: false
  property bool stackExpanded: false

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.barForeground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.fontFamily
  readonly property var entries: service ? service.history : []
  readonly property var devices: service && service.devices ? service.devices : []
  readonly property int unread: service ? Number(service.unreadCount || 0) : 0
  readonly property bool darkTheme: {
    var c = Color.background
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
  }
  readonly property color panelTint: Util.alpha(darkTheme ? Color.background : "#ffffff", darkTheme ? 0.68 : 0.56)

  function open() {
    settingsOpen = false
    stackExpanded = false
    if (root.service) root.service.refreshDevices()
    root.controller.show()
    Qt.callLater(function() {
      if (list) list.positionViewAtBeginning()
    })
  }

  function openSettings() {
    stackExpanded = false
    settingsOpen = true
    root.controller.show()
  }

  function close() {
    settingsOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function expandStack() {
    stackExpanded = true
    Qt.callLater(function() {
      if (list) list.positionViewAtBeginning()
    })
  }

  function collapseStack() {
    stackExpanded = false
    Qt.callLater(function() {
      if (list) list.positionViewAtBeginning()
    })
  }

  function toggleStack() {
    stackExpanded = !stackExpanded
    Qt.callLater(function() {
      if (list) list.positionViewAtBeginning()
    })
  }

  function invoke(key) {
    if (!root.service) return
    root.service.invokeHistory(String(key))
    root.close()
  }

  function remove(key) {
    if (root.service) root.service.removeHistory(String(key))
  }

  function mute(app) {
    if (root.service) root.service.muteApp(String(app))
  }

  function invokeAction(key, identifier) {
    if (!root.service) return
    root.service.invokeHistoryAction(String(key), String(identifier))
    root.close()
  }

  function deviceGlyph(kind) {
    switch (String(kind || "")) {
      case "mouse": return "\uF245"
      case "keyboard": return "\uF11C"
      case "audio": return "\uF025"
      case "drive": return "\uF0A0"
      case "printer": return "\uF02F"
      case "phone": return "\uF10B"
      case "monitor": return "\uF108"
      case "device": return "\uF287"
      default: return "\uF128"
    }
  }

  function deviceKindLabel(kind) {
    switch (String(kind || "")) {
      case "mouse": return "Mouse"
      case "keyboard": return "Keyboard"
      case "audio": return "Audio device"
      case "drive": return "Drive"
      case "printer": return "Printer"
      case "phone": return "Phone"
      case "monitor": return "External monitor"
      case "device": return "USB device"
      default: return "Unknown USB device"
    }
  }

  function deviceTooltip(device) {
    if (!device) return ""
    var parts = []
    var kindLabel = deviceKindLabel(device.kind)
    var name = String(device.name || "").trim()
    if (name.length > 0 && name.toLowerCase() !== kindLabel.toLowerCase()) parts.push(name)
    parts.push(kindLabel)
    var detail = String(device.detail || "").trim()
    if (detail.length > 0) parts.push(detail)
    var action = String(device.action || "")
    if (action === "files") parts.push("Open Files")
    else if (action === "printers") parts.push("Open Print Settings")
    else if (action === "display") parts.push("Open Monitor Settings")
    else parts.push("No action")
    return parts.join(" \u00b7 ")
  }

  function scrollBy(delta) {
    if (!list) return
    if (!root.stackExpanded) {
      if (delta > 0 && root.entries.length > 1) root.expandStack()
      return
    }
    if (delta < 0 && list.contentY <= 0.5) {
      root.collapseStack()
      return
    }
    var maxY = Math.max(0, list.contentHeight - list.height)
    list.contentY = Math.max(0, Math.min(maxY, list.contentY + delta * Style.space(56)))
  }

  Item {
    id: rightEdgeAnchor
    parent: root.anchorItem && root.anchorItem.QsWindow && root.anchorItem.QsWindow.window
      ? root.anchorItem.QsWindow.window.contentItem : null
    width: 1
    height: 1
    x: parent ? parent.width - width : 0
    y: 0
    visible: false
  }

  KeyboardPanel {
    id: panel
    anchorItem: rightEdgeAnchor
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420), Style.space(460))
    contentHeight: panel.fittedContentHeight(Style.space(560), Style.space(620))
    borderSpec: Border.none()

    property color savedPopupBackground: "transparent"
    property bool popupBackgroundSaved: false

    Component.onDestruction: {
      if (popupBackgroundSaved) Color.popups.background = savedPopupBackground
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: -panel.padding
      radius: Math.max(Style.cornerRadius, Style.space(18))
      color: root.panelTint
      border.width: 0
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.scrollBy(dy) }
      onTextKey: function(t) {
        if (t === "d" || t === "D") { if (root.service) root.service.toggleDnd() }
        else if (t === "s" || t === "S") root.openSettings()
        else if (t === "m" || t === "M") { if (root.service) root.service.markAllRead() }
      }

      Item {
        anchors.fill: parent

        // ---------------------------------------------------------- list view
        Item {
          id: listView
          anchors.fill: parent
          visible: !root.settingsOpen

          RowLayout {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(42)
            spacing: Style.space(6)

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 0

              Text {
                text: "Notifications"
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                text: root.unread > 0
                  ? root.unread + " unread · " + root.entries.length + " total"
                  : root.entries.length + " notification" + (root.entries.length === 1 ? "" : "s")
                textFormat: Text.PlainText
                color: Util.alpha(root.contentForeground, 0.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelButton {
              compact: true
              glyph: root.service && root.service.dnd ? "\uF1F6" : "\uF0F3"
              active: root.service ? root.service.dnd === true : false
              urgent: root.service ? root.service.dnd === true : false
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.service) root.service.toggleDnd()
            }

            PanelButton {
              compact: true
              label: root.stackExpanded ? "Collapse" : "Stack"
              active: root.stackExpanded
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.toggleStack()
            }

            PanelButton {
              compact: true
              glyph: "\uF013"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.openSettings()
            }

            PanelButton {
              compact: true
              glyph: "\u2715"
              urgent: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.close()
            }
          }

          ListView {
            id: list
            anchors.top: header.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footerArea.top
            anchors.bottomMargin: Style.space(8)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.entries
            spacing: root.stackExpanded ? Style.space(10) : -Style.space(42)
            cacheBuffer: 1200
            pressDelay: 80

            WheelHandler {
              target: list
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var direction = 0
                var angle = event.angleDelta ? event.angleDelta.y : 0
                if (angle !== 0) direction = angle > 0 ? 1 : -1
                else {
                  var pixels = event.pixelDelta ? event.pixelDelta.y : 0
                  if (pixels !== 0) direction = pixels > 0 ? 1 : -1
                }
                if (direction === 0) return
                if (!root.stackExpanded) {
                  if (direction < 0 && root.entries.length > 1) {
                    root.expandStack()
                    event.accepted = true
                  }
                  return
                }
                if (direction > 0 && list.contentY <= 0.5) {
                  root.collapseStack()
                  event.accepted = true
                  return
                }
                event.accepted = false
              }
            }

            Behavior on spacing {
              enabled: root.service ? root.service.animation : true
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            add: Transition {
              NumberAnimation {
                properties: "opacity,scale"
                from: 0
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
              }
            }

            delegate: Item {
              id: row
              required property int index
              required property var modelData

              width: list.width
              height: card.height
              z: list.count - index

              NotificationCard {
                id: card
                width: row.width
                app: String(row.modelData.app || "")
                appIcon: String(row.modelData.appIcon || "")
                summary: String(row.modelData.summary || "")
                body: String(row.modelData.body || "")
                image: String(row.modelData.image || "")
                actionsJson: String(row.modelData.actionsJson || "[]")
                urgency: Number(row.modelData.urgency || 1)
                timestamp: Number(row.modelData.timestamp || 0)
                animationEnabled: root.service ? root.service.animation : true
                compact: !root.stackExpanded && row.index > 0
                stackedView: !root.stackExpanded
                stackFront: row.index === 0
                fontFamily: root.contentFontFamily

                onCloseRequested: root.remove(row.modelData.key)
                onDismissRequested: root.remove(row.modelData.key)
                onMuteRequested: root.mute(row.modelData.app)
                onSettingsRequested: root.openSettings()
                onActionInvoked: function(identifier) { root.invokeAction(row.modelData.key, identifier) }
                onCardClicked: {
                  if (!root.stackExpanded && row.index > 0) root.expandStack()
                  else root.invoke(row.modelData.key)
                }
              }
            }
          }

          Text {
            anchors.centerIn: list
            visible: list.count === 0
            text: "You're all caught up"
            textFormat: Text.PlainText
            color: Util.alpha(root.contentForeground, 0.55)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Column {
            id: footerArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Style.space(4)

            Flow {
              id: deviceRow
              width: parent.width
              height: childrenRect.height
              spacing: Style.space(4)
              visible: root.devices.length > 0

              Repeater {
                model: root.devices

                delegate: PanelButton {
                  compact: true
                  glyph: root.deviceGlyph(modelData.kind)
                  tooltipText: root.deviceTooltip(modelData)
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: {
                    if (!root.service) return
                    if (String(modelData.action || "").length === 0) return
                    root.service.openDevice(modelData)
                    root.close()
                  }
                }
              }
            }

            RowLayout {
              id: footer
              width: parent.width
              height: Style.space(34)
              spacing: Style.space(6)

              Text {
                Layout.fillWidth: true
                text: root.stackExpanded
                  ? "Scroll to browse · up at top to stack"
                  : "Scroll down or tap to expand"
                textFormat: Text.PlainText
                color: Util.alpha(root.contentForeground, 0.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              PanelButton {
                compact: true
                label: "Mark read"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: if (root.service) root.service.markAllRead()
              }

              PanelButton {
                compact: true
                label: "Clear"
                urgent: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: if (root.service) root.service.clearHistory()
              }
            }
          }
        }

        // ------------------------------------------------------------ settings
        Item {
          id: settingsView
          anchors.fill: parent
          visible: root.settingsOpen

          RowLayout {
            id: settingsHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(42)
            spacing: Style.space(6)

            PanelButton {
              compact: true
              glyph: "\u2039"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.settingsOpen = false
            }

            Text {
              Layout.fillWidth: true
              text: "Notification settings"
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            PanelButton {
              compact: true
              glyph: "\u2715"
              urgent: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.close()
            }
          }

          Flickable {
            id: settingsFlick
            anchors.top: settingsHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
              id: settingsColumn
              width: settingsFlick.width
              spacing: Style.space(10)

              SettingRow {
                label: "Popup position"
                PanelButton { compact: true; label: "Left"; active: root.service && root.service.position === "left"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setPosition("left", true) }
                PanelButton { compact: true; label: "Center"; active: root.service && root.service.position === "center"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setPosition("center", true) }
                PanelButton { compact: true; label: "Right"; active: root.service && root.service.position === "right"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setPosition("right", true) }
              }

              SettingRow {
                label: "Popup duration"
                PanelButton { compact: true; glyph: "\u2212"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setTimeout(root.service.timeout - 1) }
                ValueText { text: (root.service ? root.service.timeout : 0) + "s" }
                PanelButton { compact: true; glyph: "+"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setTimeout(root.service.timeout + 1) }
              }

              SettingRow {
                label: "Critical duration"
                PanelButton { compact: true; glyph: "\u2212"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setCriticalTimeout(root.service.criticalTimeout - 1) }
                ValueText { text: (root.service ? root.service.criticalTimeout : 0) + "s" }
                PanelButton { compact: true; glyph: "+"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setCriticalTimeout(root.service.criticalTimeout + 1) }
              }

              SettingRow {
                label: "Visible popup cards"
                PanelButton { compact: true; label: "1"; active: root.service && root.service.maxVisible === 1; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setMaxVisible(1) }
                PanelButton { compact: true; label: "2"; active: root.service && root.service.maxVisible === 2; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setMaxVisible(2) }
                PanelButton { compact: true; label: "3"; active: root.service && root.service.maxVisible === 3; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setMaxVisible(3) }
              }

              SettingRow {
                label: "Animation"
                PanelButton { compact: true; label: root.service && root.service.animation ? "On" : "Off"; active: root.service && root.service.animation === true; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setAnimation(!root.service.animation) }
              }

              SettingRow {
                label: "Keep critical until dismissed"
                PanelButton { compact: true; label: root.service && root.service.stickyCritical ? "On" : "Off"; active: root.service && root.service.stickyCritical === true; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.setStickyCritical(!root.service.stickyCritical) }
              }

              SettingRow {
                label: "Do Not Disturb"
                PanelButton { compact: true; label: root.service && root.service.dnd ? "On" : "Off"; active: root.service && root.service.dnd === true; urgent: true; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: if (root.service) root.service.toggleDnd() }
              }

              Item { width: parent.width; height: Style.space(5) }

              Rectangle {
                width: parent.width
                height: 1
                color: Util.alpha(root.contentForeground, 0.18)
              }

              Text {
                text: "Muted apps"
                textFormat: Text.PlainText
                color: Util.alpha(root.contentForeground, 0.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }

              Text {
                visible: !root.service || !root.service.mutedList || root.service.mutedList.length === 0
                text: "No apps muted"
                textFormat: Text.PlainText
                color: Util.alpha(root.contentForeground, 0.45)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.service ? root.service.mutedList : []

                delegate: Row {
                  width: settingsColumn.width
                  height: Style.space(28)
                  spacing: Style.space(6)

                  Text {
                    width: Math.max(0, parent.width - unmuteButton.width - parent.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    textFormat: Text.PlainText
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  PanelButton {
                    id: unmuteButton
                    compact: true
                    label: "Unmute"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: if (root.service) root.service.unmuteApp(modelData)
                  }
                }
              }

              Item { width: parent.width; height: Style.space(2) }

              Text {
                width: parent.width
                text: "Changes save to ~/.config/omarchy-notify-center/config.toml and apply live."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Util.alpha(root.contentForeground, 0.42)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  Connections {
    target: panel
    ignoreUnknownSignals: true

    function onOpenChanged() {
      if (panel.open) {
        panel.savedPopupBackground = Color.popups.background
        panel.popupBackgroundSaved = true
        Color.popups.background = "transparent"
      } else if (panel.popupBackgroundSaved) {
        Color.popups.background = panel.savedPopupBackground
        panel.popupBackgroundSaved = false
      }
    }
  }

  component SettingRow: Item {
    id: settingRow
    property string label: ""
    default property alias controls: controlRow.children
    property real spacing: Style.space(6)

    width: parent ? parent.width : 0
    height: Math.max(labelText.implicitHeight, controlRow.implicitHeight)

    FieldLabel {
      id: labelText
      width: Math.max(0, settingRow.width - controlRow.width - settingRow.spacing)
      anchors.verticalCenter: parent.verticalCenter
      text: settingRow.label
    }

    Row {
      id: controlRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: settingRow.spacing
    }
  }

  component FieldLabel: Text {
    textFormat: Text.PlainText
    color: root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component ValueText: Text {
    width: Math.max(Style.space(30), implicitWidth)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    color: Util.alpha(root.contentForeground, 0.7)
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
  }
}
