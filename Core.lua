-- Ascension Chat Scanner
-- Core.lua - chat capture, storage, filters, whisper templates, slash commands.

AGF = AGF or {}

-- The folder name of this addon. The client passes it into every addon file.
-- ADDON_LOADED must be matched against this, not against a hard coded string.
local ADDON_NAME = ... or "AscensionChatScanner"

-- One axis decides the tab: what the sender wants. Every section has the same
-- three tabs. What the line is about, such as arena or donation points, is
-- kept on the row as row.kind and is a filter, not a tab.
AGF.BUCKETS = {
	"PVE_LFM", "PVE_LFG", "PVE_UNSURE",
	"PVP_LFM", "PVP_LFG", "PVP_UNSURE",
	"TRADE_WTS", "TRADE_WTB", "TRADE_UNSURE",
	-- Guild recruitment has one list and no intent split: a guild that
	-- recruits and a player who wants a guild are looking for each other.
	"GUILD_ALL",
}

AGF.SECTIONS = {
	{ id = "PVE", label = "PvE", buckets = { "PVE_LFM", "PVE_LFG", "PVE_UNSURE" } },
	{ id = "PVP", label = "PvP", buckets = { "PVP_LFM", "PVP_LFG", "PVP_UNSURE" } },
	{ id = "TRADE", label = "Trade", buckets = { "TRADE_WTS", "TRADE_WTB", "TRADE_UNSURE" } },
	{ id = "GUILD", label = "Guild", buckets = { "GUILD_ALL" } },
}
AGF.BUCKET_SECTION = {}
AGF.BUCKET_LABEL = {
	PVE_LFM = "LFM", PVE_LFG = "LFG", PVE_UNSURE = "Unsure",
	PVP_LFM = "LFM", PVP_LFG = "LFG", PVP_UNSURE = "Unsure",
	TRADE_WTS = "WTS", TRADE_WTB = "WTB", TRADE_UNSURE = "Unsure",
	GUILD_ALL = "Guild",
}

-- One whisper line per section and intent. Unsure shares the line of the LFM
-- side of its section, because an unsure row is most often a recruit post.
AGF.WHISPER_SLOTS = {
	{ key = "pveLfm", label = "PvE LFM and Unsure - they lead a group, you ask for a spot" },
	{ key = "pveLfg", label = "PvE LFG - they look for a group, you offer a spot" },
	{ key = "pvpLfm", label = "PvP LFM and Unsure - they lead an arena, battleground or world PvP group" },
	{ key = "pvpLfg", label = "PvP LFG - they look for PvP, you offer a spot" },
	{ key = "tradeWts", label = "Trade WTS and Unsure - they sell or offer, you buy" },
	{ key = "tradeWtb", label = "Trade WTB - they buy or want, you sell" },
	{ key = "guild", label = "Guild - recruitment posts, you ask about joining" },
}

AGF.WHISPER_BUCKET_SLOT = {
	PVE_LFM = "pveLfm", PVE_UNSURE = "pveLfm", PVE_LFG = "pveLfg",
	PVP_LFM = "pvpLfm", PVP_UNSURE = "pvpLfm", PVP_LFG = "pvpLfg",
	TRADE_WTS = "tradeWts", TRADE_UNSURE = "tradeWts", TRADE_WTB = "tradeWtb",
	GUILD_ALL = "guild",
}

AGF.KIND_LABEL = {
	ARENA = "Arena", BG = "Battleground", HR = "High Risk",
	PVP_OTHER = "Other PvP", GUILD = "Guild",
	PROF = "Profession", DP = "Donation Points", BAZAAR = "Bazaar Tokens",
	TRADE_OTHER = "Other Trade", OTHER = "Other",
	AURA = "Aura", TOME = "Tome", HEIRLOOM = "Heirloom",
	TRANSMOG = "Transmog", MOUNT = "Mount", RECIPE = "Recipe",
	LOOTBOT = "Lootbot", CONSUM = "Consumable", GEAR = "Gear",
	MYTHIC = "Mythic+",
}
-- Filled at ingest, so a pack activity shows its short name in the filter.
AGF.KIND_NAMES = {}

function AGF.KindName(kind)
	if not kind then
		return "?"
	end
	return AGF.KIND_LABEL[kind] or AGF.KIND_NAMES[kind] or kind
end

-- The tab that holds a given intent inside a given section.
function AGF.BucketFor(section, intent)
	if section == "TRADE" then
		if intent == "WTS" or intent == "LFM" then
			return "TRADE_WTS"
		end
		if intent == "WTB" or intent == "WTT" or intent == "LFG" then
			return "TRADE_WTB"
		end
		return "TRADE_UNSURE"
	end
	-- One list, whatever the intent says.
	if section == "GUILD" then
		return "GUILD_ALL"
	end
	local prefix = (section == "PVP") and "PVP_" or "PVE_"
	if intent == "LFM" or intent == "LFG" then
		return prefix .. intent
	end
	return prefix .. "UNSURE"
end

-- LFM, LFG, UNSURE, WTS or WTB, without the section prefix.
function AGF.IntentOf(bucket)
	local b = tostring(bucket or "")
	return b:match("_(%u+)$") or b
end

