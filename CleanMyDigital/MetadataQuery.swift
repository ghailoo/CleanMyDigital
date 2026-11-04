//
//  MetadataQuery.swift
//  CleanMyDigital
//

import Foundation

/// Shared search-term derivation for metadata providers (Discogs,
/// MusicBrainz) so every provider builds its query from the same cleaned
/// filename instead of each re-implementing its own heuristics.
enum MetadataQuery {
    /// For Albums, `expectedArtist` (the containing folder's name) is
    /// preferred over the file's own Artist tag — Albums are genuinely
    /// organized by artist folder, so the folder is often the more
    /// reliable source even when the tag is present but wrong.
    ///
    /// Singles do NOT get this treatment, unlike an earlier version of this
    /// function. Per the README, Singles files may sit loose in any
    /// folder, so the containing folder carries no reliable artist signal
    /// there at all — verified against the live Discogs API with a real
    /// Singles file whose folder was itself a release identifier ("1991 -
    /// 3 A.M. Eternal (CDM)"), not an artist: using that as the artist term
    /// found nothing, for every query shape tried. It also meant the real
    /// artist ("The KLF") never fuzzy-matched anything, so
    /// `cleanedTrackTitle`'s own "Artist - " prefix strip couldn't fire
    /// either — one wrong value was producing two wrong search terms.
    ///
    /// Compilations are organized by *release*, not by artist — the
    /// folder is the compilation's own name (e.g. "DJ Hits 100% '97-1"),
    /// never the track's artist — so `expectedArtist` there is never even
    /// a fallback candidate, only the file's own Artist tag is used.
    /// Searching Discogs/MusicBrainz for a compilation folder name as if
    /// it were an artist was returning zero results for every track,
    /// always — this is the fix for that.
    ///
    /// Singles and Compilations both fall back the same way when the file
    /// has no Artist tag either: parsing an artist out of an
    /// "Artist - Title" filename (`artistParsedFromFileName`) — a
    /// filename-derived guess beats sending no artist term at all when the
    /// filename actually states one.
    ///
    /// A "feat." credit is dropped ("Wareband Feat. Tad Robinson" → "Wareband"):
    /// Discogs credits featured artists differently, so the full string found
    /// nothing and forced the weaker title-only search.
    static func artist(for file: AudioFile) -> String {
        let artist = file.category == .albums
            ? file.expectedArtist ?? file.artist ?? artistParsedFromFileName(file.fileName) ?? ""
            : file.artist ?? artistParsedFromFileName(file.fileName) ?? ""
        return strippingFeaturedArtist(from: artist)
    }

