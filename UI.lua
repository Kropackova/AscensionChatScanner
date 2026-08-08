-- Ascension Chat Scanner
-- UI.lua - window, table, editing, player menu, filters, whisper, minimap button.

AGF = AGF or {}

local ROW_H = 18
local MAX_ROWS = 40
local PAD = 14
local SCROLL_W = 20

-- Scroll bar placement. Fine tune here.
-- SCROLL_TOP: pixels from the top of the window to the top of the bar.
--   Raise the number to push the bar further down, below the alert box.
-- SCROLL_BOTTOM: pixels from the bottom of the window to the bottom of
--   the bar. Raise it to keep more space above the resize grip.
-- TITLE_INDENT: how many edge margins the title and the sub line sit in
--   from the left. 1 lines them up with the table, 2 is the current look.
-- Right hand button groups, stacked. VIEW_TOP is the top of the Skins,
-- Rows and Filters row, ALERT_TOP the top of the Scope, bell and Alerts
-- row below it. HEADER_TOP has to clear the lower box.
local BOX_PAD = 7
local BOX_GAP = 6
-- ALERT_TOP matches the section row, VIEW_TOP matches the tab row, so the
-- right hand groups sit on the same two lines as PvE and LFM.
local ALERT_TOP = 46
local VIEW_TOP = 72
local ROW_TOP = 46
local ROW_BOTTOM = 72
-- How the two right hand rows are framed.
--   "none"  no frame at all. The rows line up with the rows on the left
--           and the table header keeps its own height.
--   "one"   one frame around both rows, with a thin line between them.
--           Costs 13 px of height, so the header moves down.
-- Two separate frames cannot line up with the left: the rows are 26 px
-- apart and two frames need 20 px of padding between them.
local GROUP_FRAME = "none"
local HEADER_TOP = (GROUP_FRAME == "none") and 100
	or (ROW_BOTTOM + 22 + BOX_PAD + 6)
local SCROLL_TOP = HEADER_TOP + 28
local SCROLL_BOTTOM = 40
local TITLE_INDENT = 1.33

-- Distance from the top of the window to the top of the table area, and from
-- the bottom of the window to the bottom of the table area. These mirror the
-- anchors used when the frames are built: the header bar sits 76 px down and is
-- 18 px tall, the table starts 4 px under it, and the table stops PAD + 30 px
-- above the bottom edge, which is the strip holding the buttons, the count and
-- the hint. They are kept as numbers because a frame sized only by anchors does
-- not report its new height until the client finishes the layout pass, so
-- asking the table area how tall it is during a resize returns the old value.
local TABLE_TOP = HEADER_TOP + 18 + 4
local TABLE_BOTTOM = PAD + 30

-- Every column the addon can draw. The active pack picks which of the middle
-- ones appear, see Packs.lua. Time, Name, Role, Lvl, W and Message are fixed.
local ALL_COLS = {
	time    = { key = "time",    label = "Time",     w = 62 },
	name    = { key = "name",    label = "Name",     w = 104 },
	role    = { key = "role",    label = "Role",     w = 104, edit = true },
	class   = { key = "class",   label = "Class",    w = 84 },
	act     = { key = "act",     label = "Activity", w = 132 },
	aura    = { key = "aura",    label = "Aura",     w = 66,  edit = true },
	looms   = { key = "looms",   label = "Looms",    w = 72,  edit = true },
	ilvl    = { key = "ilvl",    label = "iLvl",     w = 44, edit = true },
	prog    = { key = "prog",    label = "Filled",   w = 52, edit = true },
	level   = { key = "level",   label = "Lvl",      w = 40,  edit = true },
	wsp     = { key = "wsp",     label = "W",        w = 26,  whisper = true },
	message = { key = "message", label = "Message",  w = 260, flex = true },
}

-- Filled in by buildCols. Kept as one table the whole file shares, because
-- layout, headers, cells and hit testing all read it.
local COLS = {}

local function buildCols()
	-- Every section draws from one superset. Which of these are visible is
	-- decided per section inside layout(), so a section change needs no
	-- reload.
	local order = { "time", "name", "role", "class", "act", "aura", "looms",
		"ilvl", "prog", "level", "wsp", "message" }

	for i = #COLS, 1, -1 do
		COLS[i] = nil
	end
	for i = 1, #order do
		local def = ALL_COLS[order[i]]
		if def then
			COLS[#COLS + 1] = {
				key = def.key,
				label = def.label,
				w = def.w,
				edit = def.edit,
				whisper = def.whisper,
				flex = def.flex,
			}
		end
	end
end

buildCols()

