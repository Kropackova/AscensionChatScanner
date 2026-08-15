# Changelog

All notable changes to Ascension Chat Scanner.

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