    /// Parses the artist out of an "Artist - Title" filename — the text
    /// before the first " - ", once a leading track number is stripped —
    /// for when a file has no Artist tag at all to fall back on. Nil when
    /// the (track-number-stripped) filename has no " - " separator, i.e.
    /// there's nothing to parse an artist out of.
    static func artistParsedFromFileName(_ fileName: String) -> String? {
        let name = strippingLeadingTrackNumber(from: (fileName as NSString).deletingPathExtension)
        guard let dashRange = name.range(of: " - ") else { return nil }
        let left = String(name[name.startIndex..<dashRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return left.isEmpty ? nil : left
    }

    /// Strips a leading track number ("01 - ", "3.", "07_", "12)", or the
    /// same wrapped in parentheses — "(01) ") from a filename-derived
    /// title. Factored out of `cleanedTrackTitle` so `artistParsedFromFileName`
    /// starts from the same track-number-free text.
    /// Also normalizes separators first — every filename parser starts here.
    /// Non-breaking spaces ("Young MC\u{00A0}-\u{00A0}Principals Office") and
    /// en/em dashes look identical to " - " but never matched it, so the
    /// artist stayed glued to the title and searches found nothing.
    private static func strippingLeadingTrackNumber(from name: String) -> String {
        var name = name
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) // ICU \s includes NBSP
            .replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
        if let range = name.range(of: #"^\s*\(?\d{1,3}[\s._\-)]+"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    /// The search term for `release_title` (Discogs) / `release:`
    /// (MusicBrainz) — the file's own Album tag when it has one, since
    /// that's the most direct signal of the release, actually being read
    /// from the tag rather than any folder-depth guess. Falls back to the
    /// file's own containing folder name only when the tag is empty — a
    /// compilation rip with no Album tag at all still usually sits in a
    /// folder named after the release. Either way, a trailing disc/CD
    /// marker is stripped before searching, since Discogs titles a
    /// multi-disc release once and describes the discs in separate
    /// format/media metadata — see `strippingDiscAnnotation(from:)`.
    static func albumSearchTerm(for file: AudioFile) -> String {
        let tag = file.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = !tag.isEmpty ? tag : file.url.deletingLastPathComponent().lastPathComponent
        return strippingDiscAnnotation(from: base)
    }

    /// Strips a leading track number ("01 - ", "3.", "07_", "12)", or the
    /// same wrapped in parentheses — "(01) "), a leading "[Artist Name] "
    /// prefix, and for Singles also strips an "Artist - " prefix, since
    /// maxi-single files are typically named "Artist - Title (Mix)" and
    /// sending the whole name (artist included) as the track query returns
    /// zero results from both providers. Albums and Compilations skip that
    /// split — legitimate track titles can contain " - " (e.g.
    /// "Track - Reprise").
    ///
    /// The bracketed prefix is handled differently by category: for
    /// `.compilations` it's stripped unconditionally, since a leading
    /// "[Artist Name]" there is the per-track artist by convention — and
    /// `artist` for a compilation is forced to "Various" (see
    /// `DiscogsQuery`'s doc comment), which could never fuzzily match a
    /// real per-track artist name the way the other categories check
    /// against. For Singles/Albums it's still gated on a fuzzy match
    /// against `artist`, same as before — unconditional stripping would be
    /// unsafe there, where a real track title occasionally does start with
    /// a bracketed group that isn't an artist name (e.g. "[Live] Track").
    ///
    /// Deliberately does NOT strip a trailing mix/version parenthetical —
    /// e.g. "(Live At The S.S.L.)", "(Euro Club Mix)". Audited and verified
    /// against the live Discogs API: doing so turns an exact-pressing match
    /// into wrong, generic-pressing results ("The KLF - 3 A.M. Eternal
    /// (Live At The S.S.L.)" finds that exact release; "The KLF - 3 A.M.
    /// Eternal" with the mix stripped finds only generic "3 A.M. Eternal"
    /// pressings). For a maxi single, the mix name is often the single most
    /// identifying part of the title, not noise — see
    /// `DiscogsClient.searchTrack`'s doc comment, which is what actually
    /// sends this term.
    static func cleanedTrackTitle(from fileName: String, artist: String, category: LibraryCategory) -> String {
        var name = strippingLeadingTrackNumber(from: (fileName as NSString).deletingPathExtension)

        // Unlike the Singles-only " - " split below, square brackets are an
        // unambiguous delimiter — a real track title essentially never
        // legitimately contains "[Artist Name]" the way it might contain a
        // bare " - " — so this applies for every category. Anchored to the
        // very start (after the track number above) rather than matched
        // anywhere, so a legitimate bracketed suffix elsewhere in the title
        // (e.g. "Track Title [Live]") is left alone.
        if let bracketRange = name.range(of: #"^\s*\[[^\[\]]+\]\s*"#, options: .regularExpression) {
            if category == .compilations {
                name.removeSubrange(bracketRange)
            } else {
                let bracketed = String(name[bracketRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .dropFirst().dropLast()
                let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

                if !trimmedArtist.isEmpty,
                   bracketed.localizedCaseInsensitiveContains(trimmedArtist)
                        || trimmedArtist.localizedCaseInsensitiveContains(bracketed) {
                    name.removeSubrange(bracketRange)
                }
            }
        }

        if category == .singles, let dashRange = name.range(of: " - ") {
            let left = String(name[name.startIndex..<dashRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(name[dashRange.upperBound...])
            let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedArtist.isEmpty {
                // No artist to compare against — this library's filenames
                // all follow the "Artist - Title" convention, so still
                // prefer the part after the dash.
                name = right
            } else if left.localizedCaseInsensitiveContains(trimmedArtist)
                        || trimmedArtist.localizedCaseInsensitiveContains(left) {
                // Covers collaborations like "808 State & Ub40" or
                // "808 State : Ub40" filed under the "808 State" folder.
                name = right
            }
        }

        name = name.replacingOccurrences(of: "_", with: " ")
        name = strippingIdentifierNumber(from: name)
        return strippingFeaturedArtist(from: strippingSceneGroupTag(from: name))
    }

    /// Whether two normalized names differ by no more than a typo —
    /// "kingsoftommorow" vs "kingsoftomorrow", a real file whose own tag
    /// misspells the artist. Only ever a fallback, once an exact or
    /// containment check has already failed.
    ///
    /// Deliberately conservative, because a false positive here means
    /// trusting the wrong release: nothing under ten characters is fuzzy
    /// matched at all (so "Scooter" never matches "Shooter"), ten to
    /// thirteen allow one edit, and only fourteen or more allow two.
    /// ponytail: length-scaled threshold, not a similarity score.
    static func isNearMatch(_ first: String, _ second: String) -> Bool {
        let longest = max(first.count, second.count)
        let allowed = longest >= 14 ? 2 : (longest >= 10 ? 1 : 0)
        guard allowed > 0, abs(first.count - second.count) <= allowed else { return false }
        return editDistance(first, second, stoppingAbove: allowed) <= allowed
    }

    /// Levenshtein distance, abandoned early once every path already costs
    /// more than `stoppingAbove` — the answer is only ever compared against
    /// that limit, so an exact distance beyond it is wasted work.
    private static func editDistance(_ first: String, _ second: String, stoppingAbove limit: Int) -> Int {
        let first = Array(first), second = Array(second)
        guard !first.isEmpty, !second.isEmpty else { return max(first.count, second.count) }

        var previous = Array(0...second.count)
        for row in 1...first.count {
            var current = [row] + Array(repeating: 0, count: second.count)
            for column in 1...second.count {
                current[column] = first[row - 1] == second[column - 1]
                    ? previous[column - 1]
                    : min(previous[column - 1], previous[column], current[column - 1]) + 1
            }
            if current.min()! > limit { return limit + 1 }
            previous = current
        }
        return previous[second.count]
    }

    /// Drops a standalone run of six or more digits — the download/store ID
    /// a shop or ripper glues into a filename ("Archigram - Doggystyle_1318768774
    /// - Crydamoure 2" → "Archigram - Doggystyle - Crydamoure 2"). No provider
    /// indexes it, so leaving it in turns a findable title into zero results.
    ///
    /// Six is the threshold so real numbers in titles survive: years ("1999"),
    /// track numbers, "20000 Leagues", "Blink 182". A separator left dangling
    /// by the removal is cleaned up with it, and a title that is *nothing but*
    /// an ID is kept as-is rather than emptied.
    /// ponytail: length heuristic; a genuine six-digit title would lose it.
    static func strippingIdentifierNumber(from title: String) -> String {
        guard title.range(of: #"\d{6,}"#, options: .regularExpression) != nil else { return title }
        let stripped = title
            .replacingOccurrences(of: #"\d{6,}"#, with: "", options: .regularExpression)
            // "Title -  - Mix" (both sides of a removed ID) collapses to one dash.
            .replacingOccurrences(of: #"-[\s_]*-"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
        return stripped.isEmpty ? title : stripped
    }

    /// Drops the last " - " segment of a track title — "Doggystyle -
    /// Crydamoure 2" → "Doggystyle" — for a fallback search once the full
    /// title has found nothing. Filenames routinely carry a label, catalogue
    /// number or compilation name after the title, and no provider indexes
    /// those as part of the track. Returns nil when there's nothing to drop,
    /// so callers know not to repeat the same request.
    ///
    /// Only ever a fallback: a title that genuinely contains " - "
    /// ("Track - Reprise") is searched in full first, and this tier runs
    /// only when that found nothing at all.
    static func strippingTrailingDashSegment(from trackTitle: String) -> String? {
        guard let range = trackTitle.range(of: " - ", options: .backwards) else { return nil }
        let stripped = String(trackTitle[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Drops a trailing scene release-group tag — "live fast-die young-gem"
    /// → "live fast-die young". Only for all-lowercase names (how scene rips
    /// are named), so a real title ending in "-Z" or "-Mix" is left alone.
    /// ponytail: heuristic; a lowercase title really ending in "-abc" would lose it.
    static func strippingSceneGroupTag(from title: String) -> String {
        guard title == title.lowercased(),
              let range = title.range(of: #"-[a-z0-9]{2,6}$"#, options: .regularExpression)
        else { return title }
        let stripped = title.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? title : stripped
    }

    /// Drops a featured-artist credit — "(feat. Jonell)", "[ft. X]", or a bare
    /// " featuring X" before any mix parenthetical. Discogs and MusicBrainz
    /// credit featured artists separately, never in the track title, so
    /// leaving it in turns a findable title into zero results. Mix names
    /// like "(Funk Vocal Version)" are kept — they pin the pressing.
    static func strippingFeaturedArtist(from title: String) -> String {
        // Outside brackets the dot (or "featuring") is required, so a real
        // title like "The Feat Of Clay" is left alone.
        // Accented spellings happen in the wild ("(féat. Dyme)").
        let feat = #"f[eéèê]at"#
        let bracketedCredit = #"(?:"# + feat + #"\.?|ft\.?|"# + feat + #"uring)\s"#
        let bareCredit = #"(?:"# + feat + #"\.|ft\.|"# + feat + #"uring)\s"#
        return title
            .replacingOccurrences(of: #"\s*[\(\[]\s*"# + bracketedCredit + #"[^\)\]]*[\)\]]"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"# + bareCredit + #"[^\(\[]*"#, with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips a single trailing parenthetical — "Pacific 0101 (Remix Edit)"
    /// → "Pacific 0101" — for a fallback search when the full title
    /// (including a mix/edit name) returns zero results. Returns nil when
    /// there's nothing to strip, so callers know not to retry.
    static func strippingTrailingParenthetical(from trackTitle: String) -> String? {
        guard let range = trackTitle.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) else {
            return nil
        }
        let stripped = trackTitle.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Strips a trailing disc/CD marker — "(CD-1)", "(CD1)", "(CD 2)",
    /// "[Disc 1]", "(Disk 2)" and similar — from an album/release search
    /// term. Discogs (and MusicBrainz) title a multi-disc release once and
    /// describe the discs in separate format/media metadata; the disc
    /// number is never part of the release title itself, so leaving it in
    /// the search term finds nothing (confirmed against the live Discogs
    /// API: "Maxi Power Best Of 94 (CD-1)" → 0 results, "Maxi Power Best Of
    /// 94" → 2 results, the correct release, first).
    ///
    /// Deliberately narrow — only ever strips an explicit CD/Disc/Disk
    /// marker. "Vol. 1", "Volume 2", "Part 2" are left alone: those are
    /// genuinely part of some compilations' titles (e.g. this library's
    /// "100% DJ Hits '97 Vol. 1"), and stripping them would break searches
    /// that currently work.
    ///
    /// Only ever changes the *search term* returned here — never the
    /// file's Album tag or its folder name, neither of which this function
    /// touches.
    /// Strips trailing release-format markers someone typed into an Album
    /// tag — "(CDM)", "[CDS]", "(Maxi-Single)", "(EP)", "(Promo)", "(12")",
    /// iTunes-style " - Single" — since Discogs/MusicBrainz keep the format
    /// separately, never in the title. Only format words: "(Remixes)" or
    /// "(Deluxe Edition)" are real title parts and stay. Returns nil when
    /// there's nothing to strip (or stripping would leave nothing).
    static func strippingFormatSuffix(from album: String?) -> String? {
        guard let album else { return nil }
        let pattern = #"(?:\s*[\(\[]\s*(?:CDM|CDS|CD[\s-]*(?:Maxi|Single)(?:[\s-]*Single)?|Maxi(?:[\s-]*Single)?|Single|EP|Promo|Vinyl|\d{1,2}\s*(?:"|''|-?inch))\s*[\)\]]|\s+-\s+(?:Single|EP))\s*$"#
        var result = album.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result.isEmpty || result == album ? nil : result
    }

    static func strippingDiscAnnotation(from term: String) -> String {
        let pattern = #"\s*[\(\[]\s*(?:CD|Disc|Disk)\s*-?\s*\d+\s*[\)\]]\s*$"#
        guard let range = term.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return term
        }
        return term.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
