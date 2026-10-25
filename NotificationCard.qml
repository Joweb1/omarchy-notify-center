import QtQuick
import Quickshell
import qs.Commons

// One Android/iOS-style notification pill. Presentational only: the service
// owns queueing, lifetimes, history, muting and actions.
Rectangle {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string actionsJson: "[]"
  property int urgency: 1
  property double timestamp: 0
  property bool dismissing: false
  property bool animationEnabled: true
  property bool compact: false
  property bool stackedView: false
  property bool stackFront: false
  property string fontFamily: Style.fontFamily

  signal closeRequested()
  signal cardClicked()
  signal dismissRequested()
  signal muteRequested()
  signal settingsRequested()
  signal actionInvoked(string identifier)

  readonly property bool hovered: hover.hovered
  readonly property bool critical: urgency === 2
  readonly property bool fullyRounded: stackedView ? !stackFront : false
  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.45)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  readonly property color accentColor: critical ? Color.urgent : Color.notifications.countdown
  readonly property color surfaceColor: Color.notifications.background
  readonly property color borderColor: critical
    ? Util.alpha(Color.urgent, 0.65)
    : Color.notifications.border

  // Theme-aware close button: a light disc on dark surfaces, a dark disc on
  // light ones, tinted red on hover. The glyph itself is always red.
  readonly property bool darkSurface: {
    var c = surfaceColor
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
  }
  readonly property color closeBackground: closeMouse.containsMouse
    ? Util.alpha(Color.urgent, 0.32)
    : Util.alpha(darkSurface ? "#ffffff" : "#000000", darkSurface ? 0.18 : 0.10)

  readonly property string iconSource: {
    var value = String(image || "")
    if (value.length > 0) return value
    value = String(appIcon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  readonly property var actionList: {
    try {
      var parsed = JSON.parse(String(actionsJson || "[]"))
      if (!Array.isArray(parsed)) return []
      var out = []
      for (var i = 0; i < parsed.length; i++) {
        var a = parsed[i]
        if (!a || !a.identifier || a.identifier === "default") continue
        out.push({ identifier: String(a.identifier), text: String(a.text || a.identifier) })
      }
      return out
    } catch (e) {
      return []
    }
  }

  property bool menuOpen: false
  property int clockTick: 0
  property real reveal: animationEnabled ? 0 : 1

  onCompactChanged: if (compact) menuOpen = false

  width: Style.space(380)
  implicitHeight: contentRow.implicitHeight + (compact ? Style.space(12) : Style.space(22))
  height: implicitHeight
  radius: fullyRounded ? height / 2 : Math.min(height / 2, Style.space(14))
  color: surfaceColor
  border.width: Math.max(1, Math.round(Style.space(1)))
  border.color: borderColor
  clip: true
  opacity: dismissing ? 0 : reveal

  transform: Translate { y: (1 - root.reveal) * -14 }

  Behavior on opacity {
    enabled: root.animationEnabled
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }
  Behavior on reveal {
    enabled: root.animationEnabled
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }
  Behavior on implicitHeight {
    enabled: root.animationEnabled
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  Component.onCompleted: reveal = 1

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.clockTick++
  }

  HoverHandler { id: hover }

  function timeAgo(ts) {
    var seconds = Math.max(0, Math.floor((Date.now() - Number(ts || 0)) / 1000))
    if (seconds < 60) return "now"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"
    return Math.floor(hours / 24) + "d ago"
  }

  // Clicking the body opens the source; buttons above it consume their clicks.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.cardClicked()
  }

  Row {
    id: contentRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.space(16)
    anchors.rightMargin: Style.space(16)
    anchors.topMargin: root.compact ? Style.space(6) : Style.space(12)
    spacing: Style.space(10)

    Rectangle {
      id: iconSlot
      width: Style.space(32)
      height: Style.space(32)
      radius: root.critical ? height / 2 : Style.space(10)
      color: Util.alpha(root.accentColor, 0.14)
      border.width: 1
      border.color: Util.alpha(root.accentColor, 0.28)

      Image {
        id: iconImage
        anchors.fill: parent
        anchors.margins: Style.space(5)
        source: root.iconSource
        sourceSize.width: iconSlot.width * Screen.devicePixelRatio
        sourceSize.height: iconSlot.height * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: root.iconSource.length > 0 && status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: !iconImage.visible
        text: root.critical ? "\uF071" : "\uF0F3"
        color: root.accentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Column {
      id: textColumn
      width: contentRow.width - iconSlot.width - contentRow.spacing
      spacing: Style.space(3)

      Row {
        id: headerRow
        width: parent.width
        height: Math.max(closeButton.height, moreButton.height)
        spacing: Style.space(6)

        Text {
          id: appLabel
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - closeButton.width
            - (timeLabel.visible ? timeLabel.width + parent.spacing : 0)
            - (moreButton.visible ? moreButton.width + parent.spacing : 0)
            - parent.spacing)
          text: root.app.length > 0 ? root.app : "Notification"
          textFormat: Text.PlainText
          color: root.critical ? root.accentColor : root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
          elide: Text.ElideRight
        }

        Text {
          id: timeLabel
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.compact
          text: {
            root.clockTick
            return root.timeAgo(root.timestamp)
          }
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          id: moreButton
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.compact
          width: visible ? Style.space(26) : 0
          height: Style.space(26)
          radius: width / 2
          color: moreMouse.containsMouse ? Util.alpha(root.accentColor, 0.22) : Util.alpha(root.accentColor, 0.10)
          border.width: 1
          border.color: Util.alpha(root.accentColor, moreMouse.containsMouse ? 0.55 : 0.28)

          Text {
            anchors.centerIn: parent
            text: "\u22EF"
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          MouseArea {
            id: moreMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.menuOpen = !root.menuOpen
          }
        }

        Rectangle {
          id: closeButton
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(30)
          height: Style.space(30)
          radius: width / 2
          color: root.closeBackground
          border.width: 1
          border.color: Util.alpha(Color.urgent, closeMouse.containsMouse ? 0.95 : 0.58)
          Behavior on color {
            enabled: root.animationEnabled
            ColorAnimation { duration: 120 }
          }

          Text {
            anchors.centerIn: parent
            text: "\u2715"
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
          }
        }
      }

      Text {
        width: parent.width
        visible: root.summary.length > 0
        text: root.summary
        textFormat: Text.PlainText
        color: Color.notifications.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.compact ? 1 : 2
      }

      Text {
        width: parent.width
        visible: !root.compact && root.body.length > 0
        text: root.body
        textFormat: Text.PlainText
        color: root.bodyColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 3
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: !root.compact && root.actionList.length > 0

        Repeater {
          model: root.actionList

          delegate: Rectangle {
            required property var modelData

            height: Style.space(26)
            width: actionLabel.implicitWidth + Style.space(20)
            radius: height / 2
            color: actionMouse.containsMouse
              ? Util.alpha(root.accentColor, 0.24)
              : Util.alpha(root.accentColor, 0.10)
            border.width: 1
            border.color: Util.alpha(root.accentColor, actionMouse.containsMouse ? 0.6 : 0.3)

            Text {
              id: actionLabel
              anchors.centerIn: parent
              text: modelData.text
              textFormat: Text.PlainText
              color: root.accentColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            MouseArea {
              id: actionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.actionInvoked(modelData.identifier)
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: visible ? Style.space(1) : 0
        visible: root.menuOpen
        color: Util.alpha(root.dimColor, 0.35)
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: root.menuOpen

        Repeater {
          model: [
            { action: "dismiss", label: "Dismiss" },
            { action: "mute", label: "Mute " + (root.app.length > 0 ? root.app : "this app") },
            { action: "settings", label: "Notification settings" }
          ]

          delegate: Rectangle {
            required property var modelData

            height: Style.space(28)
            width: menuLabel.implicitWidth + Style.space(22)
            radius: height / 2
            color: menuMouse.containsMouse
              ? Util.alpha(Color.notifications.text, 0.14)
              : Util.alpha(Color.notifications.text, 0.06)
            border.width: 1
            border.color: Util.alpha(Color.notifications.text, menuMouse.containsMouse ? 0.35 : 0.18)

            Text {
              id: menuLabel
              anchors.centerIn: parent
              text: modelData.label
              textFormat: Text.PlainText
              color: root.bodyColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: menuMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.menuOpen = false
                if (modelData.action === "dismiss") root.dismissRequested()
                else if (modelData.action === "mute") root.muteRequested()
                else root.settingsRequested()
              }
            }
          }
        }
      }
    }
  }
}
