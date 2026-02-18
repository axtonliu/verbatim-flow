import AppKit
import Foundation

do {
    let config = try CLIConfig.parse()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    Task { @MainActor in
        let controller = AppController(config: config)
        controller.run()
    }

    RunLoop.main.run()
} catch {
    fputs("\(error)\n", stderr)
    HelpPrinter.printAndExit()
}
