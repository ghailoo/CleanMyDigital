# Changelog

Every release, newest first. The current version is **1.8.3**.

---

## What's new in 1.8.3

- **Optional: clean the Title tag too.** 1.8.2 trimmed the trailing BPM out of the
  proposed *filename* but left the tag alone. **Rename Files** now has a
  **Clean the Title tag too** checkbox that writes the trimmed title back to the file —
  `Needed You (Original Mix) 125` becomes `Needed You (Original Mix)` in the tag as
  well as the name.
  - **Off by default.** This is one of the few places the app overwrites a tag you
    already have, alongside "Remove format suffixes from Album" and your own edits in
    the inspector, so it only happens when you ask for it.
  - Every affected row shows **Title tag → …** under its proposed name before you
    rename, so you see each change first.
  - The same trim as the filename, so the tag and the name never disagree.
  - Backed up first, if "Back up originals before writing" is on, and reversible from
    the backup like any other tag write.

---

## What's new in 1.8.2

- **Renaming drops whatever follows the mix name.** Beatport-style rips end the Title
  tag with the BPM — `Needed You (Original Mix) 125` — which the file already carries
  properly in its own `BPM` field. Rename now proposes
  `Camelphat, Vomee - Needed You (Original Mix).flac`. The same slot collects keys,
  store IDs and label names; all of it goes.
  - Cut at the **last** version group, so a title carrying two —
    `(Radio Edit) [Wyclef Remix]` — keeps both.
  - A title with **no** version group is never touched. Without one there's nothing to
    say where the title ends, and guessing would eat real words:
    `Close To You (US CDS Promo) (1990)` is left exactly as it is.
  - Whole words only, so `(Dubfire)` isn't a dub and `(Editor)` isn't an edit.
- Also applied to the **song folder name** in Collect into Folders, and to the
  **search term** — since 1.8 the Title tag leads the search, so a trailing BPM was
  going to Discogs along with the title.
- Your tags are untouched, as always — this only changes the proposed filename, the
  proposed folder name and what gets searched for.

---

## What's new in 1.8.1

- **Collect into Folders can no longer flatten an artist folder.** This fixes real
  damage: scanning a folder that holds **many artist folders** (rather than one
  artist's own folder) made Collect read each artist folder as if it were one
  single's pressings. It moved the files to `Root/Song/Pressing/` and removed the
  artist folder once it was empty — turning `Artist/Song/file` into `Root/Song/file`
  and losing the artist level.
  - Collect assumes **the folder you scanned is one artist's folder**, and reads the
    first folder level under it as a release. Choose the artist folders themselves —
    you can select several at once in *Choose Folder…*
  - A folder whose name matches the Artist tag of the files inside it is now
    recognised as an artist folder and skipped, and the Collect window says so
    instead of sitting there empty.
  - The check is an **exact** name match, never "contains", so a release folder named
    after its artist (`Depeche Mode - Enjoy The Silence`) is still collected normally.
- If this already happened to you: **nothing was deleted.** Files were moved, and a
  folder was only removed once empty. *Undo Last Change* in the Collect window
  reverses the whole run — but only while that session is alive, so don't rescan,
  change category or quit the app first.

---

## What's new in 1.8

- **The Title tag leads the search now.** The artist term has always preferred the
  file's own Artist tag; the track term never did — it was always parsed out of the
  filename, even when the file carried a perfectly clean Title. That was the real
  reason a search you do by hand in one go came back **Not found** here: a file
  tagged `First Time (Jose Spinnin Cortex Remix)` was being searched for as
  `207-offer_nissim_feat_maya-first_time__jose_spinnin_cortex_remix-nvs`.
  - Scene tags, store IDs, site watermarks, codec markers and duration markers live
    in **filenames**, not in tags — so reading the tag first retires whole classes of
    them at once.
  - **The filename isn't thrown away.** When the tag's wording finds nothing, the
    search retries with the filename's reading before giving up, so an abbreviated or
    misspelled tag can't hide a release the filename would have found.
  - A placeholder tag — `Track 03`, `Audio Track`, `Untitled`, a bare number — is
    ignored and the filename is used instead.
  - Filename-only rules are never run over a tag: they'd turn *7 Seconds* into
    *Seconds*. A tag only has its codec marker, site watermark and "feat." credit
    removed.
- Applies to Discogs, MusicBrainz, the manual search sheet's prefilled boxes, and the
  track-against-tracklist matching in album lookups.

---

## What's new in 1.7.4

- **Scene-style filenames are understood.** A name like
  `207-offer_nissim_feat_maya-first_time__jose_spinnin_cortex_remix-nvs.mp3`
  writes spaces as `_` and separates the artist with a bare `-`, so the app's
  "Artist - Title" split never fired and the artist went into the search as part of
  the track name. The name is rewritten into the normal shape first now, which makes
  every existing rule work on it: artist split, trailing group tag, the lot.
  - Only when a name has underscores and not one space — that pair is the
    convention's signature. An ordinary name with a hyphen in it (`Hi-Fi Title`) is
    not touched.
- **A dotless "Feat" is dropped from the artist.** `Offer Nissim Feat Maya` is
  searched as *Offer Nissim* — both providers credit a featured artist separately.
  Artist terms only: a *title* like "The Feat Of Clay" would lose half its words, so
  there a dot is still required.

---

## What's new in 1.7.3

- **Codec names no longer poison the search.** A file called
  `… (Junior's House Mix) DTS` was searched for *with* the `DTS` — which names the
  digital format, not the recording, so neither provider has anything to match. The
  marker is dropped from the search term now, bracketed anywhere or bare at the end:
  `DTS`, `AC3`, `FLAC`, `WAV`, `MP3`, `M4A`, `AAC`, `OGG`, `WMA`, `ALAC`, `DSD`,
  `SACD`, plus `320kbps`-style bitrates and `24bit`-style depths. Only those exact
  words — a mix name like *(Radio Edit)* is untouched.
- **A track number glued to the Artist tag is dropped too.** `02_Real McCoy` is
  searched as *Real McCoy*. Narrow on purpose: two digits and a dot, dash or
  underscore, never a space, so *2 Unlimited*, *2-4 Grooves* and *3 Doors Down* keep
  their numbers.
- Neither change touches your files — the search term only.

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

- **Fixed: a blank tag is no longer mistaken for a filled one.** A ripper routinely
  leaves `DATE=` behind with nothing after it. Every writer's fill-if-missing rule
  read that as "already has a Year", so the field could never be filled and the file
  sat on **With issues** forever, however many times you applied a match. FLAC,
  APEv2 (WavPack/APE) and ID3 (MP3/AIFF/DSF) now treat an empty or whitespace-only
  value as missing, and replace it rather than leaving two copies of the field.
  M4A already behaved this way.
  - The never-overwrite rule is unchanged: a field with a *real* value still stands.

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
