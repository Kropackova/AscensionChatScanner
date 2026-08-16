# Changelog

All notable changes to Ascension Chat Scanner.

## 1.2.1

### Fixed

- Mythic raid posts were filed under Dungeon. A line like `LFM MC Mythic` was
  stored with the `MYTHIC` kind, so it appeared as "Mythic: Onyxia" with the
  Dungeon filter on and disappeared with Raid on. Mythic is a difficulty, not a
  category: the row keeps its `RAID` kind, the caption still reads "Mythic" and
  the Diff column reads Mythic. This covers every raid in the packs - Molten
  Core, Blackwing Lair, Zul'Gurub, Onyxia, AQ20, AQ40, Naxxramas, and the TBC
  raids from Karazhan to Sunwell Plateau - including lines that only say "key"
  or "keys".
- The Mythic difficulty option under the Raid category was unreachable, because
  no row could be a raid and mythic at the same time. It filters now.
- Manastorm posts that mentioned mythic were filed under Dungeon. Manastorm is
  excluded from the mythic override, the same as guild recruitment and world
  bosses.
- A mythic random dungeon post could not be reached under Dungeon > Random
  Dungeon. The row keeps its `RDF` kind, so the Random Dungeon entry matches it.
- Target counts and the target submenu counted mythic raids under Dungeon
  instead of Raid.
- The keystone rules read the row kind, which broke once a mythic row could keep
  another kind. Level 60 mode and the key range filter read a dedicated mythic
  flag instead, so a mythic raid no longer answers the key range filter and a
  mythic five man is still exempt from the level cap check.
- "Ahn'Qiraj" written without "ruins of" or "temple of" was not recognised as a
  raid target. Bare "aq" is still left alone, it is ambiguous between AQ20 and
  AQ40.

### Changed

- Row schema is 5, so rows saved by 1.2 and older are reparsed on load. A stored
  row that carries the `MYTHIC` kind takes the kind and caption its message
  really implies, and hand edited cells are kept as always.
- New row field `mythic`, true when a post is about a mythic run whatever
  category it sits in. The keystone rules read it instead of the row kind.
  
## 1.2

**New**

- **Guild section.** Guild recruitment has its own tab with Time, Name and Message, instead of sitting hidden inside PvE and PvP.
- **Level 60 only.** One switch hides levelling traffic: aura and heirloom posts, XP farms, boost and carry runs, and anything advertising a level below the cap. Keystone runs are level cap content, so they always stay.
- **Mythic+ keystone range.** Show only keys inside a range, for example 7 to 12. A post with no key number is kept.
- **Two level Activity filter.** Click Dungeon, Raid or World Boss for the whole category, or open one and pick a single instance. The number in brackets is how many posts of that kind sit in the tab you have open.
- **Difficulty column.** Normal, Heroic, Mythic and Ascended, read from the post and editable by hand. A keystone is Mythic by definition.
- **Gear level.** An iLvl column, `{ilvl}` in whisper templates, and `/acs ilvl` to print how your own average is worked out.
- **Support** joins Tank, Healer and Damage as a role.
- **TBC content pack** for Area 52: Burning Crusade dungeons, raids and world bosses only, level cap 70. The pack follows the realm you log in to.
- **Ascension custom dungeons** on the vanilla packs: Vault of the Inquisition, Road to De'Other Side, Karazhan Crypts, Torwatha and Blackrock Caverns.
- **`/acs hidden`** prints what the active filter is dropping, grouped by reason, so a filter that hides too much can be spotted.
- **Resizable columns.** Drag the line between two headers; `/acs reset` puts them back.
- Right-click **Alerts** to unlock the alert popup and drag it, right-click again to lock it.

**Changed**

- Alert scope **Section** now means the tab you are looking at, not the whole section, so sitting on PvE LFG keeps PvE LFM quiet.
- Activity names are written out in full: `Manastorm` in place of `MS`, `Random Dungeon` in place of `RDF`, `World Boss Tour` in place of `WB Tour`.
- The `Diff` column is called `Difficulty`.
- Tooltips trimmed: the section and tab buttons carry none at all, and the rest lost their filler lines.

**Fixed**

- A keystone number is never read as a character level, so `Keystone: Uldaman (10)` stays visible under Level 60 only and the Level column stays empty on mythic rows.
- A boost or carry run is treated as levelling even when the post never says xp.
- Dragging and resizing the window no longer fight each other, and the window keeps its place across a reload.
- Chat logger noise, invite spam and guild advertising no longer land in the group tabs.
- The Activity menu opens downwards over the panel instead of under it, and only one menu is open at a time.
- Gear level updates as the client answers, instead of once at login.

**Removed**

- `/acs ilvlmode`. The average is picked automatically.

## 1.1

**Mythic keystones**

- The activity caption now carries the keystone level: `Mythic+ 7: Uldaman` in place of `Dungeon: Uldaman`.
- The level is read from `[Keystone: Uldaman (3)]` item links, from `mythic+7`, from `m+7` and from `LF +5 mythic key group`.
- `Completed Mythic: 10` is ignored when reading the level. It states the highest key the sender has ever finished, not the level of the group being formed.
- A number that counts players is no longer mistaken for a level, so `Keystone: Uldaman need 2 dps` shows no level rather than a wrong one.
- `m1`, `m2` and `m3` now register as mythic runs. Previously only `m0` and the word `mythic` did.
- `M0` posts read `Mythic 0`, without a plus.
- Mythic raids read `Mythic: Molten Core`. No keystone level applies to a raid.
- Mythic posts sit behind **Mythic+** in the Activity filter.

**Content**

- Blackrock Caverns added to the dungeon list, including the short form `brc`. It is playable on every Ascension realm.

**Guild recruitment**

- Adverts written in the third person are now recognised: `recluta`, `recruta`, `recruta membros`, `vagas para`, `gremio recluta`, `hermandad recluta`. Only the gerund forms were listed before, so Spanish and Portuguese adverts were missed.
- A guild advert that promises mythic runs stays a guild instead of being re-tagged as a mythic post.

**Fixed**

- `M+` with no number behind it was destroyed by the text normaliser and the post was missed. A plus straight after a word now survives as its own token.
- The addon description listed a content pack under its old name.

## 1.0

- First release.
