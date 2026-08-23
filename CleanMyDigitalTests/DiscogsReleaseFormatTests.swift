//
//  DiscogsReleaseFormatTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `DiscogsRelease` decodes Discogs' `/database/search` `format`
/// array (e.g. `"format": ["Vinyl", "LP", "Album"]`) and joins it the same
/// way `combinedGenre` already does. Decodes from JSON, mirroring the shape
/// Discogs' real search response uses, rather than constructing the struct
/// directly.
struct DiscogsReleaseFormatTests {
    @Test func decodesAndJoinsTheFormatArray() throws {
        let release = try Self.makeRelease(format: ["Vinyl", "LP", "Album"])
        #expect(release.formattedFormat == "Vinyl, LP, Album")
    }

    @Test func formattedFormatIsEmptyWhenTheFieldIsAbsent() throws {
        let release = try Self.makeRelease(format: nil)
        #expect(release.formattedFormat.isEmpty)
    }

    @Test func formattedFormatIsEmptyWhenTheFieldIsAnEmptyArray() throws {
        let release = try Self.makeRelease(format: [])
        #expect(release.formattedFormat.isEmpty)
    }

    // MARK: - Fixture

    private static func makeRelease(format: [String]?) throws -> DiscogsRelease {
        let json = """
        {
            "id": 12345,
            "title": "2Pac - Greatest Hits",
            "year": "1998",
            \(format.map { "\"format\": \(Self.jsonArray($0)),"} ?? "")
            "thumb": "https://example.com/thumb.jpg"
        }
        """
        return try JSONDecoder().decode(DiscogsRelease.self, from: Data(json.utf8))
    }

    private static func jsonArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }
}
