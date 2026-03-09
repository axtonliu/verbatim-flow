import Foundation

struct MixedLanguageEnhancementResult {
    let text: String
    let appliedRules: [String]
}

enum MixedLanguageEnhancer {
    private static let englishTokenRegex = try? NSRegularExpression(
        pattern: "[A-Za-z][A-Za-z0-9]*(?:[-'][A-Za-z0-9]+)*",
        options: []
    )
    private static let hanCharacterRegex = try? NSRegularExpression(pattern: "\\p{Han}", options: [])
    private static let hanTokenRegex = try? NSRegularExpression(pattern: "[\\p{Han}]{2,6}", options: [])
    private static let phraseTokenRegex = try? NSRegularExpression(pattern: "[A-Za-z0-9]+", options: [])

    static func apply(text: String, localeIdentifier: String, vocabularyHints: [String]) -> MixedLanguageEnhancementResult {
        guard !text.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        guard localeIdentifier.lowercased().hasPrefix("zh"), containsHanCharacter(text) else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        let canonicalTerms = normalizedCanonicalTerms(from: vocabularyHints)
        guard !canonicalTerms.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        if containsEnglishToken(text) {
            let phraseCorrections = applyPhraseCorrections(text: output, candidates: normalizedPhraseTerms(from: vocabularyHints))
            output = phraseCorrections.text
            appliedRules.append(contentsOf: phraseCorrections.appliedRules)

            let aliasCorrections = applyExplicitAliasCorrections(text: output, aliases: DictationVocabulary.substringAliases())
            output = aliasCorrections.text
            appliedRules.append(contentsOf: aliasCorrections.appliedRules)

            let englishCorrections = applyEnglishTokenCorrections(text: output, candidates: canonicalTerms)
            output = englishCorrections.text
            appliedRules.append(contentsOf: englishCorrections.appliedRules)
        } else {
            let aliasCorrections = applyExplicitAliasCorrections(text: output, aliases: DictationVocabulary.substringAliases())
            output = aliasCorrections.text
            appliedRules.append(contentsOf: aliasCorrections.appliedRules)
        }

        let hanCorrections = applyHanTokenCorrections(text: output, candidates: canonicalTerms)
        output = hanCorrections.text
        appliedRules.append(contentsOf: hanCorrections.appliedRules)

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules)
    }

    private static func applyPhraseCorrections(text: String, candidates: [String: String]) -> MixedLanguageEnhancementResult {
        guard let regex = phraseTokenRegex, !candidates.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        for windowSize in stride(from: 3, through: 2, by: -1) {
            var changed = true
            while changed {
                changed = false
                let nsText = output as NSString
                let matches = regex.matches(in: output, options: [], range: NSRange(location: 0, length: nsText.length))
                guard matches.count >= windowSize else {
                    break
                }

                for startIndex in stride(from: matches.count - windowSize, through: 0, by: -1) {
                    let window = Array(matches[startIndex..<(startIndex + windowSize)])
                    guard let firstRange = Range(window.first!.range, in: output),
                          let lastRange = Range(window.last!.range, in: output) else {
                        continue
                    }

                    let replacementRange = firstRange.lowerBound..<lastRange.upperBound
                    let original = String(output[replacementRange])
                    let normalizedWindow = window
                        .compactMap { Range($0.range, in: output).map { String(output[$0]) } }
                        .joined()
                        .lowercased()

                    guard let candidate = candidates[normalizedWindow] else {
                        continue
                    }

                    guard shouldApplyCandidate(candidate, in: output, replacing: replacementRange) else {
                        continue
                    }

                    guard canonicalPhraseKey(original) != canonicalPhraseKey(candidate) || original != candidate else {
                        continue
                    }

                    output.replaceSubrange(replacementRange, with: candidate)
                    appliedRules.append("\(original) -> \(candidate)")
                    changed = true
                    break
                }
            }
        }

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules.reversed())
    }

    private static func containsHanCharacter(_ text: String) -> Bool {
        guard let regex = hanCharacterRegex else { return false }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func containsEnglishToken(_ text: String) -> Bool {
        guard let regex = englishTokenRegex else { return false }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func applyEnglishTokenCorrections(text: String, candidates: [String: String]) -> MixedLanguageEnhancementResult {
        guard let regex = englishTokenRegex else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        for match in matches.reversed() {
            guard match.range.location != NSNotFound else { continue }

            let range = Range(match.range, in: output)
            guard let tokenRange = range else { continue }
            let token = String(output[tokenRange])
            let normalized = token.lowercased()

            if let alias = DictationVocabulary.aliasMatch(for: token) {
                guard shouldApply(policy: alias.correctionPolicy, in: output, replacing: tokenRange) else {
                    continue
                }

                if token != alias.target {
                    output.replaceSubrange(tokenRange, with: alias.target)
                    appliedRules.append("\(token) -> \(alias.target)")
                }
                continue
            }

            if let exactTarget = DictationVocabulary.exactCaseTarget(for: token),
               exactTarget != token,
               shouldApplyCandidate(exactTarget, in: output, replacing: tokenRange) {
                output.replaceSubrange(tokenRange, with: exactTarget)
                appliedRules.append("\(token) -> \(exactTarget)")
                continue
            }

            guard candidates[normalized] == nil else {
                continue
            }

            guard let candidate = bestCandidate(for: normalized, candidates: candidates) else {
                continue
            }

            guard shouldApplyCandidate(candidate, in: output, replacing: tokenRange) else {
                continue
            }

            let replacement = adaptCase(reference: token, candidate: candidate)
            output.replaceSubrange(tokenRange, with: replacement)
            appliedRules.append("\(token) -> \(replacement)")
        }

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules.reversed())
    }

    private static func applyExplicitAliasCorrections(
        text: String,
        aliases: [DictationVocabulary.AliasProfile]
    ) -> MixedLanguageEnhancementResult {
        guard !aliases.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []
        let orderedAliases = aliases.sorted { $0.source.count > $1.source.count }

        for alias in orderedAliases {
            var matches: [Range<String.Index>] = []
            var searchStart = output.startIndex

            while searchStart < output.endIndex,
                  let range = output.range(of: alias.source, options: [.caseInsensitive], range: searchStart..<output.endIndex) {
                matches.append(range)
                searchStart = range.upperBound
            }

            for range in matches.reversed() {
                guard shouldApply(policy: alias.correctionPolicy, in: output, replacing: range) else {
                    continue
                }

                let original = String(output[range])
                guard original != alias.target else {
                    continue
                }

                let replacement = spacedReplacementIfNeeded(
                    original: original,
                    target: alias.target,
                    in: output,
                    replacing: range
                )
                output.replaceSubrange(range, with: replacement)
                appliedRules.append("\(original) -> \(alias.target)")
            }
        }

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules)
    }

    private static func applyHanTokenCorrections(text: String, candidates: [String: String]) -> MixedLanguageEnhancementResult {
        guard let regex = hanTokenRegex else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        let phoneticTerms = normalizedPhoneticTerms(from: candidates)
        guard !phoneticTerms.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        for match in matches.reversed() {
            guard match.range.location != NSNotFound else { continue }
            let range = Range(match.range, in: output)
            guard let tokenRange = range else { continue }
            let token = String(output[tokenRange])
            let latin = latinSkeleton(for: token)
            guard latin.count >= 4 else { continue }

            guard let candidate = bestPhoneticCandidate(for: latin, candidates: phoneticTerms) else {
                continue
            }

            guard shouldApplyCandidate(candidate, in: output, replacing: tokenRange) else {
                continue
            }

            output.replaceSubrange(tokenRange, with: candidate)
            appliedRules.append("\(token) -> \(candidate)")
        }

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules.reversed())
    }

    private static func normalizedCanonicalTerms(from rawHints: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for hint in rawHints {
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains(" ") {
                continue
            }

            guard trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil else {
                continue
            }

            table[trimmed.lowercased()] = trimmed
        }
        return table
    }

    private static func normalizedPhraseTerms(from rawHints: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for hint in rawHints {
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil else {
                continue
            }

            let normalized = canonicalPhraseKey(trimmed)
            guard normalized.count >= 4 else {
                continue
            }

            table[normalized] = trimmed
        }
        return table
    }

    private static func canonicalPhraseKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func shouldApplyCandidate(
        _ candidate: String,
        in text: String,
        replacing range: Range<String.Index>
    ) -> Bool {
        shouldApply(policy: DictationVocabulary.correctionPolicy(for: candidate), in: text, replacing: range)
    }

    private static func shouldApply(
        policy: DictationVocabulary.CorrectionPolicy,
        in text: String,
        replacing range: Range<String.Index>
    ) -> Bool {
        switch policy {
        case .always:
            return true
        case .contextual(let keywords):
            let context = surroundingContext(in: text, around: range, radius: 18)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return keywords.contains { context.contains($0.lowercased()) }
        }
    }

    private static func surroundingContext(
        in text: String,
        around range: Range<String.Index>,
        radius: Int
    ) -> String {
        let lowerBound = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let upperBound = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lowerBound..<upperBound])
    }

    private static func normalizedPhoneticTerms(from candidates: [String: String]) -> [String: String] {
        var table: [String: String] = [:]
        for (_, original) in candidates {
            let normalized = original.lowercased()
            let lettersOnly = normalized.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            guard lettersOnly.count >= 4 else {
                continue
            }
            table[lettersOnly] = original
        }
        return table
    }

    private static func bestCandidate(for token: String, candidates: [String: String]) -> String? {
        var best: (term: String, distance: Int)?

        for (normalized, original) in candidates {
            guard normalized.first == token.first else {
                continue
            }

            if abs(normalized.count - token.count) > 2 {
                continue
            }

            let distance = levenshtein(token, normalized)
            if distance > maxDistance(for: normalized.count) {
                continue
            }

            if let currentBest = best {
                if distance < currentBest.distance {
                    best = (original, distance)
                }
            } else {
                best = (original, distance)
            }
        }

        return best?.term
    }

    private static func maxDistance(for length: Int) -> Int {
        if length <= 4 {
            return 1
        }
        if length <= 8 {
            return 2
        }
        return 3
    }

    private static func maxPhoneticDistance(for length: Int) -> Int {
        if length <= 5 {
            return 2
        }
        if length <= 8 {
            return 3
        }
        return 4
    }

    private static func bestPhoneticCandidate(for tokenLatin: String, candidates: [String: String]) -> String? {
        var best: (term: String, distance: Int)?

        for (normalized, original) in candidates {
            guard normalized.first == tokenLatin.first else {
                continue
            }

            if abs(normalized.count - tokenLatin.count) > 5 {
                continue
            }

            let distance = levenshtein(tokenLatin, normalized)
            if distance > maxPhoneticDistance(for: normalized.count) {
                continue
            }

            if let currentBest = best {
                if distance < currentBest.distance {
                    best = (original, distance)
                }
            } else {
                best = (original, distance)
            }
        }

        return best?.term
    }

    private static func adaptCase(reference: String, candidate: String) -> String {
        if reference.rangeOfCharacter(from: CharacterSet.letters) == nil {
            return candidate
        }

        if reference.uppercased() == reference {
            return candidate.uppercased()
        }

        if let first = reference.first, String(first).uppercased() == String(first), reference.dropFirst().lowercased() == reference.dropFirst() {
            let head = String(candidate.prefix(1)).uppercased()
            let tail = String(candidate.dropFirst()).lowercased()
            return head + tail
        }

        return candidate.lowercased()
    }

    private static func spacedReplacementIfNeeded(
        original: String,
        target: String,
        in text: String,
        replacing range: Range<String.Index>
    ) -> String {
        guard containsHanCharacter(original),
              target.rangeOfCharacter(from: CharacterSet.letters) != nil else {
            return target
        }

        var replacement = target
        if let previous = previousCharacter(in: text, before: range.lowerBound), isHanCharacter(previous) {
            replacement = " " + replacement
        }
        if let next = nextCharacter(in: text, after: range.upperBound), isHanCharacter(next) {
            replacement += " "
        }
        return replacement
    }

    private static func previousCharacter(in text: String, before index: String.Index) -> Character? {
        guard index > text.startIndex else {
            return nil
        }
        return text[text.index(before: index)]
    }

    private static func nextCharacter(in text: String, after index: String.Index) -> Character? {
        guard index < text.endIndex else {
            return nil
        }
        return text[index]
    }

    private static func isHanCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: \.properties.isIdeographic)
    }

    private static func latinSkeleton(for text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        let toLatin = CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        if toLatin {
            _ = CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        }

        return (mutable as String)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        if lhsChars.isEmpty { return rhsChars.count }
        if rhsChars.isEmpty { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        var current = Array(repeating: 0, count: rhsChars.count + 1)

        for i in 1...lhsChars.count {
            current[0] = i
            for j in 1...rhsChars.count {
                let substitutionCost = lhsChars[i - 1] == rhsChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitutionCost
                )
            }
            previous = current
        }

        return previous[rhsChars.count]
    }
}
