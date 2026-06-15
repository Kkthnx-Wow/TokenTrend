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

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_TOKENTREND1 = "/tokentrend"
SLASH_TOKENTREND2 = "/tt"

SlashCmdList["TOKENTREND"] = function(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")

	if cmd == "show" then
		ns.UI:Show()
	elseif cmd == "hide" then
		ns.UI:Hide()
	elseif cmd == "theme" then
		ns:CyclePalette()
	elseif cmd == "refresh" then
		ns.Data:RequestUpdate()
		msg(L["Refresh"])
	elseif cmd == "" or cmd == "toggle" then
		ns.UI:Toggle()
	else
		msg(L["Commands:"])
		print(" " .. L["/tt - toggle the window"])
		print(" " .. L["/tt show - open the window"])
		print(" " .. L["/tt hide - close the window"])
		print(" " .. L["/tt theme - cycle color theme"])
		print(" " .. L["/tt refresh - request a fresh price"])
	end
end
