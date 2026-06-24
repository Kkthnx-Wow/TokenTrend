-- ---------------------------------------------------------------------------
-- TokenTrend - Alerts: chat + screen notifications when price hits key levels.
-- ---------------------------------------------------------------------------
-- Chart banners show signals while the window is open; this module fires when
-- the player is doing anything else. Throttled to once per calendar day per
-- signal so a sustained low/high doesn't spam every poll tick.
-- Uses Blizzard's UIErrorsFrame for on-screen toasts (same pattern as Pawn).

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F

local Alerts = {}
ns.Alerts = Alerts

local floor = math.floor
local time = time
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local UIErrorsFrame = UIErrorsFrame

local DAY = 86400

local function today()
	return floor(time() / DAY)
end

local function playAlertSound()
	if not ns.db.alertSound then return end
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	else
		PlaySound(856)
	end
end

local function screenToast(text, r, g, b)
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(text, r, g, b, 1.0, 5.0)
	end
end

local function fire(text, r, g, b)
	playAlertSound()
	screenToast(text, r, g, b)
	if ns.db.alertChat then
		ns.Print(text)
	end
end

function Alerts:Check()
	if not ns.db.alertOn30dLow and not ns.db.alertOn30dHigh then
		return
	end

	local cur = ns.Data.current
	if not cur then return end

	local day = today()

	if ns.db.alertOn30dLow then
		local isLow, low30 = ns.Analysis:Is30DayLow()
		if isLow and ns.db.lastBuyAlertDay ~= day then
			ns.db.lastBuyAlertDay = day
			local text = L["Token is at a 30-day low (%s)."]:format(F.FormatGold(low30 or cur))
			fire(text, C.Bull[1], C.Bull[2], C.Bull[3])
		end
	end

	if ns.db.alertOn30dHigh then
		local isHigh, high30 = ns.Analysis:Is30DayHigh()
		if isHigh and ns.db.lastSellAlertDay ~= day then
			ns.db.lastSellAlertDay = day
			local text = L["Token is at a 30-day high (%s)."]:format(F.FormatGold(high30 or cur))
			fire(text, C.Bear[1], C.Bear[2], C.Bear[3])
		end
	end
end

ns:OnLogin(function()
	ns:On("DataUpdated", function()
		Alerts:Check()
	end)
end)
