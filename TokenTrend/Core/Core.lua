-- ---------------------------------------------------------------------------
-- TokenTrend - Init glue + slash commands. The conductor, not the orchestra.
-- ---------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local print = print

local function msg(text)
	local accent = ns:Palette().accent
	local tag = ("|cff%s%s|r"):format(ns.F.Hex(accent), L["TokenTrend"])
	print(tag .. ": " .. text)
end
ns.Print = msg

-- ---------------------------------------------------------------------------
-- Setting changes funnel through here so the UI re-themes/re-renders live
-- instead of demanding a /reload. SetSetting -> Fire -> listeners react.
-- ---------------------------------------------------------------------------
function ns:SetSetting(key, value)
	ns.db[key] = value
	ns:Fire("SettingChanged", key, value)
end

function ns:CyclePalette()
	local order = ns.C.PaletteOrder
	local current = ns.db.palette
	local idx = 1
	for i = 1, #order do
		if order[i] == current then idx = i break end
	end
	local nextKey = order[(idx % #order) + 1]
	ns:SetSetting("palette", nextKey)
	msg(L["Theme set to %s."]:format(ns:Palette().name))
end

function ns:RequestPriceRefresh()
	ns.Data:RequestUpdate()
	msg(L["Refresh"])
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
function TokenTrend_Toggle()
	ns.UI:Toggle()
end

SLASH_TOKENTREND1 = "/tokentrend"
SLASH_TOKENTREND2 = "/tt"

-- Command dispatch table (cleaner than an if-elseif chain; add a verb here and
-- it just works). Empty input falls through to "toggle"; unknown verbs print help.
local commands = {
	show = function() ns.UI:Show() end,
	hide = function() ns.UI:Hide() end,
	toggle = function() ns.UI:Toggle() end,
	theme = function() ns:CyclePalette() end,
	refresh = function() ns:RequestPriceRefresh() end,
	sync = function()
		local on = not ns.db.sync
		ns.Sync:SetEnabled(on)
		msg(on and L["History sharing enabled."] or L["History sharing disabled."])
	end,
	clock = function()
		ns:SetSetting("clock24", not ns.db.clock24)
		msg(L["Clock set to %s."]:format(ns.db.clock24 and L["24-hour"] or L["12-hour"]))
	end,
	minimap = function()
		ns.Minimap:Toggle()
		msg(ns.db.minimap.hide and L["Minimap button hidden."] or L["Minimap button shown."])
	end,
	alerts = function()
		local on = not (ns.db.alertOn30dLow and ns.db.alertOn30dHigh)
		ns:SetSetting("alertOn30dLow", on)
		ns:SetSetting("alertOn30dHigh", on)
		msg(on and L["Price alerts enabled."] or L["Price alerts disabled."])
	end,
}

local function printHelp()
	msg(L["Commands:"])
	print(" " .. L["/tt - toggle the window"])
	print(" " .. L["/tt show - open the window"])
	print(" " .. L["/tt hide - close the window"])
	print(" " .. L["/tt theme - cycle color theme"])
	print(" " .. L["/tt refresh - request a fresh price"])
	print(" " .. L["/tt sync - toggle history sharing"])
	print(" " .. L["/tt clock - toggle 12/24-hour time"])
	print(" " .. L["/tt minimap - toggle the minimap button"])
	print(" " .. L["/tt alerts - toggle price alerts"])
end

SlashCmdList["TOKENTREND"] = function(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")
	if cmd == "" then
		cmd = "toggle"
	end
	local handler = commands[cmd] or printHelp
	handler()
end
