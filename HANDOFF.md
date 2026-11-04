# CleanMyDigital — Session Handoff

Read this first, then `CLAUDE.md` (architecture). Written 2026-09-13, refreshed 2026-11-04.

## Verify state before doing anything

```
git log --oneline -10
git status
git tag -l
```

Current: **1.3.1** on `main` (`fc61e1a`), plus branch `cleanmydigital-iii` for v3 work.
Shipped DMGs live in `~/Desktop/CleanMyDigital Docs +DMG/`; 1.2.2 and 1.3 both carry
the ID3-chunk scan crash fixed in 1.3.1 — hand testers 1.3.1 or later.
Backups: `~/Desktop/CleanMyDigital-*.bundle` (restore: `git clone <bundle>`).

## How the user (Ghailen) works — follow these

- **The user does all app testing.** Never drive the app, take screenshots, or use
  computer-use. After a change, give a short numbered test checklist.
- **Commit after each confirmed step**, one logical change per commit.
- **Token-conscious.** Keep replies short, don't re-read files you don't need,
  don't re-load skills repeatedly.
- `mistral-src/` next to the project is unrelated — never stage it (gitignored).

## Build / test

```
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' build
xcodebuild -project CleanMyDigital.xcodeproj -scheme CleanMyDigital -destination 'platform=macOS' test
```

One **known pre-existing** test failure — not a regression:
- `CleanMyDigitalUITests.testExample` — fails when a copy of the app is running.
(The old "flaky" M4A test was a real bug — blank Year/Genre atoms — fixed in `ebbe445`.)

**Stale-build trap:** twice the user tested an old binary. If a reported bug looks
already fixed, compare the DerivedData executable timestamp with source mtimes.

## Decisions already made (don't re-litigate)

- **Never overwrite an existing tag** — only fill empty fields. One opt-in exception:
  "Remove format suffixes from Album" (`TagChanges.replacesAlbum`) strips "(CDM)"-style markers.
- **Compilations** search Discogs by album title only (no "Various", no track), then
  Find All Metadata confirms the track in the release's tracklist (`firstRelease`).
- **Discogs search:** per-file lookups for Singles/Albums use free-text `q=` with
  "Artist - Title (Mix)" — the structured `artist=`+`track=` pair returned wrong or
  no results in live probes. **Keep the mix parenthetical** (it pins the pressing).
  Compilations use `release_title=` + `artist=Various`; strip trailing disc markers
  like "(CD-1)" but never "Vol."/"Part".
- For Singles, the folder is **not** the artist (`expectedArtist` is Albums-only).
- **Multi-folder scanning is Singles-only**; no folder cap (cost scales with file
  count, not folder count). Every write re-acquires access to all roots.
- Toolbar = workflow spine (Choose Folder, Rescan▾, Find All Metadata, Apply Found
  Matches) + menus Organize▾ (moves/renames files) / Check▾ (read-only) / Export▾.
- Motion: restrained, no bounce, one shared animation, respects Reduce Motion.
- Discogs token lives in the app's UserDefaults — never write it into files or commits.

## Next up

**v3 (`cleanmydigital-iii`)**: drag and drop (drop folders/files onto the window to
scan them) and stronger search in the results table.

On `main`: 1.3.1 is committed but the ID3-chunk crash fix is **unconfirmed by the
user** — it was a regression from 1.2.2's truncated-RIFF tolerance, caught by
`ID3ChunkMetadata.isWellFormed`. Finding 1 of `HIG-audit-2026-10-12.md` (layered
Icon Composer `.icon` with dark/mono variants) is still open and needs the GUI app.

## Known untested

DSF and WavPack writing have never been tried on real files. Multi-folder Singles
(apply to a file in the 2nd folder; backups land in that folder) was built and
unit-tested but not confirmed by the user.
