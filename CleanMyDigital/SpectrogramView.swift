//
//  SpectrogramView.swift
//  CleanMyDigital
//

import AppKit
import SwiftUI

/// A small spectrogram of one track, like Spectro's — time left to right,
/// frequency bottom to top, with the measured cutoff as a dashed line.
/// Decoded on demand for the selected file only; nothing is cached.
struct SpectrogramView: View {
    let url: URL
    let root: URL?
    let cutoffHz: Double?

    @State private var rendered: (image: CGImage, nyquistHz: Double)?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black)
            if let rendered {
                Image(decorative: rendered.image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                if let cutoffHz, cutoffHz < rendered.nyquistHz {
                    GeometryReader { geo in
                        let y = geo.size.height * (1 - cutoffHz / rendered.nyquistHz)
                        Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: geo.size.width, y: y)) }
                            .stroke(.green, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text(String(format: "%.1f kHz", cutoffHz / 1000))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(.black.opacity(0.6))
                            .position(x: geo.size.width - 30, y: max(8, y - 8))
                    }
                }
                Text(String(format: "%.0f kHz", rendered.nyquistHz / 1000))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(3)
            } else if failed {
                Text("Couldn't draw spectrogram").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cutoffHz.map { String(format: "Spectrogram, cutoff %.1f kilohertz", $0 / 1000) } ?? "Spectrogram")
        .task(id: url) {
            rendered = nil
            failed = false
            rendered = await Self.render(url: url, root: root)
            failed = rendered == nil
        }
    }

    @concurrent private static func render(url: URL, root: URL?) async -> (image: CGImage, nyquistHz: Double)? {
        let accessed = root?.startAccessingSecurityScopedResource() ?? false
        defer { if accessed { root?.stopAccessingSecurityScopedResource() } }
        guard let (samples, rate) = try? await SpectralCutoffReader.decodeMono(url: url) else { return nil }
        let columns = SpectralCutoffAnalyzer.spectrogram(samples: samples, columns: 360, rows: 128)
        guard let image = image(columns) else { return nil }
        return (image, rate / 2)
    }

    /// Black → purple → red → orange → yellow-white, Spectro-style.
    private static let palette: [(Double, Double, Double)] = [
        (0, 0, 0), (0.23, 0.06, 0.44), (0.71, 0.21, 0.47), (0.98, 0.53, 0.25), (0.99, 0.99, 0.75),
    ]

    nonisolated private static func color(_ dB: Float) -> (UInt8, UInt8, UInt8) {
        let t = Double(min(max((dB + 120) / 120, 0), 1)) * Double(palette.count - 1)
        let i = min(Int(t), palette.count - 2), f = t - Double(i)
        let (a, b) = (palette[i], palette[i + 1])
        func mix(_ x: Double, _ y: Double) -> UInt8 { UInt8((x + (y - x) * f) * 255) }
        return (mix(a.0, b.0), mix(a.1, b.1), mix(a.2, b.2))
    }

    nonisolated private static func image(_ columns: [[Float]]) -> CGImage? {
        guard let rows = columns.first?.count, rows > 0 else { return nil }
        let width = columns.count
        var pixels = [UInt8](repeating: 255, count: width * rows * 4)
        for (x, column) in columns.enumerated() {
            for (row, dB) in column.enumerated() {
                let offset = ((rows - 1 - row) * width + x) * 4
                (pixels[offset], pixels[offset + 1], pixels[offset + 2]) = color(dB)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
