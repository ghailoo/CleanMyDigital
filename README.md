# CleanMyDigital

**A macOS app for cleaning up a messy music library.** Point it at a folder, and it
tells you which files are missing Artist, Title, Album, Year, Genre or artwork — then
fills the gaps from Discogs and MusicBrainz, renames the files, sorts them into
folders, finds duplicates and flags fake lossless.

Built for libraries that grew out of twenty years of downloads: scene releases with
`_` for spaces, Beatport rips with the BPM glued onto the title, `02_Artist` ripper
prefixes, site watermarks, `(DTS)` codec markers, three copies of the same 12" under
three different names. The app is designed around the fact that **real filenames are
garbage and real tags are half-empty.**

<!-- screenshot pending — see docs/screenshots/README.md
<p align="center">
  <img src="docs/screenshots/main-window.png" alt="The results table after a scan, with missing fields highlighted per file" width="860">
</p>
-->

---

## Download

**[→ Download the latest release](../../releases/latest)** — a universal `.dmg`
(Apple Silicon and Intel), macOS 14 or later.

The app is **signed ad-hoc, not notarized**, so the first launch needs one extra step:

1. Open the `.dmg` and drag **CleanMyDigital** to your Applications folder.
2. **Right-click** the app → **Open** → **Open** again at the warning.

After that it launches normally. (Double-clicking it the first time gives you
"can't be opened because Apple cannot check it for malicious software" — that's
Gatekeeper on an unnotarized app, not a problem with the download.)

---

## What it actually does

| | |
|---|---|
| **Reports what's missing** | Scans a folder and shows, per file, exactly which tags are empty — plus Artist Mismatch flags where the tag disagrees with the folder it's in. |
| **Fills the gaps** | Looks each track up on Discogs and MusicBrainz, shows you the match and its confidence, and writes only the fields that were actually empty. |
| **Never overwrites your tags** | Empty fields only. The two exceptions are checkboxes you turn on yourself, and your own edits in the inspector. |
| **Renames files** | To `Artist - Title`, from the tags rather than the old filename — dropping ripper prefixes, scene underscores, codec markers and trailing BPMs. |
| **Sorts into folders** | `Artist / Song / Pressing`, keeping the folders you already made and canonicalising spellings across them. |
| **Finds duplicates** | The same track under different names, across folders, with the better copy identified. |
| **Checks quality** | Spectral analysis that catches an MP3 renamed to `.flac` — and a spectrogram so you can see it yourself. |
| **Checks albums** | Which albums are incomplete, which tracks are missing, and the folder rename to `Album (Year)`. |
| **Undoes it** | Every rename, move and collect is reversible for the rest of the session. |

Reads and writes **FLAC, MP3, M4A/AAC/ALAC, WAV, AIFF, DSF, APE and WavPack**
(`.ogg` is read-only for now). Every write goes to a temp file and is swapped in
atomically, and originals are backed up first by default.

---

<!-- screenshots pending — see docs/screenshots/README.md
## Screenshots

| | |
|---|---|
| ![Apply Found Matches](docs/screenshots/apply-found-matches.png) | **Apply Found Matches** — every field the match would fill, per file, before anything is written. |
| ![Rename Files](docs/screenshots/rename-files.png) | **Rename Files** — current name beside proposed name, with per-row notes on what changed. |
| ![Find Duplicates](docs/screenshots/find-duplicates.png) | **Find Duplicates** — the same track under several names, with the keeper chosen. |
| ![Quality check](docs/screenshots/quality-check.png) | **Check Quality** — the spectrogram that tells a real FLAC from a transcoded MP3. |

---
-->

## Guide

Everything below this line is the full guide: setup, the two rules that explain most
surprises, the folder structure each category expects, and every window in the app.
Start with **[Before you start](#before-you-start)** — you'll want a free Discogs
token before the lookup features do anything.

Past releases are in the **[changelog](CHANGELOG.md)**.

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

The one exception is a checkbox you have to turn on yourself: **Remove format
suffixes from Album** in Apply Found Matches (see below).

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
like `Artist Name/Studio Albums/Album Name/` — use **Rescan ▾ → "Rescan Treating
This Folder as the Artist"** in the toolbar, or the yellow banner's fix button if
it appears.

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

Compilations are searched on Discogs by **the compilation's title** (the Album tag, or
the folder name), not by "Various" or by the track. Find All Metadata then only
accepts a release whose tracklist actually contains your track, so a different
volume of the same series isn't picked by mistake. Some series are credited to
their compiler rather than "Various" — searching by title finds those too.

