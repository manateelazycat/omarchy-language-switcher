import QtQuick
import QtTest
import Quickshell
import SearchTestProbe 1.0
import "Plugin/CompatUi" as LanguageUi

ShellRoot {
    id: root
    SearchProbe { id: probe }
    TestCase { id: checks; when: false }
    property int navigationCount: 0
    property string pasteError: ""
    property int heartbeat: 0

    Timer { interval: 20; running: true; repeat: true; onTriggered: root.heartbeat++ }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 640
        implicitHeight: 600
        Loader {
            id: loader
            anchors.centerIn: parent
            width: 350
            height: item ? item.implicitHeight : 0
            sourceComponent: LanguageUi.SearchField {
                onNavigationRequested: function(event) {
                    if ([Qt.Key_Down, Qt.Key_Up, Qt.Key_Return, Qt.Key_Escape].indexOf(event.key) >= 0) {
                        root.navigationCount++
                        event.accepted = true
                    }
                }
                onPasteFailed: function(reason) { root.pasteError = reason }
            }
        }
    }

    function check(value, message) { if (!value) throw new Error(message) }
    function editor() { return checks.findChild(loader.item, "languageSwitcherSearchEditor") }
    function fixture(value) {
        root.pasteError = ""
        check(probe.writeFile(Qt.resolvedUrl("Plugin/fixture.json"), JSON.stringify(value)), "Write paste fixture")
        probe.writeFile(Qt.resolvedUrl("Plugin/paste.pid"), "")
    }
    function waitPaste() {
        for (var i = 0; i < 100 && loader.item.pastePending; i++) checks.wait(10)
        check(!loader.item.pastePending, "Paste did not finish")
    }
    function readerPid() {
        for (var i = 0; i < 100; i++) {
            var pid = Number(probe.readFile(Qt.resolvedUrl("Plugin/paste.pid")))
            if (pid > 0) return pid
            checks.wait(10)
        }
        throw new Error("Paste reader did not start")
    }
    function verifyEditing() {
        var field = loader.item
        field.forceActiveFocus()
        check(editor().activeFocus, "Search must receive focus")
        check(field.height > 0 && editor().height > 0 && editor().width > 0, "Search dimensions")
        probe.key(editor(), Qt.Key_E, 0, "e")
        probe.commit(editor(), "中文")
        check(field.text === "e中文", "Typing and Chinese IME commit")
        field.selectAll()
        probe.key(editor(), Qt.Key_N, 0, "n")
        check(field.text === "n", "Replace selection by typing")
        field.undo()
        check(field.text === "e中文", "Undo typing")
        field.redo()
        check(field.text === "n", "Redo typing")
        probe.preedit(editor(), "ni")
        check(field.preeditText === "ni", "Input method preedit")
        var previous = navigationCount
        probe.key(editor(), Qt.Key_Return)
        probe.key(editor(), Qt.Key_Down)
        probe.key(editor(), Qt.Key_Escape)
        check(navigationCount === previous && field.text === "n", "Preedit must not select, dismiss or insert newline")
        probe.commit(editor(), "你好")
        check(field.text === "n你好" && !field.preeditText, "Commit preedit")
        probe.key(editor(), Qt.Key_Down)
        probe.key(editor(), Qt.Key_Up)
        probe.key(editor(), Qt.Key_Return)
        probe.key(editor(), Qt.Key_Escape)
        check(navigationCount === previous + 4, "Dialog navigation keys")
        field.text = new Array(150).join("W")
        field.cursorPosition = field.text.length
        checks.wait(30)
        var viewport = editor().parent.parent
        check(viewport.contentX > 0, "Long query must scroll horizontally")
        field.cursorPosition = 0
        checks.wait(30)
        check(viewport.contentX <= 1, "Moving to beginning must scroll back")
        field.text = ""
    }
    function verifyClipboardIsolation() {
        probe.offerText()
        checks.wait(30)
        check(probe.payloadReads() === 0, "Clipboard changes must not retrieve text")
        check(editor().canPaste, "Clipboard MIME offer is recognized")
        check(probe.payloadReads() === 0, "canPaste must only inspect MIME types")
        loader.active = false
        checks.wait(30)
        probe.offerText()
        loader.active = true
        checks.wait(30)
        check(probe.payloadReads() === 0, "Construction with existing clipboard must not retrieve text")
    }
    function verifyPaste() {
        var field = loader.item
        fixture({text: "中文"})
        field.text = "English"
        field.selectAll()
        probe.key(editor(), Qt.Key_V, Qt.ControlModifier)
        waitPaste()
        check(field.text === "中文", "Ctrl+V must replace selection")
        field.undo()
        check(field.text === "English", "Undo paste must restore the selected text in one step")
        field.redo()
        check(field.text === "中文", "Redo paste in one step")
        fixture({text: "<b>English</b>"})
        field.text = ""
        probe.key(editor(), Qt.Key_Insert, Qt.ShiftModifier)
        waitPaste()
        check(field.text === "<b>English</b>", "Shift+Insert must paste plain text")
        fixture({clipboard: "English", primary: "日本語"})
        field.text = ""
        checks.mouseClick(field, field.width / 2, field.height / 2, Qt.MiddleButton)
        waitPaste()
        check(field.text === "日本語", "Middle click must use primary selection")
        field.text = ""
        checks.mouseClick(field, field.width / 2, field.height / 2, Qt.RightButton)
        checks.wait(30)
        var action = checks.findChild(field, "languageSwitcherPasteAction")
        check(action, "Custom paste menu action")
        check(action.visible && action.enabled, "Paste menu item must be visible and enabled")
        checks.mouseClick(action, action.width / 2, action.height / 2)
        waitPaste()
        check(field.text === "English", "Menu must use bounded clipboard reader; text=" + JSON.stringify(field.text) + " error=" + pasteError)
        check(probe.payloadReads() === 0, "All paste routes must bypass Qt's native clipboard reads")
        fixture({error: "too-large"})
        field.text = "unchanged"
        field.selectAll()
        field.paste(false)
        waitPaste()
        check(field.text === "unchanged" && pasteError === "too-large", "Rejected paste must preserve query and report error")
        fixture({text: "", delay: 0.1})
        field.paste(false)
        waitPaste()
        check(field.text === "", "Empty paste replaces selection")
    }
    function verifyCancellation() {
        fixture({text: "stale", delay: 5})
        var field = loader.item
        field.text = "English"
        field.paste(false)
        var pid = readerPid()
        probe.key(editor(), Qt.Key_X, 0, "x")
        checks.wait(100)
        check(!field.pastePending && !probe.alive(pid), "Continuing to edit must cancel and kill reader")
        check(field.text !== "stale", "Cancelled reader must not replace query")
        fixture({text: "stale", delay: 5})
        field.paste(false)
        pid = readerPid()
        field.paste(false)
        checks.wait(30)
        check(Number(probe.readFile(Qt.resolvedUrl("Plugin/paste.pid"))) === pid,
              "Repeated paste must not create another reader")
        field.select(0, 1)
        checks.wait(100)
        check(!field.pastePending && !probe.alive(pid), "Changing selection must cancel reader")
        fixture({text: "stale", delay: 5})
        field.paste(false)
        pid = readerPid()
        probe.preedit(editor(), "ni")
        checks.wait(100)
        check(!field.pastePending && !probe.alive(pid), "Starting IME preedit must cancel reader")
        probe.commit(editor(), "")
        fixture({text: "stale", delay: 5})
        field.paste(false)
        pid = readerPid()
        loader.active = false
        checks.wait(100)
        check(!probe.alive(pid), "Destroying field must kill reader")
        loader.active = true
        checks.wait(30)
        check(loader.item.text === "", "Reopening must not receive stale paste")
    }
    function verifyDeadline() {
        fixture({text: "late", delay: 5})
        loader.item.text = "unchanged"
        loader.item.paste(false)
        var pid = readerPid()
        var previousHeartbeat = heartbeat
        checks.wait(1100)
        check(!loader.item.pastePending && !probe.alive(pid), "Watchdog must kill a stalled helper")
        check(pasteError === "timeout" && loader.item.text === "unchanged", "Timeout must preserve the query")
        check(heartbeat - previousHeartbeat >= 20, "Shared GUI event loop must keep responding during a stalled paste")
    }
    Timer {
        interval: 250
        running: true
        onTriggered: {
            try {
                verifyEditing()
                verifyClipboardIsolation()
                verifyPaste()
                verifyCancellation()
                verifyDeadline()
                console.log("PLUGIN_SEARCH_PASS")
            } catch (error) { console.log("PLUGIN_SEARCH_FAIL", String(error)) }
            Qt.quit()
        }
    }
}
