# Changelog

All notable changes to The Sh\*t List.

Versions before 1.0.0 were development builds and were never published; they are
kept here for the record. Dates are the date the work landed, except 1.0.0, which
is the date it went up on CurseForge.

## [1.0.1] — 2026-11-11

### Fixed

- **Files could install loose in your `AddOns` folder** instead of into their own
  `TheShtList` folder, leaving the addon missing from the in-game list entirely.
  The download now states its folder structure explicitly rather than leaving
  extractors to infer it from the file paths, so every unzip tool and addon
  manager puts the files where they belong.

  If you hit this, delete any stray `TheShtList...` files sitting directly in
  `Interface\AddOns` before installing this version — they are not cleaned up
  by reinstalling.

### Added

- `/tsl testinvite` previews the invite warning without needing a real invite.

### Notes

No addon code changed in this release; only the layout of the release archive.

## [1.0.0] — 2026-09-25

First public release, on CurseForge.

### Added

- **Rate anyone** by right-clicking them: portrait, party or raid frame, or their
  name in chat. Thumbs up or down, 16 canned tags, and your own notes.
- **Warnings** with a chat line, banner and sound when someone on your list joins
  your group or invites you. Red for the bad ones, green for the good. Nothing is
  sent to chat; only you see it.
- **Group finder flags:** listed players are marked with a thumbs up or down, and
  hovering shows why, plus when and where you last grouped with them.
- **End-of-run rating:** leave a dungeon or raid you spent 10+ minutes in and a
  window lists everyone you ran with, each with +1 / -1 buttons.
- **Running tally** per player (+4/-1) with the history behind it, so one bad night
  doesn't define someone and repeat offenders stand out.
- **Tooltips** show a player's rating.
- **List window** (`/tsl`) with search, filters and sorting.
- An icon, and thumbs up/down artwork.

### Changed

- Renamed the addon folder and files from `TheShitList` to `TheShtList`, with the
  display name `The Sh*t List` — CurseForge bars profanity in names and
  descriptions, and the saved-settings file takes the folder's name. Saved player
  IDs were unaffected.
- Tag `Complete asshole` became `Total jerk`, and `Doesn't listen` was added.

## [0.7.1] — 2026-09-24

### Fixed

- Rating from the right-click menu could taint Blizzard's own menu. The addon now
  opens its own context menu instead of adding a submenu inside Blizzard's, which
  re-evaluates its entries after a pick and needs protected calls to do it.

## [0.7.0] — 2026-09-24

### Added

- Optional macro backup (`/tsl macrobackup on`), which keeps an extra copy of your
  list in hidden macros. Those live on Blizzard's servers, so they survive a local
  saved-variables failure.

### Removed

- The local saved-variables workaround in the TOC, no longer needed once Blizzard
  fixed the Forever beta's loader bug.

## [0.6.0] — 2026-09-22

### Added

- Rated players are flagged in the group finder with a thumbs up or down, with a
  hover panel showing the rating and when and where you last grouped.

## [0.5.0] — 2026-09-22

### Added

- Rate players by right-clicking their name in chat.

## [0.4.0] — 2026-09-22

### Added

- A safety net for the Forever beta's saved-variables loader bug: if the game hands
  the addon an empty list when it shouldn't, the addon says so and pauses rating
  rather than quietly overwriting your list. `/tsl startfresh` overrides it when the
  list really is meant to be empty.

## [0.3.0] — 2026-09-22

First working version.

### Added

- Rate players thumbs up or down with canned tags and notes, keyed by character ID
  so renames and duplicate names are handled correctly.
- A roster scan that warns you, privately, when someone on your list is in your group.
- Account-wide storage with a per-character mirror, merged at login.
- The list window (`/tsl`) with filters, search and sorting.
- End-of-run rating prompt after dungeons and raids.