local SKINS = {
	vanilla = {
		backdrop = {
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		},
		titleColor = { 1, 0.82, 0 },
		headerColor = { 1, 0.82, 0 },
		altAlpha = 0.10,
		lines = false,
	},
	dark = {
		backdrop = {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		bgColor = { 0.06, 0.07, 0.09, 0.94 },
		borderColor = { 0.35, 0.38, 0.45, 1 },
		titleColor = { 1, 1, 1 },
		headerColor = { 0.75, 0.82, 0.95 },
		altAlpha = 0.06,
		lines = false,
	},
	grid = {
		backdrop = {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		bgColor = { 0.04, 0.05, 0.07, 0.96 },
		borderColor = { 0.45, 0.40, 0.30, 1 },
		titleColor = { 1, 0.9, 0.6 },
		headerColor = { 1, 0.86, 0.5 },
		altAlpha = 0.16,
		lines = true,
	},
	slate = {
		backdrop = {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		bgColor = { 0.10, 0.13, 0.18, 0.92 },
		borderColor = { 0.30, 0.45, 0.62, 1 },
		titleColor = { 0.66, 0.86, 1 },
		headerColor = { 0.56, 0.76, 0.96 },
		altAlpha = 0.12,
		lines = true,
	},
	-- Almost no window at all. For a crowded screen where the addon should
	-- read as a list floating over the world.
	glass = {
		backdrop = {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		},
		bgColor = { 0, 0, 0, 0.35 },
		borderColor = { 0.75, 0.78, 0.82, 0.55 },
		titleColor = { 1, 1, 1 },
		headerColor = { 0.88, 0.90, 0.94 },
		altAlpha = 0.04,
		lines = false,
	},
	-- Loud green on near black, hard ruled. Easy to spot in a corner.
	felfire = {
		backdrop = {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		bgColor = { 0.02, 0.06, 0.03, 0.96 },
		borderColor = { 0.35, 0.95, 0.40, 1 },
		titleColor = { 0.62, 1, 0.52 },
		headerColor = { 0.50, 0.94, 0.45 },
		altAlpha = 0.18,
		lines = true,
	},
	parchment = {
		backdrop = {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		bgColor = { 0.17, 0.14, 0.10, 0.95 },
		borderColor = { 0.62, 0.52, 0.34, 1 },
		titleColor = { 1, 0.93, 0.76 },
		headerColor = { 0.96, 0.86, 0.62 },
		altAlpha = 0.14,
		lines = false,
	},
}

local frame, headerBar, tableArea, scrollBar, countText, titleText, subText
local filtersButton, alertsButton, clearButton, whisperButton, resizeGrip
local rowsButton, scopeButton, clearAllButton, rowsMenu
local soundButton
local skinsButton, skinsMenu
local alertBox, viewBox, rowsCatcher
local filterPanel, clickCatcher, menuFrame, copyFrame, levelEdit
local headers, rows, tabs, seps = {}, {}, {}, {}
local currentList = {}
local offset = 0

-- Core calls this at login, after the pack is chosen. The columns are the same
-- for every pack, so there is nothing to do once the window exists.
function AGF.ApplyPackColumns()
	if frame then
		return
	end
	buildCols()
end

-- The bottom hint sits left of the resize grip. A short window has no room for
-- it, so the text is shortened and then dropped instead of running under the
-- buttons.
local function updateHint()
	if not frame or not frame.hint then
		return
	end
	local w = frame:GetWidth() or 0
	if w < 660 then
		frame.hint:SetText("")
	elseif w < 900 then
		frame.hint:SetText("Left click to edit - right click a row for actions")
	else
		frame.hint:SetText("Left click a value to edit - W sends your whisper - right click a row for actions")
	end
end

local visibleRows = 15

local YESNO_COLOR = {
	yes = { 0.45, 0.95, 0.5 },
	maybe = { 1, 0.82, 0.2 },
	no = { 0.75, 0.75, 0.75 },
}

local function skin()
	local name = (ACS_DB and ACS_DB.style) or "vanilla"
	return SKINS[name] or SKINS.vanilla
end

-- Mini mode draws itself with the same skin.
function AGF.CurrentSkin()
	return skin()
end

-- Menu order and captions for the Skins button.
local SKIN_ORDER = {
	{ id = "vanilla", label = "Vanilla" },
	{ id = "dark", label = "Dark" },
	{ id = "grid", label = "Grid" },
	{ id = "slate", label = "Slate" },
	{ id = "parchment", label = "Parchment" },
	{ id = "glass", label = "Glass" },
	{ id = "felfire", label = "Felfire" },
}
AGF.SKIN_ORDER = SKIN_ORDER

function AGF.SetSkin(id)
	if not SKINS[id] or not ACS_DB then
		return
	end
	ACS_DB.style = id
	if AGF.ApplyStyle then
		AGF.ApplyStyle()
	end
end

-- Player menu ---------------------------------------------------------------

local function ensureTarget(name)
	if UnitExists("target") and UnitName("target") == name then
		return true
	end
	TargetByName(name, true)
	if UnitExists("target") and UnitName("target") == name then
		return true
	end
	AGF.Print(name .. " is not nearby, so that action needs the player in range.")
	return false
end

local function showCopyBox(name)
	if not copyFrame then
		copyFrame = CreateFrame("Frame", "AGF_CopyFrame", UIParent)
		copyFrame:SetWidth(240)
		copyFrame:SetHeight(70)
		copyFrame:SetPoint("CENTER")
		copyFrame:SetFrameStrata("DIALOG")
		copyFrame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 26,
			insets = { left = 9, right = 9, top = 9, bottom = 9 },
		})
		local label = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOP", 0, -14)
		label:SetText("Ctrl+C to copy")
		local box = CreateFrame("EditBox", "AGF_CopyBox", copyFrame, "InputBoxTemplate")
		box:SetWidth(180)
		box:SetHeight(20)
		box:SetPoint("BOTTOM", 0, 16)
		box:SetAutoFocus(true)
		box:SetScript("OnEscapePressed", function(self) copyFrame:Hide() end)
		box:SetScript("OnEnterPressed", function(self) copyFrame:Hide() end)
		copyFrame.box = box
		table.insert(UISpecialFrames, "AGF_CopyFrame")
	end
	copyFrame:Show()
	copyFrame.box:SetText(name)
	copyFrame.box:HighlightText()
	copyFrame.box:SetFocus()
end

-- The server refuses InviteUnit when you are in a group without rank, so the
-- row offers the client's own suggestion instead. State is read at click time.
local function inviteEntry(name)
	if AGF.CanInvite and not AGF.CanInvite() then
		return { text = "Suggest Invite", notCheckable = true, func = function()
			AGF.SuggestInvite(name)
		end }
	end
	return { text = "Invite", notCheckable = true, func = function()
		InviteUnit(name)
	end }
end

local function openPlayerMenu(bucket, name, anchor)
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "AGF_MenuFrame", UIParent, "UIDropDownMenuTemplate")
	end
	local menu = {
		{ text = name, isTitle = true, notCheckable = true },
		{ text = "Whisper", notCheckable = true, func = function()
			ChatFrame_OpenChat("/w " .. name .. " ", DEFAULT_CHAT_FRAME)
		end },
		inviteEntry(name),
		{ text = "Target", notCheckable = true, func = function()
			ensureTarget(name)
		end },
		{ text = "Add friend", notCheckable = true, func = function()
			AddFriend(name)
		end },
		{ text = "Ignore", notCheckable = true, func = function()
			AddIgnore(name)
		end },
		{ text = "Copy name", notCheckable = true, func = function()
			showCopyBox(name)
		end },
		{ text = "Remove row", notCheckable = true, func = function()
			AGF.RemoveRow(bucket, name)
		end },
		{ text = "Cancel", notCheckable = true, func = function() end },
	}
	-- Wording is sometimes genuinely ambiguous, so allow a manual move.
	-- The targets come from the section table, every tab of every section
	-- except the one the row already sits in, tucked into a submenu so the
	-- player menu stays short.
	local moves = {}
	for i = 1, #AGF.SECTIONS do
		local section = AGF.SECTIONS[i]
		for j = 1, #section.buckets do
			local target = section.buckets[j]
			if target ~= bucket then
				table.insert(moves, {
					text = section.label .. " " .. (AGF.BUCKET_LABEL[target] or target),
					notCheckable = true,
					func = function()
						AGF.MoveRow(bucket, name, target)
					end,
				})
			end
		end
	end
	table.insert(menu, #menu, {
		text = "Move to",
		notCheckable = true,
		hasArrow = true,
		menuList = moves,
	})
	UIDropDownMenu_Initialize(menuFrame, function(self, level, menuList)
		local list = (level == 1) and menu or menuList
		if not list then
			return
		end
		for i = 1, #list do
			local info = list[i]
			info.menuList = info.menuList
			UIDropDownMenu_AddButton(info, level)
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

-- Same right click menu from the mini window.
AGF.OpenPlayerMenu = openPlayerMenu

-- Layout --------------------------------------------------------------------

-- How many rows fit inside the table area right now.
--
-- A row is only counted when the whole of it fits. Two heights are compared and
-- the smaller one wins: the height the table area reports, and the height worked
-- out from the window itself. The reported height is stale for one frame after a
-- resize, because the table area is sized by anchors only, and that stale value
-- is what allowed rows to keep drawing over the buttons and the hint after the
-- window was made shorter.
local function fitRows()
	if not frame then
		return 1
	end
	local areaH = (tableArea and tableArea:GetHeight()) or 0
	local geomH = (frame:GetHeight() or 0) - TABLE_TOP - TABLE_BOTTOM
	if areaH <= 0 or geomH < areaH then
		areaH = geomH
	end
	local count = math.floor(areaH / ROW_H)
	while count > 1 and count * ROW_H > areaH do
		count = count - 1
	end
	if count < 1 then count = 1 end
	if count > MAX_ROWS then count = MAX_ROWS end
	return count
end

-- Columns are dropped from this list, first to last, until the remaining
-- columns fit the width of the table. Time, Name, W and Message always stay.
local COL_DROP_ORDER = { "prog", "looms", "aura", "ilvl", "level", "class",
	"act", "role" }
local MIN_MESSAGE_W = 120

-- The columns each section uses. Trade has no role and no level, a seller
-- has neither.
local SECTION_COLS = {
	PVE = { time = true, name = true, role = true, class = true, act = true,
		aura = true, looms = true, ilvl = true, prog = true, level = true,
		wsp = true, message = true },
	PVP = { time = true, name = true, role = true, class = true, act = true,
		ilvl = true, level = true, wsp = true, message = true },
	TRADE = { time = true, name = true, act = true, wsp = true, message = true },
}

-- True on a realm where characters have a class. Classless realms never show
-- the Class column or its filter.
function AGF.PackHasClasses()
	local pack = AGF.ActivePack and AGF.ActivePack()
	return (pack and pack.classes) and true or false
end

function AGF.SectionColumnSet()
	local id = (AGF.GetSection and AGF.GetSection()) or "PVE"
	local set = SECTION_COLS[id] or SECTION_COLS.PVE
	if set.class and not AGF.PackHasClasses() then
		local copy = {}
		for k, v in pairs(set) do
			copy[k] = v
		end
		copy.class = nil
		return copy
	end
	return set
end
local hiddenCols = {}

function AGF.ColumnIsHidden(key)
	return hiddenCols[key] == true
end

-- Columns switched off by hand with the Rows button. Kept per section, so
-- PvE can be wide while Trade stays compact, and saved between sessions.
-- Name and Message can never be switched off: without them there is no table.
local LOCKED_COLS = { name = true, message = true }

local function colStore(create)
	local section = (AGF.GetSection and AGF.GetSection()) or "PVE"
	if not ACS_DB then
		return nil
	end
	if create then
		ACS_DB.cols = ACS_DB.cols or {}
		ACS_DB.cols[section] = ACS_DB.cols[section] or {}
	end
	return ACS_DB.cols and ACS_DB.cols[section]
end

function AGF.ColumnOff(key)
	if LOCKED_COLS[key] then
		return false
	end
	local set = colStore(false)
	return set ~= nil and set[key] == true
end

function AGF.ToggleColumn(key)
	if LOCKED_COLS[key] then
		return
	end
	local set = colStore(true)
	if not set then
		return
	end
	if set[key] then
		set[key] = nil
	else
		set[key] = true
	end
	if AGF.Refresh then
		AGF.Refresh()
	end
end

function AGF.ShowAllColumns()
	local set = colStore(true)
	if not set then
		return
	end
	for k in pairs(set) do
		set[k] = nil
	end
	if AGF.Refresh then
		AGF.Refresh()
	end
end

-- One margin for every edge of the window. It scales with the window width, so
-- the title, the tabs, the table, the bottom bar and the alert box all keep the
-- same visual gap at any size or ui scale.
-- One fixed margin for every edge of the window. A percentage of the window
-- width was tried and rejected: widgets that relayout at different times ended
-- up at different offsets while the window was being dragged wider.
local EDGE_MARGIN = 16

function AGF.EdgeMargin()
	return EDGE_MARGIN
end

-- Widgets that sit on an edge register how they anchor themselves. The list is
-- replayed on every resize, so no anchor is left behind at a stale offset.
local edgeAnchors = {}

local function edgeAnchor(fn)
	table.insert(edgeAnchors, fn)
	fn(AGF.EdgeMargin())
end

function AGF.LayoutEdges()
	local m = AGF.EdgeMargin()
	for i = 1, #edgeAnchors do
		edgeAnchors[i](m)
	end
end

local function layout()
	if not frame then
		return
	end
	AGF.LayoutEdges()
	local avail = frame:GetWidth() - AGF.EdgeMargin() * 2 - SCROLL_W

	-- Step 1. Find the columns that fit. A column that does not fit is hidden.
	-- Columns are measured, not drawn at fixed offsets, so the last
	-- columns ran past the right edge of the table.
	for k in pairs(hiddenCols) do
		hiddenCols[k] = nil
	end

	-- Step 0. Hide what this section does not use at all.
	local allowed = AGF.SectionColumnSet()
	for i = 1, #COLS do
		local key = COLS[i].key
		if not allowed[key] or AGF.ColumnOff(key) then
			hiddenCols[key] = true
		end
	end

	local function neededWidth()
		local sum = 6
		for i = 1, #COLS do
			local c = COLS[i]
			if not hiddenCols[c.key] then
				sum = sum + (c.flex and MIN_MESSAGE_W or c.w) + 6
			end
		end
		return sum
	end
	local present = {}
	for i = 1, #COLS do
		present[COLS[i].key] = true
	end
	for n = 1, #COL_DROP_ORDER do
		if neededWidth() <= avail then
			break
		end
		local key = COL_DROP_ORDER[n]
		if present[key] then
			hiddenCols[key] = true
		end
	end

	-- Step 2. Share the leftover width with the message column.
	local fixed = 0
	for i = 1, #COLS do
		local c = COLS[i]
		if not hiddenCols[c.key] and not c.flex then
			fixed = fixed + c.w + 6
		end
	end
	local flexW = avail - fixed - 6
	if flexW < MIN_MESSAGE_W then
		flexW = MIN_MESSAGE_W
	end

	local x = 0
	local lastVisible = 0
	for i = 1, #COLS do
		local c = COLS[i]
		if hiddenCols[c.key] then
			c.cw = 0
			c.x = 0
		else
			c.cw = c.flex and flexW or c.w
			c.x = x
			x = x + c.cw + 6
			lastVisible = i
		end
	end

	for i = 1, #COLS do
		local h = headers[i]
		if hiddenCols[COLS[i].key] then
			h:Hide()
		else
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", headerBar, "TOPLEFT", COLS[i].x, 0)
			h:SetWidth(COLS[i].cw)
			h:SetHeight(18)
			h:Show()
		end
	end

	visibleRows = fitRows()

	for i = 1, MAX_ROWS do
		local row = rows[i]
		row:SetWidth(avail)
		for j = 1, #COLS do
			local cell = row.cells[COLS[j].key]
			if cell then
				if hiddenCols[COLS[j].key] then
					cell:Hide()
				else
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", row, "LEFT", COLS[j].x, 0)
					cell:SetWidth(COLS[j].cw)
					cell:Show()
				end
			end
		end
		if i <= visibleRows then
			row:Show()
		else
			row:Hide()
		end
	end

	local useLines = skin().lines
	for i = 1, #COLS do
		local sep = seps[i]
		if hiddenCols[COLS[i].key] or not useLines or i >= lastVisible then
			sep:Hide()
		else
			sep:ClearAllPoints()
			sep:SetPoint("TOPLEFT", tableArea, "TOPLEFT", COLS[i].x + COLS[i].cw + 2, 0)
			sep:SetPoint("BOTTOMLEFT", tableArea, "BOTTOMLEFT", COLS[i].x + COLS[i].cw + 2, 0)
			sep:SetWidth(1)
			sep:Show()
		end
	end
end

-- Rendering -----------------------------------------------------------------

local function levelText(data)
	if not data.level then
		return "?"
	end
	if data.bracket then
		return tostring(data.level) .. "+"
	end
	return tostring(data.level)
end

local function paintRow(row, data, index)
	row.data = data
	local cells = row.cells
	local now = time()
	local age = now - (data.time or now)
	local stale = age > (ACS_DB.stale or 300)

	cells.time:SetText(date("%H:%M:%S", data.time or now))
	if stale then
		cells.time:SetTextColor(0.55, 0.55, 0.55)
	else
		cells.time:SetTextColor(0.85, 0.85, 0.85)
	end

	cells.name:SetText(data.name or "?")
	cells.name:SetTextColor(1, 1, 1)

	if cells.class then
		cells.class:SetText(data.class or "-")
		cells.class:SetTextColor(0.85, 0.85, 0.85)
	end

	cells.role:SetText(AGF.RoleDisplay(data.roleText))
	if data.locked and data.locked.role then
		cells.role:SetTextColor(0.4, 0.75, 1)
	else
		cells.role:SetTextColor(0.95, 0.9, 0.7)
	end

	local function paintYesNo(cell, value, locked)
		cell:SetText(value or "no")
		if locked then
			cell:SetTextColor(0.4, 0.75, 1)
		else
			local c = YESNO_COLOR[value or "no"] or YESNO_COLOR.no
			cell:SetTextColor(c[1], c[2], c[3])
		end
	end
	if cells.aura then
		paintYesNo(cells.aura, data.aura, data.locked and data.locked.aura)
	end
	if cells.looms then
		paintYesNo(cells.looms, data.looms, data.locked and data.locked.looms)
	end

	-- Pack columns. Each one is drawn only when the pack asked for it.
	if cells.act then
		local text = data.activityShort or data.activityName
		if not text and data.profession then
			text = data.profession
			if data.profMode then
				text = text .. " (" .. data.profMode .. ")"
			end
		end
		text = text or "?"
		if data.target then
			text = text .. ": " .. data.target
		end
		cells.act:SetText(text)
		cells.act:SetTextColor(0.68, 0.84, 1)
	end
	if cells.ilvl then
		if levelEdit and levelEdit:IsShown() and levelEdit.cell == cells.ilvl then
			cells.ilvl:SetText("")
		else
			cells.ilvl:SetText(data.ilvl and tostring(data.ilvl) or "-")
		end
		if data.locked and data.locked.ilvl then
			cells.ilvl:SetTextColor(0.4, 0.75, 1)
		else
			cells.ilvl:SetTextColor(0.85, 0.85, 0.85)
		end
	end
	if cells.prog then
		if levelEdit and levelEdit:IsShown() and levelEdit.cell == cells.prog then
			cells.prog:SetText("")
		else
			cells.prog:SetText(data.prog or "-")
		end
		if data.locked and data.locked.prog then
			cells.prog:SetTextColor(0.4, 0.75, 1)
		else
			cells.prog:SetTextColor(0.85, 0.85, 0.85)
		end
	end

	-- While the level box is open over this cell, the cell stays blank, so the
	-- old value is not drawn behind the box.
	if levelEdit and levelEdit:IsShown() and levelEdit.cell == cells.level then
		cells.level:SetText("")
	else
		cells.level:SetText(levelText(data))
	end
	if data.locked and data.locked.level then
		cells.level:SetTextColor(0.4, 0.75, 1)
	else
		cells.level:SetTextColor(0.85, 0.85, 0.85)
	end

	-- The whisper cell is a one click send, so show plainly when it was used.
	if data.whispered then
		cells.wsp:SetText("|cff40ff90sent|r")
	else
		cells.wsp:SetText("|cffffd200>>|r")
	end

	cells.message:SetText(data.message or data.rawMessage or "")
	cells.message:SetTextColor(0.8, 0.82, 0.88)

	local alt = skin().altAlpha
	if index % 2 == 0 then
		row.bg:SetTexture(1, 1, 1, alt)
	else
		row.bg:SetTexture(1, 1, 1, alt * 0.35)
	end
	row.bg:Show()
	row:Show()
end

local function updateRows()
	if not frame then
		return
	end
	-- Recount here as well. Painting can run from a timer or from an incoming
	-- message, after a resize but before the next layout pass, and a stale
	-- count is what let rows draw past the bottom edge.
	visibleRows = fitRows()
	local total = #currentList
	local maxOffset = total - visibleRows
	if maxOffset < 0 then maxOffset = 0 end
	if offset > maxOffset then offset = maxOffset end

	scrollBar:SetMinMaxValues(0, maxOffset)
	scrollBar.updating = true
	scrollBar:SetValue(offset)
	scrollBar.updating = nil
	if maxOffset > 0 then
		scrollBar:Show()
	else
		scrollBar:Hide()
	end

	for i = 1, MAX_ROWS do
		local row = rows[i]
		if i <= visibleRows then
			local data = currentList[i + offset]
			if data then
				paintRow(row, data, i + offset)
			else
				row.data = nil
				for j = 1, #COLS do
					row.cells[COLS[j].key]:SetText("")
				end
				row.bg:Hide()
			end
		else
			row:Hide()
		end
	end
end

function AGF.Refresh()
	if not frame or not ACS_DB then
		return
	end
	-- Nothing to paint while the window is hidden, and OnShow refreshes.
	if not frame:IsShown() then
		return
	end
	local mode = AGF.GetMode()
	currentList = AGF.GetSortedRows(mode, ACS_DB.sortKey, ACS_DB.sortAsc)
	for i = 1, #AGF.BUCKETS do
		local key = AGF.BUCKETS[i]
		local tab = tabs[key]
		if tab then
			local shown, total = AGF.FilterCount(key)
			local text = (AGF.BUCKET_LABEL[key] or key) .. " " .. shown
			if AGF.FilterActive() and shown ~= total then
				text = text .. "/" .. total
			end
			tab:SetText(text)
			-- "Unsure 3/56" needs more room than a plain label.
			local fs = tab:GetFontString()
			local need = fs and (fs:GetStringWidth() + 24) or 92
			if need < 92 then
				need = 92
			end
			tab:SetWidth(need)
			if key == mode then
				tab:LockHighlight()
			else
				tab:UnlockHighlight()
			end
		end
	end
	if frame.layoutTabs then
		frame.layoutTabs()
	end
	-- The section decides the column set, so lay the table out again.
	layout()
	-- One name per column across the whole section. "Aura req" on one tab and
	-- "Aura" on the next read as two different columns.
	for i = 1, #COLS do
		local key = COLS[i].key
		if key == "aura" then
			headers[i].label:SetText("Aura")
		elseif key == "looms" then
			headers[i].label:SetText("Looms")
		end
	end
	countText:SetText(#currentList .. " of " .. #(ACS_DB.rows[mode] or {})
		.. " shown" .. ((AGF.FilterSummary and AGF.FilterSummary()) or ""))
	AGF.UpdateAlertButtons()
	updateRows()
end

-- Alerts, the bell and the scope button all decide the same thing, so they
-- sit next to each other on one row, level with the section row on the left.
function AGF.LayoutAlertBar()
	if not alertsButton or not soundButton or not scopeButton or not frame then
		return
	end
	-- The same margin the title, the tabs and the table use.
	local margin = AGF.EdgeMargin()
	-- Padding is zero unless the optional frame is switched on.
	local boxPad = (GROUP_FRAME == "none") and 0 or BOX_PAD
	local gap = BOX_GAP
	local scopeW = scopeButton:GetWidth()
	local soundW = soundButton:GetWidth()
	local alertsW = alertsButton:GetWidth()
	alertsButton:ClearAllPoints()
	soundButton:ClearAllPoints()
	scopeButton:ClearAllPoints()
	if alertBox then
		alertBox:ClearAllPoints()
	end
	-- Reading order: Alerts, bell, scope.
	local groupW = alertsW + gap + soundW + gap + scopeW
	scopeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
		-(margin + boxPad), -ALERT_TOP)
	soundButton:SetPoint("RIGHT", scopeButton, "LEFT", -gap, 0)
	alertsButton:SetPoint("RIGHT", soundButton, "LEFT", -gap, 0)
	-- One frame wraps both rows. LayoutViewBox sizes it, because it needs
	-- the width of both.
	AGF.alertRowWidth = groupW
	AGF.LayoutViewBox()
end

-- Skins, Rows and Filters in one row inside their own box, left of the
-- alert box. Two groups, two frames, one job each.
function AGF.LayoutViewBox()
	if not frame or not filtersButton or not rowsButton or not skinsButton then
		return
	end
	local margin = AGF.EdgeMargin()
	local boxPad = (GROUP_FRAME == "none") and 0 or BOX_PAD
	local gap = BOX_GAP
	filtersButton:ClearAllPoints()
	rowsButton:ClearAllPoints()
	skinsButton:ClearAllPoints()
	-- Lower row, same right edge as the alert row above it.
	-- Reading order: Filters, Rows, Skins.
	skinsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
		-(margin + boxPad), -VIEW_TOP)
	rowsButton:SetPoint("RIGHT", skinsButton, "LEFT", -gap, 0)
	filtersButton:SetPoint("RIGHT", rowsButton, "LEFT", -gap, 0)
	-- The frame covers whichever row is wider, so both rows keep the same
	-- right edge and the same padding.
	local viewW = skinsButton:GetWidth() + gap + rowsButton:GetWidth()
		+ gap + filtersButton:GetWidth()
	local widest = AGF.alertRowWidth or 0
	if viewW > widest then
		widest = viewW
	end
	if viewBox then
		viewBox:Hide()
	end
	if alertBox then
		if GROUP_FRAME == "none" then
			alertBox:Hide()
		else
			alertBox:ClearAllPoints()
			alertBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -margin,
				-(ROW_TOP - boxPad))
			alertBox:SetWidth(widest + (boxPad * 2))
			alertBox:SetHeight((ROW_BOTTOM + 22 + boxPad) - (ROW_TOP - boxPad))
			-- A hair line keeps the two jobs apart inside one frame.
			if not alertBox.divider then
				alertBox.divider = alertBox:CreateTexture(nil, "OVERLAY")
				alertBox.divider:SetTexture(1, 1, 1, 0.12)
				alertBox.divider:SetHeight(1)
			end
			alertBox.divider:ClearAllPoints()
			local midY = -((ROW_BOTTOM - ROW_TOP - 22) / 2 + 22 + boxPad)
			alertBox.divider:SetPoint("TOPLEFT", alertBox, "TOPLEFT", 5, midY)
			alertBox.divider:SetPoint("TOPRIGHT", alertBox, "TOPRIGHT", -5, midY)
			alertBox.divider:Show()
			alertBox:Show()
		end
	end
