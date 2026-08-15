-- Ascension Chat Scanner
-- Parser.lua - normalisation, token tables, classification. No game API here.
-- What counts as an activity comes from the active pack, see Packs.lua.

AGF = AGF or {}
AGF.VERSION = "1.2"

local function trim(s)
	s = s:gsub("^%s+", "")
	s = s:gsub("%s+$", "")
	return s
end

-- 1. Normalisation ----------------------------------------------------------

function AGF.Normalize(raw)
	if not raw then
		return " "
	end
	local t = raw
	t = t:gsub("|c%x%x%x%x%x%x%x%x", "")
	t = t:gsub("|r", "")
	t = t:gsub("|H.-|h", "")
	t = t:gsub("|h", "")
	t = t:gsub("|T.-|t", "")
	t = t:lower()
	-- Group progress such as 3/3, 8/10 or 14/15 becomes one token, so those
	-- numbers are never mistaken for a level or a wanted count.
	t = t:gsub("(%d)%s*/%s*(%d)", "%1by%2")
	-- A decimal item level such as "68.5il" is one number, not two. Without
	-- this the full stop became a space and the gear level was lost.
	t = t:gsub("(%d+)%.(%d+)", "%1")
	t = t:gsub(">", " gt ")
	t = t:gsub("<", " lt ")
	t = t:gsub("%+%s*(%d)", " plus%1 ")
	-- A plus straight after a word carries meaning even with no number behind
	-- it, as in "m+" or "mythic+". It becomes its own token so the neighbours
	-- stay separate words.
	t = t:gsub("(%a)%+", "%1 plus ")
	t = t:gsub("%+", " ")
	t = t:gsub("[/\\,%.!%?%(%)%[%]{}:;\"'%*%%=|~#&@`^]", " ")
	t = t:gsub("_", " ")
	t = t:gsub("%s+", " ")
	return " " .. trim(t) .. " "
end

-- Text for the Message column. The chat string can hold colour codes, icons
-- and hyperlinks. A hyperlink keeps its bracket text, everything else goes.
-- Ascension adds custom link types whose payload the client does not always
-- fold away, which put a long block of random characters into the table.
-- Traffic from another addon. Some Ascension addons broadcast on a numbered
-- chat channel, so the payload arrives as a normal chat event. It holds a
-- protocol header such as LC1:CONF:3427ac40: and no spaces. The parser then
-- finds random pairs such as 2s or zg inside the payload and files a row of
-- noise under Arena or Dungeon.
function AGF.IsAddonTraffic(raw)
	local s = tostring(raw or "")
	if s == "" then
		return false
	end
	-- A protocol header at the start, with no space near it.
	local head = s:sub(1, 24)
	if s:match("^[%w]+:[%u%d]+:") and not head:find(" ", 1, true) then
		return true
	end
	-- A hyperlink holds a long payload by design, so a line with a link is
	-- left to the display cleaner.
	if s:find("|H", 1, true) then
		return false
	end
	local longest = 0
	for w in s:gmatch("%S+") do
		if string.len(w) > longest then
			longest = string.len(w)
		end
	end
	if longest >= 40 then
		return true
	end
	if not s:find(" ", 1, true) and string.len(s) >= 24 then
		return true
	end
	return false
end

function AGF.DisplayText(raw)
	local src = tostring(raw or "")
	if src == "" then
		return ""
	end
	local hadLink = src:find("|H", 1, true) ~= nil
	local t = src
	t = t:gsub("|c%x%x%x%x%x%x%x%x", "")
	t = t:gsub("|r", "")
	t = t:gsub("|T.-|t", "")
	-- A complete link keeps only the text the player reads.
	t = t:gsub("|H.-|h%[(.-)%]|h", "%1")
	t = t:gsub("|H.-|h", "")
	t = t:gsub("|h", "")
	t = t:gsub("|n", " ")
	t = t:gsub("|", " ")
	-- Keep this result. If the next step removes too much, we fall back to it.
	local safe = trim((t:gsub("%s+", " ")))
	-- The rest of a link payload is a very long word. Only a line that held a
	-- link can have one, so plain chat text is never touched.
	if hadLink then
		t = t:gsub("%S+", function(w)
			if #w >= 24 and not w:lower():find("^http") and not w:lower():find("^www%.") then
				return ""
			end
			return w
		end)
	end
	t = trim((t:gsub("%s+", " ")))
	-- The Message column must never go blank. Show less clean text instead.
	if t == "" then
		t = safe
	end
	if t == "" then
		t = src
	end
	return t
end

local function has(t, token)
	return t:find(" " .. token .. " ", 1, true) ~= nil
end
AGF.Has = has

local function hasAny(t, list)
	for i = 1, #list do
		if has(t, list[i]) then
			return true, list[i]
		end
	end
	return false
end

