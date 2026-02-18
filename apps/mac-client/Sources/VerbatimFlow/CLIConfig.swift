import AppKit
import Foundation

enum OutputMode: String {
    case raw
    case formatOnly = "format-only"
}

struct Hotkey {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let display: String

    static let `default` = Hotkey(
        keyCode: 49, // space
        modifiers: [.control, .shift],
        display: "ctrl+shift+space"
    )
}

struct CLIConfig {
    let mode: OutputMode
    let localeIdentifier: String
    let hotkey: Hotkey
    let requireOnDeviceRecognition: Bool
    let dryRun: Bool

    static let `default` = CLIConfig(
        mode: .raw,
        localeIdentifier: Locale.current.identifier,
        hotkey: .default,
        requireOnDeviceRecognition: false,
        dryRun: false
    )

    static func parse() throws -> CLIConfig {
        var config = CLIConfig.default
        var index = 1
        let args = CommandLine.arguments

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--mode":
                index += 1
                guard index < args.count, let mode = OutputMode(rawValue: args[index]) else {
                    throw ConfigError.invalidValue("--mode", "raw | format-only")
                }
                config = CLIConfig(
                    mode: mode,
                    localeIdentifier: config.localeIdentifier,
                    hotkey: config.hotkey,
                    requireOnDeviceRecognition: config.requireOnDeviceRecognition,
                    dryRun: config.dryRun
                )
            case "--locale":
                index += 1
                guard index < args.count else {
                    throw ConfigError.missingValue("--locale")
                }
                config = CLIConfig(
                    mode: config.mode,
                    localeIdentifier: args[index],
                    hotkey: config.hotkey,
                    requireOnDeviceRecognition: config.requireOnDeviceRecognition,
                    dryRun: config.dryRun
                )
            case "--hotkey":
                index += 1
                guard index < args.count else {
                    throw ConfigError.missingValue("--hotkey")
                }
                let parsed = try HotkeyParser.parse(combo: args[index])
                config = CLIConfig(
                    mode: config.mode,
                    localeIdentifier: config.localeIdentifier,
                    hotkey: parsed,
                    requireOnDeviceRecognition: config.requireOnDeviceRecognition,
                    dryRun: config.dryRun
                )
            case "--require-on-device":
                config = CLIConfig(
                    mode: config.mode,
                    localeIdentifier: config.localeIdentifier,
                    hotkey: config.hotkey,
                    requireOnDeviceRecognition: true,
                    dryRun: config.dryRun
                )
            case "--dry-run":
                config = CLIConfig(
                    mode: config.mode,
                    localeIdentifier: config.localeIdentifier,
                    hotkey: config.hotkey,
                    requireOnDeviceRecognition: config.requireOnDeviceRecognition,
                    dryRun: true
                )
            case "--help", "-h":
                HelpPrinter.printAndExit()
            default:
                throw ConfigError.unknownArgument(arg)
            }
            index += 1
        }

        return config
    }
}

enum ConfigError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidValue(let flag, let expected):
            return "Invalid value for \(flag). Expected: \(expected)"
        case .unknownArgument(let arg):
            return "Unknown argument: \(arg)"
        }
    }
}

enum HelpPrinter {
    static func printAndExit() -> Never {
        let lines = [
            "verbatim-flow",
            "",
            "Usage:",
            "  verbatim-flow [--mode raw|format-only] [--locale <id>] [--hotkey ctrl+shift+space] [--require-on-device] [--dry-run]",
            "",
            "Defaults:",
            "  --mode raw",
            "  --locale system locale",
            "  --hotkey ctrl+shift+space",
            ""
        ]
        FileHandle.standardOutput.write(lines.joined(separator: "\n").data(using: .utf8)!)
        Foundation.exit(0)
    }
}

enum HotkeyParser {
    static func parse(combo: String) throws -> Hotkey {
        let components = combo
            .lowercased()
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let keyToken = components.last, !keyToken.isEmpty else {
            throw ConfigError.invalidValue("--hotkey", "like ctrl+shift+space")
        }

        var modifiers: NSEvent.ModifierFlags = []
        for token in components.dropLast() {
            switch token {
            case "cmd", "command":
                modifiers.insert(.command)
            case "opt", "option", "alt":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            default:
                throw ConfigError.invalidValue("--hotkey", "unsupported modifier \(token)")
            }
        }

        guard let keyCode = keyCode(for: keyToken) else {
            throw ConfigError.invalidValue("--hotkey", "unsupported key \(keyToken)")
        }

        return Hotkey(keyCode: keyCode, modifiers: modifiers, display: combo)
    }

    private static func keyCode(for key: String) -> UInt16? {
        let letters: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50
        ]

        if key == "space" || key == "spacebar" {
            return 49
        }

        return letters[key]
    }
}
