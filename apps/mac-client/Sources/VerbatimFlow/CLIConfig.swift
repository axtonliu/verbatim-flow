import AppKit
import Foundation

enum OutputMode: String {
    case raw
    case formatOnly = "format-only"
    case clarify
}

enum RecognitionEngine: String {
    case apple
    case whisper
    case openai
    case qwen

    var displayName: String {
        switch self {
        case .apple:
            return "Apple Speech"
        case .whisper:
            return "Whisper"
        case .openai:
            return "OpenAI Cloud"
        case .qwen:
            return "Qwen3 ASR"
        }
    }
}

enum OpenAITranscriptionModel: String, CaseIterable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case whisper1 = "whisper-1"

    var displayName: String {
        rawValue
    }
}

enum QwenModel: String, CaseIterable {
    case small = "mlx-community/Qwen3-ASR-0.6B-8bit"
    case large = "mlx-community/Qwen3-ASR-1.7B-8bit"

    var displayName: String {
        switch self {
        case .small:
            return "Qwen3-ASR-0.6B"
        case .large:
            return "Qwen3-ASR-1.7B"
        }
    }
}

enum WhisperModel: String, CaseIterable {
    case tiny
    case base
    case small
    case medium
    case largeV3 = "large-v3"

    var displayName: String {
        switch self {
        case .tiny:
            return "tiny"
        case .base:
            return "base"
        case .small:
            return "small"
        case .medium:
            return "medium"
        case .largeV3:
            return "large-v3"
        }
    }
}

struct Hotkey {
    let keyCode: UInt16?
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
    let recognitionEngine: RecognitionEngine
    let whisperModel: WhisperModel
    let whisperComputeType: String
    let openAIModel: OpenAITranscriptionModel
    let qwenModel: QwenModel
    let localeIdentifier: String
    let hotkey: Hotkey
    let requireOnDeviceRecognition: Bool
    let dryRun: Bool

    static let `default` = CLIConfig(
        mode: .raw,
        recognitionEngine: .apple,
        whisperModel: .tiny,
        whisperComputeType: "int8",
        openAIModel: .gpt4oMiniTranscribe,
        qwenModel: .small,
        localeIdentifier: Locale.current.identifier,
        hotkey: .default,
        requireOnDeviceRecognition: false,
        dryRun: false
    )

    private func replacing(
        mode: OutputMode? = nil,
        recognitionEngine: RecognitionEngine? = nil,
        whisperModel: WhisperModel? = nil,
        whisperComputeType: String? = nil,
        openAIModel: OpenAITranscriptionModel? = nil,
        qwenModel: QwenModel? = nil,
        localeIdentifier: String? = nil,
        hotkey: Hotkey? = nil,
        requireOnDeviceRecognition: Bool? = nil,
        dryRun: Bool? = nil
    ) -> CLIConfig {
        CLIConfig(
            mode: mode ?? self.mode,
            recognitionEngine: recognitionEngine ?? self.recognitionEngine,
            whisperModel: whisperModel ?? self.whisperModel,
            whisperComputeType: whisperComputeType ?? self.whisperComputeType,
            openAIModel: openAIModel ?? self.openAIModel,
            qwenModel: qwenModel ?? self.qwenModel,
            localeIdentifier: localeIdentifier ?? self.localeIdentifier,
            hotkey: hotkey ?? self.hotkey,
            requireOnDeviceRecognition: requireOnDeviceRecognition ?? self.requireOnDeviceRecognition,
            dryRun: dryRun ?? self.dryRun
        )
    }

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
                    throw ConfigError.invalidValue("--mode", "raw | format-only | clarify")
                }
                config = config.replacing(mode: mode)
            case "--engine":
                index += 1
                guard index < args.count, let engine = RecognitionEngine(rawValue: args[index]) else {
                    throw ConfigError.invalidValue("--engine", "apple | whisper | openai | qwen")
                }
                config = config.replacing(recognitionEngine: engine)
            case "--whisper-model":
                index += 1
                guard index < args.count, let model = WhisperModel(rawValue: args[index]) else {
                    throw ConfigError.invalidValue("--whisper-model", "tiny | base | small | medium | large-v3")
                }
                config = config.replacing(whisperModel: model)
            case "--whisper-compute-type":
                index += 1
                guard index < args.count else {
                    throw ConfigError.missingValue("--whisper-compute-type")
                }
                config = config.replacing(whisperComputeType: args[index])
            case "--openai-model":
                index += 1
                guard index < args.count, let model = OpenAITranscriptionModel(rawValue: args[index]) else {
                    throw ConfigError.invalidValue("--openai-model", "gpt-4o-mini-transcribe | whisper-1")
                }
                config = config.replacing(openAIModel: model)
            case "--qwen-model":
                index += 1
                guard index < args.count, let model = QwenModel(rawValue: args[index]) else {
                    throw ConfigError.invalidValue("--qwen-model", QwenModel.allCases.map(\.rawValue).joined(separator: " | "))
                }
                config = config.replacing(qwenModel: model)
            case "--locale":
                index += 1
                guard index < args.count else {
                    throw ConfigError.missingValue("--locale")
                }
                config = config.replacing(localeIdentifier: args[index])
            case "--hotkey":
                index += 1
                guard index < args.count else {
                    throw ConfigError.missingValue("--hotkey")
                }
                let parsed = try HotkeyParser.parse(combo: args[index])
                config = config.replacing(hotkey: parsed)
            case "--require-on-device":
                config = config.replacing(requireOnDeviceRecognition: true)
            case "--dry-run":
                config = config.replacing(dryRun: true)
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
            "  verbatim-flow [--mode raw|format-only|clarify] [--engine apple|whisper|openai|qwen] [--whisper-model tiny|base|small|medium|large-v3] [--whisper-compute-type int8|int8_float16|float16|float32] [--openai-model gpt-4o-mini-transcribe|whisper-1] [--qwen-model <hf-id>] [--locale <id>] [--hotkey ctrl+shift+space|shift+option] [--require-on-device] [--dry-run]",
            "",
            "Defaults:",
            "  --mode raw",
            "  --engine apple",
            "  --whisper-model tiny",
            "  --whisper-compute-type int8",
            "  --openai-model gpt-4o-mini-transcribe",
            "  --qwen-model \(QwenModel.small.rawValue)",
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
            .filter { !$0.isEmpty }

        guard !components.isEmpty else {
            throw ConfigError.invalidValue("--hotkey", "like ctrl+shift+space or shift+option")
        }

        var modifiers: NSEvent.ModifierFlags = []
        var primaryKeyCode: UInt16?

        for token in components {
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
                guard primaryKeyCode == nil else {
                    throw ConfigError.invalidValue("--hotkey", "only one non-modifier key is supported")
                }
                guard let parsedKeyCode = keyCode(for: token) else {
                    throw ConfigError.invalidValue("--hotkey", "unsupported key \(token)")
                }
                primaryKeyCode = parsedKeyCode
            }
        }

        guard primaryKeyCode != nil || !modifiers.isEmpty else {
            throw ConfigError.invalidValue("--hotkey", "at least one modifier or key is required")
        }

        return Hotkey(keyCode: primaryKeyCode, modifiers: modifiers, display: combo.lowercased())
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
