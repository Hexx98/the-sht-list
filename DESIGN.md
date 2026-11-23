# Guild sharing — design

**Status:** proposed, nothing built. Written 2026-11-23.
**Decision owner:** Hexx.

## Where this came from

A user (Jaxyl) asked for guild sync so guildmates using the addon learn about
players others have run into. The motivating case is concrete and good: someone
ninjas a drop, and you want the rest of the guild to know tonight, before he
does it to them.

The reply was that the idea is worth doing but the obvious version is not:

> It's one thing if you think someone is an asshole, it's another if you're
> telling everyone you know just to mess with the guy.

That is the design constraint, and it is a constraint on *architecture*, not on
wording in a disclaimer.

## What the obvious version gets wrong

"Guild sync" normally means one replicated database: every member's flags merged
into every member's list, permanent, growing, indistinguishable from their own
ratings. That shape is what makes the abuse real — a standing corpus of
accusations about named players, on dozens of machines, that the accused can
never see or contest, and that outlives whatever argument produced it.

## Two lists

The addon keeps **two separate lists**, and never conflates them.

**My list** — `db.players`, what exists today. Written only by its owner.
Permanent. Authoritative: this is what fires the group-join banner.

**Guild list** — `db.guild`, claims other people have sent. Attributed per
claim, **expiring**, advisory only, never merged into My list.

```lua
db.guild = {
  [guid] = {
    name = "Bobbo", class = "ROGUE",
    claims = {
      ["Hexx-Ghostwalker"]  = { tags = {ninja=true}, where = "Deadmines",
                                runAt = 1764000000, at = 1764000120 },
      ["Jaxyl-Nightreaver"] = { tags = {quitter=true}, ... },
    },
  },
}
```

Keeping them apart is what makes the whole feature defensible. A guildmate's
opinion is visibly a guildmate's opinion, with a name on it, that ages out — not
a line in your own list that you can no longer tell you didn't write.

An earlier draft of this document hid incoming claims in a "received alerts log,
pruned after 30 days" and made *copy into my list* the only way to retain
anything. That log was a guild list wearing a different hat, and the hat did not
change its properties. Better to name it and give it rules.

### What makes the guild list safe enough to persist

1. **It expires, and it visibly ages.** Each claim carries `at`; claims older
   than `GUILD_TTL` (proposed: 180 days) are dropped on login, so nothing
   accumulates indefinitely. Six months rather than six weeks because this is a
   big game and you may not cross paths with someone for months — a list that
   forgets faster than you re-encounter people is empty precisely when it is
   needed. The protection against old grudges reading as fresh news is not the
   TTL, it is showing the age: "flagged 4 months ago", with older claims
   de-emphasised. Remembering for a long time and presenting as current are
   different things, and only the second one is unfair.
2. **It never fires the hard warning.** The group-join banner reads My list,
   full stop. A guild claim produces a quieter, visually distinct, attributed
   notice — "Jaxyl flagged him: Leaves mid-run" — that informs without
   pronouncing a verdict.
3. **Every claim is attributed** to the sending character. No aggregate verdicts,
   no "4 guildies flagged him" as a score. Who said it is part of the claim.
4. **It is retractable.** A sender can withdraw a claim, and it disappears from
   everyone online.
5. **It is not backed up.** `TheShtListBackup` mirrors My list only. Other
   people's opinions are disposable by design; losing them costs nothing.
6. **Promotion is explicit.** One click copies a guild claim into My list, where
   it becomes a normal owner-authored entry. That is the only path from `db.guild`
   into `db.players`.

## Invariants

1. **`db.players` is written only by its owner.** No incoming message ever
   modifies My list. Not on merge, not on "trust this person", never.
2. **No free text crosses the wire.** Tags only — the fixed 17-entry `TAGS`
   vocabulary. `e.note` stays local, always.
3. **Every shared claim is attributed** to the character that sent it.
4. **Only My list drives the group-join banner.**
5. **Guild claims expire by default** — but see "Retention is the receiver's
   choice": this is a default, not a guarantee the addon can enforce.
6. **Guild channel only.** No cross-guild federation, no export, no web upload.

## Three features

| | Direction | Lands in | Answers |
|---|---|---|---|
| **My list** | local | `db.players`, permanent | what exists today |
| **Alerts** | push, verified, rate-limited | `db.guild`, expiring | "don't let him get anyone else tonight" |
| **Ask the guild** | pull, on demand | `db.guild`, expiring | "is this guy worth grouping with?" |

Alerts and Ask share one transport and one wire grammar, so building both is
barely more work than either. Alerts answer Jaxyl's case. Ask covers the case
Alerts cannot: a player you are about to group with, whom nobody broadcast about.

## Proof of contact

The single strongest mitigation, and it needs no new bookkeeping.

`TheShtList_LFG.lua` already records runs per character in
`TheShtListBackup.run` and `.lastRun`:

```lua
run = { id = "<time>:<key>", key = key, where = where, start = now,
        members = { [guid] = { guid, name, realm, class, since, last } },
        votes = {} }
```

