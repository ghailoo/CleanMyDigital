//
//  AudioPreview.swift
//  CleanMyDigital
//

import SwiftUI
import AVFoundation

/// Ear-checking a match before applying it — a preview, not a player: one
/// sound at a time app-wide (hence the shared instance, so a row in Apply
/// Found Matches and a row in the main table can't overlap), starting
/// `startFraction` into the file, since intros say nothing about which mix
/// it is. A file AVAudioPlayer can't decode (DSF, WavPack, APE, Ogg…) just
/// records a quiet per-file message for its row — never an alert.
@Observable
final class AudioPreview: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPreview()
    static let startFraction = 0.3

    private(set) var playingURL: URL?
    /// The last file previewed, playing or not — what Space toggles in a
    /// list with no single row selection (Apply Found Matches' cards).
    private(set) var lastURL: URL?
    private(set) var failures: [URL: String] = [:]

    private var player: AVAudioPlayer?
    /// The sandbox grant for the file's scanned root, held while playing —
    /// AVAudioPlayer reads from disk as it goes, not all up front.
    private var accessedRoot: URL?

    func toggle(_ url: URL, root: URL?) {
        if playingURL == url { stop() } else { play(url, root: root) }
    }

    func play(_ url: URL, root: URL?) {
        stop()
        lastURL = url
        if let root, root.startAccessingSecurityScopedResource() { accessedRoot = root }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.currentTime = player.duration * Self.startFraction
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            self.player = player
            playingURL = url
            failures[url] = nil
        } catch {
            failures[url] = "Can't preview this file"
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
        accessedRoot?.stopAccessingSecurityScopedResource()
        accessedRoot = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in
            if let current = self.player, ObjectIdentifier(current) == id { self.stop() }
        }
    }
}

/// The small play/stop control for one file row, plus that row's inline
/// "can't preview" note when decoding failed.
struct PreviewButton: View {
    let url: URL
    let root: URL?
    private var preview: AudioPreview { .shared }

    var body: some View {
        let isPlaying = preview.playingURL == url
        HStack(spacing: 4) {
            Button {
                preview.toggle(url, root: root)
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "Stop preview (Space)" : "Preview from 30% in (Space)")
            .accessibilityLabel(isPlaying ? "Stop preview" : "Preview audio")
            if let failure = preview.failures[url] {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
