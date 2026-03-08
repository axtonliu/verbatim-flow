import Foundation

struct GuardedText {
    let text: String
    let fellBackToRaw: Bool
}

struct TextGuard {
    let mode: OutputMode
    private let asciiToFullWidthPunctuation: [Character: Character] = [
        ",": "，",
        ".": "。",
        "!": "！",
        "?": "？",
        ";": "；",
        ":": "："
    ]
    private let paragraphLeadingMarkers: [String] = [
        "然后", "另外", "还有", "此外", "同时", "不过", "但是", "所以", "因此",
        "其实", "另外呢", "还有呢", "首先", "其次", "最后", "总之"
    ]

    func apply(raw: String) -> GuardedText {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return GuardedText(text: "", fellBackToRaw: false)
        }

        switch mode {
        case .raw:
            return GuardedText(text: trimmedRaw, fellBackToRaw: false)
        case .formatOnly:
            let formatted = formatOnlyNormalize(trimmedRaw, enableParagraphing: true)
            if semanticallyEquivalent(lhs: trimmedRaw, rhs: formatted) {
                return GuardedText(text: formatted, fellBackToRaw: false)
            }
            return GuardedText(text: trimmedRaw, fellBackToRaw: true)
        case .clarify:
            let clarified = clarifyNormalize(trimmedRaw)
            return GuardedText(text: clarified.isEmpty ? trimmedRaw : clarified, fellBackToRaw: false)
        }
    }

    private func formatOnlyNormalize(_ text: String, enableParagraphing: Bool) -> String {
        var output = text
        output = replace(output, pattern: "\\s+", template: " ")
        output = replace(output, pattern: "\\s+([,\\.!?;:，。！？；：])", template: "$1")
        if shouldPreferFullWidthPunctuation(output) {
            output = convertASCIIToFullWidthPunctuation(output)
        }
        output = injectLightweightChinesePunctuation(output)
        output = normalizeASCIIPunctuationSpacing(output)
        output = replace(output, pattern: "([，。！？；：])(\\s+)", template: "$1")
        output = replace(output, pattern: "\\s+([)\\]}>])", template: "$1")
        output = replace(output, pattern: "([(\\[<{])\\s+", template: "$1")
        if enableParagraphing {
            output = applyLightweightParagraphing(output)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clarifyNormalize(_ text: String) -> String {
        var output = text.replacingOccurrences(of: "\n", with: " ")
        output = stripFillerWords(output)
        output = collapseStutters(output)
        output = collapseImmediateDuplicateWords(output)
        output = collapseDuplicateWordPhrases(output)
        output = formatOnlyNormalize(output, enableParagraphing: false)
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

    private func shouldPreferFullWidthPunctuation(_ text: String) -> Bool {
        let hanCount = text.unicodeScalars.filter(\.properties.isIdeographic).count
        guard hanCount > 0 else {
            return false
        }

        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z]+", options: []) else {
            return true
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let latinClusterCount = regex.numberOfMatches(in: text, options: [], range: range)
        return latinClusterCount <= hanCount * 2
    }

    private func convertASCIIToFullWidthPunctuation(_ text: String) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        var output = String()
        output.reserveCapacity(text.count)

        for index in characters.indices {
            let character = characters[index]
            guard let mapped = asciiToFullWidthPunctuation[character] else {
                output.append(character)
                continue
            }

            let previous = previousNonWhitespaceCharacter(in: characters, before: index)
            let next = nextNonWhitespaceCharacter(in: characters, after: index)

            if shouldConvertToFullWidth(
                character,
                previous: previous,
                next: next
            ) {
                output.append(mapped)
            } else {
                output.append(character)
            }
        }

        return output
    }

    private func normalizeASCIIPunctuationSpacing(_ text: String) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        var output = String()
        output.reserveCapacity(text.count)

        for index in characters.indices {
            let character = characters[index]
            output.append(character)

            guard asciiToFullWidthPunctuation[character] != nil else {
                continue
            }

            guard index + 1 < characters.count, !characters[index + 1].isWhitespace else {
                continue
            }

            let previous = previousNonWhitespaceCharacter(in: characters, before: index)
            let next = nextNonWhitespaceCharacter(in: characters, after: index)

            if shouldInsertSpaceAfterASCII(
                character,
                previous: previous,
                next: next
            ) {
                output.append(" ")
            }
        }

        return output
    }

    private func injectLightweightChinesePunctuation(_ text: String) -> String {
        guard shouldPreferFullWidthPunctuation(text) else {
            return text
        }

        var output = text

        let prefixPatterns: [(String, String)] = [
            (#"^(好)(?=(继续|现在|那|我|你|我们|咱们|开始|可以|来|先))"#, "$1，"),
            (#"^(那)(?=(我|你|我们|咱们|现在|就|先|再))"#, "$1，"),
            (#"^(你看|然后|所以|但是|不过|另外|当然|其实|比如|那么|首先)(?=[\p{Han}A-Za-z0-9])"#, "$1，")
        ]

        for (pattern, template) in prefixPatterns {
            output = replace(output, pattern: pattern, template: template)
        }

        return ensureChineseTerminalPunctuation(output)
    }

    private func ensureChineseTerminalPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let last = trimmed.last, "，。！？；：,.!?;:".contains(last) {
            return trimmed
        }

        let hanCount = trimmed.unicodeScalars.filter(\.properties.isIdeographic).count
        guard hanCount >= 8 else {
            return trimmed
        }

        return trimmed + "。"
    }

    private func applyLightweightParagraphing(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsHanCharacter(trimmed) else {
            return trimmed
        }

        guard !trimmed.contains("\n"), trimmed.count >= 48 else {
            return trimmed
        }

        let sentences = splitSentences(trimmed)
        guard sentences.count >= 3 else {
            return trimmed
        }

        var paragraphs: [[String]] = []
        var current: [String] = []
        var currentLength = 0

        for sentence in sentences {
            let sentenceLength = sentence.count

            if !current.isEmpty,
               shouldStartNewParagraph(
                nextSentence: sentence,
                currentSentenceCount: current.count,
                currentLength: currentLength
               ) {
                paragraphs.append(current)
                current = []
                currentLength = 0
            }

            current.append(sentence)
            currentLength += sentenceLength
        }

        if !current.isEmpty {
            paragraphs.append(current)
        }

        guard paragraphs.count >= 2 else {
            return trimmed
        }

        return paragraphs
            .map { $0.joined() }
            .joined(separator: "\n\n")
    }

    private func splitSentences(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        var sentences: [String] = []
        var current = ""
        current.reserveCapacity(text.count)

        for character in text {
            current.append(character)
            if "。！？!?".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }

        return sentences
    }

    private func shouldStartNewParagraph(
        nextSentence: String,
        currentSentenceCount: Int,
        currentLength: Int
    ) -> Bool {
        guard currentSentenceCount > 0 else {
            return false
        }

        let trimmedNext = nextSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsWithMarker = paragraphLeadingMarkers.contains { trimmedNext.hasPrefix($0) }

        if startsWithMarker && currentLength >= 24 {
            return true
        }

        if currentSentenceCount >= 2 && currentLength >= 36 {
            return true
        }

        if currentLength >= 64 {
            return true
        }

        return false
    }

    private func shouldConvertToFullWidth(
        _ punctuation: Character,
        previous: Character?,
        next: Character?
    ) -> Bool {
        if punctuation == ":" && next == "/" {
            return false
        }

        if punctuation == "." && isASCIIAlphaNumeric(previous) && isASCIIAlphaNumeric(next) {
            return false
        }

        if (punctuation == "," || punctuation == "." || punctuation == ":")
            && isASCIIDigit(previous) && isASCIIDigit(next)
        {
            return false
        }

        if isHanCharacter(previous) || isHanCharacter(next) {
            return true
        }

        return next == nil
    }

    private func shouldInsertSpaceAfterASCII(
        _ punctuation: Character,
        previous: Character?,
        next: Character?
    ) -> Bool {
        guard let next else {
            return false
        }

        if isHanCharacter(next) {
            return false
        }

        if ")]}>\"'，。！？；：,.;:!?".contains(next) {
            return false
        }

        if punctuation == ":" && next == "/" {
            return false
        }

        if punctuation == "." && isASCIIAlphaNumeric(previous) && isASCIIAlphaNumeric(next) {
            return false
        }

        if (punctuation == "," || punctuation == "." || punctuation == ":")
            && isASCIIDigit(previous) && isASCIIDigit(next)
        {
            return false
        }

        return true
    }

    private func previousNonWhitespaceCharacter(in characters: [Character], before index: Int) -> Character? {
        guard index > 0 else { return nil }

        var currentIndex = index - 1
        while currentIndex >= 0 {
            let character = characters[currentIndex]
            if !character.isWhitespace {
                return character
            }
            currentIndex -= 1
        }

        return nil
    }

    private func nextNonWhitespaceCharacter(in characters: [Character], after index: Int) -> Character? {
        guard index + 1 < characters.count else { return nil }

        var currentIndex = index + 1
        while currentIndex < characters.count {
            let character = characters[currentIndex]
            if !character.isWhitespace {
                return character
            }
            currentIndex += 1
        }

        return nil
    }

    private func isHanCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.contains(where: \.properties.isIdeographic)
    }

    private func isASCIIDigit(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first, character?.unicodeScalars.count == 1 else {
            return false
        }
        return CharacterSet.decimalDigits.contains(scalar)
    }

    private func isASCIIAlphaNumeric(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first, character?.unicodeScalars.count == 1 else {
            return false
        }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private func canonicalWord(_ word: String) -> String {
        word
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func semanticallyEquivalent(lhs: String, rhs: String) -> Bool {
        canonicalComparableText(lhs) == canonicalComparableText(rhs)
    }

    private func canonicalComparableText(_ text: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters
            .union(.symbols)

        var normalized = ""
        normalized.reserveCapacity(text.count)

        for scalar in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || punctuation.contains(scalar) {
                continue
            } else {
                normalized.unicodeScalars.append(scalar)
            }
        }
        return normalized
    }

    private func replace(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
