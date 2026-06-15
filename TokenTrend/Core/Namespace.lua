-- ---------------------------------------------------------------------------
-- TokenTrend - Namespace, palettes, and the tiny engine everything hangs off.
-- ---------------------------------------------------------------------------
-- One global table (TokenTrendDB, the SavedVariable) and one private namespace.
-- Every other file does `local _, ns = ...` and reaches in here.

local addonName, ns = ...

ns.addonName = addonName
ns.versionString = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

-- ---------------------------------------------------------------------------
-- Constants: the financial-terminal color palettes + universal indicators
-- ---------------------------------------------------------------------------
local C = {}
ns.C = C

-- #RRGGBB -> {r,g,b} in 0..1 so the spec hex codes stay readable above.
local function hex(s)
	return {
		tonumber(s:sub(1, 2), 16) / 255,
		tonumber(s:sub(3, 4), 16) / 255,
		tonumber(s:sub(5, 6), 16) / 255,
	}
end

C.Palettes = {
	-- Option 2 "The Terminal" is the default: cyan reads great on charcoal.
	terminal = {
		key = "terminal",
		name = "The Terminal",
		bg = hex("18181B"),
		panel = hex("212126"),
		border = hex("3F3F46"),
		text = hex("F4F4F5"),
		muted = hex("A1A1AA"),
		accent = hex("06B6D4"),
	},
	-- Option 1 "Lunar Exchange": blue + silver.
	lunar = {
		key = "lunar",
		name = "Lunar Exchange",
		bg = hex("1A1C23"),
		panel = hex("23262F"),
		border = hex("8C9BAE"),
		text = hex("E2E8F0"),
		muted = hex("8C9BAE"),
		accent = hex("3B82F6"),
	},
}
C.PaletteOrder = { "terminal", "lunar" }

-- Universal financial indicators (shared by both palettes).
C.Bull = hex("22C55E") -- price up / good-to-buy green
C.Bear = hex("EF4444") -- price down / crimson
C.Neutral = hex("94A3B8") -- flat / slate

C.Font = STANDARD_TEXT_FONT
C.FontNumber = NumberFontNormal and NumberFontNormal:GetFont() or STANDARD_TEXT_FONT

-- Returns the active palette table (set after DB loads; falls back to default).
function ns:Palette()
	local key = (ns.db and ns.db.palette) or "terminal"
	return C.Palettes[key] or C.Palettes.terminal
end

-- ---------------------------------------------------------------------------
-- Engine: one event frame, one signal bus, one login queue. That's the whole
-- framework. No Ace, no per-module CreateFrame spam.
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {} -- event -> { fn, fn, ... }

-- Register a handler for a game event. First registration arms the frame.
function ns:RegisterEvent(event, fn)
	local list = eventHandlers[event]
	if not list then
		list = {}
		eventHandlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = eventHandlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

-- Internal signal bus for cross-module reactions (DataUpdated, SettingChanged).
-- Decoupled on purpose: Data fires, UI listens, neither imports the other.
local signalHandlers = {}

function ns:On(signal, fn)
	local list = signalHandlers[signal]
	if not list then
		list = {}
		signalHandlers[signal] = list
	end
	list[#list + 1] = fn
end

function ns:Fire(signal, ...)
	local list = signalHandlers[signal]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end

-- Login queue. ADDON_LOADED initializes the DB (see Config.lua); PLAYER_LOGIN
-- runs everything that needs a ready world + a ready DB.
local loginQueue = {}

function ns:OnLogin(fn)
	loginQueue[#loginQueue + 1] = fn
end

ns:RegisterEvent("PLAYER_LOGIN", function()
	for i = 1, #loginQueue do
		loginQueue[i]()
	end
end)
