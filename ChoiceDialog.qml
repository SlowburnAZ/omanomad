import QtQuick
import qs.Commons
import qs.Ui

// Three-choice modal styled after the shell's ConfirmDialog: scrim, card,
// and a row of selectable buttons. Used where two ConfirmDialog buttons
// cannot express the choice (e.g. "just uninstall" vs "delete data too").
// Esc or clicking the scrim emits canceled(); Tab/Left/Right move the
// selection; Enter activates it. The destructive choice renders
// urgent-tinted.
Item {
  id: root

  property bool opened: false
  property string message: ""
  property string cancelText: "Cancel"
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
      height: card.contentTopInset + card.contentBottomInset + messageText.implicitHeight + Style.space(20) + Style.space(34)
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

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(10)

          Repeater {
            model: [root.cancelText, root.choiceText, root.destructiveText]

            BorderSurface {
              id: choice
              required property int index
              required property string modelData

              readonly property bool selected: root.selectedIndex === index
              readonly property bool destructive: index === 2

              width: Style.space(88)
              height: Style.space(34)
              visible: modelData !== ""
              color: selected
                ? (destructive ? Util.alpha(Color.urgent, 0.22) : root.selectedBackground)
                : "transparent"
              borderSpec: Border.flat(destructive
                ? (selected ? Color.urgent : Util.alpha(Color.urgent, 0.56))
                : (selected ? root.selectedText : Util.alpha(root.foreground, 0.38)), Style.normalBorderWidth)
              radius: 0

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: choice.modelData
                color: choice.destructive
                  ? (choice.selected ? Color.urgent : root.foreground)
                  : (choice.selected ? root.selectedText : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = choice.index
                onClicked: root._activate(choice.index)
              }
            }
          }
        }
      }
    }
  }
}
