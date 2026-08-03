-- Ascension Chat Scanner
-- Mini.lua - the mini feed.
--
-- A small window holding nothing but the posts that matched the alert rules,
-- whether or not alerts are switched on: name, W, message. One click from the
-- whisper, no tabs, no filters. The feed and the alert popup are fed by the
-- same decision, AGF.AlertMatch, so an alert can never arrive without its row
-- showing up here.

AGF = AGF or {}

local FEED_MAX = 100
local ROW_H = 16
local PAD = 10
local TOP = 26
-- The name column measures itself against the names on screen and stays
-- between these two. A fixed column wasted half the window on short names.
local NAME_MIN = 40
local NAME_MAX = 110
local NAME_GAP = 6
local WSP_W = 16
local STRIPE_W = 3
-- Where a feed that has never been dragged opens: up and to the right of the
-- middle of the screen, clear of the main window.
local OPEN_X, OPEN_Y = 300, 150
local MIN_W, MIN_H = 240, 90
local MAX_W, MAX_H = 700, 700

-- Newest first. Each entry keeps its own copy of what the window draws plus a
-- reference to the live row, so a whisper marks the real row as contacted.
local feed = {}
local frame, emptyText, ruler
local rowFrames = {}
local offset = 0
local nameW = NAME_MIN

local SECTION_COLOR = {
	PVE = { 0.45, 0.85, 0.45 },
	PVP = { 0.95, 0.45, 0.45 },
	TRADE = { 1, 0.82, 0.2 },
}

local STRIPE_LEGEND = { "PVE", "PVP", "TRADE" }

local SECTION_NAME = {
	PVE = "PvE",
	PVP = "PvP",
	TRADE = "Trade",
}

local function db()
	if not ACS_DB then
		return nil
	end
	ACS_DB.mini = ACS_DB.mini or {}
	return ACS_DB.mini
end

local function skin()
	if AGF.CurrentSkin then
		return AGF.CurrentSkin()
	end
	return nil
end

-- Feed ----------------------------------------------------------------------

-- Called from the ingest path for every post that matched the alert rules,
-- whether or not the popup and the sound are switched on.
-- The main table drops a row once it expires, so the feed must not keep
-- offering a post that has expired.
local function pruneFeed()
	local limit = (ACS_DB and ACS_DB.expiry) or 900
	local now = time()
	for i = #feed, 1, -1 do
		if now - (feed[i].time or now) > limit then
			table.remove(feed, i)
		end
	end
end

function AGF.MiniPush(row, bucket)
	if not row or not row.name then
		return
	end
	local section = (AGF.BUCKET_SECTION and AGF.BUCKET_SECTION[bucket]) or "PVE"
	pruneFeed()
	table.insert(feed, 1, {
		name = row.name,
		message = row.message or "",
		bucket = bucket,
		section = section,
		time = row.time or time(),
		row = row,
	})
	while #feed > FEED_MAX do
		table.remove(feed)
	end
	if frame and frame:IsShown() then
		AGF.MiniRefresh()
	end
end

function AGF.MiniClear()
	for i = #feed, 1, -1 do
		feed[i] = nil
	end
	offset = 0
	if frame then
		AGF.MiniRefresh()
	end
end

function AGF.MiniCount()
	return #feed
end

-- Window --------------------------------------------------------------------

local function visibleCount()
	if not frame then
		return 0
	end
	local h = frame:GetHeight() - TOP - PAD
	local n = math.floor(h / ROW_H)
	if n < 1 then
		n = 1
	end
	return n
end

-- What the W button would send, used by the tooltip.
local function whisperPreview(entry)
	if not AGF.BuildWhisper then
		return nil
	end
	local ok, text = pcall(AGF.BuildWhisper, entry.row or entry, entry.bucket)
	if ok and type(text) == "string" and text ~= "" then
		if string.len(text) > 250 then
			text = string.sub(text, 1, 250)
		end
		return text
	end
	return nil
end

local function onRowClick(self, button)
	local entry = self.entry
	if not entry then
		return
	end
	if button == "RightButton" then
		if AGF.OpenPlayerMenu then
			AGF.OpenPlayerMenu(entry.bucket, entry.name, self)
		end
		return
	end
	local x = GetCursorPosition() / (self:GetEffectiveScale() or 1)
	local rel = x - self:GetLeft()
	local wspLeft = STRIPE_W + nameW + NAME_GAP
	if rel >= wspLeft and rel < wspLeft + WSP_W then
		if AGF.SendWhisper and AGF.SendWhisper(entry.row or entry, entry.bucket) then
			entry.whispered = true
		end
		AGF.MiniRefresh()
		return
	end
	if rel < wspLeft then
		ChatFrame_SendTell(entry.name)
	end