---

## Supported formats

| | Formats |
|---|---|
| **Read and write** | MP3, M4A, FLAC, WAV, AIFF, DSF, WavPack (.wv), Monkey's Audio (.ape) |
| **Read only** | M4B, M4P, AAC, CAF, MP4, ALAC, AC3, EAC3 |
| **Not supported yet** | OGG, Opus, WMA, MPC, DFF |

Unsupported files still appear in the results, flagged as unreadable, rather than
being silently skipped.

---

## The toolbar

The toolbar reads left to right as the actual workflow, then three menus of
occasional tools.

### The workflow

**Choose Folder…** — pick a folder and scan it. For Singles you can select several
folders at once (see Folder structure above). You can also **drop folders straight
onto the window**, in any state — and dropping a few tracks scans the folder they
sit in.

**Rescan** — re-read the scanned folders from disk. Use this after changing files
outside the app. In Albums, the arrow beside it also offers **Rescan Treating This
Folder as the Artist**, for structures auto-detection doesn't recognize.

**Find All Metadata** (magnifying glass) — searches Discogs and MusicBrainz for
every flagged file. **This only searches; it writes nothing.** Watch the Lookup
column fill in with "Found" or "No match."

**Apply Found Matches…** (checkmark in a circle) — this is the one that actually
writes. See the next section.

> Find All Metadata and Apply Found Matches are a pair. Searching alone changes
> nothing on disk.

### Organize — everything here moves or renames files

**Rename Files…** — proposes new filenames from the tags. Singles become
`Artist - Title (Mix)`; Albums and Compilations become `01 Artist - Title`.
Preview before applying.

**Collect into Folders…** — for Singles, a **Collect by** switch in the footer picks
the scheme. Albums and Compilations always use Genre, since the Artist scheme reads
the first folder level as one single's pressings.

- **Artist** *(Singles only)* — `Artist/Song/Pressing/file`. Groups a track's
  different mixes and pressings into a subfolder named after the release.
- **Genre** — files by the **last** value of the Genre tag, since Discogs orders them
  broad to specific and almost every dance record starts with "Electronic". What goes
  under the genre folder depends on what the genre is filing:
  - **Singles** → `Progressive House/Lane 8 - Needed You (Original Mix).flac`, flat.
  - **Albums** → `Downtempo/Air/Moon Safari (1998)/01 - Track.flac` — the release
    moves whole, so scanning `Library/Downtempo/` afterwards works exactly as scanning
    the library does.
  - **Compilations** → `Lounge/Hotel Costes 10/01 - Track.flac`.

  The genre is decided once per release by majority, so a single oddly-tagged track
  never leaves its album and a song's pressings never split up. Filenames are left
  alone, anything with no Genre tag stays put (the footer counts them), and nothing is
  deleted or swept up — emptied folders are left for you to remove.

**Find Duplicates…** — groups files sharing the same Artist and Title, keeps the
highest real quality (Lossless over Medium over Fake, then measured frequency cutoff,
then bitrate), and offers to move the rest into a `_CleanMyDigital Duplicates`
folder. Nothing is ever deleted.

**Tag Maxi Tracks…** — writes "Maxi Track" into the Grouping tag of everything longer
than four minutes. Green rows (the name says remix, mix, extended, dub…) start ticked;
yellow rows (long, but the name is silent) don't. Radio edits and originals under five
minutes never appear. See *What's new in 1.6*.

**Move All Fakes to Quarantine…** — after a quality check, moves every Fake file into
a `_CleanMyDigital Quarantine` folder inside its scanned folder. Asks first; Undo
puts them back. Nothing is ever deleted.

### Check — everything here only reads and reports

