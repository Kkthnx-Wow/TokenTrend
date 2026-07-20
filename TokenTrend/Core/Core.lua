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

-- The seed page. One constant so the popup, the import dialog, and the chat
-- link all point at the same place.
ns.SEED_URL = "https://kkthnx.com/wow/token"

-- ---------------------------------------------------------------------------
-- Copyable URL popup. An edit box that opens with the URL already typed in and
-- fully selected, so the user just hits Ctrl+C (or Cmd+C) and pastes it into a
-- browser. This is the friendliest a URL can be inside WoW, which has no way to
-- open a browser directly.
-- ---------------------------------------------------------------------------
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["TOKENTREND_URL"] = {
	text = L["Copy this address, then open it in your web browser:"],
	button1 = DONE or L["Close"],
	hasEditBox = true,
	editBoxWidth = 300,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnShow = function(self)
		local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
		if eb then
			eb:SetText(ns.SEED_URL)
			eb:HighlightText() -- pre-select so Ctrl+C grabs it immediately
			eb:SetFocus()
		end
	end,
	-- Keep the URL intact: re-select on any edit attempt, and don't let Enter or
	-- Escape leave a half-deleted string behind.
	EditBoxOnTextChanged = function(self)
		if self:GetText() ~= ns.SEED_URL then
			self:SetText(ns.SEED_URL)
			self:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(self)
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
}

function ns:ShowURL()
	StaticPopup_Show("TOKENTREND_URL")
end

-- ---------------------------------------------------------------------------
-- Import: a native paste dialog that feeds Import:Apply. Using StaticPopup with
-- an EditBox means Ctrl+V, Cmd+V and right-click paste all just work, and the
-- popup is safe to open from anywhere (no custom frame lifecycle to babysit).
-- ---------------------------------------------------------------------------
StaticPopupDialogs["TOKENTREND_IMPORT"] = {
	text = L["Paste a seed string from kkthnx.com/wow/token to fill your chart."],
	button1 = L["Import"],
	button2 = CANCEL or L["Close"],
	button3 = L["Get URL"],
	hasEditBox = true,
	editBoxWidth = 260,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3, -- avoid tainting Blizzard's default popup slots
	OnShow = function(self)
		local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
		if eb then
			eb:SetText("")
			eb:SetFocus()
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local text = self:GetText()
		ns:DoImport(text)
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	OnAccept = function(self)
		local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
		if eb then
			ns:DoImport(eb:GetText())
		end
	end,
	-- The third button opens the copyable URL instead of closing, so a user with
	-- no seed string yet can grab the address without hunting for it.
	OnAlt = function()
		ns:ShowURL()
	end,
}

function ns:DoImport(text)
	if not ns.Import then return end
	local added, totalOrErr, region = ns.Import:Apply(text)
	if added == nil then
		-- On failure the second return is the reason string.
		msg(totalOrErr or L["That doesn't look like a valid seed string."])
		return
	end
	if added == 0 then
		msg(L["Nothing new to import - your history already covers it."])
		return
	end

	msg(L["Imported %d of %d samples."]:format(added, totalOrErr))

	-- Show off the payoff: open the window if it's closed and make sure the
	-- selected range actually spans the imported history, so the user lands on a
	-- full chart instead of a view that clips it. Seed data is ~7 days, so widen
	-- a tighter range to 30d; leave wider selections (30/90/all) alone.
	if ns.db.rangeDays ~= 0 and ns.db.rangeDays < 30 then
		ns:SetSetting("rangeDays", 30)
	end
	if ns.UI then
		if ns.UI.Show and not (ns.UI.frame and ns.UI.frame:IsShown()) then
			ns.UI:Show()
		end
		ns:Fire("DataUpdated")
	end
end

function ns:OpenImport()
	StaticPopup_Show("TOKENTREND_IMPORT")
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
	import = function() ns:OpenImport() end,
	url = function()
		ns:ShowURL()
		msg(L["Seed page: %s"]:format(ns.SEED_URL))
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
	print(" " .. L["/tt import - paste history from the website"])
	print(" " .. L["/tt url - show the seed page address to copy"])
end

SlashCmdList["TOKENTREND"] = function(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")
	if cmd == "" then
		cmd = "toggle"
	end
	local handler = commands[cmd] or printHelp
	handler()
end