end

local function onRowEnter(self)
	local entry = self.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
	GameTooltip:AddLine(entry.name, 1, 0.82, 0)
	GameTooltip:AddLine(entry.message or "", 1, 1, 1, true)

	local label = (AGF.BUCKET_LABEL and AGF.BUCKET_LABEL[entry.bucket]) or "Other"
	local section = SECTION_NAME[entry.section] or "Other"
	local c = SECTION_COLOR[entry.section] or SECTION_COLOR.PVE
	GameTooltip:AddLine(section .. " " .. label, c[1], c[2], c[3])

	-- Show the whisper before it is sent, not after.
	local preview = whisperPreview(entry)
	if preview then
		GameTooltip:AddLine("W sends: " .. preview, 0.7, 0.7, 0.7, true)
	else
		GameTooltip:AddLine("No whisper line for this tab yet, set one with"
			.. " the Whisp Templates button", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
	self.hover:Show()
end

local function onRowLeave(self)
	GameTooltip:Hide()
	self.hover:Hide()
end

-- Name column width, and everything to the right of it, in one place.
local function placeCells(r)
	r.name:SetWidth(nameW)
	r.wsp:ClearAllPoints()
	r.wsp:SetPoint("LEFT", r, "LEFT", STRIPE_W + nameW + NAME_GAP, 0)
	r.message:ClearAllPoints()
	r.message:SetPoint("LEFT", r, "LEFT",
		STRIPE_W + nameW + NAME_GAP + WSP_W + 4, 0)
	r.message:SetPoint("RIGHT", r, "RIGHT", -2, 0)
end

local function makeRow(index)
	local r = CreateFrame("Button", nil, frame)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + (index - 1) * ROW_H))
	r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TOP + (index - 1) * ROW_H))
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	r.hover = r:CreateTexture(nil, "BACKGROUND")
	r.hover:SetAllPoints()
	r.hover:SetTexture(1, 1, 1, 0.10)
	r.hover:Hide()

	-- Which section a line came from, without spending a column on it.
	r.stripe = r:CreateTexture(nil, "ARTWORK")
	r.stripe:SetWidth(STRIPE_W)
	r.stripe:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
	r.stripe:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 1)

	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("LEFT", r, "LEFT", STRIPE_W + 3, 0)
	r.name:SetJustifyH("LEFT")

	r.wsp = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.wsp:SetWidth(WSP_W)
	r.wsp:SetJustifyH("CENTER")
	r.wsp:SetText("W")

	r.message = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.message:SetJustifyH("LEFT")

	placeCells(r)

	r:SetScript("OnClick", onRowClick)
	r:SetScript("OnEnter", onRowEnter)
	r:SetScript("OnLeave", onRowLeave)
	return r
end

-- Measure the names actually on screen and give the column exactly that much.
local function measureNames(first, last)
	local widest = 0
	for i = first, last do
		local entry = feed[i]
		if entry then
			ruler:SetText(entry.name)
			local w = ruler:GetStringWidth()
			if w > widest then
				widest = w
			end
		end
	end
	widest = math.floor(widest + 2)
	if widest < NAME_MIN then
		widest = NAME_MIN
	end
	if widest > NAME_MAX then
		widest = NAME_MAX
	end
	return widest
end

function AGF.MiniRefresh()
	if not frame then
		return
	end
	pruneFeed()
	local shown = visibleCount()
	if offset > #feed - shown then
		offset = #feed - shown
	end
	if offset < 0 then
		offset = 0
	end

	nameW = measureNames(1 + offset, shown + offset)

	for i = 1, shown do
		local r = rowFrames[i]
		if not r then
			r = makeRow(i)
			rowFrames[i] = r
		end
		placeCells(r)
		local entry = feed[i + offset]
		if entry then
			r.entry = entry
			local c = SECTION_COLOR[entry.section] or SECTION_COLOR.PVE
			r.stripe:SetTexture(c[1], c[2], c[3], 0.9)
			r.stripe:Show()
			-- A line you already answered goes grey, so you do not write twice.
			local done = entry.whispered or (entry.row and entry.row.whispered)
			if done then
				r.name:SetTextColor(0.5, 0.5, 0.5)
				r.message:SetTextColor(0.45, 0.45, 0.45)
				r.wsp:SetTextColor(0.45, 0.45, 0.45)
			else
				r.name:SetTextColor(1, 0.82, 0)
				r.message:SetTextColor(1, 1, 1)
				r.wsp:SetTextColor(0.4, 0.9, 0.4)
			end
			r.name:SetText(entry.name)
			r.wsp:SetText("W")
			r.message:SetText(entry.message)
			r:Show()
		else
			r.entry = nil
			r:Hide()
		end
	end
	for i = shown + 1, #rowFrames do
		rowFrames[i].entry = nil
		rowFrames[i]:Hide()
	end
	if #feed == 0 then
		emptyText:Show()
	else
		emptyText:Hide()
	end
