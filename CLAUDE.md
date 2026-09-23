# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CleanMyDigital is a macOS SwiftUI app for cleaning up a music library's metadata. The workflow
is scan → diagnose → fix: the user picks one or more folders (Singles, Albums, or Compilations),
the app reports which files are missing tags (title, artist, album, artwork, track number) or
have a mismatched artist folder, and from there the user can look up correct metadata online
(Discogs / MusicBrainz), write it back to the file's native tags, rename/collect/dedupe files,
and rename album folders. Single main window, plus five auxiliary windows for the batch-operation
workflows.

Scan results are not persisted — every launch starts from the empty state and the user re-picks a
folder. Discogs/MusicBrainz settings *do* persist (via `@AppStorage`/UserDefaults), and pre-write
backups of original files persist to disk (see Backup below).

## Build & test

Standard Xcode project. One SPM dependency (`ID3TagEditor`, for MP3/AIFF ID3v2.3 tag I/O) resolves
automatically on build. Use `xcodebuild` from the repo root:

```bash
# Build
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' build

# Run unit + UI tests
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' test

# Run one test file/case (Swift Testing)
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' \
  test -only-testing:CleanMyDigitalTests/FLACTagWriterTests

# Run a single UI test (XCTest)
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' \
  test -only-testing:CleanMyDigitalUITests/CleanMyDigitalUITests/testExample
```

Or open `CleanMyDigital.xcodeproj` in Xcode and use Cmd+B / Cmd+U.

- Unit tests (`CleanMyDigitalTests`) use the Swift Testing framework (`import Testing`, `@Test`,
  `#expect`) — ~30 real test files (tag writers, planners, scanner behavior, metadata query
  parsing, Discogs/MusicBrainz response handling, etc.). Only the Xcode-template file
  (`CleanMyDigitalTests.swift`) is still an empty stub.
- UI tests (`CleanMyDigitalUITests`) use XCTest and launch the full app via `XCUIApplication`;
  this target is still a stub.

## Architecture

### Core scanning/model layer

