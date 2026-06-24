-- ---------------------------------------------------------------------------
-- TokenTrend - Sync panel: a popover off the footer "Sync" button showing the
-- live state of peer sharing - on/off (with a toggle), how many samples this
-- session brought in, and who you've backfilled from / shared with.
-- ---------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F
local UI = ns.UI

local format = string.format
local tsort = table.sort
local tconcat = table.concat
local min = math.min
local Ambiguate = Ambiguate

local MAX_ROWS = 6 -- per list; the rest folds into "...and N more"

-- Render a sender -> count map into a capped, biggest-first block of lines.
-- Names take the panel's text color; counts are forced white for contrast.
local function listText(map)
	local rows = {}
	for name, n in pairs(map) do
		rows[#rows + 1] = { name = name, n = n }
	end
	if #rows == 0 then
		return "|cff808080" .. L["Nobody yet"] .. "|r"
	end
	tsort(rows, function(a, b) return a.n > b.n end)

	local lines = {}
	local shown = min(#rows, MAX_ROWS)
	for i = 1, shown do
		local r = rows[i]
		local who = (Ambiguate and Ambiguate(r.name, "short")) or r.name
		lines[#lines + 1] = format("%s  |cffffffff%s|r", who, F.Comma(r.n))
	end
	if #rows > shown then
		lines[#lines + 1] = format("|cff808080" .. L["...and %d more"] .. "|r", #rows - shown)
	end
	return tconcat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Build (lazy, on first open)
-- ---------------------------------------------------------------------------
function UI:BuildSyncPanel()
	if self.syncPanel then
		return self.syncPanel
	end

	local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	panel:SetSize(300, 300)
	panel:SetPoint("BOTTOMRIGHT", self.footer, "TOPRIGHT", 0, 6)
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true) -- swallow clicks so they don't fall through to the chart
	panel:Hide()
	self:Skin(panel, "panel")
	ns.Skin.CreateShadow(panel, 4)
	self.syncPanel = panel

	local title = self:Text(panel, "OVERLAY", C.Font, 14, "", "accent")
	title:SetShadowOffset(1, -1)
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["Peer Sync"])

	local close = self:CloseButton(panel)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() panel:Hide() end)
	self:SetTooltip(close, L["Close"], L["Close this panel."], "ANCHOR_LEFT")

	panel.status = self:Text(panel, "OVERLAY", C.Font, 12, "", "text")
	panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

	panel.toggle = self:Button(panel, L["Disable"], 84, function()
		ns.Sync:SetEnabled(not ns.db.sync)
		UI:RefreshSyncPanel()
	end)
	-- Share the close button's right edge so the two stack cleanly.
	panel.toggle:SetPoint("TOPRIGHT", close, "BOTTOMRIGHT", 0, -4)

	panel.gained = self:Text(panel, "OVERLAY", C.Font, 12, "", "muted")
	panel.gained:SetPoint("TOPLEFT", panel.status, "BOTTOMLEFT", 0, -10)

	panel.instanceNote = self:Text(panel, "OVERLAY", C.Font, 11, "", "muted")
	panel.instanceNote:SetPoint("TOPLEFT", panel.gained, "BOTTOMLEFT", 0, -6)
	panel.instanceNote:Hide()

	local fromHeader = self:Text(panel, "OVERLAY", C.Font, 11, "", "accent")
	fromHeader:SetPoint("TOPLEFT", panel.instanceNote, "BOTTOMLEFT", 0, -8)
	fromHeader:SetText(L["Backfilled from"])
	panel.fromBody = self:Text(panel, "OVERLAY", C.Font, 12, "", "text")
	panel.fromBody:SetPoint("TOPLEFT", fromHeader, "BOTTOMLEFT", 4, -5)
	panel.fromBody:SetJustifyH("LEFT")
	panel.fromBody:SetJustifyV("TOP")

	local toHeader = self:Text(panel, "OVERLAY", C.Font, 11, "", "accent")
	toHeader:SetPoint("TOPLEFT", panel.fromBody, "BOTTOMLEFT", -4, -14)
	toHeader:SetText(L["Shared with"])
	panel.toBody = self:Text(panel, "OVERLAY", C.Font, 12, "", "text")
	panel.toBody:SetPoint("TOPLEFT", toHeader, "BOTTOMLEFT", 4, -5)
	panel.toBody:SetJustifyH("LEFT")
	panel.toBody:SetJustifyV("TOP")

	return panel
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function UI:RefreshSyncPanel()
	local panel = self.syncPanel
	if not panel then
		return
	end
	local s = ns.Sync:Stats()

	if ns.db.sync then
		panel.status:SetText(format("%s: |cff%s%s|r", L["Status"], F.Hex(C.Bull), L["Enabled"]))
		panel.toggle.label:SetText(L["Disable"])
		self:SetTooltip(panel.toggle, L["Disable"], L["Stop sharing and receiving price history."], "ANCHOR_LEFT")
	else
		panel.status:SetText(format("%s: |cff%s%s|r", L["Status"], F.Hex(C.Neutral), L["Disabled"]))
		panel.toggle.label:SetText(L["Enable"])
		self:SetTooltip(panel.toggle, L["Enable"], L["Share price history with guild and group members to fill gaps."], "ANCHOR_LEFT")
	end

	if ns.db.sync and IsInInstance() then
		panel.instanceNote:SetText("|cff" .. F.Hex(C.Neutral) .. L["Paused while in an instance."] .. "|r")
		panel.instanceNote:Show()
	else
		panel.instanceNote:Hide()
	end

	panel.gained:SetText(format(L["Gained this session: %s"], F.Comma(s.gained) .. " " .. L["samples"]))
	panel.fromBody:SetText(listText(s.from))
	panel.toBody:SetText(listText(s.to))
end

-- ---------------------------------------------------------------------------
-- Toggle visibility (footer button)
-- ---------------------------------------------------------------------------
function UI:ToggleSyncPanel()
	self:Build()
	self:BuildSyncPanel()
	if self.syncPanel:IsShown() then
		self.syncPanel:Hide()
	else
		self:RefreshSyncPanel()
		self.syncPanel:Show()
	end
end

-- Keep the panel live while it's open and a merge lands.
ns:On("DataUpdated", function()
	if UI.syncPanel and UI.syncPanel:IsShown() then
		UI:RefreshSyncPanel()
	end
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if UI.syncPanel and UI.syncPanel:IsShown() then
		UI:RefreshSyncPanel()
	end
end)
