//
//  DSFMetadataReader.swift
//  CleanMyDigital
//

import Foundation

/// Reads a DSF (DSD Stream File)'s embedded ID3v2 tag, plus the stream
/// shape info (`fmt` chunk) needed to compute duration/bitrate — natively,
/// since AVFoundation cannot open DSF at all (confirmed empirically:
/// `AVURLAsset.load(.commonMetadata)` throws `AVFoundationErrorDomain`
/// code -11828, "file format not recognized", for every DSF file, not just
/// unusual ones). Unlike `FLACMetadataReader`/`RIFFMetadataReader`/
/// `AIFFMetadataReader` — which only supplement whatever AVFoundation
/// already found — this is DSF's *only* source of metadata and playback
/// info; there's no AVFoundation reading to fall back to or merge with.
enum DSFMetadataReader {
    struct Result {
        var metadata = NativeAudioMetadata()
        var duration: TimeInterval?
        var bitrateKbps: Int?
    }

    static func read(contentsOf url: URL) throws -> Result {
        let bytes = [UInt8](try Data(contentsOf: url))
        let header = try DSFStream.parseHeader(in: bytes)
        let format = try DSFStream.parseFormatInfo(in: bytes)

        // No `audioDataSize` to populate here — that field only feeds
        // `LibraryScanner`'s AVAssetTrack-based bitrate fallback, which
        // doesn't apply to DSF at all (no AVFoundation asset exists);
        // `bitrateKbps` below is computed directly from the fmt chunk.
        var result = Result()

        if let pointer = header.metadataPointer, pointer < bytes.count {
            let id3ChunkData = Array(bytes[pointer...])
            ID3ChunkMetadata.merge(id3ChunkData: id3ChunkData, into: &result.metadata)
        }

        if format.samplingFrequency > 0 {
            result.duration = Double(format.sampleCount) / Double(format.samplingFrequency)
        }
        if format.samplingFrequency > 0, format.bitsPerSample > 0, format.channelNum > 0 {
            let rawBitsPerSecond = Double(format.samplingFrequency) * Double(format.bitsPerSample) * Double(format.channelNum)
            result.bitrateKbps = Int((rawBitsPerSecond / 1000).rounded())
        }

        return result
    }
}
