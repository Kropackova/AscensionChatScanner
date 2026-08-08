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
}

AGF.SECTIONS = {
	{ id = "PVE", label = "PvE", buckets = { "PVE_LFM", "PVE_LFG", "PVE_UNSURE" } },
	{ id = "PVP", label = "PvP", buckets = { "PVP_LFM", "PVP_LFG", "PVP_UNSURE" } },
	{ id = "TRADE", label = "Trade", buckets = { "TRADE_WTS", "TRADE_WTB", "TRADE_UNSURE" } },
}
AGF.BUCKET_SECTION = {}
AGF.BUCKET_LABEL = {
	PVE_LFM = "LFM", PVE_LFG = "LFG", PVE_UNSURE = "Unsure",
	PVP_LFM = "LFM", PVP_LFG = "LFG", PVP_UNSURE = "Unsure",
	TRADE_WTS = "WTS", TRADE_WTB = "WTB", TRADE_UNSURE = "Unsure",
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
}

AGF.WHISPER_BUCKET_SLOT = {
	PVE_LFM = "pveLfm", PVE_UNSURE = "pveLfm", PVE_LFG = "pveLfg",
	PVP_LFM = "pvpLfm", PVP_UNSURE = "pvpLfm", PVP_LFG = "pvpLfg",
	TRADE_WTS = "tradeWts", TRADE_UNSURE = "tradeWts", TRADE_WTB = "tradeWtb",
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
	PVP = { "ARENA", "BG", "HR", "GUILD", "PVP_OTHER" },
	TRADE = { "DP", "BAZAAR", "PROF", "AURA", "TOME", "HEIRLOOM", "TRANSMOG",
		"MOUNT", "RECIPE", "LOOTBOT", "CONSUM", "GEAR", "TRADE_OTHER" },
	PVE = { "MYTHIC", "OTHER" },
}

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
				local list = (ACS_DB and ACS_DB.rows and ACS_DB.rows[s.buckets[j]]) or {}
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
		parts[#parts + 1] = AGF.KindName(f.kind)
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
	cols = { PVE = {}, PVP = {}, TRADE = {} },
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
		-- Content type, ALL or a row kind such as ARENA.
		kind = "ALL",
		-- Character class, ALL or one class name. Only reachable on a realm
		-- whose pack has classes.
		class = "ALL",
		roles = { tank = false, heal = false, damage = false },
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
	},
	rows = { PVE_LFM = {}, PVE_LFG = {}, PVE_UNSURE = {},
		PVP_LFM = {}, PVP_LFG = {}, PVP_UNSURE = {},
		TRADE_WTS = {}, TRADE_WTB = {}, TRADE_UNSURE = {} },
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

local FILTER_KEYS = { "intent", "kind", "needAura", "needLooms", "minLevel",
	"maxLevel", "word" }

AGF.FILTER_BLANK = {
	intent = "BOTH", kind = "ALL", needAura = false, needLooms = false,
	minLevel = 0, maxLevel = 0, word = "",
	roles = { tank = false, heal = false, damage = false },
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
	return f.roles.tank or f.roles.heal or f.roles.damage
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
	-- Content type. Cuts across the tabs, so it lives in the filter panel.
	if f.kind and f.kind ~= "ALL" and row.kind ~= f.kind then
		return false
	end
	-- Guild recruitment shares the group tabs but is not a group advert, so
	-- it appears only when Guild is picked in the Activity list.
	if row.kind == "GUILD" and f.kind ~= "GUILD" then
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
	-- scope SECTION: only the section you are looking at can alert.
	-- scope ALL: any section can, each judged by its own saved filter set.
	if (a.scope or "ALL") == "SECTION" and section ~= AGF.GetSection() then
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
	-- Straight from the current post. An older post must not leave a stale
	-- number behind when the sender writes again without one.
	row.size = parsed.size
	row.wanted = parsed.wanted

	-- Pack fields. Which of these the table shows is decided by the pack.
	row.activity = parsed.activity
	row.activityName = parsed.activityName
	row.activityShort = parsed.activityShort
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
		for i = 1, #EVENTS do
			self:RegisterEvent(EVENTS[i])
		end
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
				.. ")" .. ((ACS_DB.pack ~= "auto") and " - forced with /acs pack" or ""))
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
		"/acs pve | pvp | trade - pick a section",
		"/acs lfm | lfg | unsure | wts | wtb - pick a tab",
		"/acs style vanilla | dark | grid | slate | parchment | glass | felfire - same as the Skins button",
		"/acs clear - clear the current tab, clearall - clear everything",
		"/acs mini - open or close the mini feed",
		"/acs mini reset - put the mini feed back in the middle of the screen",
		"/acs minimap - show or hide the minimap button",
		"/acs alert on | off | sound | chat | popup | mode lfm|lfg|any",
		"/acs alert scope section | all - same as the Scope button above Alerts",
		"/acs alert move or unlock - drag the popup, /acs alert lock - fix it in place",
		"/acs alert reset - put the popup back in its default spot",
		"/acs expiry 900 - seconds a row stays listed",
		"/acs own - include or exclude your own messages",
		"/acs pack - show the active content pack, /acs pack coa | ascension | classic | auto to switch",
		"/acs whisper - set the one click whisper line for each tab",
		"/acs whisper pvelfm | pvelfg | pvplfm | pvplfg | wts | wtb <text> - set one line",
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
		AGF.Print("Use /acs whisper to open the setup, or /acs whisper pvelfm | pvelfg | pvplfm | pvplfg | wts | wtb <text>")
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
	elseif cmd == "pve" or cmd == "pvp" or cmd == "trade" then
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