end

function AGF.UpdateAlertButtons()
	local a = ACS_DB and ACS_DB.alert
	if not a then
		return
	end
	if alertsButton then
		alertsButton:SetText("Alerts: " .. (a.enabled and "ON" or "OFF"))
	end
	if scopeButton then
		scopeButton:SetText((a.scope or "ALL") == "SECTION" and "Section" or "All")
	end
	if rowsButton then
		rowsButton:SetText("Rows")
	end
	if soundButton then
		-- Sound on is a bright bell. Muted is the same bell desaturated, with the
		-- stock red cross over it. VOICECHAT-MUTED is only the cross, so it fills
		-- the button cleanly.
		local icon = soundButton:GetNormalTexture()
		if icon and icon.SetDesaturated then
			icon:SetDesaturated(not a.sound)
		end
		if soundButton.cross then
			if a.sound then
				soundButton.cross:Hide()
			else
				soundButton.cross:Show()
			end
		end
		-- Only a slight dim while alerts are off. The bell still has to be legible
		-- against the window frame.
		soundButton:SetAlpha(a.enabled and 1 or 0.85)
	end
end

function AGF.RefreshTimes()
	if frame and frame:IsShown() then
		updateRows()
	end
end

-- Editing -------------------------------------------------------------------

local function nextInCycle(cycle, current)
	for i = 1, #cycle do
		if cycle[i] == current then
			return cycle[i % #cycle + 1]
		end
	end
	return cycle[1]
end

local ROLE_CYCLE = { "?", "tank", "heal", "damage", "tank, damage", "heal, damage", "tank, heal, damage" }
local YESNO_CYCLE = { "no", "maybe", "yes" }

local function applyRoleText(data, text)
	data.roleText = text
	data.roleSet = {}
	for i = 1, #AGF.ROLE_ORDER do
		if text:find(AGF.ROLE_ORDER[i], 1, true) then
			data.roleSet[AGF.ROLE_ORDER[i]] = true
		end
	end
end

-- A full screen catcher sits under the open editor. The next click anywhere,
-- left or right button, closes the editor. That also stops an editor from
-- staying alive over another tab.
local editCatcher

local function ensureEditCatcher()
	if editCatcher then
		return
	end
	editCatcher = CreateFrame("Button", "AGF_EditCatcher", UIParent)
	editCatcher:SetAllPoints(UIParent)
	editCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
	editCatcher:EnableMouse(true)
	editCatcher:RegisterForClicks("AnyDown")
	editCatcher:Hide()
	editCatcher:SetScript("OnClick", function()
		AGF.CloseCellEditor()
	end)
end

-- Closes the editor and keeps the value that was there before. Escape and any
-- click outside the box both use this.
function AGF.CloseCellEditor()
	if levelEdit then
		levelEdit.data = nil
		levelEdit.cell = nil
		levelEdit:ClearFocus()
		levelEdit:Hide()
	end
	if editCatcher then
		editCatcher:Hide()
	end
	if AGF.Refresh then
		AGF.Refresh()
	end
end

local EDIT_KINDS = {
	level = { numeric = true, maxLetters = 2, width = 40 },
	ilvl = { numeric = true, maxLetters = 3, width = 44 },
	prog = { numeric = false, maxLetters = 7, width = 56 },
}

-- One editor for every typed cell: level, iLvl and Filled. Enter or Space
-- saves, Escape cancels, a click anywhere cancels. An empty box puts back
-- the value the message gave and drops the hand edit.
local function openCellEditor(row, cell, kind)
	local spec = EDIT_KINDS[kind] or EDIT_KINDS.level
	ensureEditCatcher()
	if not levelEdit then
		-- Parented to the catcher, so the box draws above it and takes its own
		-- clicks while every other click closes the editor.
		levelEdit = CreateFrame("EditBox", "AGF_LevelEdit", editCatcher, "InputBoxTemplate")
		levelEdit:SetHeight(18)
		levelEdit:SetAutoFocus(true)
		levelEdit:Hide()

		levelEdit:SetScript("OnEnterPressed", function(self)
			local data = self.data
			local k = self.kind or "level"
			if data then
				local text = self:GetText() or ""
				data.locked = data.locked or {}
				if k == "prog" then
					if text == "" then
						data.prog = data.orig and data.orig.prog or nil
						data.locked.prog = nil
					elseif text:match("^%d+%s*/%s*%d+$") then
						data.prog = text
						data.locked.prog = true
					end
				elseif k == "ilvl" then
					local v = tonumber(text)
					if text == "" then
						data.ilvl = data.orig and data.orig.ilvl or nil
						data.locked.ilvl = nil
					elseif v and v >= 1 and v <= (AGF.ILVL_MAX or 600) then
						data.ilvl = v
						data.locked.ilvl = true
					end
				else
					local v = tonumber(text)
					if text == "" then
						data.level = data.orig and data.orig.level or nil
						data.bracket = (data.orig and data.orig.bracket) or false
						data.locked.level = nil
					elseif v and v >= 1 and v <= (AGF.LEVEL_CAP or 60) then
						data.level = v
						data.bracket = false
						data.locked.level = true
					end
				end
			end
			AGF.CloseCellEditor()
		end)
		levelEdit:SetScript("OnSpacePressed", function(self)
			local save = self:GetScript("OnEnterPressed")
			if save then
				save(self)
			end
		end)
		-- A numeric box swallows the space bar before OnSpacePressed fires on
		-- some clients, so the character itself is caught as well.
		levelEdit:SetScript("OnChar", function(self, ch)
			if ch == " " then
				self:SetText((self:GetText() or ""):gsub(" ", ""))
				local save = self:GetScript("OnEnterPressed")
				if save then
					save(self)
				end
			end
		end)
		levelEdit:SetScript("OnEscapePressed", function(self)
			-- Escape is the only way to throw the typed value away.
			self.data = nil
			AGF.CloseCellEditor()
		end)
		levelEdit:SetScript("OnEditFocusLost", function(self)
			-- Clicking away keeps what was typed. Losing an edit because the
			-- mouse moved is never what anyone wanted.
			if self.data and not self.saving then
				self.saving = true
				local save = self:GetScript("OnEnterPressed")
				if save then
					save(self)
				end
				self.saving = nil
			end
			self.data = nil
			self.cell = nil
			self:Hide()
			if editCatcher then
				editCatcher:Hide()
			end
		end)
	end
	levelEdit:SetNumeric(spec.numeric and true or false)
	levelEdit:SetMaxLetters(spec.maxLetters)
	levelEdit:SetWidth(spec.width)
	levelEdit.data = row.data
	levelEdit.cell = cell
	levelEdit.kind = kind
	-- Blank the cell, otherwise the old value shows through the box.
	cell:SetText("")
	levelEdit:ClearAllPoints()
	levelEdit:SetPoint("LEFT", cell, "LEFT", -4, 0)
	local current
	if kind == "ilvl" then
		current = row.data.ilvl and tostring(row.data.ilvl) or ""
	elseif kind == "prog" then
		current = row.data.prog or ""
	else
		current = row.data.level and tostring(row.data.level) or ""
	end
	levelEdit:SetText(current)
	editCatcher:Show()
	levelEdit:Show()
	levelEdit:SetFocus()
	levelEdit:HighlightText()
end

-- Steps a yes, maybe, no cell. Every state is reachable and the step after the
-- last one puts back what the message said.
--
-- The count of clicks is held per cell instead of being worked out from the
-- value on screen. Reading the value was wrong whenever the parsed value was
-- the last one in the list: an LFM row parsed as "maybe" only flipped between
-- maybe and yes, because the revert test fired one step too early.
local function cycleStep(data, key, cycle, orig, setter)
	data.step = data.step or {}
	local step = (data.locked[key] and data.step[key]) or 0
	step = step + 1
	if step > #cycle then
		setter(orig)
		data.locked[key] = nil
		data.step[key] = nil
		return
	end
	setter(nextInCycle(cycle, data[key] or cycle[1]))
	data.locked[key] = true
	data.step[key] = step
end

local function cycleYesNo(data, key)
	local orig = (data.orig and data.orig[key]) or "no"
	cycleStep(data, key, YESNO_CYCLE, orig, function(v)
		data[key] = v
	end)
end

local function columnAt(row)
	local scale = row:GetEffectiveScale()
	local cursorX = GetCursorPosition() / scale
	local rel = cursorX - row:GetLeft()
	for i = 1, #COLS do
		if rel >= COLS[i].x and rel < COLS[i].x + (COLS[i].cw or COLS[i].w) then
			return COLS[i]
		end
	end
	return nil
end

local function onRowClick(row, button)
	local data = row.data
	if not data then
		return
	end
	if button == "RightButton" then
		openPlayerMenu(AGF.GetMode(), data.name, row)
		return
	end
	local col = columnAt(row)
	if col and col.whisper then
		AGF.SendWhisper(data, AGF.GetMode())
		return
	end
	if not col or not col.edit then
		return
	end
	data.locked = data.locked or {}
	if col.key == "role" then
		-- Same rule as the yes/no cells: every entry is reachable and the step
		-- after the last one restores the roles the message named.
		local orig = (data.orig and data.orig.roleText) or "?"
		data.step = data.step or {}
		local step = (data.locked.role and data.step.role) or 0
		step = step + 1
		if step > #ROLE_CYCLE then
			applyRoleText(data, orig)
			data.locked.role = nil
			data.step.role = nil
		else
			applyRoleText(data, nextInCycle(ROLE_CYCLE, data.roleText or "?"))
			data.locked.role = true
			data.step.role = step
		end
	elseif col.key == "aura" then
		cycleYesNo(data, "aura")
	elseif col.key == "looms" then
		cycleYesNo(data, "looms")
	elseif col.key == "level" then
		openCellEditor(row, row.cells.level, "level")
		return
	elseif col.key == "ilvl" then
		openCellEditor(row, row.cells.ilvl, "ilvl")
		return
	elseif col.key == "prog" then
		openCellEditor(row, row.cells.prog, "prog")
		return
	end
	AGF.Refresh()
end

-- Whisper setup -------------------------------------------------------------

local whisperPanel

-- Built without the stock input box art, which only drew its stretched middle
-- piece on the first box. Own backdrop, so every box looks the same.
local function makeTemplateBox(parent, y, maxLetters)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y)
	box:SetWidth(410)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxLetters or 200)
	box:SetFontObject("ChatFontNormal")
	box:SetTextColor(1, 1, 1)
	box:SetTextInsets(6, 6, 0, 0)
	box:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	box:SetBackdropColor(0, 0, 0, 0.9)
	box:SetBackdropBorderColor(0.45, 0.45, 0.52, 1)
	box:EnableMouse(true)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return box
