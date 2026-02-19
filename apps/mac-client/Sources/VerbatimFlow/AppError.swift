import Foundation

enum AppError: Error, CustomStringConvertible {
    case speechRecognizerUnavailable(String)
    case speechServiceUnavailable
    case audioRecorderStartFailed
    case whisperScriptNotFound
    case pythonRuntimeNotFound
    case whisperTranscriptionFailed(String)
    case openAIAPIKeyMissing
    case openAITranscriptionFailed(String)
    case eventSourceCreationFailed
    case eventCreationFailed
    case accessibilityPermissionRequired

    var description: String {
        switch self {
        case .speechRecognizerUnavailable(let locale):
            return "Speech recognizer is unavailable for locale: \(locale)"
        case .speechServiceUnavailable:
            return "Speech service is not available right now"
        case .audioRecorderStartFailed:
            return "Failed to start audio recorder"
        case .whisperScriptNotFound:
            return "Whisper script not found. Expected python/scripts/transcribe_once.py in the project."
        case .pythonRuntimeNotFound:
            return "Python runtime for Whisper is unavailable. Run python setup first."
        case .whisperTranscriptionFailed(let details):
            if details.isEmpty {
                return "Whisper transcription failed"
            }
            return "Whisper transcription failed: \(details)"
        case .openAIAPIKeyMissing:
            return "OPENAI_API_KEY is missing. Set it in environment or open \(OpenAISettings.fileURL.path)."
        case .openAITranscriptionFailed(let details):
            if details.isEmpty {
                return "OpenAI Cloud transcription failed"
            }
            return "OpenAI Cloud transcription failed: \(details)"
        case .eventSourceCreationFailed:
            return "Failed to create event source"
        case .eventCreationFailed:
            return "Failed to create keyboard event"
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required for text injection"
        }
    }
}
