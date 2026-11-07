# CleanMyDigital

A macOS app that scans a folder of audio files, reports which ones are missing
metadata, and helps you fill in the gaps from Discogs and MusicBrainz.

---

## What's new in 1.6

- **Tag Maxi Tracks.** *Organize ▸ Tag Maxi Tracks…* writes **"Maxi Track"** into the
  **Grouping** tag of every track that runs past four minutes, in any format the app
  can write. Each row gets a confidence:
  - **Name agrees** (green, ticked for you) — it's long *and* the name says so:
    `remix`, `mix`, `dub`, `rework`, `extended`, `maxi`, `long version`, `12 inch`.
  - **Length only** (yellow, left unticked) — long, but the name says nothing either
    way. Read it before ticking.
  - A name that calls itself a **radio edit**, an **original version** or just an
    **edit** is taken at its word and left out of the list altogether, as long as it
    runs under five minutes. Past that the clock disagrees too loudly, so it still
    appears — unticked. A maxi hint outranks a short-form one, so *Original Extended
    Mix* is still a maxi; "radio mix" and "original mix" are not.
  - Files that already have something in Grouping are never touched, including the
    ones this feature tagged last time.

  There is no undo for a tag write. The backup setting is the recovery path.
- **Grouping in the info panel.** ⌘I now shows and edits the **Grouping** field, so you
  can see the Maxi Track tag land and correct it by hand.
- **Fixed:** the progress pill's text no longer wraps one letter per line while a
  quality check runs.
- **Fixed:** a file whose name carries a mix the release never mentions
  (`Push The Feeling Belocca cheeky Bootleg` against the release `Push The Feeling
  On`) scored as no match, because the extra words dragged the score down. A result
  whose own name is almost entirely inside the filename now counts as **To review**.
- **Fixed:** a filename whose title sits inside the brackets
  (`nikke nicole ( nikke does it better ) miller lite`) scored as no match, because
  brackets are normally a mix name and get dropped before scoring. Both readings are
  scored now and the better one wins.

---

## What's new in 1.7

- **The clock corroborates the match.** A name can lie — a bootleg is called whatever
  the ripper felt like — but the length can't. When a Discogs result is credited to
  your file's own artist *and* its tracklist holds a track the same length as the
  file, the batch lookup promotes it: a **To review** becomes **Found**, and a result
  the words alone threw out comes back as **To review**.
  - Tolerance is **±7 seconds**, because a correct pressing routinely reads 4-6
    seconds off what the file measures — Discogs' times are rounded by whoever typed
    them, and rips differ in lead-in and fade.
  - **If the tracklist holds your track's title *and* its length, that's Found
    outright.** This is what an album needs: a file called `Just Like Before` scores
    nothing against a release named `Lets Push It`, even though it's track 5 on it —
    the words only ever compared the file to the *release* name.
  - The artist has to match too. Without that, any release with a track of the right
    length would qualify.
  - Only checked when the words left doubt, so a match that already reads Found
    costs no extra request.

---

## What's new in 1.5

- **Found, or to review.** A search result is now scored against your file word for
  word, in any order. Match 90% and it's **Found** (green). Match 80% and it's
  **To review** (orange) — it appears in a new **To review** filter above the table,
  and in Apply Found Matches it starts **unticked**, so nothing uncertain is written
  unless you tick it. Below that it's no match at all, same as before.
- Extra words on the provider's side count against a match: a file called
  *Sonnentanz* against a release called *Sonnentanz Summer Sun Remixes Deluxe* is a
  review, not a find.
- A typo in your own tag no longer loses the match — *Kings Of Tommorow* still
  finds *Kings Of Tomorrow*.
- **More filename noise stripped before searching:** a track-number prefix
  (`Artist - Album - 04 - Title`), a duration marker (`(5-55)`, `[4.20]`), and a
  download-site watermark (`[www.slider.kz]`).

---

## What's new in 1.4

- **Drag and drop.** Drop a folder anywhere on the window to scan it — or drop a few
  tracks and it scans the folder they sit in. Dropping another folder over the
  results rescans. Albums and Compilations still take one folder at a time: drop
  several and it scans the first and tells you which. Anything that isn't a folder
  or an audio file is ignored.
