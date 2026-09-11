//
//  PluralizationTests.swift
//  CleanMyDigitalTests
//

import Testing
@testable import CleanMyDigital

struct PluralizationTests {
    @Test func pluralizedUsesSingularForOne() {
        #expect(pluralized(1, "file") == "1 file")
    }

    @Test func pluralizedUsesRegularPluralForOtherCounts() {
        #expect(pluralized(0, "file") == "0 files")
        #expect(pluralized(5, "file") == "5 files")
    }

    @Test func pluralizedUsesTheGivenIrregularPlural() {
        #expect(pluralized(3, "child", plural: "children") == "3 children")
    }

    @Test func pluralWordOmitsTheCount() {
        #expect(pluralWord(1, "track") == "track")
        #expect(pluralWord(2, "track") == "tracks")
    }
}
