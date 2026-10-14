// SPDX-License-Identifier: MIT
// Copyright (c) David Heinemeier Hansson
// Theme styling adapted from Omarchy shell/Ui/TextField.qml (Omarchy 4.0.4).
// See OMARCHY-LICENSE for the upstream permission notice.
import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as ShellUi

// TextArea checks offered MIME types, whereas Qt 6.12 TextInput eagerly reads
// clipboard text on every change. Keep editing/IME support and handle all
// paste entry points through a bounded, asynchronous reader instead.
FocusScope {
  id: root

  property alias text: editor.text
  property alias placeholderText: editor.placeholderText
  property alias cursorPosition: editor.cursorPosition
  property alias selectionStart: editor.selectionStart
  property alias selectionEnd: editor.selectionEnd
  readonly property alias preeditText: editor.preeditText
  readonly property bool pastePending: _pastePending
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color selectionTint: Commons.Style.selectionFillFor(foreground, accent)
  property real horizontalPadding: Commons.Style.spacing.controlPaddingX
  property real verticalPadding: Commons.Style.spacing.inputPaddingY
  readonly property bool _focused: editor.activeFocus
  readonly property bool _hot: editor.hovered
  readonly property var _borderSpec: Commons.Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), foreground, accent)
  property int _revision: 0
  property int _pasteRevision: -1
  property bool _pastePending: false
  readonly property string _helperPath: decodeURIComponent(Qt.resolvedUrl("../clipboard_helper.py").toString().replace(/^file:\/\//, ""))

  signal navigationRequested(var event)
  signal pasteFailed(string reason)

  implicitWidth: Commons.Style.space(280)
  implicitHeight: metrics.height + verticalPadding * 2 + Commons.Border.top(_borderSpec) + Commons.Border.bottom(_borderSpec)

  function selectAll() { editor.selectAll() }
  function undo() { editor.undo() }
  function redo() { editor.redo() }
  function copy() { editor.copy() }
  function cut() { editor.cut() }
  function select(start, end) { editor.select(start, end) }

  function cancelPaste() {
    _pastePending = false
    if (clipboardProcess.running) clipboardProcess.signal(15)
  }

  function edited() {
    _revision++
    if (_pastePending) cancelPaste()
  }

  function paste(primary) {
    if (clipboardProcess.running) return
    editor.forceActiveFocus()
    Qt.inputMethod.commit()
    _pasteRevision = _revision
    _pastePending = true
    clipboardProcess.command = ["/usr/bin/python3", "-I", _helperPath, primary ? "primary" : "clipboard"]
    clipboardProcess.running = true
  }

  Component.onDestruction: cancelPaste()

  FontMetrics { id: metrics; font: editor.font }

  ShellUi.BorderSurface {
    anchors.fill: parent
    color: Commons.Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Commons.Style.cornerRadius
  }

  Flickable {
    id: viewport
    anchors.fill: parent
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds

    Controls.TextArea.flickable: Controls.TextArea {
      id: editor
      objectName: "languageSwitcherSearchEditor"
      focus: true
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.NoWrap
      selectByMouse: true
      selectByKeyboard: true
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
      color: root.foreground
      selectionColor: root.selectionTint
      selectedTextColor: root.foreground
      placeholderTextColor: Qt.darker(root.foreground, 1.6)
      leftPadding: root.horizontalPadding + Commons.Border.left(root._borderSpec)
      rightPadding: root.horizontalPadding + Commons.Border.right(root._borderSpec)
      topPadding: root.verticalPadding + Commons.Border.top(root._borderSpec)
      bottomPadding: root.verticalPadding + Commons.Border.bottom(root._borderSpec)
      background: null

      onTextChanged: root.edited()
      onCursorPositionChanged: root.edited()
      onSelectionStartChanged: root.edited()
      onSelectionEndChanged: root.edited()
      onPreeditTextChanged: root.edited()

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.matches(StandardKey.Paste)) {
          root.paste(false)
          event.accepted = true
          return
        }
        // The input method normally consumes candidate-navigation keys first.
        // Never change locale, close, or insert a newline during preedit.
        if (preeditText.length && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape,
                                  Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown].indexOf(event.key) >= 0) {
          event.accepted = true
          return
        }
        root.navigationRequested(event)
        // This is a single-line search, including when used without Service.
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) event.accepted = true
      }

      Controls.ContextMenu.menu: Controls.Menu {
        objectName: "languageSwitcherEditMenu"
        popupType: Controls.Popup.Item
        Controls.MenuItem { text: "撤销"; enabled: editor.canUndo; onTriggered: root.undo() }
        Controls.MenuItem { text: "重做"; enabled: editor.canRedo; onTriggered: root.redo() }
        Controls.MenuSeparator {}
        Controls.MenuItem { text: "剪切"; enabled: editor.selectedText.length > 0; onTriggered: root.cut() }
        Controls.MenuItem { text: "复制"; enabled: editor.selectedText.length > 0; onTriggered: root.copy() }
        Controls.MenuItem { objectName: "languageSwitcherPasteAction"; text: "粘贴"; enabled: !clipboardProcess.running; onTriggered: root.paste(false) }
        Controls.MenuItem { text: "删除"; enabled: editor.selectedText.length > 0; onTriggered: editor.remove(editor.selectionStart, editor.selectionEnd) }
        Controls.MenuSeparator {}
        Controls.MenuItem { text: "全选"; enabled: editor.length > 0; onTriggered: root.selectAll() }
      }
    }
  }

  // Keep this above the TextArea even when its Flickable reparents the editor.
  // Left-button selection and the context menu still go to the native editor.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    onPressed: function(mouse) {
      var position = mapToItem(editor, mouse.x, mouse.y)
      editor.cursorPosition = editor.positionAt(position.x, position.y)
      root.paste(true)
    }
  }

  Timer {
    interval: 1000
    running: root._pastePending
    onTriggered: {
      root.cancelPaste()
      root.pasteFailed("timeout")
    }
  }

  Process {
    id: clipboardProcess
    stdout: StdioCollector { id: clipboardOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root._pastePending || root._pasteRevision !== root._revision) return
      root._pastePending = false
      try {
        var result = JSON.parse(clipboardOutput.text)
        if (exitCode !== 0 || typeof result.text !== "string") {
          root.pasteFailed(String(result.error || "unavailable"))
          return
        }
        var start = editor.selectionStart
        // Replace through QTextCursor as one undoable edit, without reading
        // Qt's clipboard or clearing the document's native undo history.
        editor.cursorSelection.text = result.text
        editor.cursorPosition = start + result.text.length
      } catch (error) { root.pasteFailed("unavailable") }
    }
  }
}
