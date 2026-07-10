//
//  RIFFStream.swift
//  CleanMyDigital
//

import Foundation

/// A parsed RIFF chunk: 4-character ASCII ID plus its raw data (the
/// trailing pad byte for odd-length chunks is not included).
struct RIFFChunk {
    let id: String
    let data: [UInt8]
}

/// Low-level RIFF/WAVE parsing shared by `WAVTagWriter` (writing) and
/// `RIFFMetadataReader` (scanning).
///
/// WAV layout: "RIFF" + 4-byte little-endian size + "WAVE", then a sequence
/// of chunks (4-byte ID, 4-byte little-endian size, data, padded to an even
/// length with one zero byte when the size is odd — the pad byte is not
/// counted in the size field).
enum RIFFStream {
    static func parseChunks(in bytes: [UInt8]) throws -> [RIFFChunk] {
        guard bytes.count >= 12,
              bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46, // "RIFF"
              bytes[8] == 0x57, bytes[9] == 0x41, bytes[10] == 0x56, bytes[11] == 0x45 // "WAVE"
        else {
            throw TagWriteError.malformedFile("Missing RIFF/WAVE signature")
        }

        var chunks: [RIFFChunk] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
            let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
                | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
            let dataStart = offset + 8
            let dataEnd = dataStart + size
            guard size >= 0, dataEnd <= bytes.count else {
                throw TagWriteError.malformedFile("Truncated RIFF chunk")
            }
            chunks.append(RIFFChunk(id: id, data: Array(bytes[dataStart..<dataEnd])))
            offset = dataEnd + (size % 2 == 1 ? 1 : 0)
        }
        return chunks
    }

    /// Reassembles a full RIFF/WAVE file from `chunks`, recomputing the
    /// top-level RIFF size header.
    static func buildFile(chunks: [RIFFChunk]) -> Data {
        var body = [UInt8]()
        for chunk in chunks {
            body.append(contentsOf: fourCC(chunk.id))
            appendUInt32LE(chunk.data.count, to: &body)
            body.append(contentsOf: chunk.data)
            if chunk.data.count % 2 == 1 { body.append(0) }
        }

        var output = [UInt8]()
        output.append(contentsOf: Array("RIFF".utf8))
        appendUInt32LE(4 + body.count, to: &output) // "WAVE" + chunks
        output.append(contentsOf: Array("WAVE".utf8))
        output.append(contentsOf: body)
        return Data(output)
    }

    /// Pads/truncates a chunk ID to exactly 4 ASCII bytes, per the FourCC
    /// convention (e.g. "id3 " has a trailing space).
    static func fourCC(_ id: String) -> [UInt8] {
        var bytes = Array(id.utf8.prefix(4))
        while bytes.count < 4 { bytes.append(0x20) } // space-pad
        return bytes
    }

    static func appendUInt32LE(_ value: Int, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }

    // MARK: - LIST/INFO and "id3 " chunk identification

    static func isListInfoChunk(_ chunk: RIFFChunk) -> Bool {
        chunk.id.uppercased() == "LIST" && chunk.data.count >= 4
            && String(decoding: chunk.data[0..<4], as: UTF8.self).uppercased() == "INFO"
    }

    static func isID3Chunk(_ chunk: RIFFChunk) -> Bool {
        chunk.id.trimmingCharacters(in: .whitespaces).lowercased() == "id3"
    }

    /// Parses a LIST/INFO chunk's sub-chunks (4-char ID + NUL-terminated
    /// string value each), skipping the leading "INFO" list-type tag.
    static func parseListInfoFields(_ data: [UInt8]) -> [(id: String, value: String)] {
        guard data.count > 4 else { return [] }
        var fields: [(id: String, value: String)] = []
        var offset = 4
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let size = Int(data[offset + 4]) | Int(data[offset + 5]) << 8
                | Int(data[offset + 6]) << 16 | Int(data[offset + 7]) << 24
            let dataStart = offset + 8
            let dataEnd = dataStart + size
            guard size >= 0, dataEnd <= data.count else { break }
            var valueBytes = Array(data[dataStart..<dataEnd])
            while let last = valueBytes.last, last == 0 { valueBytes.removeLast() }
            if let value = String(bytes: valueBytes, encoding: .utf8) {
                fields.append((id: id, value: value))
            }
            offset = dataEnd + (size % 2 == 1 ? 1 : 0)
        }
        return fields
    }
}
