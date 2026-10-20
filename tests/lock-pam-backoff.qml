import QtQuick
import Quickshell
import "shim"
ShellRoot {
    id: root
    readonly property bool typedRun: Quickshell.env("LOCK_PAM_RUN") !== "untyped"
    property var pw: null
    property int ends: 0
    property int shakes: 0
    property int typed: 0
    property int endsAtLogin: 0
    property int phase: 0
    SddmShim { id: shim }
    Connections {
        target: shim.sddm
        function onLoginFailed() { root.shakes++; }
    }
    function type() {
        root.typed++;
        shim.sddm.login(Quickshell.env("USER") || "traveler", "wrong" + root.typed, 0);
    }
    Component.onCompleted: {
        for (var i = 0; i < shim.data.length; i++) {
            if (shim.data[i] && shim.data[i].config === "ryoku-lock-pw")
                root.pw = shim.data[i];
        }
        if (!root.pw) { console.error("FAIL: no ryoku-lock-pw conversation in the shim"); Qt.quit(); return; }
        root.pw.completed.connect(() => root.ends++);
        if (root.typedRun) {
            root.pw.responseRequiredChanged.connect(() => {
                if (root.pw.responseRequired && root.typed < 3)
                    Qt.callLater(root.type);
            });
        }
        shim.armWhenReady = true;
    }
    Timer {
        interval: root.typedRun ? 2000 : 3500; running: true; repeat: true
        onTriggered: {
            if (root.typedRun) {
                // three wrong keys: three shakes, and the prompt is back at once each time
                if (root.typed !== 3) { console.error("FAIL: only " + root.typed + " of 3 wrong keys got a prompt in 2s"); Qt.quit(); return; }
                if (root.shakes !== 3) { console.error("FAIL: 3 wrong keys shook " + root.shakes + " times"); Qt.quit(); return; }
                if (!root.pw.active) { console.error("FAIL: no fresh prompt after the third wrong key"); Qt.quit(); return; }
                console.log("PASS: 3 wrong keys, 3 shakes, prompt back at once");
                Qt.quit();
            } else if (root.phase === 0) {
                // A stack that denies before prompting ends at 0s, 1s and 3s.
                if (root.ends === 0) { console.error("FAIL: the password conversation never ran"); Qt.quit(); return; }
                if (root.ends > 4) { console.error("FAIL: " + root.ends + " password conversations in 3.5s, no backoff"); Qt.quit(); return; }
                if (root.shakes !== 0) { console.error("FAIL: field shook " + root.shakes + " times with no key typed"); Qt.quit(); return; }
                root.endsAtLogin = root.ends;
                root.type();
                interval = 500;
                root.phase++;
            } else {
                if (root.ends === root.endsAtLogin) { console.error("FAIL: a typed key waited out the backoff"); Qt.quit(); return; }
                if (root.shakes !== 1) { console.error("FAIL: a typed key that failed shook " + root.shakes + " times, want 1"); Qt.quit(); return; }
                console.log("PASS: " + root.endsAtLogin + " untyped failures in 3.5s without a shake, a typed key retried at once");
                Qt.quit();
            }
        }
    }
}
