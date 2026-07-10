//
//  ArtworkDownloader.swift
//  CleanMyDigital
//

import AppKit
import Foundation

/// Downloads a candidate's cover image and re-encodes it as JPEG, since
/// that's what every tag writer expects — the source could be a PNG (common
/// on the Cover Art Archive) and embedding it mislabeled as JPEG would
/// corrupt the artwork.
enum ArtworkDownloader {
    static func downloadJPEG(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TagWriteError.underlying(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw TagWriteError.underlying(CocoaError(.fileReadUnknown))
        }
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else {
            throw TagWriteError.underlying(CocoaError(.fileReadCorruptFile))
        }
        return jpeg
    }
}
