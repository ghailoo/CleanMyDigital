//
//  FileSearch.swift
//  CleanMyDigital
//

import Foundation

/// Parses the search field into terms and matches scanned files against
/// them. Pure — no SwiftUI, no filesystem — so the syntax can be tested
/// directly.
///
/// A query is whitespace-separated terms, all of which must match (AND):
///
/// - `daft discovery` — both words, each in any field.
/// - `artist:daft` — scoped to one field.
/// - `-flac` — must *not* match.
/// - `"hotel costes"` — quotes keep a phrase together, and combine with
///   both of the above (`album:"hotel costes"`, `-"best of"`).
enum FileSearch {
    enum Field: String, CaseIterable {
        case artist, title, album, genre, year, track, format, folder
    }

    struct Term: Equatable {
        /// nil means "any field".
        let field: Field?
        let text: String
        let isNegated: Bool
    }

    static func terms(in query: String) -> [Term] {
        var terms: [Term] = []
        var token = ""
        var inQuotes = false

        func flush() {
            defer { token = "" }
            var text = token
            guard !text.isEmpty else { return }

            guard text != "-" else { return }
            let isNegated = text.hasPrefix("-")
            if isNegated { text.removeFirst() }

            // Only a known field name counts as a prefix, so a colon inside
            // a title ("Pt. 2: Reprise") stays part of the search text.
            var field: Field?
            if let colon = text.firstIndex(of: ":"),
               let named = Field(rawValue: text[text.startIndex..<colon].lowercased()) {
                field = named
                text = String(text[text.index(after: colon)...])
            }

            guard !text.isEmpty else { return }
            terms.append(Term(field: field, text: text, isNegated: isNegated))
        }

        for character in query {
            if character == "\"" {
                inQuotes.toggle()
            } else if character.isWhitespace && !inQuotes {
                flush()
            } else {
                token.append(character)
            }
        }
        flush()
        return terms
    }

    static func matches(_ file: AudioFile, terms: [Term]) -> Bool {
        terms.allSatisfy { term in
            let found = values(of: term.field, in: file).contains {
                $0.localizedCaseInsensitiveContains(term.text)
            }
            return term.isNegated ? !found : found
        }
    }

    private static func values(of field: Field?, in file: AudioFile) -> [String] {
        let folder = file.url.deletingLastPathComponent().lastPathComponent
        let values: [String?] = switch field {
        case .artist: [file.artist]
        case .title: [file.title]
        case .album: [file.album]
        case .genre: [file.genre]
        case .year: [file.year]
        case .track: [file.trackNumber]
        case .format: [file.fileExtension]
        case .folder: [folder]
        case nil: [file.fileName, file.title, file.artist, file.album, file.genre,
                   file.year, file.trackNumber, file.fileExtension, folder]
        }
        return values.compactMap { $0 }
    }
}
