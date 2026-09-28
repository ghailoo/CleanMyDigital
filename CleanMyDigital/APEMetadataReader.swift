//
//  APEMetadataReader.swift
//  CleanMyDigital
//

import Foundation

/// Reads a Monkey's Audio (.ape) file's trailing APEv2 tag and its header —
/// the same shape `WavPackMetadataReader` returns, since both formats carry
/// APEv2 tags and neither can be opened by AVFoundation.
enum APEMetadataReader {
    struct Result {
        var metadata = NativeAudioMetadata()
        var duration: TimeInterval?
        var bitrateKbps: Int?
    }

    static func read(contentsOf url: URL) throws -> Result {
        let bytes = [UInt8](try Data(contentsOf: url))
        let header = try APEStream.parseHeader(in: bytes)
        let located = try APEv2Tag.locate(in: bytes)

        var result = Result()
        if let located {
            APEv2TagBuilder.fill(&result.metadata, from: located.items)
        }

        // Monkey's Audio advertises a compression level, not a bitrate, so
        // this is the same "compressed bytes ÷ duration" average the
        // WavPack reader uses. The audio runs from the start of the file
        // to wherever the tag begins.
        if let duration = header.duration, duration > 0 {
            result.duration = duration
            let audioEnd = located?.range.lowerBound ?? APEv2Tag.trailingID3v1Range(in: bytes)?.lowerBound ?? bytes.count
            result.bitrateKbps = Int((Double(audioEnd) * 8 / duration / 1000).rounded())
        }

        return result
    }
}
