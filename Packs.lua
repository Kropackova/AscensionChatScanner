-- Ascension Chat Scanner
-- Packs.lua - realm profiles and content packs. No game API here except the
-- realm name lookup, which is guarded.
--
-- The engine parses intent, roles, headcount, group size and level. It knows
-- nothing about any particular server's content. A pack supplies the content:
-- which activities exist, what people call them, and which columns the table
-- should show. One pack is active at a time, chosen by realm name.

AGF = AGF or {}

-- Matching runs on normalised text: lower case, punctuation stripped, single
-- spaces, every word surrounded by spaces. So "Atal'Zul" arrives as "atalzul"
-- and "15/25" arrives as "15by25".
--
--   phrases   multi word, matched as a whole
--   words     single tokens, matched exactly
--   targets   named encounters that identify the activity on their own
--   sizeStems stems that carry a group size, as in ms15

AGF.PACKS = {}

-- Named dungeons, raids and quest group-ups --------------------------------
-- Shared by every pack. Quest and item links arrive as their lower case link
-- text. Shorts are the way people actually type names.

-- The full five man roster, from Ragefire Chasm to the Blackrock wings, with
-- the short forms people actually type. Wing names are only matched next to
-- their instance, so a lone "gy" is never Scarlet Monastery.
local DUNGEON_PHRASES = {
	"blackrock depths", "blackrock spire", "lower blackrock spire",
	"upper blackrock spire", "zul farrak", "zulfarrak",
	"ragefire chasm", "wailing caverns", "shadowfang keep",
	"blackfathom deeps", "the stockade", "stormwind stockade",
	"gnomeregan", "razorfen kraul", "razorfen downs",
	"scarlet monastery", "sm gy", "sm lib", "sm arm", "sm cath",
	"sm graveyard", "sm library", "sm armory", "sm armoury",
	"sm cathedral", "the deadmines", "dire maul", "dire maul east",
	"dire maul west", "dire maul north", "dire maul tribute",
	"sunken temple", "temple of atal hakkar", "atal hakkar",
	"the temple of atal hakkar", "lower blackrock", "upper blackrock",
	"the four dukes", "four dukes", "tharill zun", "tharil zun",
	"rep farm", "xp farm", "exp farm", "dungeon farm", "rep grind",
	"dungeon leveling", "dungeon levelling",
}

-- Short forms that mean a dungeon and nothing else.
--
-- "vc" is left out altogether: it is a boss name as often as an instance.
--
-- "dm" is here but is absent from DUNGEON_TARGETS below. Deadmines and Dire
-- Maul are both dungeons, so a post carrying it belongs in the dungeon row
-- either way, but naming one of the two would be a guess.
local DUNGEON_WORDS = {
	"brd", "ubrs", "lbrs", "rfk", "rfd", "rfc", "scholo", "scholomance",
	"stockade", "stockades", "deadmines", "gnomer", "gnomeregan",
	"mara", "maraudon", "zf", "uldaman", "ulda", "strat", "stratholme",
	"wc", "sfk", "bfd", "sm", "st", "dm", "dme", "dmw", "dmn", "dmt",
	"razorfen", "mgt", "slabs", "arcatraz", "shattered halls",
	"m0", "m1", "m2", "m3", "mythic", "mythics",
	"dungeon", "dungeons",
}

local DUNGEON_TARGETS = {
	"blackrock depths", "blackrock spire", "lower blackrock spire",
	"upper blackrock spire", "scarlet monastery", "dire maul",
	"sunken temple", "temple of atal hakkar", "wailing caverns",
	"shadowfang keep", "blackfathom deeps", "ragefire chasm",
	"razorfen kraul", "razorfen downs", "zul farrak", "zulfarrak",
	"the four dukes", "four dukes", "tharill zun", "tharil zun",
	"brd", "ubrs", "lbrs", "rfk", "rfd", "rfc", "scholo", "scholomance",
	"stockade", "stockades", "deadmines", "gnomer", "gnomeregan",
	"mara", "maraudon", "zf", "uldaman", "ulda", "strat", "stratholme",
	"wc", "sfk", "bfd", "sm", "st", "dme", "dmw", "dmn", "dmt",
	"razorfen", "mgt", "m0", "m1", "m2", "m3",
}

