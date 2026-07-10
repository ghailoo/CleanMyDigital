//
//  AIFFStream.swift
//  CleanMyDigital
//

import Foundation

/// A parsed AIFF/AIFC chunk: 4-character ASCII ID plus its raw data (the
/// trailing pad byte for odd-length chunks is not included).
struct AIFFChunk {
    let id: String
    let data: [UInt8]
}

/// Low-level AIFF parsing, mirroring `RIFFStream` but for IFF's big-endian
/// layout: "FORM" + 4-byte big-endian size + form type ("AIFF" or "AIFC"),
/// then a sequence of chunks (4-byte ID, 4-byte big-endian size, data,
/// padded to an even length with one zero byte when the size is odd — the
/// pad byte is not counted in the size field). Every integer here is
/// big-endian, the opposite of WAV/RIFF, so this intentionally doesn't
/// share code with `RIFFStream`.
enum AIFFStream {
    static func parseChunks(in bytes: [UInt8]) throws -> (formType: String, chunks: [AIFFChunk]) {
        guard bytes.count >= 12,
              bytes[0] == 0x46, bytes[1] == 0x4F, bytes[2] == 0x52, bytes[3] == 0x4D // "FORM"
        else {
            throw TagWriteError.malformedFile("Missing FORM signature")
        }
        let formType = String(decoding: bytes[8..<12], as: UTF8.self)
        guard formType == "AIFF" || formType == "AIFC" else {
            throw TagWriteError.malformedFile("Not an AIFF/AIFC file")
        }

        var chunks: [AIFFChunk] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
            let size = Int(bytes[offset + 4]) << 24 | Int(bytes[offset + 5]) << 16
                | Int(bytes[offset + 6]) << 8 | Int(bytes[offset + 7])
            let dataStart = offset + 8
            let dataEnd = dataStart + size
            guard size >= 0, dataEnd <= bytes.count else {
                throw TagWriteError.malformedFile("Truncated AIFF chunk")
            }
            chunks.append(AIFFChunk(id: id, data: Array(bytes[dataStart..<dataEnd])))
            offset = dataEnd + (size % 2 == 1 ? 1 : 0)
        }
        return (formType, chunks)
    }

    /// Reassembles a full FORM/AIFF(C) file from `chunks`, preserving the
    /// original form type and recomputing the top-level FORM size.
    static func buildFile(chunks: [AIFFChunk], formType: String) -> Data {
        var body = [UInt8]()
        for chunk in chunks {
            body.append(contentsOf: fourCC(chunk.id))
            appendUInt32BE(chunk.data.count, to: &body)
            body.append(contentsOf: chunk.data)
            if chunk.data.count % 2 == 1 { body.append(0) }
        }

        var output = [UInt8]()
        output.append(contentsOf: Array("FORM".utf8))
        appendUInt32BE(4 + body.count, to: &output) // form type + chunks
        output.append(contentsOf: Array(formType.utf8))
        output.append(contentsOf: body)
        return Data(output)
    }

    static func isID3Chunk(_ chunk: AIFFChunk) -> Bool {
        chunk.id.trimmingCharacters(in: .whitespaces).uppercased() == "ID3"
    }

    /// Pads/truncates a chunk ID to exactly 4 ASCII bytes.
    static func fourCC(_ id: String) -> [UInt8] {
        var bytes = Array(id.utf8.prefix(4))
        while bytes.count < 4 { bytes.append(0x20) } // space-pad
        return bytes
    }

    static func appendUInt32BE(_ value: Int, to bytes: inout [UInt8]) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }
}
