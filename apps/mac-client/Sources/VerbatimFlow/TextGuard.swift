import Foundation

struct GuardedText {
    let text: String
    let fellBackToRaw: Bool
}

struct TextGuard {
    let mode: OutputMode

    func apply(raw: String) -> GuardedText {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return GuardedText(text: "", fellBackToRaw: false)
        }

        switch mode {
        case .raw:
            return GuardedText(text: trimmedRaw, fellBackToRaw: false)
        case .formatOnly:
            let formatted = formatOnlyNormalize(trimmedRaw)
            if semanticallyEquivalent(lhs: trimmedRaw, rhs: formatted) {
                return GuardedText(text: formatted, fellBackToRaw: false)
            }
            return GuardedText(text: trimmedRaw, fellBackToRaw: true)
        case .clarify:
            let clarified = clarifyNormalize(trimmedRaw)
            return GuardedText(text: clarified.isEmpty ? trimmedRaw : clarified, fellBackToRaw: false)
        }
    }

    private func formatOnlyNormalize(_ text: String) -> String {
        var output = text
        output = replace(output, pattern: "\\s+", template: " ")
        output = replace(output, pattern: "\\s+([,\\.!?;:，。！？；：])", template: "$1")
        output = replace(output, pattern: "([,\\.!?;:])(\\S)", template: "$1 $2")
        output = replace(output, pattern: "([，。！？；：])(\\s+)", template: "$1")
        output = replace(output, pattern: "\\s+([)\\]}>])", template: "$1")
        output = replace(output, pattern: "([(\\[<{])\\s+", template: "$1")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clarifyNormalize(_ text: String) -> String {
        var output = text.replacingOccurrences(of: "\n", with: " ")
        output = stripFillerWords(output)
        output = collapseStutters(output)
        output = collapseImmediateDuplicateWords(output)
        output = collapseDuplicateWordPhrases(output)
        output = formatOnlyNormalize(output)
        output = ensureTerminalPunctuation(output)
        return output
    }

    private func stripFillerWords(_ text: String) -> String {
        var output = text
        let patterns: [(String, String)] = [
            ("(?i)\\b(?:uh+|um+|erm+|hmm+|you know|i mean|like)\\b", " "),
            ("(?:^|[\\s，。！？,.!?])(?:嗯+|呃+|额+|啊+)(?=[\\s，。！？,.!?]|$)", " "),
            ("(?:^|[\\s，。！？,.!?])(?:那个|这个|怎么说呢)(?=[\\s，。！？,.!?]|$)", " "),
            ("(?i)\\b(?:sorry|correction)\\b", " ")
        ]

        for (pattern, template) in patterns {
            output = replace(output, pattern: pattern, template: template)
        }
        return output
    }

    private func collapseStutters(_ text: String) -> String {
        var output = text
        output = replace(output, pattern: "(\\p{Han})\\1{2,}", template: "$1$1")
        output = replace(output, pattern: "([A-Za-z])\\1{2,}", template: "$1$1")
        return output
    }

    private func collapseImmediateDuplicateWords(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return text }

        var result: [String] = []
        result.reserveCapacity(words.count)
        var previous: String?

        for word in words {
            let normalized = canonicalWord(word)
            if normalized.isEmpty {
                continue
            }
            if normalized == previous {
                continue
            }
            previous = normalized
            result.append(word)
        }

        return result.joined(separator: " ")
    }

    private func collapseDuplicateWordPhrases(_ text: String) -> String {
        var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 4 else {
            return text
        }

        let normalizedWords = words.map(canonicalWord)
        var normalized = normalizedWords

        for window in stride(from: 4, through: 2, by: -1) {
            var index = 0
            while index + window * 2 <= words.count {
                let lhs = normalized[index..<(index + window)]
                let rhs = normalized[(index + window)..<(index + window * 2)]
                if lhs.elementsEqual(rhs) {
                    words.removeSubrange((index + window)..<(index + window * 2))
                    normalized.removeSubrange((index + window)..<(index + window * 2))
                    continue
                }
                index += 1
            }
        }

        return words.joined(separator: " ")
    }

    private func ensureTerminalPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let last = trimmed.last, "。！？.!?".contains(last) {
            return trimmed
        }

        if containsHanCharacter(trimmed) {
            return trimmed + "。"
        }
        return trimmed + "."
    }

    private func containsHanCharacter(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if scalar.properties.isIdeographic {
                return true
            }
        }
        return false
    }

    private func canonicalWord(_ word: String) -> String {
        word
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func semanticallyEquivalent(lhs: String, rhs: String) -> Bool {
        canonicalTokens(lhs) == canonicalTokens(rhs)
    }

    private func canonicalTokens(_ text: String) -> [String] {
        let punctuation = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)

        var normalized = ""
        normalized.reserveCapacity(text.count)

        for scalar in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).unicodeScalars {
            if punctuation.contains(scalar) {
                normalized.append(" ")
            } else {
                normalized.unicodeScalars.append(scalar)
            }
        }

        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private func replace(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