-- Content types present in the rows of one section, for the filter panel.
function AGF.KindList(section)
	local seen, out = {}, {}
	for i = 1, #AGF.SECTIONS do
		local s = AGF.SECTIONS[i]
		if s.id == section then
			for j = 1, #s.buckets do
				local list = (ACS_DB and ACS_DB.rows and ACS_DB.rows[s.buckets[j]]) or {}
				for k = 1, #list do
					local kind = list[k].kind
					if kind and not seen[kind] then
						seen[kind] = true
						out[#out + 1] = kind
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Content types in one section with a row count each, most common first.
-- Every activity a section can hold, whether or not a row is in the list.
AGF.BASE_KINDS = {
	PVP = { "ARENA", "BG", "HR", "PVP_OTHER" },
	TRADE = { "DP", "BAZAAR", "PROF", "AURA", "TOME", "HEIRLOOM", "TRANSMOG",
		"MOUNT", "RECIPE", "LOOTBOT", "CONSUM", "GEAR", "TRADE_OTHER" },
	PVE = { "MYTHIC", "OTHER" },
}

-- The Activity filter is two levels deep. A category holds the activity ids
-- that belong to it and carries the named places behind its own submenu. Any
-- id that is in no category, such as Manastorm, Guild and Other, is offered on
-- its own with no submenu. None of this changes what the Activity column
-- prints, only what the filter matches.
AGF.KIND_CATEGORIES = {
	{ id = "CAT_DGN", label = "Dungeon", targetKind = "DGN",
	  kinds = { DGN = true, RDF = true, MYTHIC = true },
	  lead = { { value = "RDF", label = "Random Dungeon" } } },
	{ id = "CAT_RAID", label = "Raid", targetKind = "RAID",
	  kinds = { RAID = true } },
	{ id = "CAT_WB", label = "World Boss", targetKind = "WB",
	  kinds = { WB = true, WBT = true },
	  lead = { { value = "WBT", label = "World Boss Tour" } } },
}

AGF.KIND_CATEGORY = {}
for i = 1, #AGF.KIND_CATEGORIES do
	AGF.KIND_CATEGORY[AGF.KIND_CATEGORIES[i].id] = AGF.KIND_CATEGORIES[i]
end

-- The category one activity id belongs to, nil when it stands alone.
function AGF.CategoryForKind(kind)
	for i = 1, #AGF.KIND_CATEGORIES do
		if kind and AGF.KIND_CATEGORIES[i].kinds[kind] then
			return AGF.KIND_CATEGORIES[i]
		end
	end
	return nil
end

-- Difficulty is a dungeon and raid question. Dungeons run Normal, Heroic and
-- Mythic, where Mythic is the keystone ladder. Raids run an Ascended tier on
-- top of those three.
AGF.CATEGORY_DIFFICULTIES = {
	CAT_DGN = { "Normal", "Heroic", "Mythic" },
	CAT_RAID = { "Normal", "Heroic", "Mythic", "Ascended" },
	CAT_WB = { "Normal", "Heroic", "Mythic", "Ascended" },
}

function AGF.CategoryHasDifficulty(kind)
	return AGF.CATEGORY_DIFFICULTIES[kind or ""] ~= nil
end

function AGF.DifficultyChoices(kind)
	return AGF.CATEGORY_DIFFICULTIES[kind or ""] or AGF.DIFF_ORDER or {}
end

-- What the Activity button says: the category, or the category and the place.
function AGF.KindFilterText(f)
	f = f or (ACS_DB and ACS_DB.filter)
	local kind = (f and f.kind) or "ALL"
	if kind == "ALL" then
		return "All activities"
	end
	local cat = AGF.KIND_CATEGORY[kind]
	if not cat then
		return AGF.KindName(kind)
	end
	local target = (f and f.target) or "ALL"
	if target == "ALL" then
		return cat.label
	end
	if cat.lead then
		for i = 1, #cat.lead do
			if cat.lead[i].value == target then
				return cat.label .. ": " .. cat.lead[i].label
			end
		end
	end
	return cat.label .. ": " .. target
end

-- A count is there to tell you what is in the list you are looking at, so it
-- is taken from the open tab alone. On PvE LFG the Raid count is the number of
-- raid posts in LFG, not in the whole section.
local function countedBucket(id)
	local mode = AGF.GetMode and AGF.GetMode()
	if mode then
		return id == mode
	end
	return id:find("_UNSURE$") == nil
end

-- How many stored posts name each place, keyed by the display name the filter
-- uses. Feeds the counts in the second level of the Activity menu. A category
-- covers several row kinds: a dungeon post is DGN, RDF or MYTHIC depending on
-- how it was written, and all three belong under Dungeon.
function AGF.TargetCounts(section, category)
	local out = {}
	for i = 1, #AGF.SECTIONS do
		local s = AGF.SECTIONS[i]
		if s.id == section then
			for j = 1, #s.buckets do
				local list = (countedBucket(s.buckets[j]) and ACS_DB and ACS_DB.rows
					and ACS_DB.rows[s.buckets[j]]) or {}
				for k = 1, #list do
					local row = list[k]
					local name = row.target
					local fits = true
					if category then
						fits = ((row.kind and category.kinds[row.kind])
							or (row.activity and category.kinds[row.activity]))
							and true or false
					end
					if name and name ~= "" and fits then
						out[name] = (out[name] or 0) + 1
					end
				end
			end
		end
	end
	return out
end

function AGF.KindCounts(section)
	local seen, out = {}, {}
	local function seed(kind)
		if kind and not seen[kind] then
			seen[kind] = { kind = kind, count = 0 }
			out[#out + 1] = seen[kind]
		end
	end
	local base = AGF.BASE_KINDS[section]
	if base then
		for i = 1, #base do
			seed(base[i])
		end
	end
	if section == "PVE" and AGF.ActivePack then
		local pack = AGF.ActivePack()
		if pack and pack.activities then
			for i = 1, #pack.activities do
				local act = pack.activities[i]
				seed(act.id)
				-- Seed the caption too, so an activity nobody has posted yet is
				-- still readable instead of showing its id, such as "DGN".
				AGF.KIND_NAMES[act.id] = act.name or act.short or act.id
			end
		end
	end
	for i = 1, #AGF.SECTIONS do
		local s = AGF.SECTIONS[i]
		if s.id == section then
			for j = 1, #s.buckets do
				local list = (countedBucket(s.buckets[j]) and ACS_DB and ACS_DB.rows
					and ACS_DB.rows[s.buckets[j]]) or {}
				for k = 1, #list do
					local kind = list[k].kind
					if kind then
						if not seen[kind] then
							seen[kind] = { kind = kind, count = 0 }
							out[#out + 1] = seen[kind]
						end
						seen[kind].count = seen[kind].count + 1
					end
				end
			end
		end
	end
	for i = 1, #out do
		out[i].label = AGF.KindName(out[i].kind)
	end
	table.sort(out, function(a, b)
		if a.count == b.count then
			return a.label < b.label
		end
		return a.count > b.count
	end)
	return out
end

-- A short line for the row counter, so an empty table is never a mystery.
function AGF.FilterSummary()
	local f = ACS_DB and ACS_DB.filter
	if not f then
		return ""
	end
	local parts = {}
	if (f.kind or "ALL") ~= "ALL" then
		parts[#parts + 1] = AGF.KindFilterText(f)
	end
	if (f.difficulty or "ALL") ~= "ALL" then
		parts[#parts + 1] = f.difficulty
	end
	if (f.class or "ALL") ~= "ALL" then
		parts[#parts + 1] = f.class
	end
	for role, on in pairs(f.roles or {}) do
		if on then
			parts[#parts + 1] = AGF.RoleLabel(role)
		end
	end
	if f.needAura then
		parts[#parts + 1] = "Aura"
	end
	if f.needLooms then
		parts[#parts + 1] = "Looms"
	end
	if (f.minLevel or 0) > 0 or (f.maxLevel or 0) > 0 then
		parts[#parts + 1] = "Level " .. (f.minLevel or 0) .. " to " .. (f.maxLevel or 0)
	end
	if f.word and f.word ~= "" then
		parts[#parts + 1] = "Text " .. f.word
	end
	if #parts == 0 then
		return ""
	end
	return " - filter: " .. table.concat(parts, ", ")
end

for i = 1, #AGF.SECTIONS do
	local s = AGF.SECTIONS[i]
	for j = 1, #s.buckets do
		AGF.BUCKET_SECTION[s.buckets[j]] = s.id
	end
end
AGF.stats = { events = 0, gated = 0, stored = 0, errors = 0, comm = 0 }

local DEFAULTS = {
	mode = "PVE_LFM",
	section = "PVE",
	style = "vanilla",
	expiry = 900,
	stale = 300,
	maxRows = 200,
	showOwn = false,
	debug = false,
	sortKey = "time",
	sortAsc = false,
	-- Which columns each section draws. Set with the Rows button, kept per
	-- section and saved between sessions. A true value means the column is
	-- switched off. The starting set for PvE is written once on a fresh
	-- profile, below, and never from here: a default reapplied at every login
	-- would undo a column the player switched back on.
	cols = { PVE = {}, PVP = {}, TRADE = {}, GUILD = {} },
	-- Content pack. auto picks one from the realm name, see Packs.lua.
	pack = "auto",
	minimap = { show = true, angle = 205 },
	window = { shown = false, x = 0, y = 0, w = 780, h = 460, hasPos = false },
	-- Mini feed. mode records which window the switch button last chose, the
	-- rest is placement.
	mini = { mode = false, shown = false, hasPos = false, point = nil, rel = nil,
		x = 0, y = 0, w = 320, h = 200 },
	filter = {
		intent = "BOTH",
		-- Content type, ALL, a category such as CAT_DGN, or a row kind such
		-- as ARENA.
		kind = "ALL",
		-- The named place inside that category, ALL for all of them. RDF and
		-- WBT stand for Random Dungeon and the boss tour.
		target = "ALL",
		-- Character class, ALL or one class name. Only reachable on a realm
		-- whose pack has classes.
		class = "ALL",
		-- Raid and world boss difficulty, ALL or one of Normal, Heroic,
		-- Mythic, Ascended. A keystone row always counts as Mythic.
		difficulty = "ALL",
		roles = { tank = false, heal = false, damage = false, support = false },
		needAura = false,
		needLooms = false,
		minLevel = 0,
		maxLevel = 0,
		word = "",
	},
	alert = { enabled = false, sound = true, chat = false, popup = true, mode = "ANY",
		scope = "ALL",
		pos = { hasPos = false, x = 0, y = 0 } },
	-- One line per tab, sent only when you click the W cell in a row.
	whisper = {
		pveLfm = "Hi {name}, lvl {mylevel} with aura and looms, room in your group?",
		pveLfg = "Hi {name}, I have a group going, want an invite?",
		pvpLfm = "Hi {name}, lvl {mylevel}, room in your PvP group?",
		pvpLfg = "Hi {name}, I have a PvP group going, want an invite?",
		tradeWts = "Hi {name}, still selling? What is your price?",
		tradeWtb = "Hi {name}, still buying? I have it.",
		guild = "Hi {name}, is your guild still recruiting? Lvl {mylevel} here.",
	},
	rows = { PVE_LFM = {}, PVE_LFG = {}, PVE_UNSURE = {},
		PVP_LFM = {}, PVP_LFG = {}, PVP_UNSURE = {},
		TRADE_WTS = {}, TRADE_WTB = {}, TRADE_UNSURE = {},
		GUILD_ALL = {} },
}

local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			copyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- Every line the addon writes to chat passes through here, so the style is set
-- in one place: capital first letter, no full stop at the end of a single
-- sentence. A line that holds more than one sentence keeps its punctuation.
local function styleMessage(msg)
	local text = tostring(msg)
	local head = text:match("^(|c%x%x%x%x%x%x%x%x)")
	local rest = head and text:sub(head:len() + 1) or text
	head = head or ""
	rest = rest:gsub("^%s+", "")
	local first = rest:sub(1, 1)
	if first ~= "" then
		rest = first:upper() .. rest:sub(2)
	end
	local _, dots = rest:gsub("%.", "")
	if dots == 1 and rest:sub(-1) == "." then
		rest = rest:sub(1, -2)
	end
	return head .. rest
end

function AGF.Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffAscension Chat Scanner|r: "
			.. styleMessage(msg))
	end
end

-- Debug prints the posts the addon accepts, one line each. Everything it
-- skips is counted instead and shown by /acs probe, because a busy channel
-- would otherwise bury the accepted posts.
local function debugPrint(msg)
	if ACS_DB and ACS_DB.debug then
		AGF.Print("|cffaaaaaa" .. tostring(msg) .. "|r")
	end
end

local EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
}
AGF.EVENTS = EVENTS

-- Mode and sorting ----------------------------------------------------------

function AGF.GetMode()
	return (ACS_DB and ACS_DB.mode) or "PVE_LFM"
end

function AGF.SetMode(mode)
	for i = 1, #AGF.BUCKETS do
		if AGF.BUCKETS[i] == mode then
			local target = AGF.BUCKET_SECTION[mode] or ACS_DB.section
			AGF.SwitchSectionFilter(target)
			ACS_DB.mode = mode
			ACS_DB.section = target
			if AGF.Refresh then
				AGF.Refresh()
			end
			return
		end
	end
end

local FILTER_KEYS = { "intent", "kind", "target", "difficulty", "needAura",
	"needLooms", "minLevel", "maxLevel", "word", "maxOnly", "minKey",
	"maxKey" }

AGF.FILTER_BLANK = {
	intent = "BOTH", kind = "ALL", target = "ALL", difficulty = "ALL",
	needAura = false, needLooms = false,
	minLevel = 0, maxLevel = 0, word = "",
	maxOnly = false, minKey = 0, maxKey = 0,
	roles = { tank = false, heal = false, damage = false, support = false },
}

-- A detached copy, so the stored set does not move when the live one does.
function AGF.CopyFilter(f)
	local out = { roles = {} }
	for i = 1, #FILTER_KEYS do
		out[FILTER_KEYS[i]] = f[FILTER_KEYS[i]]
	end
	for k, v in pairs(f.roles or {}) do
		out.roles[k] = v
	end
	return out
end

-- Writes a stored set back onto the live filter. Nil means a blank set.
function AGF.ApplyFilter(f)
	f = f or AGF.FILTER_BLANK
	for i = 1, #FILTER_KEYS do
		local key = FILTER_KEYS[i]
		local v = f[key]
		if v == nil then
			v = AGF.FILTER_BLANK[key]
		end
		ACS_DB.filter[key] = v
	end
	ACS_DB.filter.roles = ACS_DB.filter.roles or {}
	for _, role in ipairs({ "tank", "heal", "damage" }) do
		ACS_DB.filter.roles[role] = (f.roles and f.roles[role]) or false
	end
end

-- The set that belongs to a section. The open section is the live filter, the
-- other two are the sets parked when you left them.
function AGF.FilterFor(section)
	if section == AGF.GetSection() then
		return ACS_DB.filter
	end
	local by = ACS_DB.filter and ACS_DB.filter.bySection
	return (by and by[section]) or AGF.FILTER_BLANK
end

-- Each section keeps its own filter set. Switching sections stores the
-- old choice and restores what that section had.
function AGF.SwitchSectionFilter(newSection)
	if not ACS_DB or not ACS_DB.filter then
		return
	end
	local old = ACS_DB.section or "PVE"
	if old == newSection then
		return
	end
	ACS_DB.filter.bySection = ACS_DB.filter.bySection or {}
	ACS_DB.filter.bySection[old] = AGF.CopyFilter(ACS_DB.filter)
	AGF.ApplyFilter(ACS_DB.filter.bySection[newSection])
	if AGF.RefreshFilterPanel then
		AGF.RefreshFilterPanel()
	end
end

function AGF.GetSection()
	return (ACS_DB and ACS_DB.section) or "PVE"
end

function AGF.SetSection(id)
	for i = 1, #AGF.SECTIONS do
		local s = AGF.SECTIONS[i]
		if s.id == id then
			AGF.SwitchSectionFilter(id)
			ACS_DB.section = id
			local current = AGF.GetMode()
			if AGF.BUCKET_SECTION[current] ~= id then
				ACS_DB.mode = s.buckets[1]
			end
			if AGF.Refresh then
				AGF.Refresh()
			end
			return
		end
	end
end

-- Aura and looms are a plain yes or no, read from the post. Maybe is a manual
-- state: click the cell when the post is too vague to call.
function AGF.StateValue(state)
	if state ~= "pos" then
		return "no"
	end
	return "yes"
end

-- Recomputes the aura and looms cells of a row for the tab it now sits in.
function AGF.ApplyStates(row)
	if not row.locked then
		row.locked = {}
	end
	if not row.locked.aura then
		row.aura = AGF.StateValue(row.auraState)
	end
	if not row.locked.looms then
		row.looms = AGF.StateValue(row.loomsState)
	end
end

-- Which side of the board you are on. Looking for a group means you want to
-- read recruit posts, looking for players means you want to read offers.
function AGF.SetFilterIntent(intent)
	ACS_DB.filter.intent = intent
	if intent == "GROUP" then
		ACS_DB.alert.mode = "LFM"
		AGF.SetMode(AGF.BucketFor(AGF.GetSection(), "LFM"))
	elseif intent == "PLAYERS" then
		ACS_DB.alert.mode = "LFG"
		AGF.SetMode(AGF.BucketFor(AGF.GetSection(), "LFG"))
	else
		ACS_DB.alert.mode = "ANY"
	end
	if AGF.Refresh then
		AGF.Refresh()
	end
end

-- Storage -------------------------------------------------------------------

local function findRow(bucket, name)
	local list = ACS_DB.rows[bucket]
	if not list then
		return nil
	end
	for i = 1, #list do
		if list[i].name == name then
			return list[i], i
		end
	end
	return nil
end

-- A name lives in one tab at a time, so a repeat post only has to be cleared
-- from the tab it was last seen in. The hint is dropped whenever a row is
-- moved, removed or cleared, and a miss falls back to the full sweep.
local lastBucketOf = {}

-- With a bucket, the hint is dropped only when it still points at that
-- bucket, so removing one row cannot blank the hint of a live row.
function AGF.ForgetName(name, bucket)
	if bucket and lastBucketOf[name] ~= bucket then
		return
	end
	lastBucketOf[name] = nil
end

function AGF.ForgetAllNames()
	for k in pairs(lastBucketOf) do
		lastBucketOf[k] = nil
	end
end

local function removeFromOtherBuckets(bucket, name)
	local hint = lastBucketOf[name]
	if hint == bucket then
		return
	end
	if hint and ACS_DB.rows[hint] then
		local list = ACS_DB.rows[hint]
		local hit = false
		for j = #list, 1, -1 do
			if list[j].name == name then
				table.remove(list, j)
				hit = true
			end
		end
		if hit then
			return
		end
	end
	for i = 1, #AGF.BUCKETS do
		local b = AGF.BUCKETS[i]
		if b ~= bucket then
			local list = ACS_DB.rows[b]
			for j = #list, 1, -1 do
				if list[j].name == name then
					table.remove(list, j)
				end
			end
		end
	end
end

function AGF.RemoveRow(bucket, name)
	AGF.ForgetName(name)
	local list = ACS_DB.rows[bucket]
	for i = #list, 1, -1 do
		if list[i].name == name then
			table.remove(list, i)
		end
	end
	if AGF.Refresh then
		AGF.Refresh()
	end
end

-- Moves every row of a player from one tab to another, for the cases where
-- the wording is genuinely ambiguous.
-- Buckets are stored as ids such as PVE_LFM. Anything the player reads
-- has to use the section and tab captions instead.
-- The bucket, label and section tables are written out by hand. When they
-- drift the symptom is a blank caption or a stale colour, which is easy to
-- miss, so they are checked at login.
function AGF.CheckTables()
	local problems = {}
	for i = 1, #AGF.BUCKETS do
		local b = AGF.BUCKETS[i]
		if not AGF.BUCKET_LABEL[b] then
			problems[#problems + 1] = "no label for " .. b
		end
		if not AGF.BUCKET_SECTION[b] then
			problems[#problems + 1] = "no section for " .. b
		end
		if not ACS_DB.rows[b] then
			problems[#problems + 1] = "no store for " .. b
		end
	end
	return problems
end

function AGF.BucketName(bucket)
	local label = AGF.BUCKET_LABEL and AGF.BUCKET_LABEL[bucket]
	local sectionId = AGF.BUCKET_SECTION and AGF.BUCKET_SECTION[bucket]
	local sectionLabel
	for i = 1, #AGF.SECTIONS do
		if AGF.SECTIONS[i].id == sectionId then
			sectionLabel = AGF.SECTIONS[i].label
		end
	end
	if sectionLabel and label then
		return sectionLabel .. " " .. label
	end
	return label or tostring(bucket)
end

function AGF.MoveRow(bucket, name, target)
	AGF.ForgetName(name)
	if bucket == target then
		return
	end
	local from = ACS_DB.rows[bucket]
	local to = ACS_DB.rows[target]
	if not from or not to then
		return
	end
	local moved = 0
	for i = #from, 1, -1 do
		if from[i].name == name then
			local row = table.remove(from, i)
			for j = #to, 1, -1 do
				if to[j].name == name then
					table.remove(to, j)
				end
			end
			AGF.ApplyStates(row)
			table.insert(to, row)
			moved = moved + 1
		end
	end
	if moved > 0 then
		AGF.Print(name .. " moved to " .. AGF.BucketName(target))
		if AGF.Refresh then
			AGF.Refresh()
		end
	end
end

function AGF.ClearBucket(bucket)
	ACS_DB.rows[bucket] = {}
	AGF.ForgetAllNames()
	if AGF.Refresh then
		AGF.Refresh()
	end
end

function AGF.CountAll()
	local n = 0
	for i = 1, #AGF.BUCKETS do
		n = n + #ACS_DB.rows[AGF.BUCKETS[i]]
	end
	return n
end

function AGF.PurgeOld()
	if not ACS_DB then
		return
	end
	local now = time()
	local removed = 0
	for i = 1, #AGF.BUCKETS do
		local list = ACS_DB.rows[AGF.BUCKETS[i]]
		for j = #list, 1, -1 do
			if now - (list[j].time or 0) > (ACS_DB.expiry or 900) then
				AGF.ForgetName(list[j].name, AGF.BUCKETS[i])
				table.remove(list, j)
				removed = removed + 1
			end
		end
		while #list > (ACS_DB.maxRows or 200) do
			local oldest, index = nil, nil
			for j = 1, #list do
				if not oldest or (list[j].time or 0) < oldest then
					oldest, index = list[j].time or 0, j
				end
			end
			if not index then
				break
			end
			AGF.ForgetName(list[index].name, AGF.BUCKETS[i])
			table.remove(list, index)
			removed = removed + 1
		end
	end
	return removed
end

-- Filters -------------------------------------------------------------------

function AGF.AnyRoleFilter()
	local f = ACS_DB.filter
	return f.roles.tank or f.roles.heal or f.roles.damage or f.roles.support
end

-- Rows in one tab that pass the current filter, plus the raw total.
function AGF.FilterCount(bucket)
	local source = (ACS_DB and ACS_DB.rows and ACS_DB.rows[bucket]) or {}
	local shown = 0
	for i = 1, #source do
		if AGF.PassesFilter(source[i]) then
			shown = shown + 1
		end
	end
	return shown, #source
end

-- True when anything at all is narrowing the view.
function AGF.FilterActive()
	local f = ACS_DB and ACS_DB.filter
	if not f then
		return false
	end
	if (f.kind or "ALL") ~= "ALL" then
		return true
	end
	if (f.difficulty or "ALL") ~= "ALL" then
		return true
	end
	if (f.class or "ALL") ~= "ALL" then
		return true
	end
	if f.needAura or f.needLooms then
		return true
	end
	if (f.word or "") ~= "" then
		return true
	end
	if (f.minLevel or 0) > 0 or (f.maxLevel or 0) > 0 then
		return true
	end
	if f.maxOnly then
		return true
	end
	if (f.minKey or 0) > 0 or (f.maxKey or 0) > 0 then
		return true
	end
	if (f.intent or "BOTH") ~= "BOTH" then
		return true
	end
	if AGF.AnyRoleFilter and AGF.AnyRoleFilter() then
		return true
	end
	return false
end

function AGF.PassesFilter(row)
	return AGF.PassesFilterWith(row, ACS_DB.filter)
end

-- Which single setting is keeping a row out of the list. Each setting is
-- relaxed on its own copy of the filter and the row is tested again, so this
-- needs no second copy of the filter rules and can never drift from them.
local REASON_FIELDS = {
	{ key = "kind", blank = "ALL", label = "Activity" },
	{ key = "target", blank = "ALL", label = "the named place" },
	{ key = "difficulty", blank = "ALL", label = "Difficulty" },
	{ key = "class", blank = "ALL", label = "Class" },
	{ key = "needAura", blank = false, label = "Aura" },
	{ key = "needLooms", blank = false, label = "Heirlooms" },
	{ key = "maxOnly", blank = false, label = "Level 60 only" },
	{ key = "minLevel", blank = 0, label = "Level from" },
	{ key = "maxLevel", blank = 0, label = "Level to" },
	{ key = "minKey", blank = 0, label = "Key from" },
	{ key = "maxKey", blank = 0, label = "Key to" },
	{ key = "word", blank = "", label = "Message contains" },
}

function AGF.FilterReasons(row, f)
	f = f or ACS_DB.filter
	if AGF.PassesFilterWith(row, f) then
		return nil
	end
	local out = {}
	for i = 1, #REASON_FIELDS do
		local field = REASON_FIELDS[i]
		local test = AGF.CopyFilter(f)
		test[field.key] = field.blank
		if AGF.PassesFilterWith(row, test) then
			-- The cap is 60 on the vanilla realms and 70 on Area 52, so this one
			-- caption is built rather than stored.
			local label = field.label
			if field.key == "maxOnly" then
				label = "Level " .. (AGF.LEVEL_CAP or 60) .. " only"
			end
			out[#out + 1] = label
		end
	end
	if #out == 0 then
		local test = AGF.CopyFilter(f)
		for i = 1, #AGF.ROLE_ORDER do
			test.roles[AGF.ROLE_ORDER[i]] = false
		end
		if AGF.PassesFilterWith(row, test) then
			out[#out + 1] = "Role"
		end
	end
	return out
end

-- /acs hidden. Prints what the filter is dropping and why, so a rule that hides
-- too much can be pointed at instead of guessed at.
-- What the filter is keeping out, counted per setting instead of one line per
-- row. Twenty hidden guild adverts are one line saying so, with a couple of
-- examples under it, which is what you need to see to know whether a setting is
-- doing what you meant.
function AGF.HiddenReport(limit)
	limit = tonumber(limit) or 2
	local f = ACS_DB.filter
	local groups, order, total = {}, {}, 0
	for bucket, list in pairs((ACS_DB and ACS_DB.rows) or {}) do
		for i = 1, #list do
			local row = list[i]
			if not AGF.PassesFilterWith(row, f) then
				total = total + 1
				local reasons = AGF.FilterReasons(row, f)
				local why = (reasons and #reasons > 0)
					and table.concat(reasons, " + ")
					or "two or more settings together"
				local g = groups[why]
				if not g then
					g = { why = why, count = 0, samples = {} }
					groups[why] = g
					order[#order + 1] = g
				end
				g.count = g.count + 1
				if #g.samples < limit then
					local msg = row.message or ""
					if #msg > 70 then
						msg = msg:sub(1, 68) .. ".."
					end
					g.samples[#g.samples + 1] = (row.name or "?")
						.. ": " .. msg
				end
			end
		end
	end
	if total == 0 then
		AGF.Print("Nothing is hidden by the filter.")
		return
	end
	table.sort(order, function(a, b)
		if a.count == b.count then
			return a.why < b.why
		end
		return a.count > b.count
	end)
	AGF.Print("Filter hides " .. total .. " rows. By setting:")
	for i = 1, #order do
		local g = order[i]
		AGF.Print("  " .. g.count .. "x " .. g.why)
		for j = 1, #g.samples do
			AGF.Print("      " .. g.samples[j])
		end
	end
	AGF.Print("  /acs hidden <n> shows n examples per setting.")
end

function AGF.PassesFilterWith(row, f)
	f = f or AGF.FILTER_BLANK
	local anyRole = false
	for i = 1, #AGF.ROLE_ORDER do
		if f.roles and f.roles[AGF.ROLE_ORDER[i]] then
			anyRole = true
		end
	end
	if anyRole then
		local ok = false
		for i = 1, #AGF.ROLE_ORDER do
			local role = AGF.ROLE_ORDER[i]
			if f.roles[role] and row.roleSet and row.roleSet[role] then
				ok = true
			end
		end
		if not ok then
			return false
		end
	end
	-- Content type. Cuts across the tabs, so it lives in the filter panel. A
	-- category passes every activity id inside it, and the named place picked
	-- on the second level narrows that to one dungeon, raid or boss.
	local kind = f.kind or "ALL"
	if kind ~= "ALL" then
		local cat = AGF.KIND_CATEGORY[kind]
		if cat then
			-- The kind answers first, the activity is the fallback. A row stored
			-- by a build that overwrote its kind still lands in the category its
			-- activity names.
			if not (cat.kinds[row.kind]
				or (row.activity and cat.kinds[row.activity])) then
				return false
			end
			local target = f.target or "ALL"
			if target ~= "ALL" then
				local lead = false
				if cat.lead then
					for i = 1, #cat.lead do
						if cat.lead[i].value == target then
							lead = true
						end
					end
				end
				if lead then
					-- Random Dungeon and the boss tour are activities, not
					-- places, so they match on the row kind. A row whose kind
					-- was overwritten by an older build answers on its
					-- activity instead.
					if row.kind ~= target and row.activity ~= target then
						return false
					end
				elseif row.target ~= target then
					return false
				end
			end
		elseif row.kind ~= kind then
			return false
		end
	end
	-- Difficulty. A post that names none never passes a difficulty filter,
	-- the same rule the class filter uses.
	if f.difficulty and f.difficulty ~= "ALL" and row.difficulty ~= f.difficulty then
		return false
	end
	-- Character class. A post that names no class never passes a class
	-- filter, because guessing one would be worse than leaving it out.
	if f.class and f.class ~= "ALL" then
		if not (row.classSet and row.classSet[f.class]) then
			return false
		end
	end
	-- A maybe still counts as a mention, so it passes an aura or looms filter.
	if f.needAura and row.aura ~= "yes" and row.aura ~= "maybe" then
		return false
	end
	if f.needLooms and row.looms ~= "yes" and row.looms ~= "maybe" then
		return false
	end
	if (f.minLevel or 0) > 0 then
		if not row.level or row.level < f.minLevel then
			return false
		end
	end
	if (f.maxLevel or 0) > 0 then
		if not row.level or row.level > f.maxLevel then
			return false
		end
	end
	-- Max level only. Levelling traffic gives itself away in three ways: it
	-- names a level or a bracket below the cap, it asks for an aura, or it
	-- asks for heirlooms. A post that says none of those is kept, because a
	-- max level advert usually states nothing about level at all.
	if f.maxOnly then
		local cap = AGF.LEVEL_CAP or 60
		-- A keystone is cap content whatever number it carries, and that
		-- number reads exactly like a character level. "Keystone: Uldaman
		-- (11)" is a key of eleven, not a level eleven player.
		local keystone = (row.kind == "MYTHIC") or (row.mythic == true)
			or (row.mythicKey ~= nil)
		if not keystone and row.level and row.level < cap then
			return false
		end
		if row.aura == "yes" or row.looms == "yes" then
			return false
		end
		-- A character at the cap earns no experience, so a post that sells it
		-- is levelling traffic whatever level it names, or names none.
		if row.levelling then
			return false
		end
	end
	-- Keystone level. A key window is a mythic question, so nothing else
	-- passes it. A mythic post with no key named passes an open search only:
	-- "LF tank m+" belongs in 0 or 1 to X, not in a 7 to 12 window.
	local minKey, maxKey = f.minKey or 0, f.maxKey or 0
	if minKey > 0 or maxKey > 0 then
		-- A mythic raid keeps the RAID kind and a mythic random dungeon keeps
		-- RDF, so the mythic flag decides here and the kind is the fallback.
		if row.kind ~= "MYTHIC" and row.mythic ~= true then
			return false
		end
		local key = row.mythicKey
		if not key then
			if minKey > 1 then
				return false
			end
		else
			if minKey > 0 and key < minKey then
				return false
			end
			if maxKey > 0 and key > maxKey then
				return false
			end
		end
	end
	if f.word and f.word ~= "" then
		local needle = f.word:lower()
		if not (row.message or ""):lower():find(needle, 1, true) then
			return false
		end
	end
	return true
end

local SORTERS = {
	time = function(a, b) return (a.time or 0) < (b.time or 0) end,
	name = function(a, b) return (a.name or "") < (b.name or "") end,
	role = function(a, b) return (a.roleText or "") < (b.roleText or "") end,
	aura = function(a, b) return (a.aura or "") < (b.aura or "") end,
	looms = function(a, b) return (a.looms or "") < (b.looms or "") end,
	level = function(a, b) return (a.level or 0) < (b.level or 0) end,
	-- Pack columns.
	act = function(a, b)
		local ta = (a.activityShort or "") .. " " .. (a.target or "")
		local tb = (b.activityShort or "") .. " " .. (b.target or "")
		return ta < tb
	end,
	diff = function(a, b)
		local rank = { Normal = 1, Heroic = 2, Mythic = 3, Ascended = 4 }
		return (rank[a.difficulty] or 0) < (rank[b.difficulty] or 0)
	end,
	ilvl = function(a, b) return (a.ilvl or 0) < (b.ilvl or 0) end,
	prog = function(a, b) return (a.prog or "") < (b.prog or "") end,
	message = function(a, b) return (a.message or "") < (b.message or "") end,
}

function AGF.GetSortedRows(bucket, key, ascending)
	local source = ACS_DB.rows[bucket] or {}
	local list = {}
	for i = 1, #source do
		if AGF.PassesFilter(source[i]) then
			list[#list + 1] = source[i]
		end
	end
	local sorter = SORTERS[key] or SORTERS.time
	table.sort(list, function(a, b)
		if ascending then
			return sorter(a, b)
		end
		return sorter(b, a)
	end)
	return list
end

-- Alerts --------------------------------------------------------------------

-- The popup, the sound, the chat line and the mini feed all ask this one
-- question, so a feed row can never disagree with an alert.
function AGF.AlertMatch(bucket, row)
	local a = ACS_DB.alert
	local intent = AGF.IntentOf(bucket)
	if intent == "UNSURE" then
		return false
	end
	if a.mode ~= "ANY" and a.mode ~= intent then
		return false
	end
	local section = AGF.BUCKET_SECTION[bucket] or "PVE"
	-- scope SECTION: only the tab you are looking at can alert, so sitting on
	-- PvE LFG keeps PvE LFM quiet.
	-- scope ALL: any tab can, each judged by its own section filter set.
	if (a.scope or "ALL") == "SECTION" and bucket ~= AGF.GetMode() then
		return false
	end
	return AGF.PassesFilterWith(row, AGF.FilterFor(section))
end

-- Alerts proper. The feed ignores this switch, see below.
local function alertWanted(bucket, row)
	if not ACS_DB.alert.enabled then
		return false
	end
	return AGF.AlertMatch(bucket, row)
end

-- Message handling ----------------------------------------------------------

local function channelLabel(event, arg4, arg9)
	if event == "CHAT_MSG_CHANNEL" then
		return arg9 or arg4 or "channel"
	end
	local short = event:gsub("^CHAT_MSG_", "")
	return short:lower():gsub("_", " ")
end

local lastSeen = {}

-- Without this the dedupe cache grows for the whole session, one entry per
-- unique line seen. The housekeeping ticker calls it every five seconds.
function AGF.PurgeSeen()
	local now = time()
	for key, seen in pairs(lastSeen) do
		if now - seen >= 3 then
			lastSeen[key] = nil
		end
	end
end

-- Debug output is public through /acs debug, so it must not carry raw chat
-- escapes or internal ids. A failure strips the escape character rather than
-- passing the raw line through.
local function safeText(s)
	local ok, clean = pcall(AGF.DisplayText, s)
	if ok and type(clean) == "string" and clean ~= "" then
		return clean
	end
	return (tostring(s):gsub("|", ""))
end

-- Rows stored by an older build carry no difficulty, no named place, no
-- keystone and no levelling flag, so the newer filters would drop them or show
-- them empty. Reparsing the message they were built from fills those in without
-- clearing the table, and a hand edited cell is left alone.
AGF.ROW_SCHEMA = 5

-- Guild recruitment used to sit in the PvE and PvP tabs. It has its own section
-- now, so stored guild rows are carried across once instead of being stranded
-- in a tab that no longer shows them.
local function moveGuildRows()
	local target = ACS_DB.rows.GUILD_ALL
	if not target then
		target = {}
		ACS_DB.rows.GUILD_ALL = target
	end
	local moved = 0
	for i = 1, #AGF.BUCKETS do
		local id = AGF.BUCKETS[i]
		if id ~= "GUILD_ALL" then
			local list = ACS_DB.rows[id]
			if list then
				-- Backwards, because rows are taken out of the list while it
				-- is being walked.
				for k = #list, 1, -1 do
					if list[k].kind == "GUILD" then
						target[#target + 1] = table.remove(list, k)
						moved = moved + 1
					end
				end
			end
		end
	end
	return moved
end

function AGF.MigrateRows()
	if not ACS_DB or not ACS_DB.rows then
		return 0
	end
	local done = moveGuildRows()
	for i = 1, #AGF.BUCKETS do
		local list = ACS_DB.rows[AGF.BUCKETS[i]] or {}
		for j = 1, #list do
			local row = list[j]
			if row.schema ~= AGF.ROW_SCHEMA then
				local text = row.rawMessage or row.message
				local parsed
				if text then
					local ok, out = pcall(AGF.Parse, text)
					if ok and type(out) == "table" then
						parsed = out
					end
				end
				if parsed then
					local locked = row.locked or {}
					if not locked.diff then
						row.difficulty = row.difficulty or parsed.difficulty
					end
					row.target = row.target or parsed.target
					row.mythicKey = row.mythicKey or parsed.mythicLevel
					if row.mythic == nil then
						row.mythic = parsed.mythic
					end
					-- Mythic used to replace the row kind outright, which
					-- filed every mythic raid and every mythic Manastorm
					-- post under Dungeon and hid it from its own activity
					-- filter. The kind follows the activity now, so a
					-- stored row takes the kind and caption the parse
					-- gives it.
					if row.kind == "MYTHIC" and parsed.kind
						and parsed.kind ~= "MYTHIC" then
						row.kind = parsed.kind
						row.activityName = parsed.activityName
						row.activityShort = parsed.activityShort
					end
					-- Keystone numbers were stored as character levels in
					-- older builds, which is what made Level 60 mode hide
					-- them. A mythic row has no level.
					if row.kind == "MYTHIC" or row.mythic == true then
						row.level = nil
					end
					if row.levelling == nil then
						row.levelling = parsed.levelling
					end
					row.activity = row.activity or parsed.activity
					row.activityName = row.activityName or parsed.activityName
					row.activityShort = row.activityShort or parsed.activityShort
					-- Support only became a role in a later build, so a stored
					-- role set never carries it unless it is rebuilt.
					if not locked.role and parsed.roleSet then
						row.roleSet = parsed.roleSet
						row.roleText = parsed.roleText
					end
					row.orig = row.orig or {}
					if row.orig.difficulty == nil then
						row.orig.difficulty = parsed.difficulty or false
					end
					done = done + 1
				end
				row.schema = AGF.ROW_SCHEMA
			end
		end
	end
	return done
end

function AGF.HandleMessage(event, message, sender, arg4, arg9, source)
	AGF.stats.events = AGF.stats.events + 1
	if not message or message == "" or not sender or sender == "" then
		return
	end

	sender = sender:match("^[^-]+") or sender

	-- Both capture paths can deliver the same line, so drop instant repeats.
	local key = sender .. "\001" .. message
	local now = time()
	if lastSeen[key] and now - lastSeen[key] < 3 then
		return
	end
	lastSeen[key] = now

	if not ACS_DB.showOwn and sender == UnitName("player") then
		return
	end

	-- Traffic from another addon must never reach the parser.
	if AGF.IsAddonTraffic and AGF.IsAddonTraffic(message) then
		AGF.stats.comm = (AGF.stats.comm or 0) + 1
		return
	end

	local parsed = AGF.Parse(message)
	if not parsed then
		return
	end
	AGF.stats.gated = AGF.stats.gated + 1

	local section = parsed.route or "PVE"
	local bucket
	if section == "TRADE" then
		bucket = AGF.BucketFor("TRADE", parsed.tradeIntent or "UNSURE")
	else
		bucket = AGF.BucketFor(section, parsed.intent or "UNSURE")
	end
	local channel = channelLabel(event, arg4, arg9)
	debugPrint(AGF.BucketName(bucket) .. " <- " .. sender .. " [" .. channel .. "] "
		.. safeText(message))

	removeFromOtherBuckets(bucket, sender)
	lastBucketOf[sender] = bucket
	local row = findRow(bucket, sender)
	local isNew = false

	if not row then
		row = { name = sender, locked = {} }
		table.insert(ACS_DB.rows[bucket], row)
		isNew = true
		AGF.stats.stored = AGF.stats.stored + 1
	end

	row.time = now
	-- The raw chat string is kept for a whisper and for a copy, the table
	-- shows the clean text.
	row.rawMessage = message
	-- A failure here must not leave the row without a message.
	local okClean, clean = pcall(AGF.DisplayText, message)
	if not okClean or type(clean) ~= "string" or clean == "" then
		clean = message
		AGF.stats.errors = AGF.stats.errors + 1
	end
	row.message = clean
	row.kind = parsed.kind or "OTHER"
	if parsed.kind and parsed.activityShort then
		-- The menu shows the full name, the table cell shows the short one.
		AGF.KIND_NAMES[parsed.kind] = parsed.activityName or parsed.activityShort
	end
	row.channel = channel
	if not row.locked then
		row.locked = {}
	end
	if not row.locked.role then
		row.roleSet = parsed.roleSet
		row.roleText = parsed.roleText
	end
	row.auraState = parsed.auraState or (parsed.aura == "yes" and "pos" or "none")
	row.loomsState = parsed.loomsState or (parsed.looms == "yes" and "pos" or "none")
	AGF.ApplyStates(row)
	if not row.locked.level then
		row.level = parsed.level
		row.bracket = parsed.bracket
	end

	-- Kept so a hand edit can be stepped back to what the message itself said.
	-- Always refreshed from the parse, even where a cell is locked by an edit.
	row.orig = row.orig or {}
	row.orig.roleText = parsed.roleText
	row.orig.level = parsed.level
	row.orig.bracket = parsed.bracket
	-- Aura and looms depend on the tab, so they use the same rule as the cells.
	row.orig.aura = AGF.StateValue(row.auraState)
	row.orig.looms = AGF.StateValue(row.loomsState)
	row.orig.ilvl = parsed.ilvl
	row.orig.prog = parsed.prog
	-- False rather than nil when the message named no difficulty, so stepping
	-- an edit back reaches "none" instead of reaching nothing.
	row.orig.difficulty = parsed.difficulty or false
	-- Straight from the current post. An older post must not leave a stale
	-- number behind when the sender writes again without one.
	row.size = parsed.size
	row.wanted = parsed.wanted

	-- Pack fields. Which of these the table shows is decided by the pack.
	row.activity = parsed.activity
	row.activityName = parsed.activityName
	row.activityShort = parsed.activityShort
	-- The keystone level the post named, nil when it named none. The key range
	-- filter reads this, so a row stored by an older build counts as unnamed.
	row.mythicKey = parsed.mythicLevel
	-- True when the post is about a mythic run, whatever category it sits in, so
	-- the keystone rules never have to read the row kind.
	row.mythic = parsed.mythic
	-- Normal, Heroic, Mythic or Ascended, nil when the post named none. A
	-- hand edited Diff cell is kept, the same as every other edited cell.
	if not row.locked.diff then
		row.difficulty = parsed.difficulty
	end
	-- True when the post sells experience, which no level 60 group does.
	row.levelling = parsed.levelling
	row.class = parsed.class
	row.classSet = parsed.classSet
	row.profession = parsed.profession
	row.profMode = parsed.profMode
	row.target = parsed.target
	if not row.locked.ilvl then
		row.ilvl = parsed.ilvl
	end
	if not row.locked.prog then
		row.prog = parsed.prog
	end

	-- The mini feed collects whatever matches the alert rules, even with
	-- alerts switched off, and even while the window is closed.
	if isNew and AGF.MiniPush and AGF.AlertMatch(bucket, row) then
		AGF.MiniPush(row, bucket)
	end

	if isNew and alertWanted(bucket, row) then
		local a = ACS_DB.alert
		if a.chat then
			AGF.Print("|cffffd100" .. AGF.BucketName(bucket) .. "|r " .. sender .. ": " .. (row.message or ""))
		end
		if a.sound then
			PlaySound("RaidWarning")
		end
		if a.popup and AGF.ShowAlert then
			AGF.ShowAlert(row, bucket)
		end
	end

	AGF.RefreshSoon()
end

-- A busy channel delivers several lines in the same frame. Repainting once per
-- frame instead of once per line keeps the cost flat on a full trade channel.
local refreshDriver = CreateFrame("Frame")
refreshDriver:Hide()
refreshDriver:SetScript("OnUpdate", function(self)
	self:Hide()
	if AGF.Refresh then
		AGF.Refresh()
	end
end)

function AGF.RefreshSoon()
	refreshDriver:Show()
end

-- Every capture path funnels through here so one error cannot kill the addon.
function AGF.Ingest(event, message, sender, arg4, arg9, source)
	if not ACS_DB then
		return
	end
	local ok, err = pcall(AGF.HandleMessage, event, message, sender, arg4, arg9, source)
	if not ok then
		AGF.stats.errors = AGF.stats.errors + 1
		AGF.lastError = tostring(err)
		if ACS_DB.debug then
			AGF.Print("|cffff5555error|r " .. AGF.lastError)
		end
	end
end

-- Capture path 1: registered chat events.
local driver = CreateFrame("Frame", "AGF_Driver", UIParent)
driver:RegisterEvent("ADDON_LOADED")

-- Capture path 2: chat display filters. This sees exactly what your chat frame
-- prints, which keeps working even if event registration behaves oddly.
local function chatFilter(chatFrame, event, ...)
	local a1, a2, a3, a4, a5, a6, a7, a8, a9 = ...
	AGF.Ingest(event, a1, a2, a4, a9, "filter")
	return false
end

local function installFilters()
	if not ChatFrame_AddMessageEventFilter then
		return 0
	end
	local count = 0
	for i = 1, #EVENTS do
		ChatFrame_AddMessageEventFilter(EVENTS[i], chatFilter)
		count = count + 1
	end
	return count
end

driver:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= ADDON_NAME then
			return
		end
		if AGF.initDone then
			return
		end
		AGF.initDone = true
		ACS_DB = ACS_DB or {}
		copyDefaults(DEFAULTS, ACS_DB)
		-- PvE opens with Looms, iLvl and Filled switched off, because few posts
		-- carry them. This runs on a fresh profile only. colsSeeded is not a
		-- default, so copyDefaults cannot restore it and the three columns are
		-- never switched off a second time.
		if not ACS_DB.colsSeeded then
			ACS_DB.colsSeeded = true
			ACS_DB.cols.PVE.looms = true
			ACS_DB.cols.PVE.ilvl = true
			ACS_DB.cols.PVE.prog = true
		end
		-- Pick the content pack before any message is parsed.
		local override = ACS_DB.pack
		if override == "auto" then
			override = nil
		end
		if AGF.SelectPack then
			AGF.SelectPack(override)
		end
		-- The pack decides the column set, so this runs before the window is
		-- ever built.
		if AGF.ApplyPackColumns then
			AGF.ApplyPackColumns()
		end
		for i = 1, #AGF.BUCKETS do
			ACS_DB.rows[AGF.BUCKETS[i]] = ACS_DB.rows[AGF.BUCKETS[i]] or {}
		end
		if not AGF.BUCKET_SECTION[ACS_DB.mode or ""] then
			ACS_DB.mode = "PVE_LFM"
		end
		AGF.PurgeOld()
		-- Older rows are brought up to the current shape here, straight after
		-- the expired ones are gone, so nothing is reparsed for nothing.
		local migrated = AGF.MigrateRows()
		if migrated > 0 and ACS_DB.debug then
			AGF.Print("Brought " .. migrated .. " stored rows up to date.")
		end
		for i = 1, #EVENTS do
			self:RegisterEvent(EVENTS[i])
		end
		-- Gear changes, so the item level cache can be dropped the moment it
		-- goes stale. The second event does not exist on every client, hence
		-- the pcall.
		self:RegisterEvent("UNIT_INVENTORY_CHANGED")
		pcall(self.RegisterEvent, self, "PLAYER_EQUIPMENT_CHANGED")
		pcall(self.RegisterEvent, self, "PLAYER_AVG_ITEM_LEVEL_UPDATE")
		-- The realm name is not always readable while addons load, so the pack
		-- is picked again once the world is up.
		pcall(self.RegisterEvent, self, "PLAYER_ENTERING_WORLD")
		AGF.filterCount = installFilters()
		local problems = AGF.CheckTables()
		if #problems > 0 and ACS_DB.debug then
			for i = 1, #problems do
				AGF.Print("Table check: " .. problems[i])
			end
		end
		AGF.Print("Version " .. AGF.VERSION .. " loaded. Type /acs to open, /acs help for commands.")
		if AGF.ActivePack then
			local pack = AGF.ActivePack()
			AGF.Print("Pack: " .. pack.name .. " (realm " .. tostring(AGF.realmName)
				.. ")" .. ((ACS_DB.pack ~= "auto") and " - forced with /acs pack" or "")
				.. (pack.contentNote and (" - " .. pack.contentNote) or ""))
		end
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		-- Only an automatic pack moves. One forced with /acs pack stays put.
		if (ACS_DB.pack or "auto") == "auto" and AGF.SelectPack then
			local before = AGF.packId
			AGF.SelectPack(nil)
			if AGF.packId ~= before then
				if AGF.ApplyPackColumns then
					AGF.ApplyPackColumns()
				end
				local pack = AGF.ActivePack()
				AGF.Print("Pack: " .. pack.name .. " (realm "
					.. tostring(AGF.realmName) .. ")"
					.. (pack.contentNote and (" - " .. pack.contentNote) or ""))
				if AGF.Refresh then AGF.Refresh() end
				if AGF.RefreshFilterPanel then AGF.RefreshFilterPanel() end
			end
		end
		return
	end

	if event == "UNIT_INVENTORY_CHANGED"
		or event == "PLAYER_EQUIPMENT_CHANGED"
		or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
		local unit = ...
		if event ~= "UNIT_INVENTORY_CHANGED" or unit == nil or unit == "player"
			then
			if AGF.InvalidateItemLevel then
				AGF.InvalidateItemLevel()
			end
		end
		return
	end

	local a1, a2, a3, a4, a5, a6, a7, a8, a9 = ...
	AGF.Ingest(event, a1, a2, a4, a9, "event")
end)

-- Housekeeping ticker, no C_Timer on 3.3.5a.
local elapsedSince = 0
driver:SetScript("OnUpdate", function(self, elapsed)
	elapsedSince = elapsedSince + (elapsed or 0)
	if elapsedSince < 5 then
		return
	end
	elapsedSince = 0
	AGF.PurgeSeen()
	local removed = AGF.PurgeOld()
	if AGF.RefreshTimes then
		pcall(AGF.RefreshTimes)
	end
	if removed and removed > 0 and AGF.Refresh then
		pcall(AGF.Refresh)
	end
end)

-- Slash commands ------------------------------------------------------------

local function printHelp()
	AGF.Print("Commands:")
	local lines = {
		"/acs - show or hide the window",
		"/acs pve | pvp | trade | guild - pick a section",
		"/acs lfm | lfg | unsure | wts | wtb - pick a tab",
		"/acs style vanilla | dark | grid | slate | parchment | glass | felfire - same as the Skins button",
		"/acs clear - clear the current tab, clearall - clear everything",
		"/acs mini - open or close the mini feed",
		"/acs mini reset - put the mini feed back in the middle of the screen",
		"/acs reset - put the main window in the middle at its default size",
		"/acs position reset - same thing",
		"/acs minimap - show or hide the minimap button",
		"/acs alert on | off | sound | chat | popup | mode lfm|lfg|any",
		"/acs alert scope section | all - same as the Scope button above Alerts",
		"/acs alert move or unlock - drag the popup, /acs alert lock - fix it in place",
		"/acs alert reset - put the popup back in its default spot",
		"/acs expiry 900 - seconds a row stays listed",
		"/acs own - include or exclude your own messages",
		"/acs pack - show the active content pack",
		"/acs pack coa | ascension | classic | tbc | auto - switch it, auto follows the realm",
		"/acs whisper - set the one click whisper line for each tab",
		"/acs whisper pvelfm | pvelfg | pvplfm | pvplfg | wts | wtb | guild <text> - set one line",
		"/acs ilvl - print your gear level, /acs ilvl <slot number> for one item",
		"/acs hidden - list what the filter is dropping right now",
		"/acs probe - print a diagnostic report, useful when reporting a bug",
		"/acs debug - print one line for every post the addon accepts",
	}
	for i = 1, #lines do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. lines[i])
	end
end

local function handleAlert(rest)
	local a = ACS_DB.alert
	local cmd, value = rest:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	if cmd == "on" then
		a.enabled = true
		AGF.Print("Alerts on")
	elseif cmd == "off" then
		a.enabled = false
		AGF.Print("Alerts off")
	elseif cmd == "sound" then
		a.sound = not a.sound
		AGF.Print("Alert sound " .. (a.sound and "on" or "off"))
	elseif cmd == "chat" then
		a.chat = not a.chat
		AGF.Print("Alert chat line " .. (a.chat and "on" or "off"))
	elseif cmd == "popup" then
		a.popup = not a.popup
		AGF.Print("Alert popup " .. (a.popup and "on" or "off"))
	elseif cmd == "move" or cmd == "unlock" then
		if AGF.SetAlertUnlocked then
			AGF.SetAlertUnlocked(true)
		end
	elseif cmd == "lock" then
		if AGF.SetAlertUnlocked then
			AGF.SetAlertUnlocked(false)
		end
	elseif cmd == "reset" then
		if AGF.ResetAlertPosition then
			AGF.ResetAlertPosition()
		end
	elseif cmd == "scope" then
		local sc = (value or ""):upper()
		if sc == "SECTION" or sc == "ALL" then
			a.scope = sc
			AGF.Print("Alert scope " .. (sc == "ALL" and "All" or "Section"))
		else
			AGF.Print("Use /acs alert scope section | all")
		end
	elseif cmd == "mode" then
		local m = (value or ""):upper()
		if m == "LFM" or m == "LFG" or m == "ANY" then
			a.mode = m
			AGF.Print("Alert mode " .. (m == "ANY" and "any" or m))
		else
			AGF.Print("Use /acs alert mode lfm | lfg | any")
		end
	else
		AGF.Print("Alerts " .. (a.enabled and "on" or "off")
			.. ", mode " .. ((a.mode == "ANY") and "any" or a.mode)
			.. ", popup " .. (a.popup and "on" or "off")
			.. ", sound " .. (a.sound and "on" or "off")
			.. ", chat " .. (a.chat and "on" or "off"))
	end
	if AGF.RefreshFilterPanel then
		AGF.RefreshFilterPanel()
	end
end

-- Whisper templates ---------------------------------------------------------

-- Accepts either a bucket name or a slot key.
local function slotKey(key)
	local k = tostring(key or "")
	if AGF.WHISPER_BUCKET_SLOT[k] then
		return AGF.WHISPER_BUCKET_SLOT[k]
	end
	for i = 1, #AGF.WHISPER_SLOTS do
		if AGF.WHISPER_SLOTS[i].key == k then
			return k
		end
	end
	return nil
end

function AGF.WhisperTemplate(key)
	if not ACS_DB or not ACS_DB.whisper then
		return ""
	end
	local slot = slotKey(key)
	if not slot then
		return ""
	end
	return ACS_DB.whisper[slot] or ""
end

-- Puts every line back to the shipped default, used by the panel button.
function AGF.ResetWhisperTemplates()
	if not ACS_DB then
		return
	end
	ACS_DB.whisper = {}
	for i = 1, #AGF.WHISPER_SLOTS do
		local key = AGF.WHISPER_SLOTS[i].key
		ACS_DB.whisper[key] = DEFAULTS.whisper[key]
	end
	AGF.Print("Whisper lines reset")
end

function AGF.SetWhisperTemplate(key, text)
	if not ACS_DB then
		return
	end
	ACS_DB.whisper = ACS_DB.whisper or {}
	local slot = slotKey(key)
	if not slot then
		return
	end
	ACS_DB.whisper[slot] = text or ""
end

-- This client has no GetAverageItemLevel, so my own gear level is added up
-- from what the character wears. The value is cached for a minute, because it
-- is asked for on every tooltip.
-- The realm averages sixteen gear slots, ranged and relic excluded, and an
-- empty slot counts as zero. Dividing by the slots actually filled is what
-- read a few points high: a missing off hand or trinket made every other
-- item weigh more than it should.
-- Gear level ---------------------------------------------------------------
-- The character sheet adds up the slots that hold an item and divides by that
-- count, not by a fixed sixteen. That is exactly why pulling a wand whose
-- level is below the average pushes the number up, and why pulling anything
-- above the average drags it down. Shirt and tabard carry no level at all and
-- are left out.
--
-- The level per item is read from the item tooltip rather than from
-- GetItemInfo. The tooltip is what the server sent for that one item, so
-- scaled and heirloom gear reads the way the character sheet reads it, and it
-- answers even when the item is not in the local cache yet.
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
	18 }
local ILVL_SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest",
	[6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
	[10] = "Hands", [11] = "Finger 1", [12] = "Finger 2",
	[13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
	[16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}

local ilvlTip
-- Returns the level, where it came from, and the item link. level is nil when
-- the slot is empty, and nil with a link when the item gave up nothing.
local function slotItemLevel(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then
		return nil, nil, nil
	end
	if not ilvlTip then
		ilvlTip = CreateFrame("GameTooltip", "AGF_IlvlTooltip", UIParent,
			"GameTooltipTemplate")
	end
	ilvlTip:SetOwner(UIParent, "ANCHOR_NONE")
	ilvlTip:ClearLines()
	local ok = pcall(ilvlTip.SetInventoryItem, ilvlTip, "player", slot)
	local seen, twoHand = {}, false
	if ok then
		local pattern = "Item Level (%d+)"
		if type(ITEM_LEVEL) == "string" then
			pattern = ITEM_LEVEL:gsub("%%d", "(%%d+)")
		end
		for i = 1, ilvlTip:NumLines() do
			local line = _G["AGF_IlvlTooltipTextLeft" .. i]
			local text = line and line:GetText()
			if text then
				local low = text:lower()
				if low:find("two%-hand") or low:find("two hand") then
					twoHand = true
				end
				local found = text:match(pattern)
				if found then
					seen[#seen + 1] = tonumber(found)
					-- Scaled gear prints the level it was scaled to in brackets
					-- behind its own: "Item Level 63 (65)".
					local bracket = text:match("%((%d+)%)")
					if bracket then
						seen[#seen + 1] = tonumber(bracket)
					end
				end
			end
		end
	end
	if #seen > 0 then
		-- The last level the tooltip printed is the one that counts. An item
		-- that scales prints its base level first and the level it plays at
		-- after it, which is why reading the first line came out low.
		return seen[#seen], "tooltip", link, seen, twoHand
	end
	local _, _, _, level, _, _, _, _, equip = GetItemInfo(link)
	if equip == "INVTYPE_2HWEAPON" then
		twoHand = true
	end
	if level and level > 0 then
		return level, "cache", link, nil, twoHand
	end
	return nil, "unread", link, nil, twoHand
end

local myIlvlValue, myIlvlAt = nil, 0

-- Equipping something clears the cache instead of waiting for the sixty second
-- timer. The tooltip needs a moment to hold the new item, so the value is read
-- again a second and a half later rather than right now.
local ilvlTimer = CreateFrame("Frame")
ilvlTimer:Hide()
ilvlTimer.wait = 0
ilvlTimer:SetScript("OnUpdate", function(self, elapsed)
	self.wait = self.wait - (elapsed or 0)
	if self.wait > 0 then
		return
	end
	self:Hide()
	if AGF.MyItemLevel then
		pcall(AGF.MyItemLevel, true)
	end
end)

function AGF.InvalidateItemLevel(delay)
	myIlvlValue, myIlvlAt = nil, 0
	ilvlTimer.wait = delay or 1.5
	ilvlTimer:Show()
end

-- Whatever the character sheet uses, it is not something the addon can see, so
-- the sheet's own reading is asked for first when the client exposes one.
local function panelItemLevel()
	local fn = rawget(_G, "GetAverageItemLevel")
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn)
	if not ok then
		return nil
	end
	local value = tonumber(b) or tonumber(a)
	if value and value > 0 and value <= (AGF.ILVL_MAX or 600) then
		return value
	end
	return nil
end
AGF.PanelItemLevel = panelItemLevel

-- Every equipped slot in one pass.
local function gearScan()
	local sum, filled, pending, twoHand = 0, 0, false, nil
	local slots = {}
	for i = 1, #ILVL_SLOTS do
		local slot = ILVL_SLOTS[i]
		local level, source, link, seen, isTwo = slotItemLevel(slot)
		slots[#slots + 1] = { slot = slot, level = level, source = source,
			link = link, seen = seen }
		if level then
			sum = sum + level
			filled = filled + 1
			if source ~= "tooltip" then
				pending = true
			end
			if slot == 16 and isTwo then
				twoHand = level
			end
		elseif source then
			-- Something is worn there but nothing could be read from it yet.
			-- Answer with what is known and compute again next time instead of
			-- freezing a number that is missing a slot.
			pending = true
		end
	end
	return sum, filled, pending, twoHand, slots
end

-- The four ways the average can be taken. Nobody knows which one the sheet
-- uses, so all four are printed by /acs ilvl and auto mode picks one.
AGF.ILVL_MODES = { "auto", "filled", "twohand", "sixteen", "seventeen" }

local function averageFor(mode, sum, filled, twoHand)
	if filled == 0 then
		return nil
	end
	if mode == "sixteen" then
		return sum / 16
	end
	if mode == "seventeen" then
		return sum / 17
	end
	if mode == "twohand" and twoHand then
		-- A two hander fills both weapon slots, so it counts twice.
		return (sum + twoHand) / (filled + 1)
	end
	return sum / filled
end

function AGF.MyItemLevel(force)
	local now = time()
	if not force and myIlvlValue and (now - myIlvlAt) < 60 then
		return myIlvlValue
	end
	local mode = (ACS_DB and ACS_DB.ilvlMode) or "auto"
	if mode == "auto" then
		local panel = panelItemLevel()
		if panel then
			myIlvlValue = math.floor(panel * 100 + 0.5) / 100
			myIlvlAt = now
			return myIlvlValue
		end
	end
	local sum, filled, pending, twoHand = gearScan()
	local value = averageFor(mode == "auto" and "filled" or mode, sum, filled,
		twoHand)
	if not value then
		return nil
	end
	myIlvlValue = math.floor(value * 100 + 0.5) / 100
	myIlvlAt = pending and 0 or now
	return myIlvlValue
end

-- /acs ilvl. Prints every slot and both averages, so a number that disagrees
-- with the character sheet can be compared slot by slot instead of guessed at.
function AGF.ItemLevelReport()
	local sum, filled, pending, twoHand, slots = gearScan()
	local empty = 0
	AGF.Print("Gear level, slot by slot:")
	for i = 1, #slots do
		local s = slots[i]
		local name = ILVL_SLOT_NAMES[s.slot] or ("Slot " .. s.slot)
		if s.level then
			-- Every level the tooltip printed is listed, so a slot that reads
			-- lower than the tooltip shows why.
			local all = ""
			if s.seen and #s.seen > 1 then
				all = " (tooltip printed " .. table.concat(s.seen, ", ") .. ")"
			end
			AGF.Print("  " .. name .. ": " .. s.level .. " from the "
				.. (s.source or "?") .. all .. " " .. (s.link or ""))
		elseif s.link then
			AGF.Print("  " .. name .. ": could not be read " .. s.link)
		else
			empty = empty + 1
		end
	end
	if filled == 0 then
		AGF.Print("  nothing equipped")
		return
	end
	AGF.Print("  sum " .. sum .. " over " .. filled .. " filled slots, "
		.. empty .. " empty"
		.. (twoHand and (", two hander at " .. twoHand) or ""))
	local mode = (ACS_DB and ACS_DB.ilvlMode) or "auto"
	for i = 1, #AGF.ILVL_MODES do
		local name = AGF.ILVL_MODES[i]
		if name ~= "auto" then
			local value = averageFor(name, sum, filled, twoHand)
			local note = ""
			if name == mode or (mode == "auto" and name == "filled") then
				note = "  <- in use"
			end
			AGF.Print("  " .. name .. ": "
				.. (value and string.format("%.2f", value) or "?") .. note)
		end
	end
	local panel = panelItemLevel()
	if panel then
		AGF.Print("  the client reports " .. string.format("%.2f", panel)
			.. ", which is what auto mode sends")
	else
		AGF.Print("  the client exposes no average of its own, so the addon"
			.. " sends the closest of the four above")
	end
	if pending then
		AGF.Print("  at least one slot did not answer yet, run it again")
	end
	AGF.MyItemLevel(true)
	AGF.Print("  a whisper sends " .. AGF.MyItemLevelText())
	AGF.Print("  /acs ilvl <slot number> prints one item's whole tooltip")
end

-- /acs ilvl 3. The whole tooltip of one slot, for the case where the level the
-- addon reads and the level the tooltip shows still disagree.
function AGF.ItemLevelDump(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then
		AGF.Print("Slot " .. slot .. " is empty.")
		return
	end
	slotItemLevel(slot)
	AGF.Print((ILVL_SLOT_NAMES[slot] or ("Slot " .. slot)) .. " " .. link)
	for i = 1, 40 do
		local line = _G["AGF_IlvlTooltipTextLeft" .. i]
		local text = line and line:GetText()
		if text and text ~= "" then
			AGF.Print("  " .. i .. ": " .. text)
		end
	end
end

-- What a whisper carries: 55.5, not 55.50 and not 55.
function AGF.MyItemLevelText()
	local value = AGF.MyItemLevel()
	if not value then
		return "?"
	end
	local text = string.format("%.2f", value)
	while text:find("0$") do
		text = text:sub(1, -2)
	end
	text = text:gsub("%.$", "")
	return text
end

-- Placeholders are replaced at click time, never before.
function AGF.BuildWhisper(row, bucket)
	if not row then
		return nil
	end
	local text = AGF.WhisperTemplate(bucket or AGF.GetMode())
	if not text or text == "" then
		return nil
	end
	local values = {
		name = row.name or "",
		role = AGF.RoleDisplay(row.roleText),
		level = row.level and tostring(row.level) or "?",
		-- {ilvl} is my own gear level, because that is what a whisper carries.
		-- Most posts never state one, so reading it from the post gave "?"
		-- nearly every time. The number the post asked for is {theirilvl}.
		ilvl = AGF.MyItemLevelText(),
		myilvl = AGF.MyItemLevelText(),
		theirilvl = row.ilvl and tostring(row.ilvl) or "?",
		aura = row.aura or "no",
		looms = row.looms or "no",
		size = row.size and tostring(row.size) or "?",
		prof = row.profession or "?",
		profmode = row.profMode or "?",
		myname = UnitName("player") or "",
		mylevel = tostring(UnitLevel("player") or 0),
	}
	text = text:gsub("{(%a+)}", function(key)
		local value = values[key:lower()]
		if value == nil then
			return "{" .. key .. "}"
		end
		return value
	end)
	return text
end

function AGF.SendWhisper(row, bucket)
	if not row or not row.name or row.name == "" then
		return false
	end
	local text = AGF.BuildWhisper(row, bucket)
	if not text or text == "" then
		AGF.Print("No whisper line set for this tab. Press the Whisp Templates button in the window, or use /acs whisper pvelfm <text>")
		return false
	end
	if text:len() > 250 then
		text = text:sub(1, 250)
	end
	SendChatMessage(text, "WHISPER", nil, row.name)
	row.whispered = time()
	if AGF.Refresh then
		AGF.Refresh()
	end
	return true
end

local WHISPER_CMD = {
	lfm = "pveLfm", pvelfm = "pveLfm",
	lfg = "pveLfg", pvelfg = "pveLfg",
	pvplfm = "pvpLfm", pvplfg = "pvpLfg",
	wts = "tradeWts", wtb = "tradeWtb",
	guild = "guild",
}

local function handleWhisper(rest)
	local sub, text = rest:match("^(%S*)%s*(.*)$")
	sub = (sub or ""):lower()
	if sub == "" then
		if AGF.ShowWhisperSetup then
			AGF.ShowWhisperSetup()
		end
		return
	end
	local slot = WHISPER_CMD[sub]
	if not slot then
		AGF.Print("Use /acs whisper to open the setup, or /acs whisper pvelfm | pvelfg | pvplfm | pvplfg | wts | wtb | guild <text>")
		return
	end
	if text == "" then
		AGF.Print(sub .. " line: " .. (AGF.WhisperTemplate(slot) or ""))
	else
		AGF.SetWhisperTemplate(slot, text)
		AGF.Print(sub .. " line saved: " .. text)
	end
end

SLASH_ASCENSIONCS1 = "/acs"
SlashCmdList["ASCENSIONCS"] = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	rest = rest or ""

	if cmd == "" then
		if AGF.Toggle then AGF.Toggle() end
	elseif cmd == "pve" or cmd == "pvp" or cmd == "trade"
		or cmd == "guild" then
		AGF.SetSection(cmd:upper())
	elseif cmd == "lfm" or cmd == "lfg" or cmd == "unsure"
		or cmd == "wts" or cmd == "wtb" then
		-- A tab is an intent inside the section you are in.
		AGF.SetMode(AGF.BucketFor(AGF.GetSection(), cmd:upper()))
		if AGF.Show then AGF.Show() end
	elseif cmd == "style" then
		local style = rest:lower()
		local names = {}
		if AGF.SKIN_ORDER then
			for i = 1, #AGF.SKIN_ORDER do
				names[#names + 1] = AGF.SKIN_ORDER[i].id
			end
		end
		local found = false
		for i = 1, #names do
			if names[i] == style then
				found = true
			end
		end
		if found then
			ACS_DB.style = style
			if AGF.ApplyStyle then AGF.ApplyStyle() end
			AGF.Print("Skin set to " .. style .. ".")
		else
			AGF.Print("Use the Skins button, or /acs style "
				.. table.concat(names, " | "))
		end
	elseif cmd == "clear" then
		AGF.ClearBucket(AGF.GetMode())
		AGF.Print("Cleared " .. AGF.BucketName(AGF.GetMode()) .. ".")
	elseif cmd == "clearall" then
		for i = 1, #AGF.BUCKETS do
			ACS_DB.rows[AGF.BUCKETS[i]] = {}
		end
		if AGF.Refresh then AGF.Refresh() end
		AGF.ForgetAllNames()
		AGF.Print("Cleared every tab.")
	elseif cmd == "reset" or (cmd == "position" and rest:lower() == "reset") then
		if AGF.ResetWindow and AGF.ResetWindow() then
			AGF.Print("Window back in the middle of the screen at 780 by 460.")
		else
			AGF.Print("The window is not built yet, open it with /acs first.")
		end
	elseif cmd == "mini" then
		if rest:lower() == "reset" then
			if AGF.MiniResetPosition then
				AGF.MiniResetPosition()
			end
		elseif AGF.MiniToggleMode then
			AGF.MiniToggleMode()
			AGF.Print("Mini feed " .. (AGF.MiniIsShown() and "on" or "off"))
		else
			AGF.Print("The mini feed is not loaded, Mini.lua is missing or failed")
		end
	elseif cmd == "minimap" then
		ACS_DB.minimap.show = not ACS_DB.minimap.show
		if AGF.UpdateMinimapButton then AGF.UpdateMinimapButton() end
		AGF.Print("Minimap button " .. (ACS_DB.minimap.show and "shown" or "hidden"))
	elseif cmd == "alert" then
		handleAlert(rest)
	elseif cmd == "whisper" then
		handleWhisper(rest)
	elseif cmd == "pack" then
		local want = rest:lower()
		if want == "" then
			local pack = AGF.ActivePack()
			AGF.Print("Pack " .. pack.name .. " on realm " .. tostring(AGF.realmName)
				.. ", setting is " .. tostring(ACS_DB.pack))
			local names = {}
			for id in pairs(AGF.PACKS) do
				names[#names + 1] = id
			end
			table.sort(names)
			AGF.Print("Available: auto, " .. table.concat(names, ", "))
			local acts = {}
			for i = 1, #pack.activities do
				acts[#acts + 1] = pack.activities[i].name
			end
			AGF.Print("This pack finds: " .. table.concat(acts, ", "))
		elseif want == "auto" or AGF.PACKS[want] then
			ACS_DB.pack = want
			AGF.SelectPack(want ~= "auto" and want or nil)
			AGF.Print("Pack set to " .. AGF.ActivePack().name
				.. ". Rows already listed keep the old reading, run /acs clearall"
				.. " to drop them. New posts use the new pack.")
			if AGF.ApplyPackColumns then
				AGF.ApplyPackColumns()
			end
			if AGF.Refresh then AGF.Refresh() end
		else
			AGF.Print("Unknown pack. Use /acs pack to list them.")
		end
	elseif cmd == "expiry" then
		local v = tonumber(rest)
		if v and v >= 60 then
			ACS_DB.expiry = v
			AGF.Print("Rows expire after " .. v .. " seconds")
		else
			AGF.Print("Current expiry " .. ACS_DB.expiry .. " seconds, minimum 60")
		end
	elseif cmd == "own" then
		ACS_DB.showOwn = not ACS_DB.showOwn
		AGF.Print("Own messages " .. (ACS_DB.showOwn and "included" or "ignored"))
	elseif cmd == "ilvl" then
		local slot = tonumber(rest)
		if slot then
			AGF.ItemLevelDump(slot)
		else
			AGF.ItemLevelReport()
		end
	elseif cmd == "hidden" then
		AGF.HiddenReport(rest)
	elseif cmd == "probe" then
		if AGF.Probe then
			AGF.Probe()
		else
			AGF.Print("Diagnostics are not available.")
		end
	elseif cmd == "debug" then
		ACS_DB.debug = not ACS_DB.debug
		AGF.Print("Debug output " .. (ACS_DB.debug and "on" or "off")
			.. ". Accepted posts only, run /acs probe for the counters.")
	elseif cmd == "help" then
		printHelp()
	else
		printHelp()
	end
end
