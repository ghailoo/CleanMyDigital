//
//  MatchConfidence.swift
//  CleanMyDigital
//

import Foundation

/// How much a provider's result actually looks like the file that was
/// searched for, decided by comparing the two names word for word, in any
/// order.
enum MatchConfidence: Sendable, Equatable {
    /// Both names are essentially the same set of words — safe to apply.
    case confident
    /// Most of the file's words are there, but not enough of the result's,
    /// or not enough of the file's. Worth a human look before writing.
    case review
    /// Too little in common to call it the same release.
    case none
}

/// Scores a search result against the file it was found for. Pure — no
/// network, no SwiftUI — so the thresholds can be tested directly.
///
/// Two percentages are measured, because the two kinds of mismatch mean
/// different things:
///
/// - **coverage** — how much of the *file's* name the result accounts for.
///   Extra words on the provider's side don't count against it.
/// - **balance** — how much of *both* names they share (Dice): a result
///   whose own name carries words the file never mentions scores lower,
///   even when it covers the file perfectly.
///
/// A result has to be balanced to be `.confident`; covering the file alone
/// only earns `.review`, which is never written without a tick.
enum MatchScore {
    static let confidentThreshold = 0.9
    static let reviewThreshold = 0.8

    static func confidence(fileName: String, resultName: String) -> MatchConfidence {
        let (coverage, balance) = percentages(fileName: fileName, resultName: resultName)
        if balance >= confidentThreshold { return .confident }
        if coverage >= reviewThreshold || balance >= reviewThreshold { return .review }
        return .none
    }

    static func percentages(fileName: String, resultName: String) -> (coverage: Double, balance: Double) {
        let fileWords = words(in: fileName)
        let resultWords = words(in: resultName)
        guard !fileWords.isEmpty, !resultWords.isEmpty else { return (0, 0) }

        let shared = Double(sharedWordCount(fileWords, resultWords))
        return (coverage: shared / Double(fileWords.count),
                balance: 2 * shared / Double(fileWords.count + resultWords.count))
    }

    /// The comparable words of a name: lowercased, unaccented, punctuation
    /// gone, and without the parts a provider's own name never carries —
    /// a "feat." credit, and anything in brackets.
    ///
    /// Brackets go because a release is titled "Finally", while the file is
    /// "Finally (DJ Meri Mix)": the mix name identifies a *track* inside the
    /// release, not the release, so counting it would push every maxi single
    /// below every threshold. Which pressing a file is stays the tracklist
    /// step's job (`DiscogsClient.firstRelease`), not this one's.
    static func words(in name: String) -> [String] {
        // Per dash-separated part, because a credit runs only to the end of
        // the part it's in: stripping "Kings Of Tomorrow Feat. Julie McKnight
        // - Finally" whole would swallow the title along with the credit.
        let withoutCredits = name
            .components(separatedBy: " - ")
            .map { MetadataQuery.strippingFeaturedArtist(from: $0) }
            .joined(separator: " ")
        let withoutBrackets = withoutCredits.replacingOccurrences(
            of: #"[\(\[][^()\[\]]*[\)\]]"#, with: " ", options: .regularExpression)
        let folded = withoutBrackets.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let separated = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return separated.split(separator: " ").map(String.init)
    }

    /// Words shared by both names, each one usable once, and tolerant of a
    /// typo — the file's own tag spells it "Tommorow" often enough
    /// (see `MetadataQuery.isNearMatch`, which is stricter because it judges
    /// whole names rather than single words).
    private static func sharedWordCount(_ first: [String], _ second: [String]) -> Int {
        var unused = second
        var shared = 0
        for word in first {
            guard let index = unused.firstIndex(where: { sameWord($0, word) }) else { continue }
            unused.remove(at: index)
            shared += 1
        }
        return shared
    }

    private static func sameWord(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        // Short words are compared exactly: at four letters a single edit is
        // the difference between "love" and "live".
        let longest = max(first.count, second.count)
        let allowed = longest >= 8 ? 2 : (longest >= 5 ? 1 : 0)
        guard allowed > 0, abs(first.count - second.count) <= allowed else { return false }
        return MetadataQuery.editDistance(first, second, stoppingAbove: allowed) <= allowed
    }
}
