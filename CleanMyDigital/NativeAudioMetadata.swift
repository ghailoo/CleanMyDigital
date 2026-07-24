//
//  NativeAudioMetadata.swift
//  CleanMyDigital
//

import Foundation

/// Metadata read directly from a file's own container format, bypassing
/// AVFoundation — used where AVFoundation's reading is incomplete or
/// unreliable (FLACs with a nonstandard ID3v2 prefix, WAV LIST/INFO
/// chunks). Shared shape for `FLACMetadataReader` and `RIFFMetadataReader`
/// so `LibraryScanner.inspect()` can merge either the same way.
struct NativeAudioMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var genre: String?
    var trackNumber: String?
    var artworkData: Data?
    /// The size, in bytes, of just the audio-sample data — excluding the
    /// container header and every metadata/tag/artwork chunk. Lets bitrate
    /// be computed accurately for formats where AVFoundation's own
    /// `AVAssetTrack.estimatedDataRate` comes back unavailable (FLAC, WAV).
    var audioDataSize: Int64?
}
