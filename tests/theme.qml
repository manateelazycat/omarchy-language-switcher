import QtQuick
import QtTest
import Quickshell
import qs.Commons as Commons
import "Plugin" as Plugin

ShellRoot {
    id: root
    Plugin.Service { id: service }
    TestCase { id: checks; when: false }
    function check(value, message) { if (!value) throw new Error(message); }
    function verifyTheme() {
        var card = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherCard");
        var search = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherSearch");
        var notice = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherNotice");
        var row = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherRow0");
        check(card && search && notice && row, "Dialog objects are missing");
        check(card.color === Commons.Color.menu.background, "Card background");
        check(card.border.color === Commons.Color.menu.border, "Card border");
        check(search.foreground === Commons.Color.foreground, "Search foreground");
        check(search.accent === Commons.Color.accent, "Search accent");
        check(row.color === Commons.Color.menu.selectedBackground, "Selected row background");
        check(row.border.color === Commons.Color.menu.selectedBorder, "Selected row border");
        check(notice.color === Commons.Color.menu.background, "Notice background");
        service.noticeError = true;
        checks.wait(30);
        check(notice.border.color === Commons.Color.urgent, "Error notice border");
        service.noticeError = false;
    }
    Timer {
        interval: 250; running: true
        onTriggered: {
            try {
                service.filtered = [{code: "en_US.UTF-8", title: "English", subtitle: "English", active: true, installed: true}];
                checks.wait(30);
                verifyTheme();
                Commons.Color.shellValues = ({});
                Commons.Color.loadColors('background = "#060b1e"\nforeground = "#ffcead"\naccent = "#7d82d9"');
                checks.wait(30);
                verifyTheme();
                Commons.Color.loadColors('background = "#fafafa"\nforeground = "#202020"\naccent = "#0055aa"');
                checks.wait(30);
                verifyTheme();
                check(!service.busy, "A locale change was unexpectedly started");
                console.log("PLUGIN_THEME_PASS");
            } catch (error) { console.log("PLUGIN_THEME_FAIL", String(error)); }
            Qt.quit();
        }
    }
}