**Rule:** a player may only be the subject of an outgoing Alert if their GUID
appears in `run.members` or `lastRun.members`, and the run started less than
`ALERT_WINDOW` (proposed: 2 hours) ago.

What this buys:

- You cannot alert the guild about someone you never grouped with. Drive-by
  slander of a name you saw in chat is not expressible.
- You cannot re-fire a months-old grudge as fresh news.
- The claim carries verifiable circumstances for free — `where` and `start` are
  already in the run — so anyone else from that run can contradict it.

Ask-the-guild replies are *not* gated this way: answering "yes, he's on my list"
reveals nothing you did not already choose to record.

## Transport

`C_ChatInfo.RegisterAddonMessagePrefix("TSL")`, `C_ChatInfo.SendAddonMessage`
with channel `"GUILD"`, received via `CHAT_MSG_ADDON`.

**Pre-flight check required:** confirm `C_ChatInfo` exists and guild addon
messages actually deliver on this client (interface 16001). Plater ships
AceComm-3.0 and ChatThrottleLib, which target exactly these calls, so the API is
almost certainly present — but a bundled library referencing it is not proof it
works. Verify in game before writing the protocol against it.

Every message fits in a single 255-byte payload. No chunking, no serialisation
library, no `ChatThrottleLib` dependency. Pipe-delimited, version number second
so the grammar can change later:

```
A|1|<guid>|<name>|<tagids>|<where>|<runAt>     alert
X|1|<guid>                                      retract my claim
Q|1|<guid>|<nonce>                              ask the guild
R|1|<guid>|<nonce>|<tagids>|<lastSeen>          reply to an ask
```

`<tagids>` is a comma-separated list of ids from `TAGS` (`ninja`, `goodheal`,
…). Unknown ids are ignored by the receiver, so adding tags later is safe. A
GUID is ~20 characters, so even a long tag list leaves headroom.

## Alerts: lifecycle

**Sending.** After a run, the existing rate prompt gains a "tell the guild"
checkbox, available only for bad tags and only while proof of contact holds.
Capped at `ALERT_CAP` per day (proposed: 3), which makes an alert a scarce
signal rather than a feed and bounds how much damage one bad evening does.

**Receiving.** Shown once — chat line, or toast if `banner` is on:

> **Hexx** flagged **Bobbo** — Ninja looter · grouped in Deadmines, 6 min ago
> `[Copy to my list]` `[Dismiss]` `[Mute Hexx]`

Either way it lands in `db.guild` under the sender's name, and ages out on
`GUILD_TTL`. `[Dismiss]` only closes the toast. `[Copy to my list]` is the sole
path into `db.players`, writing a normal owner-authored entry with
`updated = time()` exactly as a manual rating would.

**Retracting.** `X` removes the sender's claim from `db.guild` on every client
online at the time. It does not reach people who were offline; see open
questions. Retracting does not restore the daily cap.

## Ask the guild: lifecycle

Right-click a player, or hover a name in the LFG scanner → "ask the guild".
Broadcasts `Q` with a nonce. Online guildmates whose My list holds an active
entry for that GUID reply `R`. Results collect for a few seconds, render once,
and are stored in `db.guild` like any other claim:

> **Bobbo** — asked the guild: **Hexx** (Ninja looter), **Jaxyl** (Leaves mid-run)

No reply, no answer. Silence is indistinguishable from "nobody has him", which
is correct and avoids leaking who is online. A guildmate answers at most once
per nonce; replies arriving after the window closes are ignored.

## Where the two lists show up

- **Window** (`TheShtList_Window.lua`): tabs, **Mine** and **Guild**. The Guild
  tab lists each player with who flagged them, which tag, and how long ago.
- **Group-join banner:** My list only, unchanged. A guild claim gets a separate,
  quieter line underneath, attributed.
- **LFG scanner** (`TheShtList_LFG.lua`): the highest-value spot, since it is
  where you decide whether to group at all. Show guild claims, but visually
  distinct from your own and always with the sender's name — advisory, not a
  verdict.

## Disputed claims

When two players from the same run flag each other, the real event was probably
a loot argument, not a ninja. Both claims carry the same `where`/`runAt`, so it
is cheap to spot.

Show both marked **disputed** rather than taking either at face value. Costs
almost nothing and refuses to pick a side the addon cannot adjudicate.

## Settings and defaults

All sharing is **off by default**. An addon that starts broadcasting player
judgments on first login would be indefensible.

```lua
shareAlerts = false   -- send my alerts to the guild
recvAlerts  = true    -- show and keep alerts others send
answerAsks  = false   -- reply when a guildmate asks about someone on my list
guildTTL    = 180     -- days before a guild claim expires (0 = never)
muted       = {}      -- per-sender mute, set from the alert toast
```

`recvAlerts` defaults true because receiving costs the user nothing, but it is
only reachable once sharing has been opted into — nobody is a silent recipient
of a feature they never enabled.

### Retention is the receiver's choice

`guildTTL` is applied locally, by the client holding the claim, as presets rather
than a typed number of days: **1 month / 3 months / 6 months / 1 year / never**.
Six months is the default. Shortening it takes effect on the next login and drops
older claims immediately — predictable beats clever.

