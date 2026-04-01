import Foundation
import AppKit

enum AppLauncher {
    /// Open the Maperick CLI in Terminal.app
    static func openMaperickInTerminal() {
        guard let binaryPath = AppConstants.findMaperickBinary() else {
            // Show alert if binary not found
            let alert = NSAlert()
            alert.messageText = "Maperick CLI not found"
            alert.informativeText = "Could not find the maperick binary. Install it with:\n\ncargo install --path /path/to/Maperick"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Open Terminal.app with the maperick command
        let script = """
        tell application "Terminal"
            activate
            do script "\(binaryPath)"
        end tell
        """

        if let scriptData = script.data(using: .utf8) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            try? task.run()
        }
    }
}
