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

        if let title = changes.title, isNew(.title) {
            builder.title(frame: ID3FrameWithStringContent(content: title))
        }
        if let artist = changes.artist, isNew(.artist) {
            builder.artist(frame: ID3FrameWithStringContent(content: artist))
        }
        if let album = changes.album, isNew(.album) {
            builder.album(frame: ID3FrameWithStringContent(content: album))
        }
        if let year = changes.year, isNew(.recordingYear),
           let yearValue = Int(year.trimmingCharacters(in: .whitespaces)) {
            builder.recordingYear(frame: ID3FrameWithIntegerContent(value: yearValue))
        }
        if let genre = changes.genre, isNew(.genre) {
            builder.genre(frame: ID3FrameGenre(genre: nil, description: genre))
        }
        if let trackNumber = changes.trackNumber, isNew(.trackPosition) {
            let (part, total) = TagWriteHelpers.parseTrackPosition(trackNumber)
            builder.trackPosition(frame: ID3FramePartOfTotal(part: part, total: total))
        }
        if let artworkJPEG = changes.artworkJPEG, isNew(.attachedPicture(.frontCover)) {
            builder.attachedPicture(
                pictureType: .frontCover,
                frame: ID3FrameAttachedPicture(picture: artworkJPEG, type: .frontCover, format: .jpeg))
        }

        return builder.build()
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func preserve(name: FrameName, frame: ID3Frame, on builder: ID32v3TagBuilder) {
        switch name {
        case .title:
            if let f = frame as? ID3FrameWithStringContent { builder.title(frame: f) }
        case .album:
            if let f = frame as? ID3FrameWithStringContent { builder.album(frame: f) }
        case .albumArtist:
            if let f = frame as? ID3FrameWithStringContent { builder.albumArtist(frame: f) }
        case .artist:
            if let f = frame as? ID3FrameWithStringContent { builder.artist(frame: f) }
        case .composer:
            if let f = frame as? ID3FrameWithStringContent { builder.composer(frame: f) }
        case .conductor:
            if let f = frame as? ID3FrameWithStringContent { builder.conductor(frame: f) }
        case .contentGrouping:
            if let f = frame as? ID3FrameWithStringContent { builder.contentGrouping(frame: f) }
        case .copyright:
            if let f = frame as? ID3FrameWithStringContent { builder.copyright(frame: f) }
        case .encodedBy:
            if let f = frame as? ID3FrameWithStringContent { builder.encodedBy(frame: f) }
        case .encoderSettings:
            if let f = frame as? ID3FrameWithStringContent { builder.encoderSettings(frame: f) }
        case .fileOwner:
            if let f = frame as? ID3FrameWithStringContent { builder.fileOwner(frame: f) }
        case .lyricist:
            if let f = frame as? ID3FrameWithStringContent { builder.lyricist(frame: f) }
        case .mixArtist:
            if let f = frame as? ID3FrameWithStringContent { builder.mixArtist(frame: f) }
        case .publisher:
            if let f = frame as? ID3FrameWithStringContent { builder.publisher(frame: f) }
        case .subtitle:
            if let f = frame as? ID3FrameWithStringContent { builder.subtitle(frame: f) }
        case .beatsPerMinute:
            if let f = frame as? ID3FrameWithIntegerContent { builder.beatsPerMinute(frame: f) }
        case .originalFilename:
            if let f = frame as? ID3FrameWithStringContent { builder.originalFilename(frame: f) }
        case .lengthInMilliseconds:
            if let f = frame as? ID3FrameWithIntegerContent { builder.lengthInMilliseconds(frame: f) }
        case .sizeInBytes:
            if let f = frame as? ID3FrameWithIntegerContent { builder.sizeInBytes(frame: f) }
        case .genre:
            if let f = frame as? ID3FrameGenre { builder.genre(frame: f) }
        case .discPosition:
            if let f = frame as? ID3FramePartOfTotal { builder.discPosition(frame: f) }
        case .trackPosition:
            if let f = frame as? ID3FramePartOfTotal { builder.trackPosition(frame: f) }
        case .initialKey:
            if let f = frame as? ID3FrameWithStringContent { builder.initialKey(frame: f) }
        case .recordingDayMonth:
            if let f = frame as? ID3FrameRecordingDayMonth { builder.recordingDayMonth(frame: f) }
        case .recordingYear:
            if let f = frame as? ID3FrameWithIntegerContent { builder.recordingYear(frame: f) }
        case .recordingHourMinute:
            if let f = frame as? ID3FrameRecordingHourMinute { builder.recordingHourMinute(frame: f) }
        case .recordingDateTime:
            // v2.4-only frame with no v2.3 equivalent — decompose into the
            // separate day/month, hour/minute, and year frames v2.3 uses.
            if let f = frame as? ID3FrameRecordingDateTime {
                let dateTime = f.recordingDateTime
                if dateTime.date?.day != nil || dateTime.date?.month != nil {
                    builder.recordingDayMonth(
                        frame: ID3FrameRecordingDayMonth(day: dateTime.date?.day, month: dateTime.date?.month))
                }
                if dateTime.time?.hour != nil || dateTime.time?.minute != nil {
                    builder.recordingHourMinute(
                        frame: ID3FrameRecordingHourMinute(hour: dateTime.time?.hour, minute: dateTime.time?.minute))
                }
                if let year = dateTime.date?.year {
                    builder.recordingYear(frame: ID3FrameWithIntegerContent(value: year))
                }
            }
        case .attachedPicture(let pictureType):
            if let f = frame as? ID3FrameAttachedPicture {
                builder.attachedPicture(pictureType: pictureType, frame: f)
            }
        case .unsynchronizedLyrics(let language):
            if let f = frame as? ID3FrameWithLocalizedContent {
                builder.unsynchronisedLyrics(language: language, frame: f)
            }
        case .comment(let language):
            if let f = frame as? ID3FrameWithLocalizedContent { builder.comment(language: language, frame: f) }
        case .iTunesGrouping:
            if let f = frame as? ID3FrameWithStringContent { builder.iTunesGrouping(frame: f) }
        case .iTunesMovementName:
            if let f = frame as? ID3FrameWithStringContent { builder.iTunesMovementName(frame: f) }
        case .iTunesMovementIndex:
            if let f = frame as? ID3FrameWithIntegerContent { builder.iTunesMovementIndex(frame: f) }
        case .iTunesMovementCount:
            if let f = frame as? ID3FrameWithIntegerContent { builder.iTunesMovementCount(frame: f) }
        case .iTunesPodcastCategory:
            if let f = frame as? ID3FrameWithStringContent { builder.iTunesPodcastCategory(frame: f) }
        case .iTunesPodcastDescription:
            if let f = frame as? ID3FrameWithStringContent { builder.iTunesPodcastDescription(frame: f) }
        case .iTunesPodcastID:
            if let f = frame as? ID3FrameWithStringContent { builder.iTunesPodcastID(frame: f) }
        case .iTunesPodcastKeywords:
            if let f = frame as? ID3FrameWithStringContent { builder.iTunesPodcastKeywords(frame: f) }
        }
    }
}
