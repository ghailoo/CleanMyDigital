//
//  BlankTagIsMissingTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

/// A ripper routinely leaves an empty field behind — `DATE=` in a FLAC, a
/// blank Year item in an APEv2 tag. Every writer's fill-if-missing rule
/// used to read that as "already has one", so the field could never be
/// filled and the file stayed stuck on "With issues" forever. A blank is
/// not a value.
@Suite struct BlankTagIsMissingTests {
    // MARK: FLAC

    private static func flacComments(existing: [String], changes: TagChanges) -> [String] {
        FLACTagWriter.merged(comments: existing, changes: changes)
    }

    @Test func aBlankDateIsFilled() {
        let out = Self.flacComments(
            existing: ["ARTIST=Nightcrawlers", "DATE=", "GENRE=House"],
            changes: { var c = TagChanges(); c.year = "1995"; return c }())
        #expect(out.contains("DATE=1995"))
        #expect(!out.contains("DATE="))       // the blank one is gone, not kept alongside
        #expect(out.filter { $0.hasPrefix("DATE=") }.count == 1)
    }

    @Test func aWhitespaceOnlyValueIsAlsoBlank() {
        let out = Self.flacComments(
            existing: ["DATE=   "],
            changes: { var c = TagChanges(); c.year = "1995"; return c }())
        #expect(out.contains("DATE=1995"))
        #expect(out.filter { $0.uppercased().hasPrefix("DATE=") }.count == 1)
    }

    /// The never-overwrite rule is untouched: a real value stands.
    @Test func arealValueIsNeverOverwritten() {
        let out = Self.flacComments(
            existing: ["DATE=1992"],
            changes: { var c = TagChanges(); c.year = "1995"; return c }())
        #expect(out.contains("DATE=1992"))
        #expect(!out.contains("DATE=1995"))
    }

    // MARK: APEv2

    @Test func aBlankAPEv2FieldIsFilled() {
        let existing = [APEv2Tag.Item(key: "Year", isBinary: false, valueBytes: [])]
        var changes = TagChanges()
        changes.year = "1995"
        let items = APEv2TagBuilder.build(changes: changes, existing: existing)
        let years = items.filter { $0.key.caseInsensitiveCompare("Year") == .orderedSame }
        #expect(years.count == 1)
        #expect(years.first?.textValue == "1995")
    }

    @Test func arealAPEv2ValueIsNeverOverwritten() {
        let existing = [APEv2Tag.Item(key: "Year", isBinary: false, valueBytes: Array("1992".utf8))]
        var changes = TagChanges()
        changes.year = "1995"
        let items = APEv2TagBuilder.build(changes: changes, existing: existing)
        #expect(items.filter { $0.key.caseInsensitiveCompare("Year") == .orderedSame }
            .first?.textValue == "1992")
    }
}