end

local function saveWhisperPanel()
	if not whisperPanel or not whisperPanel.boxes then
		return
	end
	for i = 1, #whisperPanel.boxes do
		local box = whisperPanel.boxes[i]
		AGF.SetWhisperTemplate(box.slot, box:GetText() or "")
	end
	AGF.Print("Whisper lines saved")
end

-- One box per slot, built from AGF.WHISPER_SLOTS, so the panel can never drift
-- away from what AGF.WhisperTemplate actually sends.
local function createWhisperPanel()
	whisperPanel = CreateFrame("Frame", "AGF_WhisperPanel", UIParent)
	whisperPanel:SetWidth(470)
	whisperPanel:SetHeight(300)
	whisperPanel:SetPoint("CENTER")
	whisperPanel:SetFrameStrata("FULLSCREEN_DIALOG")
	whisperPanel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24,
		insets = { left = 8, right = 8, top = 8, bottom = 8 },
	})
	whisperPanel:EnableMouse(true)
	whisperPanel:SetMovable(true)
	whisperPanel:RegisterForDrag("LeftButton")
	whisperPanel:SetScript("OnDragStart", function(self) self:StartMoving() end)
	whisperPanel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	-- Solid backing so chat behind the panel cannot be read through it.
	local solid = whisperPanel:CreateTexture(nil, "BORDER")
	solid:SetTexture(0.04, 0.04, 0.05, 1)
	solid:SetPoint("TOPLEFT", 7, -7)
	solid:SetPoint("BOTTOMRIGHT", -7, 7)

	local title = whisperPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 20, -18)
	title:SetText("Whisp Templates")

	local intro = whisperPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", 22, -38)
	intro:SetWidth(420)
	intro:SetJustifyH("LEFT")
	intro:SetText("Nothing is sent automatically. The W cell in a row sends the"
		.. " line of that row's own tab, once per click.")

	whisperPanel.boxes = {}
	local slots = AGF.WHISPER_SLOTS or {}
	local y = -68
	for i = 1, #slots do
		local label = whisperPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 20, y)
		label:SetWidth(420)
		label:SetJustifyH("LEFT")
		label:SetText(slots[i].label)

		local box = makeTemplateBox(whisperPanel, y - 16)
		box.slot = slots[i].key
		box:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			saveWhisperPanel()
		end)
		whisperPanel.boxes[i] = box
		y = y - 56
	end

	local tokens = whisperPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tokens:SetPoint("TOPLEFT", 22, y - 6)
	tokens:SetWidth(420)
	tokens:SetJustifyH("LEFT")
	tokens:SetText("Placeholders, filled in when you click: {name} {role} {level}"
		.. " {aura} {looms} {size} read from the post, {myname} {mylevel} for"
		.. " you, {prof} {profmode} on profession rows.")

	-- Height follows the number of slots, so nothing can overlap again.
	whisperPanel:SetHeight(-y + 116)

	local save = CreateFrame("Button", nil, whisperPanel, "UIPanelButtonTemplate")
	save:SetWidth(90)
	save:SetHeight(22)
	save:SetPoint("BOTTOMRIGHT", -114, 18)
	save:SetText("Save")
	save:SetScript("OnClick", saveWhisperPanel)

	local close = CreateFrame("Button", nil, whisperPanel, "UIPanelButtonTemplate")
	close:SetWidth(90)
	close:SetHeight(22)
	close:SetPoint("BOTTOMRIGHT", -18, 18)
	close:SetText("Close")
	close:SetScript("OnClick", function()
		saveWhisperPanel()
		whisperPanel:Hide()
	end)

	local reset = CreateFrame("Button", nil, whisperPanel, "UIPanelButtonTemplate")
	reset:SetWidth(110)
	reset:SetHeight(22)
	reset:SetPoint("BOTTOMLEFT", 18, 18)
	reset:SetText("Reset lines")
	reset:SetScript("OnClick", function()
		if AGF.ResetWhisperTemplates then
			AGF.ResetWhisperTemplates()
			AGF.ShowWhisperSetup()
		end
	end)

	table.insert(UISpecialFrames, "AGF_WhisperPanel")
	whisperPanel:Hide()