end

local function savePlacement()
	local m = db()
	if not m or not frame then
		return
	end
	local point, _, rel, x, y = frame:GetPoint()
	m.point = point
	m.rel = rel
	m.x = x
	m.y = y
	m.w = frame:GetWidth()
	m.h = frame:GetHeight()
	m.hasPos = true
end

local function placeFrame()
	local m = db() or {}
	frame:SetWidth(m.w or 320)
	frame:SetHeight(m.h or 200)
	frame:ClearAllPoints()
	if m.hasPos and m.point then
		frame:SetPoint(m.point, UIParent, m.rel or m.point, m.x or 0, m.y or 0)
	else
		-- A feed that has never been dragged opens up and to the right of the
		-- middle, clear of the table. Reset is a different promise and writes a
		-- placement of its own.
		frame:SetPoint("CENTER", UIParent, "CENTER", OPEN_X, OPEN_Y)
	end
end

-- /acs mini reset. A feed dragged to the edge, or left behind by a change of
-- resolution or ui scale, comes back to the middle of the screen. The
-- placement is saved, so the feed is still in the middle at the next login.
function AGF.MiniResetPosition()
	local m = db()
	if m then
		m.hasPos = true
		m.point = "CENTER"
		m.rel = "CENTER"
		m.x = 0
		m.y = 0
	end
	if frame then
		placeFrame()
	end
	AGF.Print("Mini feed moved back to the centre")
end

-- The mode button. Blizzard's smaller and bigger icons, in a frame the
-- same size as UIPanelCloseButton so the pair reads as one control.
-- UI-Panel-MinimizeButton is not used: this client reskins it to a cross.
local BTN = 32
-- The mini window carries the same pair, a little smaller.
local MINI_BTN = 26

-- dir is down for minimise, up for the full window, and out for the pop out,
-- which is the minimise icon turned over so the pair reads as opposites.
local function modeButton(parent, anchor, dir, tipTitle, tipText, onClick, size)
	local b = CreateFrame("Button", nil, parent)
	local side = size or BTN
	b:SetWidth(side)
	b:SetHeight(side)
	b:SetPoint("RIGHT", anchor, "LEFT", 6, 0)
	local art = (dir == "up") and "UI-Panel-BiggerButton"
		or "UI-Panel-SmallerButton"
	b:SetNormalTexture("Interface\\Buttons\\" .. art .. "-Up")
	b:SetPushedTexture("Interface\\Buttons\\" .. art .. "-Down")
	if dir == "out" then
		local up, down = b:GetNormalTexture(), b:GetPushedTexture()
		if up then up:SetTexCoord(1, 0, 1, 0) end
		if down then down:SetTexCoord(1, 0, 1, 0) end
	end
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(tipTitle)
		GameTooltip:AddLine(tipText, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return b
end

AGF.MiniModeButton = modeButton

local function build()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "ACS_MiniWindow", UIParent)
	-- Clamped, so a drag cannot leave the feed with nothing but a sliver on
	-- screen, and in UISpecialFrames so Escape closes it like every other
	-- window the addon opens.
	frame:SetClampedToScreen(true)
	table.insert(UISpecialFrames, "ACS_MiniWindow")
	-- The frame owns the saved flag. Escape hides it without calling MiniHide,
	-- so writing the flag anywhere else would leave the feed reopening itself
	-- at the next login.
	frame:SetScript("OnShow", function()
		local m = db()
		if m then
			m.shown = true
		end
	end)
	frame:SetScript("OnHide", function()
		local m = db()
		if m then
			m.shown = false
		end
	end)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetMinResize(MIN_W, MIN_H)
	frame:SetMaxResize(MAX_W, MAX_H)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePlacement()
	end)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(self, delta)
		offset = offset - delta
		AGF.MiniRefresh()
	end)

	-- The top strip is the drag handle and the only place with room for
	-- an explanation, so the colour legend lives in its tooltip.
	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(TOP)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	-- Stop short of the close and mode buttons, they own that corner.
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(MINI_BTN * 2 + 8), 0)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePlacement()
	end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(frame, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, 0)
		GameTooltip:AddLine("Mini feed")
		GameTooltip:AddLine("Everything matching your alert filters, newest"
			.. " first.", 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Stripe colours", 0.7, 0.7, 0.7)
		for i = 1, #STRIPE_LEGEND do
			local id = STRIPE_LEGEND[i]
			local c = SECTION_COLOR[id]
			GameTooltip:AddLine(SECTION_NAME[id], c[1], c[2], c[3])
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click a name to open a whisper.", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Left-click W to send your line.", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Right-click a row for the full menu.",
			0.7, 0.7, 0.7)
		GameTooltip:AddLine("Drag this strip to move the window.",
			0.7, 0.7, 0.7)
		GameTooltip:AddLine("Drag the corner to resize.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Off screen, only ever used to measure text.
	ruler = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ruler:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 200)
	ruler:Hide()

	-- Same pair as the big window: close on the right, mode switch next to it.
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetWidth(MINI_BTN)
	close:SetHeight(MINI_BTN)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Close the mini feed")
		GameTooltip:AddLine("Closes the feed. A main window already on screen"
			.. " stays open.", 1, 1, 1, true)
		GameTooltip:AddLine("/acs mini brings the feed back, /acs opens the"
			.. " table.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	close:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	close:SetScript("OnClick", function()
		AGF.MiniHide()
	end)

	modeButton(frame, close, "up", "Full window",
		"Back to the table with sections, filters and rows.",
		function()
			AGF.MiniMode(false)
		end, MINI_BTN)

	-- Name strip, level with the buttons. The addon name is dimmed because
	-- the window it belongs to is the one thing already obvious.
	local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	caption:SetPoint("LEFT", frame, "TOPLEFT", PAD + 4, -(4 + MINI_BTN / 2))
	caption:SetText("|cffffffffMini feed|r |cff808080Ascension Chat Scanner|r")

	emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + STRIPE_W + 3, -TOP)
	emptyText:SetText("Waiting for alerts")

	local grip = CreateFrame("Button", nil, frame)
	grip:SetWidth(16)
	grip:SetHeight(16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		savePlacement()
		AGF.MiniRefresh()
	end)

	frame:SetScript("OnSizeChanged", function()
		AGF.MiniRefresh()
	end)

	placeFrame()
	AGF.MiniApplyStyle()
	frame:Hide()
