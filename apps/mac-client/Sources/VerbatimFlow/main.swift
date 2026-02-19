import AppKit
import Foundation

do {
    let config = try CLIConfig.parse()
    let app = NSApplication.shared

    let delegate = MainActor.assumeIsolated {
        MenuBarApp(config: config)
    }
    MainActor.assumeIsolated {
        app.delegate = delegate
    }
    withExtendedLifetime(delegate) {
        app.run()
    }
} catch {
    fputs("\(error)\n", stderr)
    HelpPrinter.printAndExit()
}