end

function AGF.ShowWhisperSetup()
	if not whisperPanel then
		createWhisperPanel()
	end
	for i = 1, #whisperPanel.boxes do
		local box = whisperPanel.boxes[i]
		box:SetText(AGF.WhisperTemplate(box.slot) or "")
		box:SetCursorPosition(0)
	end
	whisperPanel:Show()
end

-- Whisp Templates is a switch, so a second click closes the panel. Whatever
-- is typed is kept, the same as the Close button does.
function AGF.ToggleWhisperSetup()
	if whisperPanel and whisperPanel:IsShown() then
		saveWhisperPanel()
		whisperPanel:Hide()
		return
	end
	AGF.ShowWhisperSetup()
end

-- Filters panel -------------------------------------------------------------

local function closeFilterPanel()
	-- The activity dropdown is parented to UIParent, so it survives the
	-- panel unless it is closed by hand.
	CloseDropDownMenus()
	if filterPanel then filterPanel:Hide() end
	if clickCatcher then clickCatcher:Hide() end
end

local function makeCheck(parent, label, x, y, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetWidth(22)
	check:SetHeight(22)
	check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	text:SetText(label)
	check.label = text
	check:SetScript("OnClick", function(self)
		onClick(self:GetChecked() and true or false)
		AGF.Refresh()
		AGF.RefreshFilterPanel()
	end)
	return check
end

local function createFilterPanel()
	clickCatcher = CreateFrame("Frame", "AGF_ClickCatcher", UIParent)
	clickCatcher:SetAllPoints(UIParent)
	clickCatcher:SetFrameStrata("FULLSCREEN")
	clickCatcher:EnableMouse(true)
	clickCatcher:SetScript("OnMouseDown", closeFilterPanel)
	clickCatcher:Hide()

	filterPanel = CreateFrame("Frame", "AGF_FilterPanel", UIParent)
	filterPanel:SetWidth(210)
	filterPanel:SetHeight(438)
	filterPanel:SetFrameStrata("FULLSCREEN_DIALOG")
	filterPanel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24,
		insets = { left = 8, right = 8, top = 8, bottom = 8 },
	})
	filterPanel:EnableMouse(true)

	-- Solid backing so nothing underneath shows through the panel.
	local solid = filterPanel:CreateTexture(nil, "BORDER")
	solid:SetTexture(0.04, 0.04, 0.05, 1)
	solid:SetPoint("TOPLEFT", 7, -7)
	solid:SetPoint("BOTTOMRIGHT", -7, 7)

	filterPanel:Hide()

	local title = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Show and alert on")

	local p = filterPanel
	-- Every widget is built once here and placed by LayoutFilterPanel. A
	-- filter a section cannot use is hidden and leaves no gap behind.
	p.items = {}
	local function item(f, sections, height, indent, when)
		p.items[#p.items + 1] = { frame = f, sections = sections,
			h = height or 24, x = indent or 14, when = when }
		return f
	end
	local GROUPS = { PVE = true, PVP = true }
	local EVERY = { PVE = true, PVP = true, TRADE = true }
	local PVE_ONLY = { PVE = true }

	p.roleChecks = {}
	for i = 1, #AGF.ROLE_ORDER do
		local role = AGF.ROLE_ORDER[i]
		p.roleChecks[role] = makeCheck(p, AGF.RoleLabel(role), 14, 0, function(value)
			ACS_DB.filter.roles[role] = value
		end)
		item(p.roleChecks[role], GROUPS, 24, 14)
	end
	p.auraCheck = makeCheck(p, "Aura", 14, 0, function(value)
		ACS_DB.filter.needAura = value
	end)
	item(p.auraCheck, PVE_ONLY, 24, 14)
	p.loomsCheck = makeCheck(p, "Looms", 14, 0, function(value)
		ACS_DB.filter.needLooms = value
	end)
	item(p.loomsCheck, PVE_ONLY, 24, 14)

	p.intentLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.intentLabel:SetText("I am looking for")
	item(p.intentLabel, EVERY, 22, 16)

	p.intentChecks = {}
	local INTENTS = { "GROUP", "PLAYERS", "BOTH" }
	for i = 1, #INTENTS do
		local value = INTENTS[i]
		p.intentChecks[value] = makeCheck(p, value, 14, 0, function()
			AGF.SetFilterIntent(value)
			AGF.RefreshFilterPanel()
		end)
		item(p.intentChecks[value], EVERY, 22, 14)
	end

	p.levelLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.levelLabel:SetText("Level from / to, 0 = any")
	item(p.levelLabel, GROUPS, 20, 16)

	p.minLevel = CreateFrame("EditBox", "AGF_MinLevel", p, "InputBoxTemplate")
	p.minLevel:SetWidth(38)
	p.minLevel:SetHeight(18)
	p.minLevel:SetAutoFocus(false)
	p.minLevel:SetNumeric(true)
	p.minLevel:SetMaxLetters(2)
	item(p.minLevel, GROUPS, 28, 20)

	p.maxLevel = CreateFrame("EditBox", "AGF_MaxLevel", p, "InputBoxTemplate")
	p.maxLevel:SetWidth(38)
	p.maxLevel:SetHeight(18)
	p.maxLevel:SetPoint("LEFT", p.minLevel, "RIGHT", 14, 0)
	p.maxLevel:SetAutoFocus(false)
	p.maxLevel:SetNumeric(true)
	p.maxLevel:SetMaxLetters(2)
	p.maxLevelFollows = true

	local function commitLevels()
		ACS_DB.filter.minLevel = tonumber(p.minLevel:GetText()) or 0
		ACS_DB.filter.maxLevel = tonumber(p.maxLevel:GetText()) or 0
		AGF.Refresh()
	end
	p.minLevel:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	p.maxLevel:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	p.minLevel:SetScript("OnEditFocusLost", commitLevels)
	p.maxLevel:SetScript("OnEditFocusLost", commitLevels)

	p.wordLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.wordLabel:SetText("Message contains")
	item(p.wordLabel, EVERY, 20, 16)

	p.word = CreateFrame("EditBox", "AGF_WordFilter", p, "InputBoxTemplate")
	p.word:SetWidth(150)
	p.word:SetHeight(18)
	p.word:SetAutoFocus(false)
	p.word:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	p.word:SetScript("OnEditFocusLost", function(self)
		ACS_DB.filter.word = self:GetText() or ""
		AGF.Refresh()
	end)
	item(p.word, EVERY, 30, 20)

	p.kindLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.kindLabel:SetText("Activity")
	item(p.kindLabel, EVERY, 20, 16)

	-- One button that steps through the types present in this section.
	p.kindButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.kindButton:SetWidth(150)
	p.kindButton:SetHeight(20)
	p.kindButton:SetText("All activities")
	p.kindMenu = CreateFrame("Frame", "AGFKindMenu", UIParent, "UIDropDownMenuTemplate")
	p.kindMenu.displayMode = "MENU"

	local function pickKind(kind)
		ACS_DB.filter.kind = kind
		AGF.RefreshFilterPanel()
		AGF.Refresh()
	end

	local function initKindMenu(self, level)
		local current = (ACS_DB and ACS_DB.filter and ACS_DB.filter.kind) or "ALL"
		local info = UIDropDownMenu_CreateInfo()
		info.text = "All activities"
		info.checked = (current == "ALL")
		info.func = function() pickKind("ALL") end
		UIDropDownMenu_AddButton(info, level)
		local counts = (AGF.KindCounts and AGF.KindCounts(AGF.GetSection())) or {}
		for i = 1, #counts do
			local c = counts[i]
			local entry = UIDropDownMenu_CreateInfo()
			entry.text = c.label .. "  (" .. c.count .. ")"
			entry.checked = (current == c.kind)
			entry.func = function() pickKind(c.kind) end
			UIDropDownMenu_AddButton(entry, level)
		end
	end

	UIDropDownMenu_Initialize(p.kindMenu, initKindMenu, "MENU")

	p.kindButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p.kindButton:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			pickKind("ALL")
			return
		end
		ToggleDropDownMenu(1, nil, p.kindMenu, self, 0, 0)
	end)
	item(p.kindButton, EVERY, 30, 20)

	-- Class. Offered only where characters have one, so the panel on the
	-- classless realms looks exactly as it did before.
	p.classLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.classLabel:SetText("Class")
	item(p.classLabel, GROUPS, 20, 16, AGF.PackHasClasses)

	p.classButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.classButton:SetWidth(150)
	p.classButton:SetHeight(20)
	p.classButton:SetText("All classes")
	p.classMenu = CreateFrame("Frame", "AGFClassMenu", UIParent, "UIDropDownMenuTemplate")
	p.classMenu.displayMode = "MENU"

	local function pickClass(value)
		ACS_DB.filter.class = value
		AGF.RefreshFilterPanel()
		AGF.Refresh()
	end

	local function initClassMenu(self, level)
		local current = (ACS_DB and ACS_DB.filter and ACS_DB.filter.class) or "ALL"
		local info = UIDropDownMenu_CreateInfo()
		info.text = "All classes"
		info.checked = (current == "ALL")
		info.func = function() pickClass("ALL") end
		UIDropDownMenu_AddButton(info, level)
		local list = AGF.CLASSES or {}
		for i = 1, #list do
			local name = list[i]
			local entry = UIDropDownMenu_CreateInfo()
			entry.text = name
			entry.checked = (current == name)
			entry.func = function() pickClass(name) end
			UIDropDownMenu_AddButton(entry, level)
		end
	end

	UIDropDownMenu_Initialize(p.classMenu, initClassMenu, "MENU")

	p.classButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p.classButton:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			pickClass("ALL")
			return
		end
		ToggleDropDownMenu(1, nil, p.classMenu, self, 0, 0)
	end)
	item(p.classButton, GROUPS, 30, 20, AGF.PackHasClasses)

	p.resetButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.resetButton:SetWidth(80)
	p.resetButton:SetHeight(20)
	p.resetButton:SetText("Reset")
	p.resetButton:SetScript("OnClick", function()
		ACS_DB.filter.roles = { tank = false, heal = false, damage = false }
		ACS_DB.filter.needAura = false
		ACS_DB.filter.needLooms = false
		ACS_DB.filter.class = "ALL"
		ACS_DB.filter.minLevel = 0
		ACS_DB.filter.maxLevel = 0
		ACS_DB.filter.word = ""
		ACS_DB.filter.intent = "BOTH"
		ACS_DB.filter.kind = "ALL"
		AGF.RefreshFilterPanel()
		AGF.Refresh()
	end)

	local close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	close:SetWidth(80)
	close:SetHeight(20)
	close:SetPoint("LEFT", p.resetButton, "RIGHT", 8, 0)
	close:SetText("Close")
	close:SetScript("OnClick", closeFilterPanel)
