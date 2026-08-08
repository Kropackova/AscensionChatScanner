# Changelog

All notable changes to Ascension Chat Scanner.

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
