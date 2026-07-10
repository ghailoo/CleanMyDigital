# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CleanMyDigital is a macOS SwiftUI app that scans a folder of audio files and reports which
ones are missing metadata (title, artist, album, artwork). Single-window, no persistence —
every launch starts from the empty state and the user picks a folder to scan.

## Build & test

This is a standard Xcode project (no SPM package, no external dependencies). Use `xcodebuild`
from the repo root:

```bash
# Build
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' build

# Run unit + UI tests
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' test

# Run a single test (Swift Testing)
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' \
  test -only-testing:CleanMyDigitalTests/CleanMyDigitalTests/example

# Run a single UI test (XCTest)
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' \
  test -only-testing:CleanMyDigitalUITests/CleanMyDigitalUITests/testExample
```

Or just open `CleanMyDigital.xcodeproj` in Xcode and use Cmd+B / Cmd+U.

- Unit tests (`CleanMyDigitalTests`) use the Swift Testing framework (`import Testing`, `@Test`, `#expect`).
- UI tests (`CleanMyDigitalUITests`) use XCTest and launch the full app via `XCUIApplication`.
- Both test targets are currently stubs (no real assertions yet).

## Architecture

Three source files, each with one job:

- **`LibraryScanner.swift`** — an `@Observable` class that owns all scan state (`state`,
  `files`, `scannedCount`/`totalCount`, `scannedFolder`). `ContentView` reads this directly;
  there is no separate view model layer.
  - `scan(folder:)` runs in two phases: `.enumerating` (walk the directory tree off the main
    actor via `Task.detached`, filtering by extension) then `.scanning` (read metadata for
    each file with bounded concurrency — 8 at a time — via `withTaskGroup`).
  - Metadata reading (`inspect(_:)`) uses `AVURLAsset` and merges `commonMetadata` with every
    format-specific metadata block (ID3, iTunes, etc.) so tags AVFoundation doesn't normalize
    to "common" identifiers are still picked up by matching raw keys (e.g. `TIT2`, `©nam`).
  - `supportedExtensions` are formats AVFoundation can actually open. `unsupportedAudioExtensions`
    (ogg, wma, ape, …) are recognized-but-unreadable formats — they still show up in results,
    flagged as unreadable, rather than being silently skipped.
  - The folder is accessed via a security-scoped bookmark (`startAccessingSecurityScopedResource`)
    since the app is sandboxed with no persisted file-access entitlement — access only lasts for
    the duration of one scan.

- **`AudioFile.swift`** — the plain `Sendable` result struct for one scanned file, plus the
  derived logic for what counts as "missing": `missingFields`, `hasIssues`, `hasNoMetadata`.
  This is where the rules for what makes a file "complete" live — change them here, not in the view.

- **`ContentView.swift`** — single SwiftUI view driven entirely by `scanner.state`
  (`.idle` → `.enumerating`/`.scanning` → `.finished`), plus local `@State` for filter, search
  text, sort order, and table selection. Filtering/searching/sorting of `scanner.files` happens
  in the `filteredFiles` computed property, not in the scanner. The results `Table` view and the
  "Copy Report" clipboard action both key off `AudioFile.hasIssues` / `missingFields`.

There's no networking, persistence, or external dependencies — everything is local file/AVFoundation
work plus SwiftUI state.