-- Raids. Kept apart from the five man list so the Activity filter can show
-- them on their own, and matched before dungeons so "lf mc" is a raid.
local RAID_PHRASES = {
	"molten core", "blackwing lair", "zul gurub", "zulgurub",
	"ruins of ahn qiraj", "temple of ahn qiraj", "ahn qiraj",
	"emerald sanctum", "black temple", "gruul s lair", "gruuls lair",
	"serpentshrine cavern", "tempest keep", "sunwell plateau",
	"battle for mount hyjal", "mount hyjal",
	"onyxia s lair", "onyxias lair", "raid night", "raid group",
	"full clear", "raid clear",
}

local RAID_WORDS = {
	"mc", "bwl", "ony", "onyxia", "zg", "aq", "aq20", "aq40", "naxx",
	"nax", "naxxramas", "kara", "karazhan", "hyjal", "gruul",
	"mag", "magtheridon", "ssc", "tk", "bt", "swp", "raid", "raids",
}

local RAID_TARGETS = {
	"molten core", "blackwing lair", "zul gurub", "zulgurub",
	"ruins of ahn qiraj", "temple of ahn qiraj", "ahn qiraj",
	"emerald sanctum", "black temple", "serpentshrine cavern",
	"tempest keep", "sunwell plateau", "mount hyjal",
	"mc", "bwl", "ony", "onyxia", "zg", "aq20", "aq40", "naxx", "nax",
	"naxxramas", "kara", "karazhan", "hyjal", "gruul", "mag",
	"magtheridon", "ssc", "tk", "bt", "swp",
}

-- World bosses that stand outside any instance. The realm adds its own, so a
-- pack extends this list rather than replacing it.
local WORLD_BOSSES = {
	"azuregos", "kazzak", "lord kazzak", "emeriss", "lethon", "taerar",
	"ysondre", "dragons of nightmare", "nightmare dragon",
	"nightmare dragons", "doom lord kazzak", "doomwalker",
}

-- Ascension realms ---------------------------------------------------------
-- Bosses that stand outside any instance on the Ascension realms. They are
-- added to the vanilla list rather than replacing it, so every pack knows
-- both. A boss that cannot be reached on a realm simply never appears.
local COA_BOSSES = {
	"kaldros", "kaldros depthbreaker", "soggoth", "sogoth", "snowgrave",
	"atalzul", "atal zul", "setis", "settis",
}

