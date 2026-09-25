# The Sh*t List

A WoW addon for remembering the players worth grouping with, and the ones worth avoiding.

- **Rate anyone:** right-click a player — their portrait, a party or raid frame, or their name in chat — and pick **The Sh\*t List**. Give a thumbs up or down, tick tags ("Great healer", "Ninja looter", ...), or write a note.
- **Warnings:** when someone on your list joins your group or invites you, you get a coloured chat line, an on-screen banner and a sound. Only you ever see it; nothing is sent to chat.
- **Group finder:** listed players are flagged with a thumbs up or down, and hovering shows their rating, so you can decide before you join or invite.
- **After a run:** leave a dungeon or raid you spent 10+ minutes in and a window lists everyone you ran with, each with +1 / -1 buttons, while you still remember who did what.
- **Tooltips** show a player's rating and tally.
- **List window:** `/tsl` opens it, with search, filters and sorting; click a row to edit.

## Commands

`/tsl`, `/tsl list [bad|good|mixed]`, `/tsl group`, `/tsl rate`, `/tsl remove <name>`,
`/tsl banner|sound|good`, `/tsl test [good|mixed|bad]`, `/tsl macrobackup [on|off]`, `/tsl help`

## Notes

Ratings are keyed by character ID, so renames and same-name players are handled correctly.
Data is account-wide (`TheShtListDB`) with a per-character mirror (`TheShtListBackup`)
merged at login.

If the game ever hands the addon an empty list when it shouldn't (as the WoW Forever beta
did in September 2026, for every addon), it says so and pauses rating rather than quietly
overwriting your list. `/tsl macrobackup on` keeps an extra copy in hidden macros, which
live on Blizzard's servers and survive that kind of failure.

The folder is named `TheShtList` because the saved-settings file takes the folder's name,
and CurseForge does not allow profanity.
