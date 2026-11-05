//
//  ID3TagBuilder.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Builds an ID3v2.3 `ID3Tag` from `TagChanges`, merged onto whatever frames
/// an existing tag already has. Shared by `MP3TagWriter` (which owns the
/// whole MP3 file) and `WAVTagWriter` (which embeds the resulting tag bytes
/// in an "id3 " RIFF chunk).
///
/// ID3TagEditor's `write(tag:mp3:)` replaces the *entire* tag with whatever
/// frames are in the `ID3Tag` you hand it — it does not merge with what's
/// already there. So every existing frame is first re-applied onto a fresh
/// v2.3 builder before adding our own fields, and only the ones the file
/// doesn't already have.
enum ID3TagBuilder {
    static func build(changes: TagChanges, existing: ID3Tag?) -> ID3Tag {
        let builder = ID32v3TagBuilder()
        let existingFrames = existing?.frames ?? [:]
        for (name, frame) in existingFrames {
            preserve(name: name, frame: frame, on: builder)
        }

        func isNew(_ name: FrameName) -> Bool { existingFrames[name] == nil }

        if let title = changes.title, isNew(.title) || changes.replaces(.title) {
            _ = builder.title(frame: ID3FrameWithStringContent(content: title))
        }
        if let artist = changes.artist, isNew(.artist) || changes.replaces(.artist) {
            _ = builder.artist(frame: ID3FrameWithStringContent(content: artist))
        }
        // Re-setting the frame replaces the preserved one on the builder.
        if let album = changes.album, isNew(.album) || changes.replaces(.album) {
            _ = builder.album(frame: ID3FrameWithStringContent(content: album))
        }
        if let year = changes.year, isNew(.recordingYear) || changes.replaces(.year),
           let yearValue = Int(year.trimmingCharacters(in: .whitespaces)) {
            _ = builder.recordingYear(frame: ID3FrameWithIntegerContent(value: yearValue))
        }
        if let genre = changes.genre, isNew(.genre) || changes.replaces(.genre) {
            _ = builder.genre(frame: ID3FrameGenre(genre: nil, description: genre))
        }
        if let trackNumber = changes.trackNumber, isNew(.trackPosition) || changes.replaces(.trackNumber) {
            let (part, total) = TagWriteHelpers.parseTrackPosition(trackNumber)
            _ = builder.trackPosition(frame: ID3FramePartOfTotal(part: part, total: total))
        }
        if let grouping = changes.grouping, isNew(.contentGrouping) || changes.replaces(.grouping) {
            _ = builder.contentGrouping(frame: ID3FrameWithStringContent(content: grouping))
        }
        if let artworkJPEG = changes.artworkJPEG, isNew(.attachedPicture(.frontCover)) {
            _ = builder.attachedPicture(
                pictureType: .frontCover,
                frame: ID3FrameAttachedPicture(picture: artworkJPEG, type: .frontCover, format: .jpeg))
        }

        return builder.build()
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func preserve(name: FrameName, frame: ID3Frame, on builder: ID32v3TagBuilder) {
        switch name {
        case .title:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.title(frame: f) }
        case .album:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.album(frame: f) }
        case .albumArtist:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.albumArtist(frame: f) }
        case .artist:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.artist(frame: f) }
        case .composer:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.composer(frame: f) }
        case .conductor:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.conductor(frame: f) }
        case .contentGrouping:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.contentGrouping(frame: f) }
        case .copyright:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.copyright(frame: f) }
        case .encodedBy:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.encodedBy(frame: f) }
        case .encoderSettings:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.encoderSettings(frame: f) }
        case .fileOwner:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.fileOwner(frame: f) }
        case .lyricist:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.lyricist(frame: f) }
        case .mixArtist:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.mixArtist(frame: f) }
        case .publisher:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.publisher(frame: f) }
        case .subtitle:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.subtitle(frame: f) }
        case .beatsPerMinute:
            if let f = frame as? ID3FrameWithIntegerContent { _ = builder.beatsPerMinute(frame: f) }
        case .originalFilename:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.originalFilename(frame: f) }
        case .lengthInMilliseconds:
            if let f = frame as? ID3FrameWithIntegerContent { _ = builder.lengthInMilliseconds(frame: f) }
        case .sizeInBytes:
            if let f = frame as? ID3FrameWithIntegerContent { _ = builder.sizeInBytes(frame: f) }
        case .genre:
            if let f = frame as? ID3FrameGenre { _ = builder.genre(frame: f) }
        case .discPosition:
            if let f = frame as? ID3FramePartOfTotal { _ = builder.discPosition(frame: f) }
        case .trackPosition:
            if let f = frame as? ID3FramePartOfTotal { _ = builder.trackPosition(frame: f) }
        case .initialKey:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.initialKey(frame: f) }
        case .recordingDayMonth:
            if let f = frame as? ID3FrameRecordingDayMonth { _ = builder.recordingDayMonth(frame: f) }
        case .recordingYear:
            if let f = frame as? ID3FrameWithIntegerContent { _ = builder.recordingYear(frame: f) }
        case .recordingHourMinute:
            if let f = frame as? ID3FrameRecordingHourMinute { _ = builder.recordingHourMinute(frame: f) }
        case .recordingDateTime:
            // v2.4-only frame with no v2.3 equivalent — decompose into the
            // separate day/month, hour/minute, and year frames v2.3 uses.
            if let f = frame as? ID3FrameRecordingDateTime {
                let dateTime = f.recordingDateTime
                if dateTime.date?.day != nil || dateTime.date?.month != nil {
                    _ = builder.recordingDayMonth(
                        frame: ID3FrameRecordingDayMonth(day: dateTime.date?.day, month: dateTime.date?.month))
                }
                if dateTime.time?.hour != nil || dateTime.time?.minute != nil {
                    _ = builder.recordingHourMinute(
                        frame: ID3FrameRecordingHourMinute(hour: dateTime.time?.hour, minute: dateTime.time?.minute))
                }
                if let year = dateTime.date?.year {
                    _ = builder.recordingYear(frame: ID3FrameWithIntegerContent(value: year))
                }
            }
        case .attachedPicture(let pictureType):
            if let f = frame as? ID3FrameAttachedPicture {
                _ = builder.attachedPicture(pictureType: pictureType, frame: f)
            }
        case .unsynchronizedLyrics(let language):
            if let f = frame as? ID3FrameWithLocalizedContent {
                _ = builder.unsynchronisedLyrics(language: language, frame: f)
            }
        case .comment(let language):
            if let f = frame as? ID3FrameWithLocalizedContent { _ = builder.comment(language: language, frame: f) }
        case .iTunesGrouping:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.iTunesGrouping(frame: f) }
        case .iTunesMovementName:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.iTunesMovementName(frame: f) }
        case .iTunesMovementIndex:
            if let f = frame as? ID3FrameWithIntegerContent { _ = builder.iTunesMovementIndex(frame: f) }
        case .iTunesMovementCount:
            if let f = frame as? ID3FrameWithIntegerContent { _ = builder.iTunesMovementCount(frame: f) }
        case .iTunesPodcastCategory:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.iTunesPodcastCategory(frame: f) }
        case .iTunesPodcastDescription:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.iTunesPodcastDescription(frame: f) }
        case .iTunesPodcastID:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.iTunesPodcastID(frame: f) }
        case .iTunesPodcastKeywords:
            if let f = frame as? ID3FrameWithStringContent { _ = builder.iTunesPodcastKeywords(frame: f) }
        }
    }
}