local ALL_BOSSES = {}
for i = 1, #WORLD_BOSSES do
	ALL_BOSSES[#ALL_BOSSES + 1] = WORLD_BOSSES[i]
end
for i = 1, #COA_BOSSES do
	ALL_BOSSES[#ALL_BOSSES + 1] = COA_BOSSES[i]
end

-- Guild recruitment ---------------------------------------------------------
-- A guild advert is not a group advert, but it is posted in the same channels
-- and in every language spoken on the realm. It is matched before any other
-- activity, because a recruiting guild names the raids and dungeons it runs.
--
-- Only wording that can mean nothing else is listed here. A bare "guild" is
-- deliberately absent: "guild run, need 3 dps" is a raid advert, not
-- recruitment. The same goes for a bare "clan", which people use for any
-- group of friends.
local GUILD_PHRASES = {
	-- English
	"guild recruiting", "guild is recruiting", "is recruiting",
	"now recruiting", "we are recruiting", "we re recruiting",
	"currently recruiting", "recruiting for our", "recruiting members",
	"recruiting players", "recruiting raiders", "recruiting all",
	"recruiting new", "guild recruitment", "join our guild",
	"join the guild", "join our ranks", "looking for guild",
	"looking for a guild", "lf guild", "lf a guild", "lf active guild",
	"need a guild", "want a guild", "seeking a guild", "guild needed",
	"new guild", "social guild", "raiding guild", "casual guild",
	"hardcore guild", "levelling guild", "leveling guild", "pvp guild",
	"guild bank", "guild perks", "guild for", "our guild is",
	"guild invites", "whisper for guild", "guild tag",
	-- Spanish
	"hermandad reclutando", "reclutando gente", "reclutando miembros",
	"buscamos gente para la hermandad", "busco hermandad",
	"unete a nuestra hermandad", "clan reclutando", "busco clan",
	"gremio reclutando", "busco gremio",
	-- Portuguese
	"guilda recrutando", "procuro guilda", "recrutando membros",
	"estamos recrutando", "guilda recruta",
	-- French
	"guilde recrute", "nous recrutons", "recrutement guilde",
	"cherche guilde", "rejoignez notre guilde", "guilde cherche",
	-- German
	"gilde sucht", "gilde rekrutiert", "wir suchen mitglieder",
	"suche gilde", "mitglieder gesucht", "neue mitglieder",
	-- Italian
	"gilda cerca", "cerco gilda", "reclutiamo",
	-- Polish, Czech and Slovak
	"gildia rekrutuje", "szukam gildii", "hledam guildu", "hledam gildu",
	"nabirame nove", "nabor do gildy", "nabor do guildy",
	-- Russian, in Cyrillic and in the latin spellings people type on an
	-- English client
	"nabor v gildiyu", "ishu gildiyu", "gildiya nabiraet",
	"набор в гильдию", "ищу гильдию", "гильдия набирает",
	-- Nordic, Finnish, Turkish, Chinese
	"gilde soker", "gille soker", "kilta hakee", "uye ariyoruz",
	"lonca ariyorum", "公会招人", "招募会员", "公会招募",
}

-- Single words that mean recruitment on their own.
local GUILD_WORDS = {
	"recruiting", "recruitment", "recruits", "recruit",
	"reclutando", "reclutamos", "recrutando", "recrutamento",
	"recrute", "recrutons", "recrutement",
	"rekrutiert", "rekrutuje", "rekrutacja", "nabirame",
	"гильдия", "гильдию",
}

-- Words that make "lf <word>" a player asking to be taken in.
local GUILD_GROUP_WORDS = {
	"guild", "guilds", "guilda", "guilde", "gilde", "gilda", "gildia",
	"hermandad", "gremio", "clan", "kilta", "gille", "lonca",
}

-- Shared activities ---------------------------------------------------------
-- Every realm this addon supports runs the same content, so the activities
-- live here once. A pack is this list plus whatever that realm adds.

local ACT_GUILD = {
	id = "GUILD",
	name = "Guild",
	short = "Guild",
	phrases = GUILD_PHRASES,
	words = GUILD_WORDS,
}

local ACT_MS = {
	id = "MS",
	name = "Manastorm",
	short = "MS",
	-- Manastorm keeps its own matcher, because bare "ms" needs the main spec
	-- loot rule rejected. See AGF.MatchesManastorm.
	matcher = "manastorm",
	sizeStems = { "ms", "manastorm", "manastorms", "mstorm", "manastrom" },
}

local ACT_WBT = {
	id = "WBT",
	name = "World Boss Tour",
	short = "WB tour",
	phrases = {
		"world tour", "world boss tour", "world bosses tour",
		"worldboss tour", "worldbosses tour", "wb tour", "boss tour",
		"world boss tours", "world tour instanced", "tour instanced",
	},
	words = { "wbt" },
	targets = ALL_BOSSES,
}

local ACT_WB = {
	id = "WB",
	name = "World Boss",
	short = "World Boss",
	phrases = { "world boss", "world bosses", "worldboss", "worldbosses" },
	targets = ALL_BOSSES,
	-- A boss name on its own is enough. The tour has its own wording and is
	-- matched first, so "tour" never lands in here.
	targetIdentifies = true,
}

local ACT_RAID = {
	id = "RAID",
	name = "Raid",
	short = "Raid",
	phrases = RAID_PHRASES,
	words = RAID_WORDS,
	targets = RAID_TARGETS,
	targetIdentifies = true,
}

local ACT_RDF = {
	id = "RDF",
	name = "Random Dungeon",
	short = "RDF",
	phrases = {
		"random dungeon", "random dungeons", "random heroic",
		"heroic random", "daily heroic", "daily dungeon",
		"dungeon spam", "dungeon finder", "rdf spam", "spam rdf",
		"rdf run", "rdf runs", "mythic rdf", "rdf mythic",
		-- An "aura spam" group is always the dungeon finder loop.
		"aura spam", "spam aura", "aura grp", "aura group",
		"aura xp spam", "xp aura spam",
	},
	-- rfd is a common typo for rdf in the logs. On a level 60 realm it is
	-- never Razorfen Downs.
	words = { "rdf", "rfd", "lfd", "rhc", "rdfs" },
}

local ACT_DGN = {
	id = "DGN",
	name = "Dungeon",
	short = "Dungeon",
	phrases = DUNGEON_PHRASES,
	words = DUNGEON_WORDS,
	targets = DUNGEON_TARGETS,
	targetIdentifies = true,
}

-- Order decides the winner, first match wins. Guild recruitment is tested
-- first, then anything the realm adds, then the widest content down to the
-- narrowest, so "lf mc" is a raid and not a dungeon.
local function baseActivities(extra)
	local list = { ACT_GUILD }
	if extra then
		for i = 1, #extra do
			list[#list + 1] = extra[i]
		end
	end
	list[#list + 1] = ACT_WBT
	list[#list + 1] = ACT_WB
	list[#list + 1] = ACT_RAID
	list[#list + 1] = ACT_RDF
	list[#list + 1] = ACT_DGN
	return list
end

-- Tokens that make "lf <token>" a request to be invited rather than a leader
-- recruiting. Each pack gets its own copy, because dungeon names are appended
-- to it further down.
local BASE_GROUP_WORDS = {
	"rdf", "rdfs", "rfd", "lfd", "rhc", "tour", "wbt", "boss", "bosses",
	"worldboss", "kaldros", "soggoth", "snowgrave", "atalzul", "setis",
	"kazzak", "azuregos", "raid", "raids", "mc", "bwl", "zg", "ony",
	"aq20", "aq40", "naxx",
}

local function baseGroupWords(extra)
	local list = {}
	for i = 1, #BASE_GROUP_WORDS do
		list[#list + 1] = BASE_GROUP_WORDS[i]
	end
	for i = 1, #GUILD_GROUP_WORDS do
		list[#list + 1] = GUILD_GROUP_WORDS[i]
	end
	if extra then
		for i = 1, #extra do
			list[#list + 1] = extra[i]
		end
	end
	return list
end

-- The packs -----------------------------------------------------------------
-- Conquest of Azeroth is the base. Ascension is the same content with
-- Manastorm running on top of it. Classic is the same content again, on a
-- realm where character class is worth showing, so its table carries a Class
-- column the other two hide.

AGF.PACKS.coa = {
	id = "coa",
	name = "Conquest of Azeroth",
	activities = baseActivities(),
	groupWords = baseGroupWords(),
	generic = "RDF",
}

AGF.PACKS.ascension = {
	id = "ascension",
	name = "Ascension",
	activities = baseActivities({ ACT_MS }),
	groupWords = baseGroupWords({
		"ms", "mss", "msing", "manastorm", "manastorms", "mstorm",
		"manastrom", "manstorm",
	}),
	generic = "RDF",
}

AGF.PACKS.classic = {
	id = "classic",
	name = "Classic",
	activities = baseActivities(),
	groupWords = baseGroupWords(),
	generic = "RDF",
	-- Classes matter on this realm, so the Class column and the class filter
	-- are offered here and nowhere else.
	classes = true,
}

-- Generic fallback ----------------------------------------------------------
-- "59 TANK LFG WITH AURA" names no activity, but on every Ascension realm
-- that is the main leveling loop. When intent is clear, a role is present
-- and one of these phrases shows up, the parser tags the row with the pack's
-- generic activity instead of dropping it.

AGF.GENERIC_PHRASES = {
	"with aura", "have aura", "got aura", "has aura", "w aura",
	"aura exp", "aura xp", "exp buff", "xp buff", "exp aura", "xp aura",
	"aura of exp", "aura of experience", "aura and head", "aura head",
}

-- Professions ---------------------------------------------------------------
-- Universal, every pack parses these. name is what the table shows. Aliases
-- are normalised words and phrases people actually type, shorts included:
-- bs is blacksmithing, jwc and jc are jewelcrafting, lw is leatherworking.

AGF.PROFESSIONS = {
	{ id = "ALCH", name = "Alchemy",
	  aliases = { "alchemy", "alchemist", "alch", "alchy" } },
	{ id = "BS", name = "Blacksmithing",
	  aliases = { "blacksmithing", "blacksmith", "bs" } },
	{ id = "ENCH", name = "Enchanting",
	  aliases = { "enchanting", "enchanter", "ench", "enchant", "enchanteur" } },
	{ id = "ENG", name = "Engineering",
	  aliases = { "engineering", "engineer", "eng", "engi", "engy" } },
	{ id = "HERB", name = "Herbalism",
	  aliases = { "herbalism", "herbalist", "herb" } },
	{ id = "INS", name = "Inscription",
	  aliases = { "inscription", "inscriber", "scribe", "insc" } },
	{ id = "JC", name = "Jewelcrafting",
	  aliases = { "jewelcrafting", "jewelcrafter", "jc", "jwc" } },
	{ id = "LW", name = "Leatherworking",
	  aliases = { "leatherworking", "leatherworker", "lw" } },
	{ id = "MIN", name = "Mining",
	  aliases = { "mining", "miner" } },
	{ id = "SKIN", name = "Skinning",
	  aliases = { "skinning", "skinner" } },
	{ id = "TAIL", name = "Tailoring",
	  aliases = { "tailoring", "tailor" } },
	{ id = "COOK", name = "Cooking",
	  aliases = { "cooking", "cook", "chef" } },
	{ id = "FA", name = "First Aid",
	  aliases = { "first aid", "firstaid" } },
	{ id = "LOCK", name = "Lockpicking",
	  aliases = { "lockpicking", "lock picking", "lockpick", "lp" } },
}

-- Marks that mean the sender offers services, not that they are looking.
local OFFER_MARKS = {
	"lfw", "offering", "offer", "selling", "can craft", "free craft",
	"your mats", "service", "services", "tips", "free",
}

-- Returns the display name and "looking" or "offering", or nil, nil when no
-- profession shows up in the text.
function AGF.ParseProfession(t)
	if not AGF.Has then
		return nil, nil
	end
	for i = 1, #AGF.PROFESSIONS do
		local p = AGF.PROFESSIONS[i]
		for j = 1, #p.aliases do
			if AGF.Has(t, p.aliases[j]) then
				local mode = "looking"
				for k = 1, #OFFER_MARKS do
					if AGF.Has(t, OFFER_MARKS[k]) then
						mode = "offering"
						break
					end
				end
				return p.name, mode
			end
		end
	end
	return nil, nil
end

-- Display names for matched targets, keyed by the normalised token.

AGF.PRETTY = {
	["mc"] = "Molten Core",
	["molten core"] = "Molten Core",
	["bwl"] = "Blackwing Lair",
	["blackwing lair"] = "Blackwing Lair",
	["ony"] = "Onyxia",
	["onyxia"] = "Onyxia",
	["zg"] = "Zul'Gurub",
	["zul gurub"] = "Zul'Gurub",
	["zulgurub"] = "Zul'Gurub",
	["aq20"] = "Ruins of Ahn'Qiraj",
	["ruins of ahn qiraj"] = "Ruins of Ahn'Qiraj",
	["aq40"] = "Temple of Ahn'Qiraj",
	["temple of ahn qiraj"] = "Temple of Ahn'Qiraj",
	["ahn qiraj"] = "Ahn'Qiraj",
	["naxx"] = "Naxxramas",
	["nax"] = "Naxxramas",
	["naxxramas"] = "Naxxramas",
	["emerald sanctum"] = "Emerald Sanctum",
	["kara"] = "Karazhan",
	["karazhan"] = "Karazhan",
	["gruul"] = "Gruul's Lair",
	["mag"] = "Magtheridon",
	["magtheridon"] = "Magtheridon",
	["ssc"] = "Serpentshrine Cavern",
	["serpentshrine cavern"] = "Serpentshrine Cavern",
	["tk"] = "Tempest Keep",
	["tempest keep"] = "Tempest Keep",
	["bt"] = "Black Temple",
	["black temple"] = "Black Temple",
	["swp"] = "Sunwell Plateau",
	["sunwell plateau"] = "Sunwell Plateau",
	["hyjal"] = "Mount Hyjal",
	["mount hyjal"] = "Mount Hyjal",
	["brd"] = "Blackrock Depths",
	["blackrock depths"] = "Blackrock Depths",
	["ubrs"] = "Upper Blackrock Spire",
	["upper blackrock spire"] = "Upper Blackrock Spire",
	["lbrs"] = "Lower Blackrock Spire",
	["lower blackrock spire"] = "Lower Blackrock Spire",
	["blackrock spire"] = "Blackrock Spire",
	["scholo"] = "Scholomance",
	["scholomance"] = "Scholomance",
	["strat"] = "Stratholme",
	["stratholme"] = "Stratholme",
	["mara"] = "Maraudon",
	["maraudon"] = "Maraudon",
	["zf"] = "Zul'Farrak",
	["zul farrak"] = "Zul'Farrak",
	["zulfarrak"] = "Zul'Farrak",
	["ulda"] = "Uldaman",
	["uldaman"] = "Uldaman",
	["sm"] = "Scarlet Monastery",
	["scarlet monastery"] = "Scarlet Monastery",
	["st"] = "Sunken Temple",
	["sunken temple"] = "Sunken Temple",
	["temple of atal hakkar"] = "Sunken Temple",
	["dme"] = "Dire Maul East",
	["dmw"] = "Dire Maul West",
	["dmn"] = "Dire Maul North",
	["dmt"] = "Dire Maul Tribute",
	["dire maul"] = "Dire Maul",
	["wc"] = "Wailing Caverns",
	["wailing caverns"] = "Wailing Caverns",
	["sfk"] = "Shadowfang Keep",
	["shadowfang keep"] = "Shadowfang Keep",
	["bfd"] = "Blackfathom Deeps",
	["blackfathom deeps"] = "Blackfathom Deeps",
	["rfc"] = "Ragefire Chasm",
	["ragefire chasm"] = "Ragefire Chasm",
	["rfk"] = "Razorfen Kraul",
	["razorfen kraul"] = "Razorfen Kraul",
	["rfd"] = "Razorfen Downs",
	["razorfen downs"] = "Razorfen Downs",
	["gnomer"] = "Gnomeregan",
	["gnomeregan"] = "Gnomeregan",
	["stockade"] = "The Stockade",
	["stockades"] = "The Stockade",
	["deadmines"] = "The Deadmines",
	["mgt"] = "Magisters' Terrace",
	["m0"] = "Mythic 0",
	["m1"] = "Mythic 1",
	["m2"] = "Mythic 2",
	["m3"] = "Mythic 3",
	["emeriss"] = "Emeriss",
	["lethon"] = "Lethon",
	["taerar"] = "Taerar",
	["ysondre"] = "Ysondre",
	["dragons of nightmare"] = "Dragons of Nightmare",
	["nightmare dragon"] = "Dragons of Nightmare",
	["nightmare dragons"] = "Dragons of Nightmare",
	["lord kazzak"] = "Kazzak",
	["doom lord kazzak"] = "Kazzak",
	["doomwalker"] = "Doomwalker",
	["kaldros"] = "Kaldros",
	["kaldros depthbreaker"] = "Kaldros",
	["soggoth"] = "Soggoth",
	["sogoth"] = "Soggoth",
	["snowgrave"] = "Snowgrave",
	["atalzul"] = "Atal'Zul",
	["atal zul"] = "Atal'Zul",
	["setis"] = "Setis",
	["settis"] = "Setis",
	["kazzak"] = "Kazzak",
	["azuregos"] = "Azuregos",
}

function AGF.PrettyName(token)
	if not token then
		return nil
	end
	if AGF.PRETTY[token] then
		return AGF.PRETTY[token]
	end
	return (token:gsub("^%l", string.upper))
end

-- Realm routing -------------------------------------------------------------
-- Patterns run against the lower case realm name. First match wins.

AGF.DEFAULT_PACK = "ascension"

AGF.REALM_PACKS = {
	{ pattern = "conquest", pack = "coa" },
	{ pattern = "voljin", pack = "coa" },
	{ pattern = "vol jin", pack = "coa" },
	{ pattern = "rexxar", pack = "coa" },
	{ pattern = "bronzebeard", pack = "classic" },
	{ pattern = "dawnrise", pack = "ascension" },
	{ pattern = "darkmoon", pack = "ascension" },
	{ pattern = "area 52", pack = "ascension" },
	{ pattern = "area52", pack = "ascension" },
}

-- Resolves a realm name to a pack id. Returns the default when nothing hits.
function AGF.PackForRealm(realm)
	if type(realm) ~= "string" or realm == "" then
		return AGF.DEFAULT_PACK
	end
	local name = realm:lower():gsub("[^%a%s]", "")
	for i = 1, #AGF.REALM_PACKS do
		local entry = AGF.REALM_PACKS[i]
		if name:find(entry.pattern, 1, true) then
			return entry.pack
		end
	end
	return AGF.DEFAULT_PACK
end

-- The pack in use. Core sets this on login. ACS_DB.pack can force one for
-- testing, which is what /acs pack does.
AGF.packId = AGF.DEFAULT_PACK

function AGF.ActivePack()
	return AGF.PACKS[AGF.packId] or AGF.PACKS[AGF.DEFAULT_PACK]
end

-- Chooses the pack. An override wins over the realm.
function AGF.SelectPack(override)
	local realm
	if GetRealmName then
		local ok, value = pcall(GetRealmName)
		if ok then
			realm = value
		end
	end
	AGF.realmName = realm or "?"
	local id
	if override and AGF.PACKS[override] then
		id = override
	else
		id = AGF.PackForRealm(realm)
	end
	AGF.packId = id
	return AGF.ActivePack()
end

-- Every pack treats dungeon names and generic group words as objects that
-- make "lf <word>" a request to be invited.
local SHARED_GROUP_WORDS = { "dungeon", "dungeons" }
for _, pack in pairs(AGF.PACKS) do
	for i = 1, #DUNGEON_WORDS do
		pack.groupWords[#pack.groupWords + 1] = DUNGEON_WORDS[i]
	end
	for i = 1, #SHARED_GROUP_WORDS do
		pack.groupWords[#pack.groupWords + 1] = SHARED_GROUP_WORDS[i]
	end
end

