# CleanMyDigital

A macOS app that scans a folder of audio files, reports which ones are missing
metadata, and helps you fill in the gaps from Discogs and MusicBrainz.

---

## Before you start

### 1. Add a Discogs token (strongly recommended)

Most of the lookup features need one. Open **CleanMyDigital → Settings → Discogs**
and paste a personal access token from
[discogs.com/settings/developers](https://www.discogs.com/settings/developers).

### 2. Add a MusicBrainz contact email (optional)

**Settings → MusicBrainz.** No API key needed, but MusicBrainz requires a contact
email in the request header. Without it, the MusicBrainz tab won't search.

### 3. Check the backup setting

**Settings → Writing → "Back up originals before writing"** is **on by default**.
Before the app modifies any file for the first time, it copies the original into a
`_CleanMyDigital Backups` folder at the root of whatever you scanned. Leave this on
while testing.

---

## Two rules that explain most surprises

**1. The app never overwrites a tag that already has a value.** It only fills in
fields that are genuinely empty. If a file already says the Genre is "Rock" and
Discogs says "Hard Rock," the file keeps "Rock." This is deliberate — it can't
silently degrade your existing tagging. It also means an "Apply" button will be
greyed out, or report "already complete," when nothing is actually missing.

**2. Nothing persists between launches.** Every time you open the app you start
from an empty state and pick a folder. Scan results, Discogs lookups, and
confirmations all live only in the current session.

---

## Pick a category first

On launch the app asks what you're scanning. This isn't cosmetic — each category
checks different things and searches differently.

| | **Singles** | **Albums** | **Compilations** |
|---|---|---|---|
| Track Number required | No | Yes | Yes |
| Artist checked against folder | No | **Yes** | No |
| Title / Artist / Album / Year / Genre / Artwork required | Yes | Yes | Yes |

You can change the category from the segmented control in the toolbar. The
available buttons change with it.

---

## Folder structure

### Albums

The expected layout is:

```
YourLibraryFolder/
  Artist Name/
    Album Name (Year)/
      01 - Track.flac
      02 - Track.flac
```

**You can scan either level:**

- **Scan `YourLibraryFolder/`** — the folder containing many artists. The app takes
  each first-level folder name as an artist name.
- **Scan `Artist Name/` directly** — the app now detects this automatically. If
  most of the subfolders look like album names (they contain a year, or several
  " - " separators), it treats the folder you scanned as the artist and shows a
  quiet grey confirmation line.

If auto-detection doesn't fire but should — for example when there's an extra level
like `Artist Name/Studio Albums/Album Name/` — use the **"Treat This Folder as the
Artist"** toolbar button, or the yellow banner's fix button if it appears.

**The Artist Mismatch flag** compares each file's Artist tag against its artist
folder. A tag that *extends* the folder name is fine — "Anouar Brahem Trio" filed
under "Anouar Brahem" won't be flagged. A genuinely different name will be.

### Singles

No required structure. Files can sit loose in one folder. The app expects filenames
roughly like `Artist - Title (Mix).flac`, and uses that convention when cleaning up
search terms and proposing new filenames.

**You can select several folders at once.** Singles are often filed one folder per
artist, so in the Choose Folder dialog you can Cmd-click several artist folders and
scan them together as one list — no need to scan their shared parent and wait for
everything else underneath it.

Each file stays associated with the folder it came from, so backups
(`_CleanMyDigital Backups`) and moved duplicates (`_CleanMyDigital Duplicates`) are
created inside that file's own folder rather than all being collected under one.
Find Duplicates works across the whole selection, which is the point — it will catch
the same track filed under two different artists.

Multi-select is Singles-only. Albums and Compilations both derive meaning from the
scanned folder's own structure (artist folders, one folder per release), so they
still take one folder at a time.

### Compilations

Group each compilation in its own folder. No artist-folder check is performed,
since the whole point is that the tracks are by different artists.

---

## Supported formats

| | Formats |
|---|---|
| **Read and write** | MP3, M4A, FLAC, WAV, AIFF, DSF, WavPack (.wv) |
| **Read only** | M4B, M4P, AAC, CAF, MP4, ALAC, AC3, EAC3 |
| **Not supported yet** | OGG, Opus, WMA, Monkey's Audio (.ape), MPC, DFF |

Unsupported files still appear in the results, flagged as unreadable, rather than
being silently skipped.

---

## The toolbar, button by button

### Always available

**Choose Folder…** — pick a folder and scan it.

**Rescan** — re-read the same folder. Use this after changing files outside the app.

**Find All Metadata** (magnifying glass) — searches Discogs and MusicBrainz for
every flagged file. **This only searches; it writes nothing.** Watch the Lookup
column fill in with "Found" or "No match."

**Apply Found Matches…** (checkmark in a circle) — this is the one that actually
writes. It opens a window listing every file that got a match, and writes the
Artist / Album / Year / Genre / Artwork fields the search found. Title and Track
Number for Discogs matches still need the per-file tracklist step below.

> Find All Metadata and Apply Found Matches are a pair. Searching alone changes
> nothing on disk.

**Rename Files…** — proposes new filenames from the tags. Singles become
`Artist - Title (Mix)`; Albums and Compilations become `01 Artist - Title`.
Preview before applying.

**Find Duplicates…** — groups files sharing the same Artist and Title, keeps the
highest real quality (measured frequency cutoff first, then bitrate), and offers to
move the rest into a `_CleanMyDigital Duplicates` folder. Nothing is ever deleted.

**Check for Transcodes** — measures each file's real frequency cutoff. A file
claiming to be lossless but cutting off below ~17 kHz was probably re-encoded from
a lower-quality source. Results appear in the Cutoff column.

**Copy Report** / **Export CSV…** — get the results out as text or a spreadsheet.

**Treat This Folder as the Artist** — rescans the current folder using its own name
as the artist, for structures auto-detection doesn't recognize.

### Singles only

**Collect into Folders…** — groups a track's different mixes into a subfolder named
after the release.

### Albums only

**Check Album Completeness…** — see below.

### Right-click any row

**Find Metadata…** — the per-file lookup. This is the only place that can fill in
**Title and Track Number** from Discogs, because it loads the release's full
tracklist and lets you pick which track the file is. It also lets you correct the
search terms by hand when the automatic ones guess wrong.

---

## Check Album Completeness (Albums only)

This answers a different question from everything else: **does this folder contain
every track the release should have?** It says nothing about whether those tracks'
tags are filled in — that's the main table's job.

Each album folder gets a status:

- **Complete** — the track-number tags say "x of 12" and 12 files are present.
- **Missing tracks 3, 7** — the tags say how many there should be, and some are absent.
- **Unknown locally** — no file states a total, so the tags can't confirm anything.
  Very common with FLAC, which usually stores the track number without a total.

For anything not confirmed locally, **Check on Discogs** opens a search. Pick the
right release from the candidates (check the format and year — CD, Vinyl, and
reissues all differ), and you'll see each of your files matched to a track on that
release. If a match is wrong, click the file to reassign it.

**Apply to Album** then writes the release's shared fields to every file at once.
The completeness result is only recorded once you actually apply — browsing a
candidate and backing out doesn't mark anything confirmed.

You can also rename the folder itself to `Album Name (Year)` from here, when the
tags provide both. It asks for confirmation first.

---

## What to report

Useful things to tell us:

- A file the app said was unreadable that plays fine elsewhere
- A wrong Artist Mismatch flag, along with the folder path and the Artist tag
- A Discogs search returning nothing when the release clearly exists
- Any file that sounds different, won't play, or changes size after a write
- Any error message that doesn't explain what to do next

If a write goes wrong, the original is in `_CleanMyDigital Backups` at the root of
whatever you scanned (assuming the backup setting was on).