The receiver is the right place for the knob, because it is their disk and their
list. But it has an honest consequence: **you cannot control how long your claim
survives on someone else's machine.** A guildmate who picks "never" keeps your
flag forever, and nothing stops them, because this is an open-source Lua addon
running on their computer — they can set the value, or edit the file.

So expiry is a courtesy default that makes the decent behaviour the easy
behaviour. It is not a technical guarantee, and the design should not lean on it
as one. A sender-specified expiry carried in the claim would be equally advisory
for the same reason, so it is not worth the bytes.

What *is* enforceable sits on the sending side, where this addon is the only
thing that can produce a valid claim at all: proof of contact, the alert window,
the daily cap, tags-only, and attribution. Those hold regardless of what any
recipient configures, which is why they carry the weight here.

## Abuse model

**Mitigated**

- Fabricated encounters — proof of contact makes them inexpressible.
- Stale grudges re-fired as news — the 2-hour alert window.
- Mass dumping and brigading — the daily cap plus attribution.
- Character assassination in prose — notes never leave the client.
- One person's grudge becoming everyone's automatic red flag — only My list
  fires the banner, and only its owner writes it.
- A permanent shared record *by default* — claims expire on a six-month TTL and
  are never backed up. Qualified, not solved: see below.
- Untraceable claims — every claim carries the sender's name.

**Not mitigated, honestly**

- **Spite-flagging a real encounter.** Someone loses a roll fairly, is annoyed,
  and flags you as a ninja. Proof of contact is satisfied. No addon can
  adjudicate a loot dispute, and disputed-claim detection only catches the
  symmetric case. This is the residual risk, and it is real.
- **Screenshots.** Once a claim renders on someone else's screen it can be
  pasted into guild chat with the sender's name on it. None of this prevents
  reputation damage; it changes how easy, deniable and scalable it is.
- **A guild that wants to be a mob.** The design assumes a social group with
  shared reputation stakes. It does not survive a guild that collectively
  decides to harass someone, and should not pretend to.
- **Retention, on someone else's machine.** `guildTTL` is a local setting in a
  Lua addon, so a recipient can keep your claim forever by choosing "never" or
  by editing the file. Expiry makes the decent default easy; it does not bind
  anyone. Only the sending-side rules — proof of contact, window, cap,
  tags-only, attribution — hold no matter how a recipient is configured.

If the residual risk is unacceptable, declining Jaxyl's request outright is a
legitimate outcome. The addon is already useful as a private memory aid — which
is exactly what the current 46-entry list is.

## Out of scope

- Syncing `e.note`, ever.
- Syncing `e.up` / `e.down` tallies — personal counters, not claims; aggregating
  them across people turns the addon into a scoring system.
- Merging incoming claims into `db.players` automatically, however trusted the
  sender.
- Cross-guild sharing, party/raid broadcast, public lists, web export.
- Reusing `merge()` for anything shared. It is last-write-wins on `updated`,
  right for reconciling your own characters and wrong for other people's
  opinions — it would let a guildmate overwrite your rating.

## Open questions

1. **Attribution in the inline warning.** Signed claims deter slander but expose
   the sender; "Hexx flagged the GM's mate" has social cost inside a guild,
   which suppresses honest use. Option: attributed in the Guild tab, unattributed
   in the toast. Unresolved.
2. **Should good tags broadcast too?** Symmetric sharing makes the feature read
   as reputation rather than a hit list, a genuine counterweight. But it doubles
   traffic and dilutes the alert's scarcity. Leaning yes, with good-tag alerts
   not counting against `ALERT_CAP`.
3. **Window and cap values.** 2 hours and 3/day are guesses; worth an evening of
   real use before fixing them. Note that the alert window and the TTL are
   unrelated knobs and should not be tuned together: the window is how fresh an
   encounter must be to broadcast at all, the TTL is how long the guild
   remembers. Keeping the window short and the TTL long is deliberate.
4. **Retracts miss offline players.** Accept it, or carry tombstones in the next
   `R` reply.
5. **Does the Guild tab need a size cap** as well as a TTL? Rough arithmetic says
   not urgently: My list is 46 entries in a 14 KB saved-variables file, about
   300 bytes each, so an active 50-person guild flagging a few players a month
   each lands around 900 claims and ~270 KB over six months. Tolerable. Revisit
   if a 300-member guild actually produces an unusable Guild tab, and solve it
   by paging the UI before trimming anyone's data.

## Build order

1. Pre-flight: verify `C_ChatInfo` and guild addon messages on interface 16001.
2. Transport, wire grammar, prefix registration, plus `/tsl debug comm`.
3. `db.guild` storage, TTL expiry on login, and the Guild tab.
4. **Ask the guild.** The smaller feature, and it proves transport and storage
   with no broadcast risk.
5. **Alerts** — proof of contact, the cap, the toast, copy-to-my-list.
6. Disputed-claim detection.
7. Settings UI and the opt-in flow.

Shipping 1–4 alone would already be a useful release, and it stays reversible in
a way a merged, permanent shared list never is.
