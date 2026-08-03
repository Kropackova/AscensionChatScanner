-- Ascension Chat Scanner
-- Alerts.lua - on screen notification. The frame is sized to the text, it
-- appears in place with a very short fade, holds, then fades out. Recruit
-- posts are rare, so those alerts hold two and a half times longer.
--
-- The frame can be unlocked and dragged. The position is stored per character
-- as the centre point of the frame, so the frame still grows around that point
-- when a long message arrives.

AGF = AGF or {}

local QUEUE_MAX = 5
local IN_TIME = 0.10
local HOLD_TIME = 2.0
local RARE_MULT = 2.5
local FADE_TIME = 0.6

-- Frame sizing bounds.
local PAD_X = 30
local PAD_TOP = 11
local PAD_BOTTOM = 11
local GAP = 4
local MIN_W = 220
local MAX_W = 520

local queue = {}
local popup, driver
local phase, timer, holdFor = nil, 0, HOLD_TIME
local unlocked = false

-- One colour scale for the whole addon: the section, never the intent. These
-- are the mini feed stripe colours written as chat escapes.
local SECTION_COLOR = {
	PVE = "|cff73d973",
	PVP = "|cfff27373",
	TRADE = "|cffffd133",
}

-- Saved position. Built on demand, because the frame may never be shown.
local function posDB()
	ACS_DB = ACS_DB or {}
	ACS_DB.alert = ACS_DB.alert or {}
	if type(ACS_DB.alert.pos) ~= "table" then
		ACS_DB.alert.pos = { hasPos = false, x = 0, y = 0 }
	end
	return ACS_DB.alert.pos
end

local function savePosition()
	if not popup then
		return
	end
	local cx, cy = popup:GetCenter()
	if not cx or not cy then
		return
	end
	local p = posDB()
	p.x = cx
	p.y = cy
	p.hasPos = true
end

local function createPopup()
	popup = CreateFrame("Frame", "AGF_Alert", UIParent)
	popup:SetWidth(MIN_W)
	popup:SetHeight(60)
	popup:SetFrameStrata("HIGH")
	popup:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 20,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	-- Mouse is off while locked, so a real alert never eats a click.
	popup:EnableMouse(false)
	popup:SetMovable(true)
	popup:RegisterForDrag("LeftButton")
	popup:SetScript("OnDragStart", function(self)
		if unlocked then
			self:StartMoving()
		end
	end)
	popup:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)

	-- Blue wash, shown only while the frame is unlocked, so it is obvious at a
	-- glance that this frame can be dragged.
	popup.moveTint = popup:CreateTexture(nil, "BORDER")
	popup.moveTint:SetTexture(0.15, 0.45, 0.95, 0.35)
	popup.moveTint:SetPoint("TOPLEFT", 6, -6)
	popup.moveTint:SetPoint("BOTTOMRIGHT", -6, 6)
	popup.moveTint:Hide()

	popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popup.title:SetPoint("TOP", popup, "TOP", 0, -PAD_TOP)
	popup.title:SetJustifyH("CENTER")

	popup.body = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	popup.body:SetPoint("TOP", popup.title, "BOTTOM", 0, -GAP)
	popup.body:SetJustifyH("CENTER")

	popup:Hide()
end

-- Saved spot if there is one, otherwise middle of the screen vertically, two
-- thirds across. The frame grows around that point, it never moves once shown.
local function placePopup()
	local p = posDB()
	popup:ClearAllPoints()
	if p.hasPos then
		popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
		return
	end
	local w = UIParent:GetWidth() or 1024
	local h = UIParent:GetHeight() or 768
	popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", w * 0.66, h * 0.5)
end

-- Measure both lines and shrink the frame to fit them.
local function fitPopup()
	-- Unwrapped measurement first.
	popup.title:SetWidth(0)
	popup.body:SetWidth(0)
	local natural = math.max(popup.title:GetStringWidth() or 0, popup.body:GetStringWidth() or 0)
	local width = natural + PAD_X * 2
	if width < MIN_W then
		width = MIN_W
	end
	if width > MAX_W then
		width = MAX_W
	end
	local inner = width - PAD_X * 2
	popup.title:SetWidth(inner)
	popup.body:SetWidth(inner)

	local titleH = popup.title:GetStringHeight() or 14
	local bodyH = popup.body:GetStringHeight() or 12
	local height = PAD_TOP + titleH + GAP + bodyH + PAD_BOTTOM
	if height < 52 then
		height = 52
	end
	popup:SetWidth(width)
	popup:SetHeight(height)