end

function AGF.MiniApplyStyle()
	if not frame then
		return
	end
	local s = skin()
	if s and s.backdrop then
		frame:SetBackdrop(s.backdrop)
		if s.bgColor then
			frame:SetBackdropColor(s.bgColor[1], s.bgColor[2], s.bgColor[3],
				s.bgColor[4] or 1)
		end
		if s.borderColor then
			frame:SetBackdropBorderColor(s.borderColor[1], s.borderColor[2],
				s.borderColor[3], s.borderColor[4] or 1)
		end
	else
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
end

-- Mode ----------------------------------------------------------------------

function AGF.MiniIsMode()
	local m = db()
	return (m and m.mode) and true or false
end

function AGF.MiniIsShown()
	return frame and frame:IsShown() and true or false
end

function AGF.MiniShow()
	build()
	frame:Show()
	AGF.MiniRefresh()
end

function AGF.MiniHide()
	if frame then
		frame:Hide()
	end
end

-- true switches the small window on and hides the big one, false does the
-- reverse. mini.mode records the last choice for the buttons; /acs always
-- opens the main window, so a remembered mode can never strand the player.
function AGF.MiniMode(on)
	local m = db()
	if m then
		m.mode = on and true or false
	end
	if on then
		if AGF.HideMain then
			AGF.HideMain()
		end
		AGF.MiniShow()
	else
		AGF.MiniHide()
		if AGF.ShowMain then
			AGF.ShowMain()
		end
	end
end

-- Pop out. The feed is a layer over the main window, not a replacement for
-- it, so mini.mode stays with the swap button and is not touched here.
function AGF.MiniPopOut()
	AGF.MiniShow()
end

-- /acs mini and the pop out button follow what is on screen rather than the
-- stored flag, and neither one closes the table.
function AGF.MiniToggleMode()
	if AGF.MiniIsShown() then
		AGF.MiniHide()
	else
		AGF.MiniPopOut()
	end
end

-- Times age, so the list is swept once a second while it is on screen.
local ticker = CreateFrame("Frame", "ACS_MiniTicker", UIParent)
local since = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	if not frame or not frame:IsShown() then
		return
	end
	since = since + (elapsed or 0)
	if since < 1 then
		return
	end
	since = 0
	AGF.MiniRefresh()
end)
