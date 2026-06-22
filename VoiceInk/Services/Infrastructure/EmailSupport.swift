import Foundation
import AppKit

/// Support for this fork is handled through GitHub issues.
struct EmailSupport {
    private static let issuesURL = "https://github.com/morqan/VoiceInk/issues"

    static func openSupportEmail() {
        if let url = URL(string: issuesURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