**Check Album Completeness…** *(Albums only)* — see below.

**Check Quality of All Files** — grades each file Lossless, Medium or Fake from its
real frequency content (see *What's new in 1.3*). Results appear in the Quality
column and as Finder colour dots. Right-click selected files ▸ **Check Quality** to
check only those. While it runs, the progress bar has **Pause** and **Stop**.

### Export

**Copy Report** / **Export CSV…** — get the results out as text or a spreadsheet.

### Greyed out?

Hover any dimmed button — its tooltip says what's blocking it. Most often it's
"scan a folder first", or, for Find All Metadata, a missing Discogs token or
MusicBrainz contact email in Settings.

### Right-click any row

**Find Metadata…** — the per-file lookup. This is the only place that can fill in
**Title and Track Number** from Discogs, because it loads the release's full
tracklist and lets you pick which track the file is. It also lets you correct the
search terms by hand when the automatic ones guess wrong.

---

## Finding a file in the results

The search field (⌘F) filters the table as you type. Every term has to match, so
adding words narrows the list:

| You type | You get |
| --- | --- |
| `daft discovery` | rows matching **both** words, each in any field |
| `artist:daft` | only the Artist field |
| `-flac` | everything **except** FLAC |
| `"hotel costes"` | the phrase, kept together |
| `album:"hotel costes" -live` | combine them |

Fields you can name: `artist`, `title`, `album`, `genre`, `year`, `track`,
`format`, `folder`. A term with no field searches the filename, every tag, the
format and the containing folder.

The buttons above the table (Total, With issues, No metadata, Complete, Found,
To review, Fake) filter separately, and stack with whatever you've typed.

---

## Apply Found Matches

A review window for everything Find All Metadata found. Files are grouped by folder;
each file is a card showing the release that was found and one line per field:

```
Field     Current                    After Apply
Album     —                       →  Can't Help Myself (Remix)   ← highlighted: will be written
Artist    2 Brothers On The 4th Floor   2 Brothers On The 4th Floor ✓   ← already agrees
```

- **Highlighted with an arrow** — this value will be written.
- **Grey** — stays exactly as it is. A ✓ means the match agrees with your file.
- **"Discogs: … — not applied"** — the match says something different, but your
  existing value is kept (the never-overwrite rule).
- **"3 changes"** badge — how many fields this file will get.
- **"Check release"** (orange) — Artist and Album both disagree with the match.
  Probably the wrong release: use **Correct…** before applying.

Differences that are only a format marker don't count: an Album of
"Turn Da Music Up (CDM)" agrees with Discogs' "Turn Da Music Up".

**Correct…** re-searches one file. **Re-match Album… / Re-match Compilation…** (in
the folder header) re-searches the whole folder at once — use it when every track
got the same wrong release.

A match marked **To review** (orange) starts unticked: its name only partly agrees
with your file, so it's never written unless you tick it yourself.

Untick a file (or a whole folder) to leave it out; its card fades so you can see it
won't be written. **Apply Selected Matches** writes the rest, one file at a time,
with a backup first if that setting is on.

### Remove format suffixes from Album (optional)

A checkbox in the window's footer, **off by default**. When on, existing Album tags
that end in a format marker — `(CDM)`, `[CDS]`, `(CD Single)`, `(Maxi-Single)`,
`(EP)`, `(Single)`, `(Promo)`, `(Vinyl)`, `(12")`, or iTunes-style ` - Single` /
` - EP` — are cleaned. Real title parts like "(Remixes)" or "(Deluxe Edition)" are
left alone.

Each cleanup shows up as a normal highlighted change *before* you apply, so you can
check it. It only affects files listed in this window, and only the Album field.

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
- A "Check release" warning on a match that is actually correct (or no warning on
  one that is clearly wrong)
- A format suffix that should have been removed but wasn't, or a title that was
  cleaned when it shouldn't have been
- Any file that sounds different, won't play, or changes size after a write
- Any error message that doesn't explain what to do next

If a write goes wrong, the original is in `_CleanMyDigital Backups` at the root of
whatever you scanned (assuming the backup setting was on).
