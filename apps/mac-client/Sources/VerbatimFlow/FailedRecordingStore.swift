import Foundation

enum FailedRecordingStore {
    struct Entry: Codable {
        let audioFilePath: String
        let recognitionEngineRawValue: String
        let localeIdentifier: String
        let languageIsAutoDetect: Bool?
        let whisperModelRawValue: String
        let whisperComputeType: String
        let openAIModelRawValue: String
        let qwenModelRawValue: String?
        let createdAt: Date
        let durationSeconds: TimeInterval

        var audioFileURL: URL {
            URL(fileURLWithPath: audioFilePath)
        }

        var recognitionEngine: RecognitionEngine? {
            RecognitionEngine(rawValue: recognitionEngineRawValue)
        }

        var whisperModel: WhisperModel? {
            WhisperModel(rawValue: whisperModelRawValue)
        }

        var openAIModel: OpenAITranscriptionModel? {
            OpenAITranscriptionModel(rawValue: openAIModelRawValue)
        }

        var qwenModel: QwenModel? {
            guard let raw = qwenModelRawValue else { return nil }
            return QwenModel(rawValue: raw)
        }
    }

    private struct Paths {
        let directoryURL: URL
        let audioFileURL: URL
        let metadataFileURL: URL
    }

    private static func paths(baseDirectory: URL? = nil) -> Paths {
        let rootDirectory: URL
        if let baseDirectory {
            rootDirectory = baseDirectory
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
            rootDirectory = applicationSupport.appendingPathComponent("VerbatimFlow", isDirectory: true)
        }

        let directoryURL = rootDirectory.appendingPathComponent("FailedRecordings", isDirectory: true)
        return Paths(
            directoryURL: directoryURL,
            audioFileURL: directoryURL.appendingPathComponent("last_failed_recording.m4a"),
            metadataFileURL: directoryURL.appendingPathComponent("last_failed_recording.json")
        )
    }

    static func load(baseDirectory: URL? = nil) -> Entry? {
        let pathSet = paths(baseDirectory: baseDirectory)
        guard let metadataData = try? Data(contentsOf: pathSet.metadataFileURL) else {
            return nil
        }

        guard let entry = try? JSONDecoder().decode(Entry.self, from: metadataData) else {
            clear(baseDirectory: baseDirectory)
            return nil
        }

        guard FileManager.default.fileExists(atPath: entry.audioFileURL.path) else {
            clear(baseDirectory: baseDirectory)
            return nil
        }

        return entry
    }

    @discardableResult
    static func save(
        sourceAudioURL: URL,
        recognitionEngine: RecognitionEngine,
        localeIdentifier: String,
        languageIsAutoDetect: Bool,
        whisperModel: WhisperModel,
        whisperComputeType: String,
        openAIModel: OpenAITranscriptionModel,
        qwenModel: QwenModel,
        durationSeconds: TimeInterval,
        baseDirectory: URL? = nil
    ) -> Entry? {
        let pathSet = paths(baseDirectory: baseDirectory)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: pathSet.directoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: pathSet.audioFileURL.path) {
                try fileManager.removeItem(at: pathSet.audioFileURL)
            }
            if fileManager.fileExists(atPath: pathSet.metadataFileURL.path) {
                try fileManager.removeItem(at: pathSet.metadataFileURL)
            }

            try fileManager.moveItem(at: sourceAudioURL, to: pathSet.audioFileURL)

            let entry = Entry(
                audioFilePath: pathSet.audioFileURL.path,
                recognitionEngineRawValue: recognitionEngine.rawValue,
                localeIdentifier: localeIdentifier,
                languageIsAutoDetect: languageIsAutoDetect,
                whisperModelRawValue: whisperModel.rawValue,
                whisperComputeType: whisperComputeType,
                openAIModelRawValue: openAIModel.rawValue,
                qwenModelRawValue: qwenModel.rawValue,
                createdAt: Date(),
                durationSeconds: durationSeconds
            )

            let metadataData = try JSONEncoder().encode(entry)
            try metadataData.write(to: pathSet.metadataFileURL, options: .atomic)
            return entry
        } catch {
            RuntimeLogger.log("[retry-audio] failed to persist last failed recording: \(error)")
            return nil
        }
    }

    static func clear(baseDirectory: URL? = nil) {
        let pathSet = paths(baseDirectory: baseDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: pathSet.audioFileURL.path) {
            try? fileManager.removeItem(at: pathSet.audioFileURL)
        }
        if fileManager.fileExists(atPath: pathSet.metadataFileURL.path) {
            try? fileManager.removeItem(at: pathSet.metadataFileURL)
        }
    }
}