end

local function startNext()
	local item = table.remove(queue, 1)
	if not item then
		phase = nil
		popup:Hide()
		return
	end
	local sectionId = AGF.BUCKET_SECTION and AGF.BUCKET_SECTION[item.bucket]
	local color = SECTION_COLOR[sectionId or ""] or "|cffffffff"
	local role = AGF.RoleDisplay(item.roleText)
	popup.title:SetText(color .. AGF.BucketName(item.bucket) .. "|r  " .. (item.name or "?")
		.. "  |cffaaaaaa" .. role .. "|r")
	popup.body:SetText(item.message or "")
	fitPopup()
	placePopup()
	-- No scaling, no sliding. It simply appears where it belongs.
	popup:SetScale(1)
	popup:SetAlpha(0)
	popup:Show()
	-- Recruit posts are the scarce side of the board, so hold them longer.
	if AGF.IntentOf(item.bucket) == "LFM" then
		holdFor = HOLD_TIME * RARE_MULT
	else
		holdFor = HOLD_TIME
	end
	phase = "in"
	timer = 0
end

-- Unlocked mode. The frame holds a sample message and can be dragged. Real
-- alerts are ignored while it is unlocked, so the sample cannot be replaced
-- under the cursor half way through a drag.
function AGF.AlertUnlocked()
	return unlocked
end

function AGF.SetAlertUnlocked(state)
	if not popup then
		createPopup()
	end
	unlocked = state and true or false
	phase = nil
	timer = 0
	if unlocked then
		popup:EnableMouse(true)
		popup.moveTint:Show()
		popup:SetBackdropBorderColor(0.35, 0.7, 1, 1)
		popup.title:SetText("|cff66ccffMove me|r")
		popup.body:SetText("Drag this frame where you want alerts to appear.")
		fitPopup()
		placePopup()
		popup:SetAlpha(1)
		popup:Show()
		AGF.Print("Alert frame unlocked. Drag it, then right-click the minimap button to lock it.")
	else
		savePosition()
		popup.moveTint:Hide()
		popup:SetBackdropBorderColor(1, 1, 1, 1)
		popup:EnableMouse(false)
		popup:SetAlpha(0)
		popup:Hide()
		AGF.Print("Alert frame locked.")
	end
end

-- Toggle sits on top of the setter, never the other way round, or the two
-- call each other. /acs alert lock and unlock call the setter directly.
function AGF.ToggleAlertLock()
	AGF.SetAlertUnlocked(not unlocked)
end

function AGF.ResetAlertPosition()
	local p = posDB()
	p.hasPos = false
	p.x = 0
	p.y = 0
	if popup and popup:IsShown() then
		placePopup()
	end
	AGF.Print("Alert frame back to the default spot.")
end

function AGF.ShowAlert(row, bucket)
	if unlocked then
		return
	end
	if not popup then
		createPopup()
	end
	if #queue >= QUEUE_MAX then
		table.remove(queue, 1)
	end
	queue[#queue + 1] = {
		bucket = bucket or "PVE_UNSURE",
		name = row and row.name,
		message = row and row.message,
		roleText = row and row.roleText,
	}
	if not phase then
		startNext()
	end
end

driver = CreateFrame("Frame", "AGF_AlertDriver", UIParent)
driver:SetScript("OnUpdate", function(self, elapsed)
	if not phase then
		return
	end
	timer = timer + (elapsed or 0)
	if phase == "in" then
		local p = timer / IN_TIME
		if p >= 1 then
			popup:SetAlpha(1)
			phase = "hold"
			timer = 0
		else
			popup:SetAlpha(p)
		end
	elseif phase == "hold" then
		if timer >= holdFor then
			phase = "fade"
			timer = 0
		end
	elseif phase == "fade" then
		local p = timer / FADE_TIME
		if p >= 1 then
			popup:SetAlpha(0)
			popup:Hide()
			phase = nil
			timer = 0
			if #queue > 0 then
				startNext()
			end
		else
			popup:SetAlpha(1 - p)
		end
	end
end)