end

-- Wording changes with the section, because a trade line has no group.
local INTENT_TEXT = {
	PVE = { title = "I am looking for", GROUP = "A group to join",
		PLAYERS = "Players to join me", BOTH = "Both" },
	PVP = { title = "I am looking for", GROUP = "A group to join",
		PLAYERS = "Players to join me", BOTH = "Both" },
	TRADE = { title = "I want to see", GROUP = "Players selling",
		PLAYERS = "Players buying", BOTH = "Both" },
}

-- Places the widgets the open section uses, top down, and sizes the panel to
-- what it placed. Nothing is left floating in a gap.
function AGF.LayoutFilterPanel()
	if not filterPanel or not filterPanel.items then
		return
	end
	local section = (AGF.GetSection and AGF.GetSection()) or "PVE"
	local y = -36
	for i = 1, #filterPanel.items do
		local it = filterPanel.items[i]
		if it.sections[section] and (not it.when or it.when()) then
			it.frame:ClearAllPoints()
			it.frame:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", it.x, y)
			it.frame:Show()
			y = y - it.h
		else
			it.frame:Hide()
		end
	end
	if filterPanel.maxLevel then
		if filterPanel.minLevel:IsShown() then
			filterPanel.maxLevel:Show()
		else
			filterPanel.maxLevel:Hide()
		end
	end
	y = y - 12
	filterPanel.resetButton:ClearAllPoints()
	filterPanel.resetButton:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 20, y)
	filterPanel:SetHeight(-y + 40)
end

function AGF.RefreshFilterPanel()
	if not filterPanel then
		return
	end
	local f = ACS_DB.filter
	local section = (AGF.GetSection and AGF.GetSection()) or "PVE"
	for i = 1, #AGF.ROLE_ORDER do
		local role = AGF.ROLE_ORDER[i]
		filterPanel.roleChecks[role]:SetChecked(f.roles[role] and true or false)
	end
	filterPanel.auraCheck:SetChecked(f.needAura and true or false)
	filterPanel.loomsCheck:SetChecked(f.needLooms and true or false)

	local words = INTENT_TEXT[section] or INTENT_TEXT.PVE
	filterPanel.intentLabel:SetText(words.title)
	local intent = f.intent or "BOTH"
	for value, check in pairs(filterPanel.intentChecks) do
		check:SetChecked(value == intent)
		if check.label then
			check.label:SetText(words[value] or value)
		end
	end

	filterPanel.minLevel:SetText((f.minLevel or 0) > 0 and tostring(f.minLevel) or "")
	filterPanel.maxLevel:SetText((f.maxLevel or 0) > 0 and tostring(f.maxLevel) or "")
	filterPanel.word:SetText(f.word or "")
	local kind = f.kind or "ALL"
	filterPanel.kindButton:SetText(kind == "ALL" and "All activities"
		or AGF.KindName(kind))
	local class = f.class or "ALL"
	filterPanel.classButton:SetText(class == "ALL" and "All classes" or class)
	AGF.LayoutFilterPanel()
end

local function toggleFilterPanel()
	if not filterPanel then
		createFilterPanel()
	end
	if filterPanel:IsShown() then
		closeFilterPanel()
		return
	end
	-- Always anchored to the button, never to the cursor.
	filterPanel:ClearAllPoints()
	filterPanel:SetPoint("TOPRIGHT", filtersButton, "BOTTOMRIGHT", 0, -4)
	AGF.RefreshFilterPanel()
	clickCatcher:Show()
	filterPanel:Show()
end

-- Style ---------------------------------------------------------------------

function AGF.ApplyStyle()
	if not frame then
		return
	end
	local s = skin()
	frame:SetBackdrop(s.backdrop)
	if s.bgColor then
		frame:SetBackdropColor(s.bgColor[1], s.bgColor[2], s.bgColor[3], s.bgColor[4])
	end
	if s.borderColor then
		frame:SetBackdropBorderColor(s.borderColor[1], s.borderColor[2], s.borderColor[3], s.borderColor[4])
	end
	titleText:SetTextColor(s.titleColor[1], s.titleColor[2], s.titleColor[3])
	for i = 1, #headers do
		headers[i].label:SetTextColor(s.headerColor[1], s.headerColor[2], s.headerColor[3])
	end
	layout()
	AGF.Refresh()
	if AGF.MiniApplyStyle then
		AGF.MiniApplyStyle()
	end
end

-- Window --------------------------------------------------------------------

local function savePosition()
	local x, y = frame:GetLeft(), frame:GetBottom()
	if x and y then
		ACS_DB.window.x = x
		ACS_DB.window.y = y
		ACS_DB.window.hasPos = true
	end
	ACS_DB.window.w = frame:GetWidth()
	ACS_DB.window.h = frame:GetHeight()
end

