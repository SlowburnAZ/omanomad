import QtQuick
import qs.Commons
import qs.Ui

// Three-choice modal styled after the shell's ConfirmDialog: scrim, card,
// message, and buttons — the two scope choices side by side (centered) with
// Cancel centered on its own row beneath. Esc or clicking the scrim emits
// canceled(); Tab or Left/Right move the selection (0 cancel, 1 keep,
// 2 purge); Enter activates it. The destructive choice renders
// urgent-tinted. Buttons size to their labels so no copy is clipped.
Item {
  id: root

  property bool opened: false
  property string message: ""
  property string choiceText: "Continue"
  property string destructiveText: ""
  property int selectedIndex: 1
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  signal canceled()
  signal chosen(string scope)

  function _activate(index) {
    if (index === 0) root.canceled()
    else if (index === 1) root.chosen("keep")
    else root.chosen("purge")
  }

  function handleKey(event) {
    if (!root.opened) return false

    if (event.key === Qt.Key_Escape) {
      root.canceled()
      return true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = (root.selectedIndex + 1) % 3
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root._activate(root.selectedIndex)
      return true
    }

    return false
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(370))
      height: card.contentTopInset + card.contentBottomInset
        + messageText.implicitHeight + Style.space(20)
        + choiceRow.height + Style.space(10) + cancelBtn.height
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(18)
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: messageText
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.message
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
        }

        BorderSurface {
          id: cancelBtn
          readonly property bool selected: root.selectedIndex === 0

          width: Math.max(Style.space(72), cancelLabel.implicitWidth + Style.space(18))
          height: Style.space(34)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          color: selected ? root.selectedBackground : "transparent"
          borderSpec: Border.flat(selected ? root.selectedText : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
          radius: 0

          Text {
            id: cancelLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "Cancel"
            color: cancelBtn.selected ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = 0
            onClicked: root._activate(0)
          }
        }

        Row {
          id: choiceRow
          spacing: Style.space(10)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: cancelBtn.top
          anchors.bottomMargin: Style.space(10)

          BorderSurface {
            id: keepBtn
            readonly property bool selected: root.selectedIndex === 1

            width: Math.max(Style.space(72), keepLabel.implicitWidth + Style.space(18))
            height: Style.space(34)
            color: selected ? root.selectedBackground : "transparent"
            borderSpec: Border.flat(selected ? root.selectedText : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
            radius: 0

            Text {
              id: keepLabel
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.choiceText
              color: keepBtn.selected ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = 1
              onClicked: root._activate(1)
            }
          }

          BorderSurface {
            id: purgeBtn
            readonly property bool selected: root.selectedIndex === 2

            width: Math.max(Style.space(72), purgeLabel.implicitWidth + Style.space(18))
            height: Style.space(34)
            color: selected ? Util.alpha(Color.urgent, 0.22) : "transparent"
            borderSpec: Border.flat(selected ? Color.urgent : Util.alpha(Color.urgent, 0.56), Style.normalBorderWidth)
            radius: 0

            Text {
              id: purgeLabel
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.destructiveText
              color: purgeBtn.selected ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = 2
              onClicked: root._activate(2)
            }
          }
        }
      }
    }
  }
}
