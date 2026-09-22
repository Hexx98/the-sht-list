# The Shit List

A WoW Forever addon for remembering the players you loved and the ones you'd rather not see again.

- **Rate anyone:** right-click a player (party/raid frame, target, focus), open **The Shit List**, then give a thumbs up/down, tick canned tags ("Complete asshole", "Great healer", ...) or add a note.
- **End-of-run rating:** leave a dungeon/raid you ran for 10+ minutes and a window lists everyone you grouped with, each with +1 / -1 buttons. The addon keeps a running tally with dates and places.
- **Warnings:** when someone on your list joins your group, you get a banner, a sound and a chat line. Only you see them; nothing is sent to party chat.
- **Tooltips** show a player's rating and tally.
- **List window:** `/tsl` opens it, with filters, search and sorting; click a row to edit.

Commands: `/tsl`, `/tsl rate`, `/tsl list`, `/tsl group`, `/tsl remove <name>`, `/tsl banner|sound|good`, `/tsl test`, `/tsl help`.

Data is account-wide (`TheShitListDB`) with a per-character backup mirror (`TheShitListBackup`) that is merged on login.