- **`LibraryScanner.swift`** — the single `@Observable` source of truth for scan state, tag
  writes, batch file operations, and online lookup/analysis jobs. Key pieces:
  - `scan(folders:category:artistOverride:)` scans one or several roots as one library (multiple
    roots are mainly for Singles, commonly one folder per artist); `root(containing:)` resolves any
    file back to whichever scanned root it came from. `reset()` returns to a pristine pre-scan state
    (used on category change) — distinct from a rescan, and the only thing that clears
    `albumCompletenessResults`.
  - `applyTagChanges(_:to:backupFirst:)` re-acquires security-scoped access, optionally backs up
    via `BackupManager`, dispatches to `TagWriterRouter`, then re-inspects the file and updates
    `files` in place.
  - `renameFiles`/`collectIntoFolders`/`moveDuplicates`/`renameAlbumFolders` apply planner-produced
    proposals via `FileManager`, all logging into one `lastRenameBatch` undo stack
    (`undoLastFileOperation`).
  - `findAllMetadata(discogsToken:musicBrainzContact:)` runs a cancellable batch lookup (Discogs
    first, MusicBrainz fallback) into `lookupResults: [URL: LookupOutcome]`.
  - `analyzeSpectrum()` runs a cancellable, bounded-concurrency spectral analysis batch into
    `spectralResults: [URL: SpectralCutoffOutcome]`.
  - `inspect(_:)` reads metadata per format: DSF/WavPack go through native readers only
    (AVFoundation can't open them); FLAC/WAV/AIFF combine AVFoundation with a native reader
    (`FLACMetadataReader`/`RIFFMetadataReader`/`AIFFMetadataReader`) wherever AVFoundation is
    incomplete or unreliable; everything else is AVFoundation-only.
  - The folder is accessed via a security-scoped bookmark since the app is sandboxed with no
    persisted file-access entitlement.

- **`AudioFile.swift`** — the plain `Sendable` result struct for one file, plus the derived rules
  for what's "missing" (`issues`, `hasIssues`, `hasNoMetadata`, `hasArtistMismatch`). This is where
  the completeness rules live — change them here, not in the view. `LibraryCategory` (Singles /
  Albums / Compilations) drives category-specific rules throughout the app (e.g. Singles skip
  Track Number; artist-folder checking only applies to Albums).

### Per-format audio I/O

No shared `TagWriter` protocol — each writable format is an independent enum with a static
`write(_:to:)`. **`TagWriter.swift`** defines the shared vocabulary: `TagChanges` (fields to
write), `TagWriteError`, `TagWriteHelpers` (atomic temp-file-then-swap), and `TagWriterRouter`
(dispatches by extension). Writable formats: FLAC, MP3, M4A, WAV, AIFF, DSF, WavPack.

Per-format trio: **Stream** (low-level chunk parser) → **MetadataReader** (builds a shared
`NativeAudioMetadata`) → **TagWriter** (rewrites the tag chunk, reassembling the rest of the file
byte-for-byte):

- **MP3** — no native reader (AVFoundation reads it); `MP3TagWriter` + `ID3TagBuilder` write
  ID3v2.3 via the `ID3TagEditor` package.
- **AIFF** — `AIFFStream`/`AIFFMetadataReader` (big-endian FORM chunks) +
  `AIFFTagWriter` (rewrites the "ID3 " chunk via `ID3ChunkMetadata`/`ID3TagBuilder`).
- **WAV** — `RIFFStream`/`RIFFMetadataReader` (little-endian RIFF) + `WAVTagWriter`.
- **FLAC** — `FLACStream`/`FLACMetadataReader` (METADATA_BLOCK chain, Vorbis comments, PICTURE
  block; tolerates a nonstandard prepended ID3v2 prefix) + `FLACTagWriter` (edits the block chain
  directly, no dependency).
- **DSF** — `DSFStream`/`DSFMetadataReader` (DSD chunks) + `DSFTagWriter` (rewrites an embedded
  ID3 tag, same `ID3ChunkMetadata` pattern as AIFF).
- **WavPack** — `WavPackStream`/`WavPackMetadataReader` (parses the leading "wvpk" block header
  only) + `WavPackTagWriter` (rewrites the trailing **APEv2** tag via `APEv2Tag`/
  `APEv2TagBuilder`, preserving an optional trailing ID3v1 block).
- **`NativeAudioMetadata.swift`** — the shared result struct every native reader returns, so
  `inspect()` can merge any of them uniformly, and so bitrate can fall back to a reader's
  `audioDataSize` when AVFoundation's own rate is unavailable.
- **`M4ATagWriter.swift`** is structurally different: no chunk editing — it re-exports via
  `AVAssetExportSession` (passthrough, no re-encode) with a merged `AVMetadataItem` list.

### Online metadata lookup

1. **`MetadataQuery.swift`** derives provider-agnostic search terms from a scanned file
   (category-aware artist/album/title cleanup).
2. **`DiscogsClient.swift`** — REST client for Discogs search/release-detail, rate-limited
   (~1 req/sec, actor-based) with 429 backoff and in-memory release-detail caching; tiered retry
   (full term → parenthetical-stripped → optional artist-only fallback).
3. **`MusicBrainzClient.swift`** — parallel client for MusicBrainz's recording search, same
   rate-limiting pattern, sends a required contact-email User-Agent.
4. **`LookupOutcome.swift`** — `MetadataProvider`, `LookupCandidate` (tagged union over either
   provider's result, with `buildChanges(fillable:)` turning a candidate into `TagChanges`), and
   `LookupOutcome` (`.found`/`.noMatch`) — what `LibraryScanner.lookupResults` stores per file.
5. **`ArtworkDownloader.swift`** downloads and re-encodes cover art to JPEG (writers expect JPEG;
   sources may serve PNG).
6. **`MatchComparisonBuilder.swift`** — pure, network-free — builds per-field current-vs-match
   comparisons for review UI, driven off `fillableFields` so the UI can't drift from what would
   actually be written. **`MetadataComparisonRow.swift`** is the shared row view for it.

Two consumption paths: automatic batch lookup (no review, `LibraryScanner.findAllMetadata`), and
interactive per-file/per-album search (`MetadataLookupView.swift` / `AlbumMetadataLookupView.swift`)
where the user picks a candidate before applying.

### Planners

Each is an enum of pure, filesystem-free, network-free static functions that turn scan state into
a list of proposals; a corresponding auxiliary window calls the planner `onAppear`, shows proposals
for selection, and Apply calls the matching `LibraryScanner` method to actually do the I/O.

- **`RenamePlanner`** — "Artist - Title" (with zero-padded track number for Albums/Compilations),
  per-folder collision-checked.
- **`CollectionPlanner`** — groups loose Singles into per-release subfolders.
- **`DuplicatePlanner`** — groups by Artist+Title, ranks by measured quality (spectral cutoff, else
  bitrate) to pick a keeper, plans moving extras into a `_CleanMyDigital Duplicates` review
  subfolder (never deletes).
- **`FoundMatchPlanner`** — groups a batch lookup's found matches by folder for review.
- **`AlbumFolderRenamePlanner`** — proposes "Album Title (Year)" folder names from an album's tags.
- **`AlbumCompletenessChecker`** — groups Albums/Compilations by folder into `AlbumGroup`,
  derives local completeness purely from stated track totals (no network). `AlbumGroup` is shared
  by several other planners/views.

### Backup

**`BackupManager.swift`** — before a file's tags are written for the first time in a session (and
only if "Back up originals before writing" is enabled in Settings), copies the original bytes
verbatim into a `_CleanMyDigital Backups` folder inside the scanned root (mirroring the relative
path) — chosen because it's inside the already-granted security scope. No-op if a backup already
exists there. A backup failure is a soft `TagWriteError.backupFailed`, not a thrown error — it
doesn't block the write.

### Lossy-transcode detection

- **`SpectralCutoffReader.swift`** decodes three representative windows of a track via
  `AVAssetReader` into mono Float32 PCM.
- **`SpectralCutoffAnalyzer.swift`** (pure, unit-testable) FFTs the samples (Accelerate/vDSP,
  Hann-windowed) and reports the highest frequency still above the noise floor — a low-bitrate
  lossy encode permanently discards high frequencies, so this fingerprints transcodes that
  re-encoding to FLAC/high-bitrate MP3 can't undo.
- Results feed both the results table (a "Cutoff" column) and `DuplicatePlanner`'s quality ranking.

### UI layer

- **`ContentView.swift`** — the main window, driven by `scanner.state`
  (`.idle`/`.enumerating`/`.scanning`/`.finished`), plus local `@State` for filter/search/sort/
  selection and `@AppStorage` reads of Discogs/MusicBrainz settings. A mandatory category-picker
  sheet gates folder selection on first launch. Filtering/searching/sorting of `scanner.files`
  happens in `filteredFiles`, not in the scanner. The toolbar opens five auxiliary windows (Rename
  Files, Collect into Folders, Find Duplicates, Check Album Completeness, Apply Found Matches) via
  `@Environment(\.openWindow)`; a true modal `.sheet(item:)` is used only for `MetadataLookupView`.
- **`CleanMyDigitalApp.swift`** registers those five as separate `WindowGroup`s — each is named
  `*SheetView` in code but is actually its own OS-level window, not a SwiftUI sheet — plus a
  `Settings` scene for `SettingsView`.
- **`RenameSheetView`**, **`CollectSheetView`**, **`DuplicatesSheetView`**,
  **`AlbumCompletenessSheetView`**, **`ApplyFoundMatchesSheetView`** — all follow the same shape:
  build proposals from the matching planner `onAppear`, render a selectable list/table, Apply calls
  back into `LibraryScanner`. `AlbumCompletenessSheetView` also offers per-album Discogs lookup and
  folder renaming; `ApplyFoundMatchesSheetView` is the review/apply UI for
  `scanner.lookupResults`, grouped by folder.
- **`MetadataLookupView.swift`** — modal per-file sheet: segmented Discogs/MusicBrainz search,
  candidate comparison, apply.
- **`AlbumMetadataLookupView.swift`** — album-level counterpart: one Discogs search per
  `AlbumGroup`, tracklist matched against every file in the folder.
- **`SettingsView.swift`** — Discogs token, MusicBrainz contact email, backup toggle, all via
  `@AppStorage`.

### Networking & dependencies

The sandbox has outgoing network enabled (`ENABLE_OUTGOING_NETWORK_CONNECTIONS`). Two external
HTTPS APIs are called via `URLSession`: **Discogs** (search + release detail, needs a user-supplied
token) and **MusicBrainz** (recording search, needs a contact email in the User-Agent per their
etiquette policy) plus the **Cover Art Archive** for MusicBrainz cover art. All are self
rate-limited (~1 req/sec). One SPM dependency, **`ID3TagEditor`**
(github.com/chicio/ID3TagEditor), is used for MP3/AIFF ID3v2.3 read/write.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
