import Foundation

enum WindowTitleMatcher {
    static func bestMatchIndex(for query: String, in candidates: [String]) -> Int? {
        candidates
            .enumerated()
            .compactMap { element -> (index: Int, score: Int, length: Int)? in
                let index = element.offset
                let candidate = element.element
                guard let score = score(candidate: candidate, query: query) else {
                    return nil
                }
                return (index: index, score: score, length: candidate.count)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.length < rhs.length
            }
            .first?
            .index
    }

    static func score(candidate: String, query: String) -> Int? {
        let normalizedCandidate = normalized(candidate)
        let normalizedQuery = normalized(query)

        guard !normalizedCandidate.isEmpty, !normalizedQuery.isEmpty else {
            return nil
        }

        let queryTokens = tokens(from: normalizedQuery)
        let candidateTokens = Set(tokens(from: normalizedCandidate))
        let matchedTokenCount = queryTokens.filter(candidateTokens.contains).count
        let containsFullQuery = normalizedCandidate.contains(normalizedQuery)

        guard containsFullQuery || matchedTokenCount > 0 else {
            return nil
        }

        var score = 0

        if normalizedCandidate == normalizedQuery {
            score += 1_000
        }

        if normalizedCandidate.hasPrefix(normalizedQuery) {
            score += 250
        }

        if containsFullQuery {
            score += 700
        }

        score += matchedTokenCount * 120

        if matchedTokenCount == queryTokens.count {
            score += 200
        }

        score -= abs(normalizedCandidate.count - normalizedQuery.count)

        return score
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokens(from normalizedText: String) -> [String] {
        normalizedText
            .split(separator: " ")
            .map(String.init)
    }
}