- **A real search syntax.** Every word has to match now, so `daft discovery` narrows
  instead of widening:
  - `artist:daft` — search one field. Fields: `artist`, `title`, `album`, `genre`,
    `year`, `track`, `format`, `folder`.
  - `-flac` — exclude anything matching.
  - `"hotel costes"` — keep a phrase together, and combine it with the rest
    (`album:"hotel costes"`).
  - A plain word now also searches genre, year, track number, format and the
    containing folder — none of which were searchable before.
- **Better matching for messy filenames.** A download ID glued into a filename
  (`Doggystyle_1318768774`) is dropped before searching, and a title that still
  finds nothing is retried without whatever trails the last " - " — usually a label
  or compilation name the filename carried along.

---

## What's new in 1.3

- **Is it really lossless?** *Check ▸ Check Quality of All Files* (or right-click
  selected files ▸ *Check Quality*) grades every file **Lossless**, **Medium** or
  **Fake**, the same way the Spectro app does: it looks for the hard frequency
  ceiling an MP3/AAC encoder leaves behind, which converting to FLAC or WAV can't
  undo. The grade appears in the **Quality** column, with the reason in its tooltip.
  - **Lossless** — full-range audio, as expected from a real lossless file.
  - **Medium** — honestly lossy (MP3/AAC), or a lossless file with thin highs, or a
    hi-res file that's really CD quality.
  - **Fake** — a lossy file dressed up as lossless, or a low-bitrate MP3.
- **Finder colour dots.** Each checked file gets a green, yellow or red dot in Finder.
  This only adds a colour label; the audio is not touched.
- **Pause** the check from its progress bar, and resume where it left off.
- **Spectrogram** of the selected track in the info panel (⌘I), with the measured
  cutoff marked.
- **Fake filter** in the summary row, and **Organize ▸ Move All Fakes to
  Quarantine…**, which moves them into a `_CleanMyDigital Quarantine` folder (with
  Undo). Nothing is deleted.
- **Find Duplicates keeps the best-sounding copy**: Lossless beats Medium beats Fake,
  so a genuine MP3 is kept over a fake FLAC.
- **Fix:** AIFF files couldn't be measured at all.

---

## What's new in 1.2

- **Track info panel (⌘I).** A side panel showing the selected track's cover art and
  details, where you can **edit tags directly** — Title, Artist, Album, Year, Genre,
  Track. Select several tracks and shared values appear once; anything you type
  applies to all of them. This is the one place existing tags are overwritten, and
  only the fields you change.
- **Release organizer.** "Collect into Folders" now builds
  `Artist / Song / Pressing` folders: every version of a song lands in one folder,
  with each pressing as its own subfolder, covers and scans alongside their tracks.
  Different spellings ("Justified & Ancient" / "And Ancient") merge, and a folder
  holding more than four different songs is left alone, so albums and compilations
  aren't broken up.
- **Monkey's Audio (.ape) support** — read, tag, rename and collect, same as the
  other formats.
- **Better matching.** Searches now ignore "feat." credits (including "féat."),
  scene tags like "-gem", and invisible characters in filenames. A result by the
  right artist counts as a match instead of a warning.
- **Progress you can see and stop**, with a live count of matches found.
- **Keyboard:** ⌘O choose folder, ⌘R rescan, ⌘I info panel, ⌘F search, Esc closes a
  window, Return runs its main action.
- **Fix:** .m4a files showed Year and Genre as missing when they weren't, and then
  failed to apply with "nothing to write".

---

## What's new in 1.1

- **Apply Found Matches, redesigned.** Each file is a card with a one-line
  *Current → After Apply* comparison per field. Only what will actually be written
  is highlighted.
- **"Check release" warning** on any match whose Artist *and* Album both disagree
  with your file — the most likely sign of a wrong release.
- **Remove format suffixes from Album** (optional) — cleans markers like "(CDM)",
  "(EP)" or " - Single" from existing Album tags. See Apply Found Matches below.
- **Better compilation searches** — found by the compilation's title, then the track
  is confirmed on the release's tracklist.
- **Fix:** some .m4a files reported "nothing to write" even though Year or Genre was
  empty. They're now filled correctly.

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

**Collect into Folders…** *(Singles only)* — groups a track's different mixes into
a subfolder named after the release.

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