local function createWindow()
	frame = CreateFrame("Frame", "AGF_Window", UIParent)
	frame:SetWidth(ACS_DB.window.w or 780)
	frame:SetHeight(ACS_DB.window.h or 460)
	if ACS_DB.window.hasPos then
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ACS_DB.window.x, ACS_DB.window.y)
	else
		frame:SetPoint("CENTER")
	end
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetMinResize(640, 260)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(self, delta)
		scrollBar:SetValue(offset - (delta or 0) * 3)
	end)
	table.insert(UISpecialFrames, "AGF_Window")

	titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	edgeAnchor(function(m)
		titleText:ClearAllPoints()
		titleText:SetPoint("TOPLEFT", m * TITLE_INDENT, -16)
	end)
	titleText:SetText("Ascension Chat Scanner")

	subText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
	subText:SetText("Pack: "
		.. ((AGF.ActivePack and AGF.ActivePack().name) or "?"))

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -8, -8)
	close:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Close the window")
		GameTooltip:AddLine("Scanning carries on in the background.",
			1, 1, 1, true)
		GameTooltip:AddLine("/acs opens it again.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	close:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Minimize: hand over to the mini feed. The mini window carries the
	-- same pair of buttons and switches back.
	-- Built by Mini.lua so both windows carry the identical control.
	if AGF.MiniModeButton then
		local mini = AGF.MiniModeButton(frame, close, "down", "Mini feed",
			"Swap this window for a small feed of the alerted posts:"
				.. " name, W and message.",
			function()
				AGF.MiniMode(true)
			end)
		-- Pop out. Same feed, but this window stays where it is.
		AGF.MiniModeButton(frame, mini, "out", "Pop out the mini feed",
			"Opens the small feed beside this window instead of"
				.. " replacing it.",
			function()
				if AGF.MiniIsShown and AGF.MiniIsShown() then
					AGF.MiniHide()
				else
					AGF.MiniPopOut()
				end
			end)
	end

	-- Section row: PvE, PvP, Trade. Sits above the tab row.
	local sectionButtons = {}
	local sprev
	for i = 1, #AGF.SECTIONS do
		local s = AGF.SECTIONS[i]
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		-- Same size as a tab, so the two left rows read as one block.
		b:SetWidth(92)
		b:SetHeight(22)
		if sprev then
			b:SetPoint("LEFT", sprev, "RIGHT", 6, 0)
		else
			edgeAnchor(function(m)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", m, -46)
			end)
		end
		b:SetText(s.label)
		b:SetScript("OnClick", function()
			offset = 0
			AGF.SetSection(s.id)
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(s.label)
			GameTooltip:AddLine("Switches to the " .. s.label .. " tabs.",
				1, 1, 1, true)
			GameTooltip:AddLine("Each section keeps its own filters and"
				.. " columns.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		sectionButtons[s.id] = b
		sprev = b
	end

	-- Tabs. Every bucket gets a button; only the active section's show.
	for i = 1, #AGF.BUCKETS do
		local key = AGF.BUCKETS[i]
		local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		tab:SetWidth(92)
		tab:SetHeight(22)
		tab:SetText(AGF.BUCKET_LABEL[key] or key)
		tab:SetScript("OnClick", function()
			offset = 0
			AGF.SetMode(key)
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(AGF.BucketName and AGF.BucketName(key)
				or (AGF.BUCKET_LABEL[key] or key))
			GameTooltip:AddLine("The number is how many posts this tab"
				.. " holds.", 1, 1, 1, true)
			GameTooltip:AddLine("With a filter on, 4/29 means four of the"
				.. " twenty-nine pass it.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
		tabs[key] = tab
	end

	local function layoutTabs()
		local section = AGF.GetSection()
		local prev
		for i = 1, #AGF.BUCKETS do
			local key = AGF.BUCKETS[i]
			local tab = tabs[key]
			tab:ClearAllPoints()
			if AGF.BUCKET_SECTION[key] == section then
				if prev then
					tab:SetPoint("LEFT", prev, "RIGHT", 6, 0)
				else
					tab:SetPoint("TOPLEFT", AGF.EdgeMargin(), -72)
				end
				tab:Show()
				prev = tab
			else
				tab:Hide()
			end
		end
		for i = 1, #AGF.SECTIONS do
			local s = AGF.SECTIONS[i]
			local b = sectionButtons[s.id]
			if s.id == section then
				b:LockHighlight()
			else
				b:UnlockHighlight()
			end
		end
	end
	frame.layoutTabs = layoutTabs

	alertsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	alertsButton:SetWidth(96)
	alertsButton:SetHeight(22)
	alertsButton:SetText("Alerts: OFF")
	alertsButton:RegisterForClicks("LeftButtonUp")
	alertsButton:SetScript("OnClick", function(self)
		ACS_DB.alert.enabled = not ACS_DB.alert.enabled
		AGF.Print("Alerts " .. (ACS_DB.alert.enabled and "on" or "off"))
		AGF.Refresh()
	end)
	alertsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Alerts")
		GameTooltip:AddLine("Turns alerts on or off.", 1, 1, 1, true)
		GameTooltip:AddLine("Popup, sound and chat keep their own settings.",
			0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Right-click the minimap button to move the"
			.. " popup.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	alertsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Speaker. The popup is always shown when alerts are on. This only decides
	-- whether the popup is silent or comes with a sound.
	soundButton = CreateFrame("Button", nil, frame)
	soundButton:SetWidth(22)
	soundButton:SetHeight(22)
	soundButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	soundButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Bell_01")
	local speaker = soundButton:GetNormalTexture()
	if speaker then
		speaker:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		-- 87 percent of the button, centred. 22 x 0.87 is 19.1, so the inset is
		-- 1.4 on every side.
		speaker:ClearAllPoints()
		speaker:SetPoint("TOPLEFT", soundButton, "TOPLEFT", 1.4, -1.4)
		speaker:SetPoint("BOTTOMRIGHT", soundButton, "BOTTOMRIGHT", -1.4, 1.4)
	end
	-- VOICECHAT-ON is dropped. The arcs sit off centre inside their own file and
	-- fill only part of it, so they cannot be lined up with the bell without
	-- guessing at texture coordinates. Sound on is a bright bell instead.
	soundButton.cross = soundButton:CreateTexture(nil, "OVERLAY")
	soundButton.cross:SetTexture("Interface\\COMMON\\VOICECHAT-MUTED")
	soundButton.cross:SetPoint("TOPLEFT", soundButton, "TOPLEFT", 1.4, -1.4)
	soundButton.cross:SetPoint("BOTTOMRIGHT", soundButton, "BOTTOMRIGHT", -1.4, 1.4)
	soundButton.cross:Hide()

	-- One builder, used by OnEnter and again by OnClick, so the text follows the
	-- state without the cursor having to leave the button and come back.
	local function soundTooltip()
		GameTooltip:SetOwner(soundButton, "ANCHOR_LEFT")
		GameTooltip:AddLine("Alert sound")
		GameTooltip:AddLine(ACS_DB.alert.sound
			and "On. The popup comes with a sound."
			or "Muted. The popup appears silently.", 1, 1, 1)
		GameTooltip:AddLine("Click to " .. (ACS_DB.alert.sound and "mute it." or "unmute it."), 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end

	soundButton:SetScript("OnClick", function()
		ACS_DB.alert.sound = not ACS_DB.alert.sound
		AGF.Print("Alert sound " .. (ACS_DB.alert.sound and "on" or "off"))
		if ACS_DB.alert.sound then
			PlaySound("RaidWarning")
		end
		AGF.UpdateAlertButtons()
		if GetMouseFocus and GetMouseFocus() == soundButton then
			soundTooltip()
		end
	end)
	soundButton:SetScript("OnEnter", function()
		soundTooltip()
	end)
	soundButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	filtersButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	filtersButton:SetWidth(80)
	filtersButton:SetHeight(22)
	-- Room on the right for the speaker button.
	filtersButton:SetText("Filters")
	filtersButton:SetScript("OnClick", toggleFilterPanel)
	filtersButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Filters")
		GameTooltip:AddLine("Shows only the posts you want to see.",
			1, 1, 1, true)
		GameTooltip:AddLine("Each section keeps its own set, saved between"
			.. " sessions.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	filtersButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Scope. Sits above Alerts, next to the mute bell, because both decide how
	-- alerts behave rather than what the table shows.
	scopeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scopeButton:SetWidth(66)
	scopeButton:SetHeight(22)
	scopeButton:SetText("All")
	scopeButton:SetScript("OnClick", function()
		local a = ACS_DB.alert
		a.scope = ((a.scope or "ALL") == "ALL") and "SECTION" or "ALL"
		AGF.Print("Alert scope " .. (a.scope == "ALL" and "All" or "Section"))
		AGF.UpdateAlertButtons()
	end)
	scopeButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Alert scope")
		GameTooltip:AddLine("All: every section can alert, each judged by its"
			.. " own saved filters.", 1, 1, 1, true)
		GameTooltip:AddLine("Section: only the section you are looking at can"
			.. " alert.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	scopeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Thin box around mute, scope and alerts, so the three read as one control.
	alertBox = CreateFrame("Frame", nil, frame)
	alertBox:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
	alertBox:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	alertBox:SetBackdropColor(0, 0, 0, 0.25)
	alertBox:SetBackdropBorderColor(0.55, 0.45, 0.25, 0.9)

	viewBox = CreateFrame("Frame", nil, frame)
	viewBox:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
	viewBox:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	viewBox:SetBackdropColor(0, 0, 0, 0.25)
	viewBox:SetBackdropBorderColor(0.55, 0.45, 0.25, 0.9)

	AGF.LayoutAlertBar()

	-- Rows. Which columns this section draws.
	local function initRowsMenu(self, level)
		local allowed = AGF.SectionColumnSet()
		local info = UIDropDownMenu_CreateInfo()
		local sid = (AGF.GetSection and AGF.GetSection()) or "PVE"
		local sectionLabel = sid
		for i = 1, #AGF.SECTIONS do
			if AGF.SECTIONS[i].id == sid then
				sectionLabel = AGF.SECTIONS[i].label
			end
		end
		info.text = "Columns in " .. sectionLabel
		info.isTitle = true
		info.notCheckable = true
		UIDropDownMenu_AddButton(info, level)
		for i = 1, #COLS do
			local c = COLS[i]
			if allowed[c.key] and c.key ~= "name" and c.key ~= "message" then
				local key = c.key
				info = UIDropDownMenu_CreateInfo()
				info.text = c.label
				info.checked = not AGF.ColumnOff(key)
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.func = function()
					AGF.ToggleColumn(key)
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
		info = UIDropDownMenu_CreateInfo()
		info.text = "Show all"
		info.notCheckable = true
		info.func = function()
			AGF.ShowAllColumns()
		end
		UIDropDownMenu_AddButton(info, level)
	end

	rowsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	rowsButton:SetWidth(80)
	rowsButton:SetHeight(22)
	rowsButton:SetPoint("RIGHT", filtersButton, "LEFT", -6, 0)
	rowsButton:SetText("Rows")
	-- A click anywhere outside the open menu closes it. The stock dropdown only
	-- closes on a second click of the button, which felt stuck.
	rowsButton:SetScript("OnClick", function(self)
		if not rowsMenu then
			rowsMenu = CreateFrame("Frame", "ACSRowsMenu", UIParent,
				"UIDropDownMenuTemplate")
		end
		if not rowsCatcher then
			rowsCatcher = CreateFrame("Frame", nil, UIParent)
			rowsCatcher:SetAllPoints(UIParent)
			-- Below the dropdown itself, above everything else, so clicks inside
			-- the menu still reach the check buttons.
			rowsCatcher:SetFrameStrata("FULLSCREEN")
			rowsCatcher:EnableMouse(true)
			rowsCatcher:SetScript("OnMouseDown", function(catcher)
				catcher:Hide()
				CloseDropDownMenus()
			end)
			-- Also hide the catcher when the menu closes any other way, so it
			-- never swallows a click while no menu is open.
			rowsCatcher:SetScript("OnUpdate", function(catcher)
				if not (DropDownList1 and DropDownList1:IsShown()) then
					catcher:Hide()
				end
			end)
			rowsCatcher:Hide()
		end
		UIDropDownMenu_Initialize(rowsMenu, initRowsMenu, "MENU")
		ToggleDropDownMenu(1, nil, rowsMenu, self, 0, 0)
		if DropDownList1 and DropDownList1:IsShown() then
			rowsCatcher:Show()
		else
			rowsCatcher:Hide()
		end
	end)
	rowsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Rows")
		GameTooltip:AddLine("Chooses which columns the table shows.",
			1, 1, 1, true)
		GameTooltip:AddLine("Each section keeps its own choice, saved between"
			.. " sessions.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	rowsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Shared with the Rows menu: one full screen frame that closes whichever
	-- dropdown is open as soon as a click lands outside it.
	local function ensureMenuCatcher()
		if not rowsCatcher then
			rowsCatcher = CreateFrame("Frame", nil, UIParent)
			rowsCatcher:SetAllPoints(UIParent)
			rowsCatcher:SetFrameStrata("FULLSCREEN")
			rowsCatcher:EnableMouse(true)
			rowsCatcher:SetScript("OnMouseDown", function(catcher)
				catcher:Hide()
				CloseDropDownMenus()
			end)
			rowsCatcher:SetScript("OnUpdate", function(catcher)
				if not (DropDownList1 and DropDownList1:IsShown()) then
					catcher:Hide()
				end
			end)
			rowsCatcher:Hide()
		end
		return rowsCatcher
	end

	local function initSkinsMenu(self, level)
		local current = (ACS_DB and ACS_DB.style) or "vanilla"
		for i = 1, #SKIN_ORDER do
			local entry = SKIN_ORDER[i]
			local info = UIDropDownMenu_CreateInfo()
			info.text = entry.label
			info.checked = (current == entry.id)
			info.func = function()
				AGF.SetSkin(entry.id)
				CloseDropDownMenus()
				if rowsCatcher then rowsCatcher:Hide() end
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end

	skinsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	skinsButton:SetWidth(80)
	skinsButton:SetHeight(22)
	skinsButton:SetPoint("BOTTOMRIGHT", filtersButton, "TOPRIGHT", 0, 6)
	skinsButton:SetText("Skins")
	skinsButton:SetScript("OnClick", function(self)
		if not skinsMenu then
			skinsMenu = CreateFrame("Frame", "ACSSkinsMenu", UIParent,
				"UIDropDownMenuTemplate")
		end
		local catcher = ensureMenuCatcher()
		UIDropDownMenu_Initialize(skinsMenu, initSkinsMenu, "MENU")
		ToggleDropDownMenu(1, nil, skinsMenu, self, 0, 0)
		if DropDownList1 and DropDownList1:IsShown() then
			catcher:Show()
		else
			catcher:Hide()
		end
	end)
	skinsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Skins")
		GameTooltip:AddLine("Changes how both windows look.", 1, 1, 1, true)
		GameTooltip:AddLine("Saved between sessions.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	skinsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	AGF.LayoutViewBox()

	-- Header bar
	headerBar = CreateFrame("Frame", nil, frame)
	edgeAnchor(function(m)
		headerBar:ClearAllPoints()
		headerBar:SetPoint("TOPLEFT", m, -HEADER_TOP)
		headerBar:SetPoint("TOPRIGHT", -(m + SCROLL_W), -HEADER_TOP)
	end)
	headerBar:SetHeight(18)

	for i = 1, #COLS do
		local col = COLS[i]
		local button = CreateFrame("Button", nil, headerBar)
		button:SetHeight(18)
		local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("LEFT", 2, 0)
		label:SetText(col.label)
		button.label = label
		button:SetScript("OnClick", function()
			if ACS_DB.sortKey == col.key then
				ACS_DB.sortAsc = not ACS_DB.sortAsc
			else
				ACS_DB.sortKey = col.key
				ACS_DB.sortAsc = false
			end
			offset = 0
			AGF.Refresh()
		end)
		headers[i] = button
	end

	local headerLine = frame:CreateTexture(nil, "ARTWORK")
	headerLine:SetTexture(1, 1, 1, 0.25)
	headerLine:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -1)
	headerLine:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, -1)
	headerLine:SetHeight(1)

	-- Table area
	tableArea = CreateFrame("Frame", nil, frame)
	tableArea:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
	-- The bottom strip holds the Clear Tab and Whisp Templates buttons, the count and
	-- the hint line, so the table must stop well above the frame edge.
	edgeAnchor(function(m)
		tableArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(m + SCROLL_W), m + 30)
	end)
	tableArea:EnableMouseWheel(true)
	tableArea:SetScript("OnMouseWheel", function(self, delta)
		scrollBar:SetValue(offset - (delta or 0) * 3)
	end)

	for i = 1, #COLS do
		local sep = tableArea:CreateTexture(nil, "BACKGROUND")
		sep:SetTexture(1, 1, 1, 0.12)
		sep:Hide()
		seps[i] = sep
	end

	scrollBar = CreateFrame("Slider", "AGF_ScrollBar", frame, "UIPanelScrollBarTemplate")
	-- The stock template assumes its parent is a ScrollFrame and calls
	-- parent:SetVerticalScroll() on every value change. Our parent is a plain
	-- frame, so the inherited handler is replaced before any value is set.
	scrollBar:SetScript("OnValueChanged", function(self, value)
		local newOffset = math.floor((value or 0) + 0.5)
		if newOffset ~= offset then
			offset = newOffset
			if not self.updating then
				updateRows()
			end
		end
	end)
	edgeAnchor(function(m)
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD + 2, -SCROLL_TOP)
		scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD + 2, SCROLL_BOTTOM)
	end)
	scrollBar:SetWidth(16)
	scrollBar:SetMinMaxValues(0, 0)
	scrollBar:SetValueStep(1)
	scrollBar:SetValue(0)

	-- Rows
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, tableArea)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", tableArea, "TOPLEFT", 0, -(i - 1) * ROW_H)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints(row)
		row.bg:SetTexture(1, 1, 1, 0.05)
		row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
		row.highlight:SetAllPoints(row)
		row.highlight:SetTexture(1, 1, 1, 0.14)
		row.cells = {}
		for j = 1, #COLS do
			local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cell:SetHeight(ROW_H)
			cell:SetJustifyH("LEFT")
			cell:SetJustifyV("MIDDLE")
			cell:SetNonSpaceWrap(false)
			row.cells[COLS[j].key] = cell
		end
		row:SetScript("OnClick", onRowClick)
		row:SetScript("OnEnter", function(self)
			if not self.data then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:AddLine(self.data.name or "?", 1, 0.82, 0)
			GameTooltip:AddLine(self.data.message or self.data.rawMessage or "(no message stored)", 1, 1, 1, true)
			GameTooltip:AddLine(" ")
			if self.data.size then
				GameTooltip:AddLine("Group size: " .. self.data.size .. " players", 0.6, 0.6, 0.6)
			end
			if self.data.wanted then
				GameTooltip:AddLine("Asking for: " .. self.data.wanted, 0.6, 0.6, 0.6)
			end
			GameTooltip:AddLine("Channel: " .. tostring(self.data.channel or "?"), 0.6, 0.6, 0.6)
			local preview = AGF.BuildWhisper and AGF.BuildWhisper(self.data, AGF.GetMode())
			if preview and preview ~= "" then
				GameTooltip:AddLine("W sends: " .. preview, 0.45, 0.7, 1, true)
			else
				GameTooltip:AddLine("No whisper line for this tab yet, set one with the Whisp Templates button", 0.6, 0.6, 0.6, true)
			end
			if self.data.whispered then
				GameTooltip:AddLine("Whispered at " .. date("%H:%M:%S", self.data.whispered), 0.6, 0.6, 0.6)
			end
			GameTooltip:AddLine("Left-click a value to edit it, right-click the row for actions", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end

	-- Bottom bar
	clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearButton:SetWidth(110)
	clearButton:SetHeight(20)
	edgeAnchor(function(m)
		clearButton:ClearAllPoints()
		clearButton:SetPoint("BOTTOMLEFT", m, m - 4)
	end)
	clearButton:SetText("Clear Tab")
	clearButton:SetScript("OnClick", function()
		AGF.ClearBucket(AGF.GetMode())
	end)
	clearButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Clear Tab")
		GameTooltip:AddLine("Empties the tab you are looking at.", 1, 1, 1, true)
		GameTooltip:AddLine("Every other tab keeps its posts.",
			0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	clearButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Clear all wipes every tab in every section, so it asks first.
	if not StaticPopupDialogs["ACS_CLEAR_ALL"] then
		StaticPopupDialogs["ACS_CLEAR_ALL"] = {
			text = "Clear every tab in PvE, PvP and Trade?",
			button1 = YES,
			button2 = NO,
			OnAccept = function()
				-- Empty the tables directly, then repaint once.
				for i = 1, #AGF.BUCKETS do
					ACS_DB.rows[AGF.BUCKETS[i]] = {}
				end
				if AGF.ForgetAllNames then
					AGF.ForgetAllNames()
				end
				AGF.Refresh()
				AGF.Print("All tabs cleared")
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
	end

	clearAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearAllButton:SetWidth(90)
	clearAllButton:SetHeight(20)
	clearAllButton:SetPoint("LEFT", clearButton, "RIGHT", 6, 0)
	clearAllButton:SetText("Clear All")
	clearAllButton:SetScript("OnClick", function()
		StaticPopup_Show("ACS_CLEAR_ALL")
	end)
	clearAllButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Clear All")
		GameTooltip:AddLine("Empties every tab in all three sections.",
			1, 1, 1, true)
		GameTooltip:AddLine("Filters, columns and skins are kept. It asks"
			.. " first.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	clearAllButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	whisperButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	whisperButton:SetWidth(116)
	whisperButton:SetHeight(20)
	whisperButton:SetPoint("LEFT", clearAllButton, "RIGHT", 6, 0)
	whisperButton:SetText("Whisp Templates")
	whisperButton:SetScript("OnClick", function()
		AGF.ToggleWhisperSetup()
	end)
	whisperButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Whisp Templates")
		GameTooltip:AddLine("Six whisper lines, with the details of the post"
			.. " filled in as you send.", 1, 1, 1, true)
		GameTooltip:AddLine("Each Unsure tab shares the line of its own"
			.. " section.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	whisperButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	countText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	countText:SetPoint("BOTTOMLEFT", whisperButton, "BOTTOMRIGHT", 10, 5)
	countText:SetText("")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	edgeAnchor(function(m)
		hint:ClearAllPoints()
		hint:SetPoint("BOTTOMRIGHT", -(m + 16), m)
	end)
	hint:SetText("Left click a value to edit - W sends your whisper - right click a row for actions")
	hint:SetJustifyH("RIGHT")
	frame.hint = hint

	resizeGrip = CreateFrame("Button", nil, frame)
	resizeGrip:SetWidth(16)
	resizeGrip:SetHeight(16)
	resizeGrip:SetPoint("BOTTOMRIGHT", -6, 6)
	resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeGrip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	resizeGrip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		savePosition()
		layout()
		AGF.Refresh()
	end)

	frame:SetScript("OnSizeChanged", function()
		layout()
		updateHint()
		updateRows()
	end)
	frame:SetScript("OnShow", function()
		if ACS_DB then ACS_DB.window.shown = true end
		layout()
		updateHint()
		AGF.Refresh()
	end)
	frame:SetScript("OnHide", function()
		if ACS_DB then ACS_DB.window.shown = false end
		closeFilterPanel()
	end)

	AGF.ApplyStyle()
	frame:Hide()
end

-- The full window on its own, used by mini mode when it hands back.
function AGF.ShowMain()
	if not frame then
		return
	end
	frame:Show()
	AGF.Refresh()
end

function AGF.HideMain()
	if frame then
		frame:Hide()
	end
end

-- /acs always toggles the main window. The mini feed is a separate layer
-- controlled by /acs mini and the switch button; it stays open independently.
function AGF.Show()
	AGF.ShowMain()
end

function AGF.Toggle()
	if not frame then
		return
	end
	if frame:IsShown() then
		frame:Hide()
	else
		AGF.ShowMain()
	end
end

-- Minimap button ------------------------------------------------------------

local minimapButton

local function placeMinimapButton()
	local angle = math.rad(ACS_DB.minimap.angle or 205)
	local x = 80 * math.cos(angle)
	local y = 80 * math.sin(angle)
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function createMinimapButton()
	minimapButton = CreateFrame("Button", "AGF_MinimapButton", Minimap)
	minimapButton:SetWidth(31)
	minimapButton:SetHeight(31)
	minimapButton:SetFrameStrata("MEDIUM")
	minimapButton:SetMovable(true)

	local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", 0, 1)

	local border = minimapButton:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT")

	minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapButton:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			-- Locks or unlocks the alert popup for dragging.
			if AGF.ToggleAlertLock then
				AGF.ToggleAlertLock()
			end
		else
			AGF.Toggle()
		end
	end)
	minimapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Ascension Chat Scanner")
		GameTooltip:AddLine("Left-click opens or closes the window.",
			1, 1, 1, true)
		GameTooltip:AddLine("Right-click locks or unlocks the alert popup"
			.. " for dragging.", 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Drag to move this button around the minimap.",
			0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	minimapButton:RegisterForDrag("LeftButton")
	minimapButton:SetScript("OnDragStart", function(self)
		self.dragging = true
	end)
	minimapButton:SetScript("OnDragStop", function(self)
		self.dragging = nil
	end)
	minimapButton:SetScript("OnUpdate", function(self)
		if not self.dragging then
			return
		end
		local mx, my = Minimap:GetCenter()
		local scale = UIParent:GetScale()
		local cx, cy = GetCursorPosition()
		cx, cy = cx / scale, cy / scale
		ACS_DB.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
		placeMinimapButton()
	end)
	placeMinimapButton()
end

function AGF.UpdateMinimapButton()
	if not minimapButton then
		return
	end
	if ACS_DB.minimap.show then
		placeMinimapButton()
		minimapButton:Show()
	else
		minimapButton:Hide()
	end
end

-- Bootstrap -----------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	-- createWindow hides the frame, which fires OnHide and clears the flag,
	-- so read the saved state first.
	local wasShown = ACS_DB and ACS_DB.window.shown
	local wasMini = ACS_DB and ACS_DB.mini and ACS_DB.mini.shown
	local ok, err = pcall(createWindow)
	if not ok then
		AGF.Print("|cffff5555interface error|r " .. tostring(err))
		return
	end
	pcall(createMinimapButton)
	AGF.UpdateMinimapButton()
	if wasShown then
		AGF.Show()
	end
	if wasMini and AGF.MiniShow then
		AGF.MiniShow()
	end
end)