local function words(t)
	local out = {}
	for w in t:gmatch("%S+") do
		out[#out + 1] = w
	end
	return out
end

-- Tokens the pack treats as a group object, so "lf rdf" and "lf ms" both mean
-- the sender wants to join something.
local function packGroupWord(w)
	local pack = AGF.ActivePack and AGF.ActivePack()
	if not pack or not pack.groupWords then
		return false
	end
	for i = 1, #pack.groupWords do
		if pack.groupWords[i] == w then
			return true
		end
	end
	return false
end

-- 2. Manastorm gate and group size ------------------------------------------
-- MS15 means Manastorm with fifteen players. Those numbers are group sizes,
-- never levels and never wanted counts, so they are tagged before anything
-- else looks at the text.

local MS_WORDS = {
	["ms"] = true, ["mss"] = true, ["msing"] = true, ["manastorm"] = true,
	["manastorms"] = true, ["manastormu"] = true, ["manastormy"] = true,
	["manastrom"] = true, ["manstorm"] = true, ["mstorm"] = true,
}
-- "mana" on its own is a deliberate non-match, it names a resource.

local MS_PHRASES = { "mana storm", "mana storms", "m storm", "ms storm" }

-- Contexts where ms means main spec loot, not Manastorm.
local MS_REJECT = {
	"ms gt os", "os gt ms", "ms os", "os ms", "mainspec", "main spec",
	"ms over os", "ms first", "ms only loot",
}

-- Tags ms15, ms 15, manastorm15 and 15 man as a size token and returns it.
function AGF.MarkSize(t)
	local size
	local function keep(n)
		local v = tonumber(n)
		if v and v >= 2 and v <= 40 then
			size = size or v
		end
	end
	-- Size stems come from the pack. Manastorm has ms15, most content does
	-- not name its size that way, so this list is often empty.
	local stems = {}
	local pack = AGF.ActivePack and AGF.ActivePack()
	if pack then
		for i = 1, #pack.activities do
			local list = pack.activities[i].sizeStems
			if list then
				for j = 1, #list do
					stems[#stems + 1] = list[j]
				end
			end
		end
	end
	for i = 1, #stems do
		local stem = stems[i]
		t = t:gsub(" " .. stem .. "(%d+) ", function(n)
			keep(n)
			return " " .. stem .. " size" .. n .. " "
		end)
		t = t:gsub(" " .. stem .. " (%d+) ", function(n)
			keep(n)
			return " " .. stem .. " size" .. n .. " "
		end)
	end
	t = t:gsub(" (%d+) ?man ", function(n)
		keep(n)
		return " size" .. n .. " man "
	end)
	-- Spelled out small groups.
	if t:find(" duo ", 1, true) then
		keep(2)
	end
	if t:find(" trio ", 1, true) then
		keep(3)
	end
	return t, size
end

function AGF.MatchesManastorm(t)
	for i = 1, #MS_PHRASES do
		if has(t, MS_PHRASES[i]) then
			return true
		end
	end
	local list = words(t)
	local plainMs = false
	for i = 1, #list do
		local w = list[i]
		if MS_WORDS[w] then
			if w == "ms" or w == "mss" then
				plainMs = true
			else
				return true
			end
		elseif w:match("^ms%d+s?$") or w:match("^manastorm%d+$") or w:match("^mstorm%d+$") then
			return true
		end
	end
	if plainMs then
		if hasAny(t, MS_REJECT) then
			return false
		end
		return true
	end
	return false
end

-- 3. Roles ------------------------------------------------------------------

local ROLE_WORDS = {
	tank = {
		"tank", "tanks", "tanking", "tanker", "tnk", "mt", "ot", "maintank",
		"offtank", "prot", "protection", "bear", "guardian", "t",
	},
	heal = {
		"heal", "heals", "healz", "healer", "healers", "healor", "healing",
		"healler", "healo", "resto", "rdruid", "rsham", "holy", "hpal",
		"hpala", "hpriest", "disc", "tree", "healadin", "hps", "h",
	},
	damage = {
		"dps", "dd", "damage", "dmg", "rdps", "mdps", "gigadps", "pumper",
		"pumpers", "aoe", "aoes", "ranged", "melee", "caster", "arms",
		"fury", "ret", "feral", "cat", "boomkin", "moonkin", "boomy", "ele",
		"enh", "shadow", "sp", "spriest", "destro", "affli", "affly", "demo",
		"arcane", "fire", "frost", "combat", "sub", "assa", "mm", "bm",
		"surv", "unholy", "mage", "lock", "warlock", "rogue", "hunter",
		"hunt", "d",
	},
	-- Ascension has a fourth role. "suport" outnumbers "support" in the
	-- channel log by five to one, so the misspelling is not optional. "sup"
	-- on its own is left out, it is a greeting far more often than a role.
	support = {
		"support", "supports", "suport", "suports", "supp", "supps",
		"suppo", "supporter", "suporter", "supportu", "buffer", "buffers",
	},
}

local ROLE_WORD_MAP = {}
for role, list in pairs(ROLE_WORDS) do
	for i = 1, #list do
		ROLE_WORD_MAP[list[i]] = role
	end
end

local ROLE_PHRASES = {
	{ "off tank", "tank" }, { "main tank", "tank" }, { "prot pala", "tank" },
	{ "prot paladin", "tank" }, { "prot warr", "tank" }, { "blood dk", "tank" },
	{ "resto druid", "heal" }, { "resto sham", "heal" }, { "holy pala", "heal" },
	{ "holy priest", "heal" }, { "disc priest", "heal" },
	{ "frost dk", "damage" }, { "unholy dk", "damage" },
	{ "warr dps", "damage" }, { "dps warr", "damage" },
	{ "ranged dps", "damage" }, { "melee dps", "damage" },
	{ "aoe dps", "damage" }, { "dps aoe", "damage" }, { "big aoe", "damage" },
	{ "huge aoe", "damage" }, { "good aoe", "damage" }, { "big pumper", "damage" },
	{ "sup dps", "support" }, { "dps sup", "support" },
}

-- One line that asks for everything. It fills all three roles, so a tank
-- filter and a healer filter both find the post.
local ANY_ROLE_PHRASES = {
	"lf all", "lfm all", "all roles", "any role", "any roles",
	"all welcome", "anyone welcome", "everyone welcome", "any and all",
	-- "Keystone: Ragefire Chasm (1) need all" wants every role, and read as
	-- nothing at all it used to leave the Role cell empty.
	"need all", "need any", "need everyone", "need everything",
	"all classes", "any class welcome", "need rest", "need the rest",
}

local COMPACT = { t = "tank", h = "heal", d = "damage", s = "support" }
local ROLE_ORDER = { "tank", "heal", "damage", "support" }
AGF.ROLE_ORDER = ROLE_ORDER

-- Captions for anything a player reads. The keys stay lower case.
AGF.ROLE_LABEL = { tank = "Tank", heal = "Healer", damage = "Damage",
	support = "Support", any = "Any" }

function AGF.RoleLabel(role)
	return AGF.ROLE_LABEL[role] or role
end

-- Turns a stored role string such as "tank, damage" into "Tank, Damage".
-- Stored ids stay lower case, this is display only.
function AGF.RoleDisplay(text)
	if not text or text == "" then
		return "?"
	end
	local out = {}
	for word in tostring(text):gmatch("[^,%s]+") do
		out[#out + 1] = AGF.RoleLabel(word)
	end
	if #out == 0 then
		return "?"
	end
	return table.concat(out, ", ")
end

-- Returns the role a single word stands for, or nil.
local function roleAt(word)
	local role = ROLE_WORD_MAP[word]
	if role then
		return role
	end
	local num, rest = word:match("^(%d+)(%a+)$")
	if num and rest and ROLE_WORD_MAP[rest] then
		return ROLE_WORD_MAP[rest]
	end
	if word:match("^%d[thds]") and word:gsub("%d[thds]", "") == "" then
		return "compact"
	end
	return nil
end

-- Character class. Only read where the pack says classes exist. On the
-- classless realms every character can learn every spell, so the column is
-- not offered and this value is never drawn.
AGF.CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
	"Shaman", "Mage", "Warlock", "Druid" }

-- Two word spellings are read first, so "holy pala" is a paladin and not a
-- healer with no class.
local CLASS_PHRASES = {
	{ "holy pala", "Paladin" },
	{ "prot pala", "Paladin" }, { "ret pala", "Paladin" },
	{ "prot warr", "Warrior" }, { "arms warr", "Warrior" },
	{ "fury warr", "Warrior" }, { "resto druid", "Druid" },
	{ "feral druid", "Druid" }, { "resto sham", "Shaman" },
	{ "ele sham", "Shaman" }, { "enh sham", "Shaman" },
	{ "shadow priest", "Priest" }, { "holy priest", "Priest" },
	{ "disc priest", "Priest" },
}

-- Single words that name a class and nothing else. "war" is left out because
-- it is a word, and "mag" is left out because it is Magtheridon.
local CLASS_WORDS = {
	warrior = "Warrior", warriors = "Warrior", warr = "Warrior",
	warri = "Warrior", warrs = "Warrior",
	paladin = "Paladin", paladins = "Paladin", pala = "Paladin",
	pally = "Paladin", pallies = "Paladin", hpala = "Paladin",
	hpal = "Paladin", retri = "Paladin",
	hunter = "Hunter", hunters = "Hunter", huntard = "Hunter",
	hntr = "Hunter",
	rogue = "Rogue", rogues = "Rogue", rog = "Rogue", rouge = "Rogue",
	priest = "Priest", priests = "Priest", spriest = "Priest",
	hpriest = "Priest", shadowpriest = "Priest",
	shaman = "Shaman", shamans = "Shaman", sham = "Shaman",
	shammy = "Shaman", rsham = "Shaman",
	mage = "Mage", mages = "Mage",
	warlock = "Warlock", warlocks = "Warlock", lock = "Warlock",
	locks = "Warlock",
	druid = "Druid", druids = "Druid", dudu = "Druid", drood = "Druid",
	rdruid = "Druid", boomkin = "Druid", moonkin = "Druid",
}

-- Returns the text for the cell and the set the class filter reads. A post
-- naming more than two classes is a recruitment list, so the cell says so
-- rather than growing sideways.
function AGF.ParseClass(t)
	local seen, out = {}, {}
	for i = 1, #CLASS_PHRASES do
		local name = CLASS_PHRASES[i][2]
		if has(t, CLASS_PHRASES[i][1]) and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	for _, w in ipairs(words(t)) do
		local name = CLASS_WORDS[w]
		if name and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	if #out == 0 then
		return nil, nil
	end
	if #out > 2 then
		return "Several", seen
	end
	return table.concat(out, " / "), seen
end

function AGF.ParseRoles(t)
	local set = {}
	for i = 1, #ROLE_PHRASES do
		if has(t, ROLE_PHRASES[i][1]) then
			set[ROLE_PHRASES[i][2]] = true
		end
	end
	for _, w in ipairs(words(t)) do
		local role = ROLE_WORD_MAP[w]
		if role then
			set[role] = true
		else
			local num, rest = w:match("^(%d+)(%a+)$")
			if num and rest and ROLE_WORD_MAP[rest] then
				set[ROLE_WORD_MAP[rest]] = true
			elseif w:match("^%d[thds]") and w:gsub("%d[thds]", "") == "" then
				for _, letter in w:gmatch("(%d)([thds])") do
					set[COMPACT[letter]] = true
				end
			end
		end
	end
	for i = 1, #ANY_ROLE_PHRASES do
		if has(t, ANY_ROLE_PHRASES[i]) then
			set.tank, set.heal, set.damage = true, true, true
			set.support = true
			set.any = true
		end
	end
	return set
end

function AGF.RoleText(set)
	if not set then
		return "?"
	end
	-- Every role at once reads better as one word than as a list of three.
	if set.any then
		return "any"
	end
	local out = {}
	for i = 1, #ROLE_ORDER do
		if set[ROLE_ORDER[i]] then
			out[#out + 1] = ROLE_ORDER[i]
		end
	end
	if #out == 0 then
		return "?"
	end
	return table.concat(out, ", ")
end

-- 4. Intent -----------------------------------------------------------------
-- Word position carries the meaning. A role named after the looking-for token
-- is a role being recruited. A role named before it is the sender describing
-- themselves. "lf dps" recruits, "dps lf" offers.

local NOISE_WORDS = {
	"what", "whats", "why", "how", "when", "where", "who", "which", "idk",
	"should", "anyone know", "does", "do i", "can i get", "is it", "are",
	"wts", "wtb", "selling", "buying", "price", "gz", "grats", "lol",
	"ty", "thanks", "says", "bugged", "broken", "question",
}

-- Wording only a group leader uses.
local LEADER_SIGNS = {
	"pst", "pst me", "pst for inv", "pst info", "pm info", "pm me",
	"pm for info", "pm for inv", "msg me", "message me", "whisper me",
	"w me", "dm me", "invite bot", "inv bot", "priority", "spots",
	"spot", "spot left", "spots left", "join us", "we need", "forming",
	"making group", "making grp", "who wants", "anyone wants", "need more",
	"include in message", "send info", "apply",
}

-- Wording only a player looking for a group uses.
local LFG_STRONG = {
	"inv me", "invite me", "inv pls", "inv plz", "inv plox", "pls inv",
	"plz inv", "invite pls", "invite plz", "send invite", "send inv",
	"invite please", "inv please", "can i join", "could i join",
	"looking to join", "want to join", "wanna join", "lf inv", "lfinv",
	"lf invite", "need inv", "need invite", "need group", "need grp",
	"need a group", "need party", "want group", "want inv", "inv here",
	"take me", "add me", "count me", "me too", "sign me up", "im free",
	"i am free", "available for", "free for ms", "ready for ms",
}

local LFM_WEAK = {
	"lfm", "lf m", "lfmore", "lf more", "need more", "spot open",
	"spots open", "spot left", "spots left", "forming", "making group",
	"making grp", "who wants", "anyone wants", "join us", "we need",
	"recruiting for ms", "still need", "more needed",
}

local LFG_WEAK = {
	"lfg", "lf g", "lf group", "lf grp", "lf grup", "lf grupe", "lf gruop",
	"looking for group", "lf party", "lf pt", "lf run", "lf raid", "lf ms",
	"lf manastorm", "lg ms", "lg", "lfms", "free dps", "free heal",
	"free tank", "any room", "room for me", "plus1", "plus2", "plus3",
	"lf farm", "lf spam", "lf carry", "lf lvling", "lf leveling",
	"searching for ms", "search for ms", "searching ms", "seeking ms",
	"any ms", "ms pls", "ms plz", "join ms", "wanna ms", "up for ms",
	"down for ms", "in for ms", "anyone doing ms", "who is doing ms",
	"whos doing ms", "looking for ms",
}

local SELF_ADS = {
	"with aura", "w aura", "have aura", "got aura", "has aura", "exp aura",
	"full looms", "full loom", "looms", "loom", "loomed", "heirloom",
	"heirlooms", "prestige", "prestiged", "geared", "i have", "i am",
	"im", "my", "free", "ready", "available", "lvling", "leveling",
	"can go", "want to go", "wanna go",
}

local function lfKindOf(w)
	if w == "lfm" or w == "lfmore" or w:match("^lfm%d+$") or w:match("^lf%d+m$") then
		return "lfm"
	end
	if w == "lfg" or w == "lg" or w == "lgf" or w == "lfms" or w:match("^lfg%d*$") then
		return "lfg"
	end
	if w == "lf" or w:match("^lf%d+$") then
		return "lf"
	end
	if w == "looking" or w == "searching" or w == "seeking" or w == "search" then
		return "lf"
	end
	if w == "need" or w == "needs" or w == "want" or w == "wants" or w == "wanted" then
		return "need"
	end
	return nil
end

-- What the looking-for token points at. "lf ms" and "lf group" mean the
-- sender wants a group and any role named afterwards describes the sender.
-- "lf dps" and "lf 2 tanks" mean the sender is filling a group. This beats
-- the role-position rule, because "lf ms dps" puts the role after the token
-- while still being an offer.
local GROUP_OBJECTS = {
	["group"] = true, ["grp"] = true, ["grup"] = true, ["gruop"] = true,
	["grupe"] = true, ["gruppe"] = true, ["party"] = true, ["pt"] = true,
	["raid"] = true, ["run"] = true, ["team"] = true, ["farm"] = true,
	["farming"] = true, ["spam"] = true, ["spamm"] = true, ["loop"] = true,
	["push"] = true, ["carry"] = true, ["leveling"] = true,
	["levelling"] = true, ["lvling"] = true, ["lvls"] = true,
	["duo"] = true, ["trio"] = true, ["ms"] = true, ["mss"] = true,
	["msing"] = true, ["manastorm"] = true, ["manastorms"] = true,
	["mstorm"] = true, ["manastrom"] = true, ["manstorm"] = true,
}

-- Words that carry no meaning between the token and its object.
local OBJECT_FILLERS = {
	["a"] = true, ["an"] = true, ["the"] = true, ["for"] = true,
	["some"] = true, ["any"] = true, ["to"] = true, ["in"] = true,
	["on"] = true, ["of"] = true, ["fast"] = true, ["quick"] = true,
	["new"] = true, ["good"] = true, ["big"] = true, ["giga"] = true,
	["chill"] = true, ["active"] = true,
}

local function lfObjectIsGroup(list, at)
	for i = at + 1, math.min(at + 4, #list) do
		local w = list[i]
		if w:match("^size%d+$") or OBJECT_FILLERS[w] then
			-- Skip and keep reading.
		elseif roleAt(w) then
			return false
		elseif w:match("^%d+$") then
			return false
		elseif GROUP_OBJECTS[w] or packGroupWord(w) or w:match("^ms%d+s?$")
			or w:match("^manastorm%d+$") or w:match("^mstorm%d+$") then
			return true
		else
			return false
		end
	end
	return false
end

-- A wanted headcount, not a level. Only small numbers count as a headcount
-- unless the text spells it out with m, more or a spot.
function AGF.RecruitCount(t)
	local explicit = t:match(" lf ?(%d+) ?m ") or t:match(" lf ?(%d+) ?m[thd] ")
		or t:match(" lf ?(%d+) ?more ") or t:match(" lfm ?(%d+) ")
		or t:match(" need ?(%d+) ") or t:match(" (%d+) more ")
		or t:match(" (%d+) spot ") or t:match(" (%d+) spots ")
		or t:match(" want (%d+) ") or t:match(" looking for (%d+) ")
	if explicit then
		return tonumber(explicit)
	end
	local loose = t:match(" lf ?(%d+) ")
	if loose then
		local v = tonumber(loose)
		if v and v <= 9 then
			return v
		end
	end
	return nil
end

-- Trade has its own pair of intents. Want to trade counts as want to buy.
local WTS_WORDS = { "wts", "selling", "sell", "sells", "for sale", "lfw",
	"offering", "offer", "can craft", "crafting", "your mats", "my mats",
	"providing", "in stock" }
local WTB_WORDS = { "wtb", "buying", "buy", "wtt", "paying", "will pay",
	"looking for", "need", "needs", "want", "wanted", "searching for",
	"lf", "lfw for", "anyone selling" }

function AGF.TradeIntent(t)
	for i = 1, #WTS_WORDS do
		if has(t, WTS_WORDS[i]) then
			return "WTS"
		end
	end
	for i = 1, #WTB_WORDS do
		if has(t, WTB_WORDS[i]) then
			return "WTB"
		end
	end
	return "UNSURE"
end

function AGF.Classify(t)
	local list = words(t)
	local firstLF, kind
	for i = 1, #list do
		local k = lfKindOf(list[i])
		if k and not firstLF then
			firstLF, kind = i, k
		end
	end

	local before, after = {}, {}
	local countBefore, countAfter = 0, 0
	for i = 1, #list do
		local role = roleAt(list[i])
		if role then
			if firstLF and i > firstLF then
				if not after[role] then
					after[role] = true
					countAfter = countAfter + 1
				end
			else
				if not before[role] then
					before[role] = true
					countBefore = countBefore + 1
				end
			end
		end
	end

	local leader = hasAny(t, LEADER_SIGNS)
	local selfAd = hasAny(t, SELF_ADS)
	local count = AGF.RecruitCount(t)

	-- 1. Someone asking to be taken along says so plainly.
	if hasAny(t, LFG_STRONG) then
		return "LFG"
	end

	-- 2. Guild adverts and chatter.
	if has(t, "recruiting") or has(t, "recruit") or has(t, "recrute")
		or has(t, "guild") or has(t, "guilde") or has(t, "gilde") then
		return "UNSURE"
	end
	if not firstLF and not leader and not hasAny(t, LFM_WEAK)
		and not hasAny(t, LFG_WEAK) and hasAny(t, NOISE_WORDS) then
		return "UNSURE"
	end

	-- 3. Explicit lfm, or a wanted headcount.
	if kind == "lfm" or count then
		return "LFM"
	end

	-- 4. Explicit lfg always means the sender wants a group.
	if kind == "lfg" then
		return "LFG"
	end

	-- 5. need or want: a role after it is being recruited.
	if kind == "need" then
		if countAfter > 0 then
			return "LFM"
		end
		if countBefore > 0 then
			return "LFG"
		end
		return leader and "LFM" or "LFG"
	end

	-- 6. Bare lf: what the token points at wins, then role position.
	if kind == "lf" then
		-- "lf ms", "lf ms dps", "lf group", "searching for ms": the sender
		-- wants the group, so a role afterwards describes the sender.
		if lfObjectIsGroup(list, firstLF) then
			if count or leader or t:find("%d+by%d+") then
				return "LFM"
			end
			return "LFG"
		end
		if countAfter >= 2 then
			return "LFM"
		end
		if countAfter == 1 then
			if leader then
				return "LFM"
			end
			if selfAd or countBefore > 0 then
				return "LFG"
			end
			return "LFM"
		end
		if countBefore > 0 then
			return "LFG"
		end
		if leader then
			return "LFM"
		end
		return "LFG"
	end

	-- 7. No looking-for token at all.
	if t:find("%d+by%d+") then
		-- Group progress such as 2/2 tanks, 8/10 dps, 14/15.
		return "LFM"
	end
	if hasAny(t, LFM_WEAK) or leader then
		return "LFM"
	end
	if hasAny(t, LFG_WEAK) then
		return "LFG"
	end
	if countBefore > 0 and (selfAd or countBefore >= 1) then
		return "LFG"
	end
	return "UNSURE"
end

-- 5. Aura of Experience and heirlooms ---------------------------------------
-- Deterministic, never unknown. One mention means yes. No mention means no.
-- A negation means no and carries across a list, so "no aura or looms" sets
-- both to no.

local AURA_SET = {
	aura = true, auras = true, aurra = true, aur = true, aurea = true,
	auraexp = true, auraxp = true, expaura = true, xpaura = true,
	aoexp = true, auraofexp = true,
}

local LOOM_SET = {
	loom = true, looms = true, loomed = true, loomz = true, lums = true,
	heirloom = true, heirlooms = true, heriloom = true, herilooms = true,
	hierloom = true, hierlooms = true, heirlomes = true, hairlooms = true,
	hairloom = true, heirlums = true,
}

local NEGATORS = {
	["no"] = true, ["not"] = true, ["non"] = true, ["none"] = true,
	["without"] = true, ["wo"] = true, ["dont"] = true, ["doesnt"] = true,
	["havent"] = true, ["hasnt"] = true, ["lacking"] = true,
	["missing"] = true, ["zero"] = true, ["never"] = true, ["nope"] = true,
}

-- Filler that keeps a negation open: "no aura or full looms".
local CARRIERS = {
	["or"] = true, ["and"] = true, ["any"] = true, ["the"] = true,
	["my"] = true, ["full"] = true, ["exp"] = true, ["xp"] = true,
	["experience"] = true, ["of"] = true, ["a"] = true, ["yet"] = true,
	["have"] = true, ["has"] = true, ["got"] = true,
}

-- A token right after the keyword that flips it: "aura off", "looms no".
local OFF_WORDS = {
	["off"] = true, ["no"] = true, ["none"] = true, ["0"] = true,
	["missing"] = true, ["gone"] = true,
}

function AGF.ParseAuraLooms(t)
	local list = words(t)
	local auraPos, auraNeg = false, false
	local loomPos, loomNeg = false, false
	local scope = 0

	for i = 1, #list do
		local word = list[i]

		-- Glued negatives such as noaura, nolooms, unloomed.
		local stripped = word:gsub("^un", "")
		stripped = stripped:gsub("^no", "")
		local gluedNeg = false
		if stripped ~= word and (AURA_SET[stripped] or LOOM_SET[stripped]) then
			gluedNeg = true
		end

		if gluedNeg then
			if AURA_SET[stripped] then
				auraNeg = true
			end
			if LOOM_SET[stripped] then
				loomNeg = true
			end
			scope = 0
		elseif NEGATORS[word] then
			scope = 4
		elseif AURA_SET[word] or LOOM_SET[word] then
			local nextWord = list[i + 1]
			local negated = false
			if scope > 0 then
				negated = true
			elseif nextWord and OFF_WORDS[nextWord] then
				negated = true
			end
			if AURA_SET[word] then
				if negated then
					auraNeg = true
				else
					auraPos = true
				end
			else
				if negated then
					loomNeg = true
				else
					loomPos = true
				end
			end
			if scope > 0 then
				scope = scope - 1
			end
		elseif CARRIERS[word] then
			-- keeps the current negation scope open
		elseif scope > 0 then
			scope = scope - 1
		end
	end

	-- State is what the text literally did: pos = mentioned, neg = denied,
	-- none = never mentioned. The displayed value depends on the tab, because
	-- a mention means different things in a recruit post and in an offer.
	local auraState = "none"
	if auraNeg then
		auraState = "neg"
	elseif auraPos then
		auraState = "pos"
	end
	local loomState = "none"
	if loomNeg then
		loomState = "neg"
	elseif loomPos then
		loomState = "pos"
	end

	local aura = (auraState == "pos") and "yes" or "no"
	local looms = (loomState == "pos") and "yes" or "no"
	return aura, looms, auraState, loomState
end

function AGF.ParseAura(t)
	local aura = AGF.ParseAuraLooms(t)
	return aura
end

function AGF.ParseLooms(t)
	local _, looms = AGF.ParseAuraLooms(t)
	return looms
end

-- 6. Level ------------------------------------------------------------------

-- The highest character level on the realm. A number above it is an item
-- level, so the level parser stops here and BareIlvl picks the number up.
local LEVEL_CAP = 60

-- The widest item level worth believing. Above this the number is a price,
-- a gold amount or an item name.
local ILVL_MAX = 600

-- Published so the cell editor accepts exactly what the parser accepts.
AGF.LEVEL_CAP = LEVEL_CAP

-- The cap is 60 on the vanilla realms and 70 on Area 52. Packs.lua calls this
-- the moment it picks a pack, which happens before the first message arrives.
function AGF.SetLevelCap(value)
	value = tonumber(value)
	if not value or value < 10 or value > 255 then
		return
	end
	LEVEL_CAP = value
	AGF.LEVEL_CAP = value
end
AGF.ILVL_MAX = ILVL_MAX

local LEVEL_PATTERNS = {
	" lvl (%d+) ", " lvl(%d+) ", " lv (%d+) ", " lv(%d+) ",
	" level (%d+) ", " level(%d+) ", " (%d+) lvl ", " (%d+)lvl ",
	" (%d+) lv ", " (%d+)lv ", " l(%d+) ",
}

function AGF.ParseLevel(t, hasCount)
	for i = 1, #LEVEL_PATTERNS do
		local v = tonumber(t:match(LEVEL_PATTERNS[i]) or "")
		if v and v >= 1 and v <= LEVEL_CAP then
			return v, false
		end
	end
	local lo, hi = t:match(" (%d+)%s*%-%s*(%d+) ")
	if lo and hi then
		lo, hi = tonumber(lo), tonumber(hi)
		if lo and hi and lo >= 1 and hi <= LEVEL_CAP and lo <= hi then
			return lo, true
		end
	end
	-- A lone number can be a level, but only when nothing else claims it.
	if not hasCount then
		local found, seen = nil, 0
		for _, w in ipairs(words(t)) do
			if w:match("^%d+$") then
				seen = seen + 1
				found = tonumber(w)
			end
		end
		if seen == 1 and found and found >= 10 and found <= LEVEL_CAP then
			return found, false
		end
	end
	return nil, false
end

-- 7. Pack activities, item level, hard reserve, progress --------------------

-- Which activity the message is about, or nil when the pack knows nothing
-- about it. Pack order decides precedence, so a tour beats a single boss.
function AGF.MatchActivity(t)
	local pack = AGF.ActivePack and AGF.ActivePack()
	if not pack then
		return nil
	end
	for i = 1, #pack.activities do
		local a = pack.activities[i]
		local hit = false

		-- Manastorm keeps its own matcher, because bare ms has to reject the
		-- main spec loot rule.
		if a.matcher == "manastorm" and AGF.MatchesManastorm(t) then
			hit = true
		end
		if not hit and a.phrases then
			for j = 1, #a.phrases do
				if has(t, a.phrases[j]) then
					hit = true
					break
				end
			end
		end
		if not hit and a.words then
			for j = 1, #a.words do
				if has(t, a.words[j]) then
					hit = true
					break
				end
			end
		end

		-- A named target always enriches the row. It only identifies the
		-- activity when the pack says so.
		local target
		if a.targets then
			for j = 1, #a.targets do
				if has(t, a.targets[j]) then
					target = a.targets[j]
					if a.targetIdentifies then
						hit = true
					end
					break
				end
			end
		end

		if hit then
			return a.id, a.name, a.short or a.name, target
		end
	end
	return nil
end

-- Item level. Tagged like a size token, so the number can never be read again
-- as a level or as a wanted headcount. "65 ilvl" becomes "ilv65 ilvl".
local ILVL_STEMS = { "ilvl", "ilvls", "ilv", "ilevel", "itemlevel", "il" }

function AGF.MarkIlvl(t)
	local found
	local function keep(n)
		local v = tonumber(n)
		if v and v >= 10 and v <= 600 then
			found = found or v
		end
	end
	for i = 1, #ILVL_STEMS do
		local stem = ILVL_STEMS[i]
		t = t:gsub(" " .. stem .. " (%d+) ", function(n)
			keep(n)
			return " " .. stem .. " ilv" .. n .. " "
		end)
		t = t:gsub(" " .. stem .. "(%d+) ", function(n)
			keep(n)
			return " " .. stem .. " ilv" .. n .. " "
		end)
		t = t:gsub(" (%d+) " .. stem .. " ", function(n)
			keep(n)
			return " ilv" .. n .. " " .. stem .. " "
		end)
		t = t:gsub(" (%d+)" .. stem .. " ", function(n)
			keep(n)
			return " ilv" .. n .. " " .. stem .. " "
		end)
	end
	-- "i72". A one letter stem is only trusted well above the level cap,
	-- because "i 2" is far more often "invite 2" than an item level.
	t = t:gsub(" i(%d+) ", function(n)
		local v = tonumber(n)
		if v and v > LEVEL_CAP and v <= ILVL_MAX then
			keep(n)
			return " ilv" .. n .. " ilvl "
		end
		return " i" .. n .. " "
	end)
	-- "68+" arrives from the normaliser as "68 plus". Above the level cap it
	-- can only be gear, at or below it it is a level range and stays put.
	t = t:gsub(" (%d+) plus ", function(n)
		local v = tonumber(n)
		if v and v > LEVEL_CAP and v <= ILVL_MAX then
			keep(n)
			return " ilv" .. n .. " ilvl "
		end
		return " " .. n .. " plus "
	end)
	-- "+64" arrives from the normaliser as "plus64". Written in front it means
	-- what "64+" means behind: a gear floor, never a keystone level.
	t = t:gsub(" plus(%d+) ", function(n)
		local v = tonumber(n)
		if v and v > LEVEL_CAP and v <= ILVL_MAX then
			keep(n)
			return " ilv" .. n .. " ilvl "
		end
		return " plus" .. n .. " "
	end)
	return t, found
end

function AGF.ParseIlvl(t)
	local _, v = AGF.MarkIlvl(t)
	return v
end

-- "lfg zg 62 dps" states an item level without saying so. The realm caps a
-- character at LEVEL_CAP, so a bare number above it can only be gear. Only
-- one bare number is accepted, the same rule the lone level uses: with two
-- loose numbers in a line there is no way to tell which one is the gear.
-- isTrade switches the rule off: in a trade post a lone number is a price
-- far more often than it is gear.
function AGF.BareIlvl(t, isTrade)
	if isTrade then
		return nil
	end
	local found, seen = nil, 0
	for _, w in ipairs(words(t)) do
		if w:match("^%d+$") then
			seen = seen + 1
			found = tonumber(w)
		end
	end
	if seen == 1 and found and found > LEVEL_CAP and found <= ILVL_MAX then
		return found
	end
	return nil
end

-- Difficulty. Raids and world bosses on this realm run Normal, Heroic, Mythic
-- and Ascended, so the tag earns its own column. A keystone settles it before
-- any word does: a key is Mythic by definition.
-- Levelling traffic. A character at the cap earns no experience, so a post
-- that sells experience is a levelling group whatever level it names, or none.
-- "UBRS XP farm" and "dungeon spam got xp" are the wording in the logs.
local XP_WORDS = { "xp", "xps", "exp", "exps", "experience", "leveling",
	"levelling", "lvling", "lvlup", "powerlevel", "powerleveling" }
local XP_PHRASES = {
	"xp farm", "exp farm", "xp farming", "exp farming", "xp spam",
	"exp spam", "xp grind", "exp grind", "xp run", "exp run",
	"got xp", "for xp", "need xp", "want xp", "xp boost", "boost xp",
	"power level", "power leveling", "power levelling", "level up",
	"lvl up", "dungeon leveling", "dungeon levelling",
}

-- Boosting. "LFM UBRS BOOST 60 TANK CARRY SUPER RUN EZ" sells experience
-- without ever saying xp. The words on their own are not proof: a keystone
-- group says carry too, and a sold boost belongs to Trade, so the caller
-- asks about these only for a non mythic group post.
local BOOST_WORDS = { "boost", "boosts", "boosting", "boosted", "boostin",
	"carry", "carries", "carrying", "carried", "plvl", "plevel" }
local BOOST_PHRASES = { "boost run", "boost runs", "carry run", "carry runs",
	"boost group", "carry group" }

function AGF.ParseBoost(t)
	if not (t and AGF.Has) then
		return false
	end
	for i = 1, #BOOST_PHRASES do
		if AGF.Has(t, BOOST_PHRASES[i]) then
			return true
		end
	end
	for i = 1, #BOOST_WORDS do
		if AGF.Has(t, BOOST_WORDS[i]) then
			return true
		end
	end
	return false
end

function AGF.ParseLevelling(t)
	if not (t and AGF.Has) then
		return false
	end
	for i = 1, #XP_PHRASES do
		if AGF.Has(t, XP_PHRASES[i]) then
			return true
		end
	end
	for i = 1, #XP_WORDS do
		if AGF.Has(t, XP_WORDS[i]) then
			return true
		end
	end
	return false
end

local DIFF_WORDS = {
	{ " ascended ", "Ascended" },
	{ " ascendant ", "Ascended" },
	{ " asc ", "Ascended" },
	{ " mythic ", "Mythic" },
	{ " myth ", "Mythic" },
	{ " heroic ", "Heroic" },
	{ " hc ", "Heroic" },
	{ " hcs ", "Heroic" },
	{ " normal ", "Normal" },
	{ " norm ", "Normal" },
	{ " nm ", "Normal" },
}

function AGF.ParseDifficulty(t, mythicLevel)
	if mythicLevel then
		return "Mythic"
	end
	if not t then
		return nil
	end
	for i = 1, #DIFF_WORDS do
		if t:find(DIFF_WORDS[i][1], 1, true) then
			return DIFF_WORDS[i][2]
		end
	end
	return nil
end

AGF.DIFF_ORDER = { "Normal", "Heroic", "Mythic", "Ascended" }

-- Raid progress. Normalisation already folded 15/25 into 15by25. A total of
-- ten or more also settles the group size, which is how tours advertise it.
function AGF.ParseProgress(t)
	local a, b = t:match("(%d+)by(%d+)")
	if not a then
		return nil
	end
	local have, total = tonumber(a), tonumber(b)
	if not have or not total then
		return nil
	end
	if total < 2 or total > 40 or have > total then
		return nil
	end
	local size
	if total >= 10 then
		size = total
	end
	return have .. "/" .. total, size
end

-- 8. Entry point ------------------------------------------------------------

-- Addon adverts are not player adverts. FrostSeek broadcasts its own link into
-- the same channels, and it matched the LFG wording in the log.
local AD_MARKS = {
	"frostseek", "http://", "https://", "github.com", "curseforge",
}

function AGF.IsAddonAdvert(raw)
	local low = string.lower(tostring(raw or ""))
	for i = 1, #AD_MARKS do
		if string.find(low, AD_MARKS[i], 1, true) then
			return true
		end
	end
	return false
end

-- Sections -------------------------------------------------------------------
-- Every row lands in one of three sections. PvE is the activity rows, the
-- original LFM and LFG tabs. PvP is arenas, battlegrounds and other pvp.
-- Trade is professions, donation points, bazaar tokens and the leftover
-- trade lines. Routing happens here in the parser: it returns a route and
-- Core turns that into a bucket.

local PVP_ARENA = { "arena", "2v2", "3v3", "5v5", "2s", "3s", "5s" }
local PVP_BG = {
	"bg", "bgs", "battleground", "battlegrounds", "wsg", "warsong",
	"warsong gulch", "ab", "arathi", "arathi basin", "av", "alterac",
	"alterac valley", "eots", "eye of the storm", "sota", "strand",
	"strands", "strand of the ancients", "wintergrasp", "wg", "ioc",
	"isle of conquest",
}
local PVP_OTHER = {
	"pvp", "premade", "premades", "rated", "wpvp", "world pvp",
	"duel", "duels", "arena points", "honor farm", "rating push",
}
-- Weak pvp words only count when the line also wants people.
local PVP_WEAK = { "honor", "rating", "cap", "partner", "teammates" }

-- High Risk is the endgame PvP mode on the Ascension realms. The same two
-- letters are also the loot rule Hard Reserved, which is written in dungeon
-- and raid adverts all day: "LF2M ZH HC HR MS/OS".
--
-- The rule is therefore context, not spelling. Any HR wording counts as the
-- PvP mode only when the line also says something about PvP. On its own it
-- is a loot rule, so it names no activity and the line is read as whatever
-- else it is about.
local HR_WORDS = { "hr", "hrs", "high risk", "high-risk", "highrisk",
	"hrisk", "h risk" }

-- Wording that carries the PvP mode inside itself. No second word needed.
local HR_STRONG = { "hr pvp", "pvp hr", "hr mode", "high risk mode",
	"hr arena", "hr bg", "hr duel", "hr duels", "hr gank", "hr ganking",
	"hr world pvp", "hr wpvp", "high risk pvp", "high risk arena",
	"high risk bg", "high risk zone", "high risk farm" }

-- What makes the rest of the line PvP. The arena, battleground and other PvP
-- lists are reused, so a word only has to be added in one place.
local HR_CONTEXT = { "pvp", "p v p", "world pvp", "wpvp", "gank", "ganking",
	"gankers", "open world", "outdoor pvp", "kill on sight", "kos" }

local function pvpContext(t)
	if hasAny(t, HR_CONTEXT) or hasAny(t, PVP_ARENA) or hasAny(t, PVP_BG)
		or hasAny(t, PVP_OTHER) then
		return true
	end
	return false
end

function AGF.MatchHighRisk(t)
	if hasAny(t, HR_STRONG) then
		return true
	end
	if not hasAny(t, HR_WORDS) then
		return false
	end
	return pvpContext(t)
end

-- Guild recruitment reaches both group tabs. A guild that recruits for arena
-- teams belongs in PvP, one that recruits raiders belongs in PvE, and the
-- same test decides it.
function AGF.IsPvPContext(t)
	return pvpContext(t)
end

-- Mythic keystones. The realm writes them several ways:
--   "LFM Keystone: Uldaman (3)"    the level rides in brackets
--   "LFG mythic+7", "LF tank m+"   written as a plus, often with no number
--   "Completed Mythic: 10"         the highest key the sender has ever run,
--                                  never the level of the group being formed
--
-- The normaliser has already lowered the text, dropped the brackets and
-- turned "+7" into "plus7", so a bracketed level arrives as a bare number.
local MYTHIC_WORDS = { "mythic", "mythics", "mythic dungeon", "keystone",
	"keystones", "mplus", "m plus" }

-- A number straight after one of these counts players, not keystone levels:
-- "Keystone: Uldaman need 2 dps".
local NOT_A_LEVEL = {
	need = true, needs = true, lf = true, lfm = true, lfg = true,
	inv = true, more = true, want = true, wanted = true, missing = true,
	x = true, got = true, have = true, spots = true, spot = true,
}

-- A word straight behind the number turns it back into a head count:
-- "mythic 2 dps" wants two damage dealers, not a key level of two.
local COUNTED_BY = {
	dps = true, dd = true, dds = true, dd_s = true, tank = true,
	tanks = true, heal = true, heals = true, healer = true, healers = true,
	healz = true, healz_ = true, more = true, ppl = true, people = true,
	players = true, player = true, spots = true, spot = true, man = true,
	mans = true, spec = true, specs = true,
}

local MYTHIC_TIERS = { m0 = 0, m1 = 1, m2 = 2, m3 = 3 }

-- True when the post is about a mythic run, with the keystone level whenever
-- the text states one.
function AGF.MatchMythic(t)
	-- The boast goes first, so its number can never be read as a level and its
	-- "mythic" can never make idle chat look like a group post.
	local clean = t:gsub("completed%s+mythic%s*%d*", " ")
	clean = clean:gsub("%s+", " ")

	local level
	local isMythic = hasAny(clean, MYTHIC_WORDS)

	for token, tier in pairs(MYTHIC_TIERS) do
		if has(clean, token) then
			isMythic = true
			level = level or tier
		end
	end

	-- "mythic+7" and "m+7".
	local plus = clean:match("mythic plus(%d+)") or clean:match(" m plus(%d+)")
	if plus then
		isMythic = true
		level = tonumber(plus)
	end

	-- "mythic 10" and "mythic key 10" write the level as a plain number behind
	-- the word. Two digits at most, and the head count words in front are
	-- ruled out further down the same way the keystone line does it.
	if not level then
		local after = clean:match("mythics? key (%d%d?)")
			or clean:match("mythics? (%d%d?)")
		local n = tonumber(after or "")
		if n and n >= 0 and n <= 99 then
			isMythic = true
			level = n
		end
	end

	-- "M8+", "m12" and "lfg m8" name the keystone level without the word
	-- anywhere near it. The tiers above cover m0 to m3, this covers the rest of
	-- the ladder. Two digits at most, so a date or an item count is never read
	-- as a keystone.
	if not level then
		local bare = clean:match(" m(%d%d?) ") or clean:match(" m(%d%d?)$")
		local n = tonumber(bare or "")
		if n and n >= 0 and n <= 99 then
			isMythic = true
			level = n
		end
	end

	-- "LF +5 MYTHIC KEY GROUP" puts the plus in front of the wording instead of
	-- behind it. A loose plus one is left alone: "+1" far more often asks for an
	-- invite than names a keystone.
	if not level and isMythic then
		local loose = tonumber(clean:match(" plus(%d+)") or "")
		if loose and loose >= 2 and loose <= 40 then
			level = loose
		end
	end

	-- "Keystone: Wailing Caverns - Pit of the Fangs (9)". The first number
	-- after the word is the level, unless the word in front of it shows the
	-- number is a head count.
	if not level then
		local after = clean:match(" keystone (.*)$")
		if after then
			local lead, num = after:match("^(%D-)(%d+)")
			if num then
				local prev = lead:match("(%a+)%s*$")
				if not (prev and NOT_A_LEVEL[prev]) then
					local n = tonumber(num)
					if n and n >= 1 and n <= 40 then
						level = n
					end
				end
			end
		end
	end

	-- "1 healer for mythic 10" and "mythic 8 lfm" write the level with no plus
	-- and no brackets. The number straight behind the word is the level unless
	-- the word behind that shows it counts players.
	if not level then
		local num, after = clean:match("mythics? (%d+) ?(%a*)")
		local n = tonumber(num or "")
		if n and n >= 1 and n <= 40 and not COUNTED_BY[after or ""] then
			level = n
		end
	end

	-- A bare "m keys" or "push keys" carrying no number at all.
	if not isMythic and (has(clean, "keys") or has(clean, "key"))
		and (has(clean, "m") or has(clean, "push")) then
		isMythic = true
	end

	return isMythic, level
end

function AGF.MatchPvP(t)
	if AGF.MatchHighRisk(t) then
		return "HR"
	end
	for i = 1, #PVP_ARENA do
		if has(t, PVP_ARENA[i]) then return "ARENA" end
	end
	for i = 1, #PVP_BG do
		if has(t, PVP_BG[i]) then return "BG" end
	end
	for i = 1, #PVP_OTHER do
		if has(t, PVP_OTHER[i]) then return "PVP_OTHER" end
	end
	for i = 1, #PVP_WEAK do
		if has(t, PVP_WEAK[i]) then
			local intent = AGF.Classify(t)
			if intent == "LFM" or intent == "LFG" then
				return "PVP_UNSURE"
			end
			return nil
		end
	end
	return nil
end

local DP_WORDS = { "dp", "donation", "donations", "donor", "donate", "donation points", "donation point" }
local BAZAAR_WORDS = { "bazaar", "bazaar token", "bazaar tokens" }
local TRADE_WORDS = { "wts", "wtb", "wtt", "selling", "buying", "trading" }

local GOODS = {
	{ id = "AURA", name = "Aura", words = { "aura of experience", "aura of exp",
		"aura xp", "xp aura", "exp aura", "aura" } },
	{ id = "TOME", name = "Tome", words = { "tome of specialization", "tome of spec",
		"tome" } },
	{ id = "HEIRLOOM", name = "Heirloom", words = { "heirloom", "heirlooms",
		"weapon token", "looms" } },
	{ id = "TRANSMOG", name = "Transmog", words = { "transmog", "tmog", "mog set" } },
	{ id = "MOUNT", name = "Mount", words = { "reins of", "mount" } },
	{ id = "RECIPE", name = "Recipe", words = { "recipe", "pattern", "formula",
		"schematic", "plans" } },
	{ id = "LOOTBOT", name = "Lootbot", words = { "lootbot", "lootbox", "loot box",
		"mystic scroll", "mystic enchant" } },
	{ id = "CONSUM", name = "Consumable", words = { "flask", "flasks", "potion",
		"elixir", "scroll of" } },
	{ id = "GEAR", name = "Gear", words = { "staff", "sword", "greatsword",
		"axe", "dagger", "blade", "runeblade", "warblade", "slicer", "saber",
		"mace", "hammer", "spear", "glaive", "bow", "gun", "wand", "shield",
		"buckler", "effigy", "tomahawk", "cloak", "cape", "robe", "tunic",
		"vest", "hood", "helm", "crown", "shoulders", "pauldrons", "bracers",
		"gauntlets", "gloves", "belt", "girdle", "leggings", "pants", "boots",
		"treads", "ring of", "band", "pendant", "necklace", "amulet", "wings",
		"attire", "armor", "armour" } },
}

-- What a trade line is about. Only used when nothing more precise matched.
function AGF.MatchGoods(t)
	for i = 1, #GOODS do
		local g = GOODS[i]
		for j = 1, #g.words do
			if has(t, g.words[j]) then
				return g.id, g.name
			end
		end
	end
	return nil
end

function AGF.MatchTrade(t)
	for i = 1, #DP_WORDS do
		if has(t, DP_WORDS[i]) then return "DP" end
	end
	for i = 1, #BAZAAR_WORDS do
		if has(t, BAZAAR_WORDS[i]) then return "BAZAAR" end
	end
	for i = 1, #TRADE_WORDS do
		if has(t, TRADE_WORDS[i]) then return "TRADE_UNSURE" end
	end
	return nil
end

-- Stream adverts and pure trade spam. The Vol'jin logs showed these ride the
-- same channels as everything else and repost endlessly.
--
-- Guild recruitment used to be dropped here. It is a Guild activity now, so
-- it is parsed like any other post and hidden by the filter instead. Dropping
-- it at this point would make that activity unreachable.
--
-- Rules, deterministic:
--   1. Bazaar Token spam is trade, whatever the wording
--   2. wts / wtb / wtt with an item link is trade; the same words without a
--      link stay in, because "wtb tank for brd run" is a group advert
local SPAM_WORDS = { "wts", "wtb", "wtt", "selling", "buying" }

local STREAM_WORDS = { "twitch tv", "twitch", "t tv", "youtube", "youtu be",
	"youtu", "discord gg", "streaming", "live now", "has conjured" }

local GROUP_PROOF = { "lfm", "lfg", "lf inv", "need tank", "need tanks",
	"need heal", "need healer", "need healers", "need dps", "need dd",
	"need dds", "ms os", "pedir inv", "whisp class" }

function AGF.IsSpam(raw, t)
	-- A line that proves it is a real advert is never spam, whatever else it
	-- says.
	if hasAny(t, GROUP_PROOF) or AGF.RecruitCount(t) then
		return false
	end
	-- Stream adverts are dropped entirely. They are not group content and
	-- they repost endlessly. Trade has its own tabs.
	for i = 1, #STREAM_WORDS do
		if has(t, STREAM_WORDS[i]) then
			return true
		end
	end
	return false
end

function AGF.Parse(raw)
	local t = AGF.Normalize(raw)
	if AGF.IsAddonAdvert(raw) then
		return nil, t
	end
	if AGF.IsSpam(raw, t) then
		return nil, t
	end
	local size, ilvl
	t, size = AGF.MarkSize(t)
	t, ilvl = AGF.MarkIlvl(t)
	local actId, actName, actShort, target = AGF.MatchActivity(t)
	local mythicLevel

	-- A line that opens with wts / wtb / wtt is trade whatever it names.
	local head = t:match("^%s*(%a+)")
	if head == "wts" or head == "wtb" or head == "wtt" then
		actId, actName, actShort, target = nil, nil, nil, nil
	end

	-- Generic fallback. "59 TANK LFG WITH AURA" names no activity, but a role
	-- plus an aura or exp phrase is the realm's main leveling loop. The pack
	-- says which activity that is.
	if not actId then
		local pack = AGF.ActivePack and AGF.ActivePack()
		if pack and pack.generic and AGF.GENERIC_PHRASES then
			local earlyRoles = AGF.ParseRoles(t)
			if earlyRoles and next(earlyRoles) then
				for i = 1, #AGF.GENERIC_PHRASES do
					if has(t, AGF.GENERIC_PHRASES[i]) then
						for j = 1, #pack.activities do
							local a = pack.activities[j]
							if a.id == pack.generic then
								actId, actName, actShort = a.id, a.name, a.short or a.name
								break
							end
						end
						break
					end
				end
			end
		end
	end

	-- PvP. No activity matched, so arenas and battlegrounds get their say
	-- before professions and trade do.
	local route, subBucket
	if not actId then
		subBucket = AGF.MatchPvP(t)
		if subBucket then
			route = "PVP"
		end
	elseif actId == "GUILD" then
		-- Guild recruitment is its own section. A guild that recruits for PvP
		-- or for raids is still a guild, so there is nothing to route by
		-- content and nothing worth splitting by intent.
		route = "GUILD"
		subBucket = "GUILD"
	end

	-- Profession fallback. "LF BS with lionheart" and "Enchanter LFW your
	-- mats" name a craft, not an activity. These rows land in the Prof tab.
	local profession, profMode
	if not actId and not route then
		profession, profMode = AGF.ParseProfession(t)
		if profession then
			route = "TRADE"
			subBucket = "PROF"
		end
	end

	-- Donation points, bazaar tokens, leftover trade.
	if not actId and not route then
		subBucket = AGF.MatchTrade(t)
		if subBucket then
			route = "TRADE"
		end
	end

	if not actId and not route then
		return nil, t
	end
	local intent = AGF.Classify(t)
	-- A question is not an advert.
	if raw:find("%?%s*$") and not hasAny(t, LFG_STRONG)
		and not has(t, "lfm") and not has(t, "lfg") and not AGF.RecruitCount(t) then
		intent = "UNSURE"
	end
	-- Spanish, French and German adverts. Measured in the Vol'jin log:
	-- "GENTE PARA AZUREGOS PEDIR INV QUEDAN POCOS HUECOS" is a leader.
	local LFM_FOREIGN = { "gente para", "mas gente", "pedir inv", "quedan pocos",
		"hay sumon", "faltan", "necesitamos", "vamos a matar", "venez",
		"cherchons", "suchen noch" }
	local LFG_FOREIGN = { "busco grupo", "quiero entrar", "cherche groupe",
		"suche gruppe", "cerco gruppo" }
	if hasAny(t, LFM_FOREIGN) then
		intent = "LFM"
	elseif hasAny(t, LFG_FOREIGN) then
		intent = "LFG"
	end

	-- Talking about content is not looking for it.
	-- Opinions about content, classes and balance are the bulk of what a global
	-- channel carries. None of it is an advert.
	local CHATTER = { "tbh", "imo", "imho", "no point", "i think", "i guess",
		"does anyone know", "anyone know", "why is", "what is", "how do",
		"is tier", "tier s", "tier a", "better than", "is better",
		"is worse", "is trash", "is garbage", "any good", "worth it",
		"nerfed", "buffed", "after the buff", "after the nerf", "sucks",
		"suks", "the meta", "in my opinion", "i agree", "i disagree",
		"skill issue", "you should", "they should",
		-- Trade chat argues about prices and warns about people as much as it
		-- sells. None of that is an offer.
		"scam", "scammer", "scamming", "scammed", "flipper", "flipping",
		"dont buy from", "do not buy from", "dont get underpaid",
		"overprice", "overpriced", "underpaid", "check other buyers",
		"doesnt mean", "does not mean", "dont get" }
	-- Anything here means the line still asks for something, so opinion
	-- wording only downgrades it instead of dropping it.
	-- Trade verbs such as "selling" are deliberately not here. Warning other
	-- players off a seller uses the same words as selling does, and this list
	-- only decides whether a line that already reads as opinion is kept.
	local INVITE_MARKERS = { "lf", "inv", "invite", "invites", "pst", "pm",
		"whisper", "w me", "msg me", "dm", "join", "joining", "need",
		"looking for", "wts", "wtb", "wtt", "recruiting", "recruit",
		"apply", "spot", "spots", "summon", "summons", "port", "boost",
		"boosting", "carry" }
	if not has(t, "lfm") and not has(t, "lfg") and not AGF.RecruitCount(t)
		and not hasAny(t, LFG_STRONG) then
		if hasAny(t, CHATTER) then
			intent = "UNSURE"
			-- Nothing in the line asks for anything at all. An opinion about a
			-- class, a boss or the meta is not an advert, so it is dropped
			-- rather than parked in Unsure, where it only pads the tab.
			if not hasAny(t, INVITE_MARKERS) then
				return nil
			end
		end
	end

	-- Asking whether anyone runs a thing is asking to join it.
	if not has(t, "lfm") and not AGF.RecruitCount(t) then
		if t:find("any group") or t:find("any .- group ")
			or t:find("anyone doing") or t:find("anyone running")
			or t:find("any .- spam run") or t:find("any run") or t:find("spammer")
			or t:find("any .- tour") or t:find("can i join")
			or t:find("looking to join") then
			intent = "LFG"
		end
	end
	if route == "PVP" or route == "TRADE" then
		actName = subBucket == "DP" and "Donation points"
			or subBucket == "BAZAAR" and "Bazaar tokens"
			or subBucket == "HR" and "High Risk"
			or subBucket == "GUILD" and "Guild"
			or subBucket == "ARENA" and "Arena"
			or subBucket == "BG" and "Battleground"
			or subBucket == "PVP_OTHER" and "PvP"
			or subBucket == "PVP_UNSURE" and "PvP"
			or subBucket == "TRADE_UNSURE" and "Trade"
			or actName
		actShort = actName
	end
	-- The tab is decided by intent alone. What the line is about travels with
	-- the row as kind, and the filter panel uses it.
	local kind
	if route == "PVP" then
		kind = (subBucket == "PVP_UNSURE") and "PVP_OTHER" or subBucket
	elseif route == "TRADE" then
		kind = (subBucket == "TRADE_UNSURE") and "TRADE_OTHER" or subBucket
		if kind == "TRADE_OTHER" then
			local goodsId, goodsName = AGF.MatchGoods(t)
			if goodsId then
				kind = goodsId
				actName, actShort = goodsName, goodsName
			end
		end
	else
		kind = actId or "OTHER"
		-- Mythic runs are their own axis in PvE. The keystone level replaces the
		-- caption and the dungeon stays in the target, so a row reads
		-- "Mythic+ 7: Uldaman".
		-- Guild recruitment stays a guild even when the advert promises
		-- mythic runs, and a world boss is never a keystone.
		if actId ~= "WB" and actId ~= "WBT" and actId ~= "GUILD" then
			local isMythic, keyLevel = AGF.MatchMythic(t)
			-- "m2" on its own is a tier, not a place, so it leaves the target
			-- and becomes the caption.
			local tier = target and tostring(target):match("^m([0-3])$")
			if tier then
				isMythic = true
				keyLevel = keyLevel or tonumber(tier)
				target = nil
			end
			if isMythic and actId == "RAID" then
				-- The realm runs mythic raids as well, but a keystone level never
				-- belongs to one. A number in "LFM MC Mythic 1 tank" counts
				-- players, so the plus and the level both go: "Mythic: Molten
				-- Core".
				kind = "MYTHIC"
				mythicLevel = nil
				actName, actShort = "Mythic", "Mythic"
			elseif isMythic then
				kind = "MYTHIC"
				mythicLevel = keyLevel
				if keyLevel and keyLevel > 0 then
					actName = "Mythic+ " .. keyLevel
				elseif keyLevel == 0 then
					actName = "Mythic 0"
				elseif target then
					actName = "Mythic+"
				else
					actName = "Mythic+ Dungeon"
				end
				actShort = actName
			end
		end
	end
	local tradeIntent
	if route == "TRADE" then
		tradeIntent = AGF.TradeIntent(t)
	end

	local count = AGF.RecruitCount(t)
	local level, bracket = AGF.ParseLevel(t, count ~= nil)
	-- A keystone run is level cap content, always. Whatever number the line
	-- carries is the key, the dungeon wing or the group size, never the level
	-- of a character, so a mythic row never keeps a level at all.
	if kind == "MYTHIC" or mythicLevel or has(t, "keystone")
		or has(t, "keystones") then
		level, bracket = nil, false
	end
	if not ilvl then
		ilvl = AGF.BareIlvl(t, route == "TRADE")
	end
	local roleSet = AGF.ParseRoles(t)
	-- A leader who names no role wants anyone: "Keystone: Zul'Farrak (1) LFM".
	-- Only for a recruit post. A player looking for a group who names no role
	-- has said nothing about what they play, so that stays unknown.
	if intent == "LFM" and route ~= "TRADE" and not next(roleSet) then
		roleSet.tank, roleSet.heal, roleSet.damage = true, true, true
		roleSet.any = true
	end
	local classText, classSet = AGF.ParseClass(t)
	local aura, looms, auraState, loomsState = AGF.ParseAuraLooms(t)
	local prog, progSize = AGF.ParseProgress(t)
	local levelling = AGF.ParseLevelling(t)
	-- A boost run is a levelling group even when it never says xp. A keystone
	-- group that asks for a carry is not, and a sold boost sits in Trade, so
	-- both are left alone.
	if not levelling and route ~= "TRADE" and kind ~= "MYTHIC"
		and not mythicLevel and AGF.ParseBoost(t) then
		levelling = true
	end
	return {
		intent = intent,
		kind = kind,
		tradeIntent = tradeIntent,
		activity = actId,
		activityName = actName,
		activityShort = actShort,
		mythicLevel = mythicLevel,
		difficulty = AGF.ParseDifficulty(t, mythicLevel),
		levelling = levelling,
		profession = profession,
		profMode = profMode,
		route = route,
		subBucket = subBucket,
		target = AGF.PrettyName and AGF.PrettyName(target) or target,
		roleSet = roleSet,
		roleText = AGF.RoleText(roleSet),
		class = classText,
		classSet = classSet,
		aura = aura,
		looms = looms,
		auraState = auraState,
		loomsState = loomsState,
		ilvl = ilvl,
		prog = prog,
		level = level,
		bracket = bracket,
		size = size or progSize,
		wanted = count,
	}, t
end
