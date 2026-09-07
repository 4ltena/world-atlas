import AppKit

/// ⌘Q とメニューの「終了」を受ける。**判断は `OpenVaults` にあり、ここは尋ねて返すだけ。**
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { OpenVaults.mayQuit() } ? .terminateNow : .terminateCancel
    }
}
