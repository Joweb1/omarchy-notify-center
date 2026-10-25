import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string label: ""
  property string glyph: ""
  property bool active: false
  property bool urgent: false
  property bool compact: false
  property color foreground: Color.foreground
  property string fontFamily: Style.fontFamily
  property string tooltipText: ""

  signal clicked()

  implicitWidth: Math.max(
    compact ? Style.space(26) : Style.space(30),
    (glyph.length > 0 ? glyphText.implicitWidth : labelText.implicitWidth) + Style.space(16)
  )
  implicitHeight: compact ? Style.space(26) : Style.space(30)
  width: implicitWidth
  height: implicitHeight
  radius: height / 2

  readonly property color tone: urgent ? Color.urgent : Color.accent
  color: active
    ? Util.alpha(tone, 0.24)
    : (mouse.containsMouse ? Util.alpha(tone, 0.18) : Util.alpha(foreground, 0.06))
  border.width: 1
  border.color: active || mouse.containsMouse
    ? Util.alpha(tone, 0.65)
    : Util.alpha(foreground, 0.18)

  Behavior on color {
    ColorAnimation { duration: 120 }
  }

  Text {
    id: glyphText
    anchors.centerIn: parent
    visible: root.glyph.length > 0
    text: root.glyph
    textFormat: Text.PlainText
    color: root.urgent ? Color.urgent : (root.active ? Color.accent : root.foreground)
    font.family: root.fontFamily
    font.pixelSize: root.compact ? Style.font.title : Style.font.heading
    font.bold: true
  }

  Text {
    id: labelText
    anchors.centerIn: parent
    visible: root.glyph.length === 0 && root.label.length > 0
    text: root.label
    textFormat: Text.PlainText
    color: root.urgent ? Color.urgent : (root.active ? Color.accent : root.foreground)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: root.active
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}
