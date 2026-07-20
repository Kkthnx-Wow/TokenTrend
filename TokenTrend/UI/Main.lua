-- ---------------------------------------------------------------------------
-- TokenTrend - Main window: chrome, theming, header, tabs, footer.
-- ---------------------------------------------------------------------------
-- Built lazily on first open (no frames at load). Tabs are contributed by
-- Chart.lua / Stats.lua appending to UI.tabDefs before the window is built.

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F

local UI = {}
ns.UI = UI

local Skin = ns.Skin
local statusTicker

UI.tabDefs = {} -- { { id, label, build(panel) -> refreshFn } }
UI.themed = {} -- recolor closures, replayed on theme change
UI.activeTab = 1

-- Shared 1px pixel backdrop (NDui bdTex) for banners/tooltips.
ns.UI.BACKDROP = Skin.BackdropTable()

-- ---------------------------------------------------------------------------
-- Theming primitives. Everything skinnable registers a closure so a live
-- /tt theme swap repaints without a reload.
-- ---------------------------------------------------------------------------
function UI:OnTheme(fn)
	self.themed[#self.themed + 1] = fn
	if self.frame then
		fn(ns:Palette())
	end -- apply immediately if live
end

function UI:ApplyTheme()
	local p = ns:Palette()
	for i = 1, #self.themed do
		self.themed[i](p)
	end
end

-- Skin a frame: NDui pixel border + optional shadow/bg texture.
-- role: "window" | "panel" | "plot"
function UI:Skin(frame, role)
	Skin.ApplyPanelBackdrop(frame, role)
	if role == "window" and not frame.__ttShadow then
		Skin.CreateShadow(frame, 4)
		Skin.CreateBgTex(frame, 0.06)
	elseif role == "panel" and not frame.__ttBgTex then
		Skin.CreateBgTex(frame, 0.04)
	end
	self:OnTheme(function()
		Skin.RefreshBackdrop(frame)
	end)
end

-- Toggle styling for chart/history control buttons.
function UI:StyleButtonToggle(btn, active)
	if not btn then
		return
	end
	local p = ns:Palette()
	Skin.SetButtonActive(btn, active)
	if active then
		btn.label:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
	else
		btn.label:SetTextColor(p.muted[1], p.muted[2], p.muted[3])
	end
end

-- A themed FontString. role: "text" | "muted" | "accent".
function UI:Text(parent, layer, fontPath, size, flags, role)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(fontPath or C.Font, size or 12, flags or "")
	role = role or "text"
	self:OnTheme(function(p)
		local col = role == "muted" and p.muted or role == "accent" and p.accent or p.text
		fs:SetTextColor(col[1], col[2], col[3])
	end)
	return fs
end

-- Flat NDui-style button: pixel border, gradient wash, accent hover.
function UI:Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 64, 22)

	local label = b:CreateFontString(nil, "OVERLAY")
	label:SetFont(C.Font, 12, "")
	label:SetShadowOffset(1, -1)
	label:SetPoint("CENTER")
	label:SetText(text)
	b.label = label

	Skin.AttachButtonBg(b)

	if onClick then
		b:SetScript("OnClick", onClick)
	end

	self:OnTheme(function(p)
		if b.SetFlatRest then
			b:SetFlatRest()
		end
		if b.__ttActive then
			b:SetFlatHover(true)
		end
		label:SetTextColor(p.text[1], p.text[2], p.text[3])
	end)
	return b
end

-- Attach a hover tooltip to any frame. `title` shows bright; optional `body`
-- wraps muted beneath it. We HookScript (not SetScript) so a button's existing
-- highlight OnEnter/OnLeave keeps firing. Calling again just updates the text -
-- handy for buttons whose meaning flips with state (clock, sync toggle).
function UI:SetTooltip(frame, title, body, anchor)
	frame.ttTitle, frame.ttBody, frame.ttAnchor = title, body, anchor or "ANCHOR_TOP"
	if frame.__ttHooked then
		return
	end
	frame.__ttHooked = true
	frame:HookScript("OnEnter", function(self)
		if not self.ttTitle then
			return
		end
		GameTooltip:SetOwner(self, self.ttAnchor)
		GameTooltip:AddLine(self.ttTitle)
		if self.ttBody then
			local p = ns:Palette()
			GameTooltip:AddLine(self.ttBody, p.muted[1], p.muted[2], p.muted[3], true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- A square, themed close button. Resting state matches the panel; hovering
-- flushes it Bear-red so "this closes things" reads instantly. No more stock
-- Blizzard X clashing with our charcoal.
function UI:CloseButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	Skin.AttachButtonBg(b, { noHover = true })

	local glyph = b:CreateFontString(nil, "OVERLAY")
	glyph:SetFont(C.Font, 15, "")
	glyph:SetShadowOffset(1, -1)
	glyph:SetPoint("CENTER", 0, 0)
	glyph:SetText("\195\151")
	b.glyph = glyph

	local function rest()
		local p = ns:Palette()
		if b.SetFlatRest then
			b:SetFlatRest()
		end
		glyph:SetTextColor(p.muted[1], p.muted[2], p.muted[3])
	end
	b:SetScript("OnEnter", function()
		Skin.TintBackdrop(b.__bg, C.Bear, 0.85)
		b.__bg:SetBackdropBorderColor(C.Bear[1], C.Bear[2], C.Bear[3], 1)
		glyph:SetTextColor(1, 1, 1)
	end)
	b:SetScript("OnLeave", rest)
	self:OnTheme(rest)
	return b
end

-- A horizontal low<->high range bar with a marker for the current value -
-- "where in the range are we right now?" Used by the header (Day Range) and
-- the Stats tab (30-Day Range). The caller sizes rb.frame; call
-- rb:Update(low, high, current[, colorByFrac]) to refresh.
function UI:RangeBar(parent, captionText)
	local rb = {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(30)
	rb.frame = f

	if captionText then
		local cap = self:Text(f, "OVERLAY", C.Font, 10, "", "muted")
		cap:SetPoint("TOP", 0, 0)
		cap:SetText(captionText)
		rb.caption = cap
	end

	local track = f:CreateTexture(nil, "ARTWORK")
	track:SetPoint("TOPLEFT", 0, -13)
	track:SetPoint("TOPRIGHT", 0, -13)
	track:SetHeight(4)
	rb.track = track

	local marker = f:CreateTexture(nil, "OVERLAY")
	marker:SetSize(3, 12)
	marker:Hide()
	rb.marker = marker

	local lowFS = self:Text(f, "OVERLAY", C.Font, 10, "", "muted")
	lowFS:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
	rb.low = lowFS
	local highFS = self:Text(f, "OVERLAY", C.Font, 10, "", "muted")
	highFS:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -3)
	highFS:SetJustifyH("RIGHT")
	rb.high = highFS

	self:OnTheme(function(p)
		track:SetColorTexture(p.border[1], p.border[2], p.border[3], 0.55)
	end)

	function rb:Update(low, high, current, colorByFrac)
		if not (low and high and current) or high <= low then
			self.marker:Hide()
			self.low:SetText("")
			self.high:SetText("")
			return
		end
		self.low:SetText(F.FormatGoldShort(low))
		self.high:SetText(F.FormatGoldShort(high))

		local frac = (current - low) / (high - low)
		if frac < 0 then
			frac = 0
		elseif frac > 1 then
			frac = 1
		end
		local w = self.track:GetWidth()
		if w <= 0 then
			return
		end
		self.marker:ClearAllPoints()
		self.marker:SetPoint("CENTER", self.track, "LEFT", frac * w, 0)
		if colorByFrac then
			-- Green (cheap, near low) -> red (pricey, near high).
			local bull, bear = C.Bull, C.Bear
			self.marker:SetColorTexture(
				bear[1] * frac + bull[1] * (1 - frac),
				bear[2] * frac + bull[2] * (1 - frac),
				bear[3] * frac + bull[3] * (1 - frac),
				1
			)
		else
			local p = ns:Palette()
			self.marker:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 1)
		end
		self.marker:Show()
	end

	return rb
end

-- ---------------------------------------------------------------------------
-- Window construction
-- ---------------------------------------------------------------------------
local function persistGeometry(self)
	local point, _, relPoint, x, y = self:GetPoint()
	local w = ns.db.window
	w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

function UI:Build()
	if self.frame then
		return
	end

	local w = ns.db.window
	local frame = CreateFrame("Frame", "TokenTrendFrame", UIParent, "BackdropTemplate")
	self.frame = frame
	-- Size is a fixed design constant (no resize grip), so pull it from the
	-- defaults rather than the saved value. Only the *position* is user state.
	frame:SetSize(ns.defaults.window.width, ns.defaults.window.height)
	frame:SetPoint(w.point, UIParent, w.relPoint, w.x, w.y)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		persistGeometry(f)
	end)
	frame:SetScript("OnHide", function()
		ns.db.window.shown = false
		if statusTicker then
			statusTicker:Cancel()
			statusTicker = nil
		end
	end)
	tinsert(UISpecialFrames, "TokenTrendFrame") -- ESC closes it
	self:Skin(frame, "window")

	-- Header ----------------------------------------------------------------
	-- Inset 3px (not 1) so the header panel's own border doesn't paint straight
	-- over the window's frame border - leaves a clean 2px gap of window bg.
	local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	header:SetPoint("TOPLEFT", 3, -3)
	header:SetPoint("TOPRIGHT", -3, -3)
	header:SetHeight(64)
	self:Skin(header, "panel")
	self.header = header

	-- Brand icon, sitting just left of the name.
	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", 12, -12)
	F.SetTokenIcon(icon)
	self.icon = icon

	local title = self:Text(header, "OVERLAY", C.Font, 16, "", "accent")
	title:SetShadowOffset(1, -1)
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
	title:SetText(L["TokenTrend"])

	local subtitle = self:Text(header, "OVERLAY", C.Font, 11, "", "muted")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	self.subtitle = subtitle

	-- Big current price + change arrow, right-aligned.
	local price = self:Text(header, "OVERLAY", C.FontNumber, 30, "", "text")
	price:SetShadowOffset(1, -1)
	price:SetPoint("TOPRIGHT", -36, -10)
	self.priceText = price

	local arrow = header:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(16, 16)
	arrow:SetPoint("RIGHT", price, "LEFT", -6, 1)
	self.arrow = arrow

	local change = self:Text(header, "OVERLAY", C.Font, 12, "", "muted")
	change:SetPoint("TOPRIGHT", price, "BOTTOMRIGHT", 0, -2)
	self.changeText = change

	-- Day range bar, centered in the header gap between the title and price.
	self.dayRange = self:RangeBar(header, L["Day Range"])
	self.dayRange.frame:SetPoint("TOP", header, "TOP", 0, -10)
	self.dayRange.frame:SetWidth(190)

	-- Close button (themed, not the stock Blizzard X).
	local close = self:CloseButton(header)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		UI:Hide()
	end)
	self:SetTooltip(close, L["Close"], L["Close the window. Type /tt to reopen."], "ANCHOR_LEFT")

	-- Tab strip -------------------------------------------------------------
	local tabStrip = CreateFrame("Frame", nil, frame)
	tabStrip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -6)
	tabStrip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -8, -6)
	tabStrip:SetHeight(22)
	self.tabButtons = {}

	local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	content:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", -8, -6)
	-- Match the header's 3px inset on the right so its border doesn't paint over
	-- the frame border either. Bottom stays clear for the footer row.
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 40)
	self:Skin(content, "panel")
	self.content = content

	-- Build tab buttons + panels from contributed defs.
	local prevBtn
	for i, def in ipairs(self.tabDefs) do
		local btn = self:Button(tabStrip, def.label, 86, function()
			UI:SelectTab(i)
		end)
		if def.tip then
			self:SetTooltip(btn, def.label, def.tip)
		end
		if prevBtn then
			btn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
		else
			btn:SetPoint("LEFT", 0, 0)
		end
		prevBtn = btn
		self.tabButtons[i] = btn

		local panel = CreateFrame("Frame", nil, content)
		panel:SetPoint("TOPLEFT", 8, -8)
		panel:SetPoint("BOTTOMRIGHT", -8, 8)
		panel:Hide()
		def.panel = panel
		def.refresh = def.build(panel) -- builder returns a refresh fn
	end

	-- Footer ----------------------------------------------------------------
	-- Its own roomy row, vertically centered, clear of the content border.
	local footer = CreateFrame("Frame", nil, frame)
	footer:SetPoint("BOTTOMLEFT", 10, 9)
	footer:SetPoint("BOTTOMRIGHT", -10, 9)
	footer:SetHeight(24)
	self.footer = footer

	local status = self:Text(footer, "OVERLAY", C.Font, 11, "", "muted")
	status:SetPoint("LEFT", 2, 0)
	self.statusText = status

	local themeBtn = self:Button(footer, L["Theme"], 72, function()
		ns:CyclePalette()
	end)
	themeBtn:SetPoint("RIGHT", 0, 0)
	self:SetTooltip(themeBtn, L["Theme"], L["Cycle between the color themes."])
	local refreshBtn = self:Button(footer, L["Refresh"], 72, function()
		ns:RequestPriceRefresh()
	end)
	refreshBtn:SetPoint("RIGHT", themeBtn, "LEFT", -8, 0)
	self:SetTooltip(refreshBtn, L["Refresh"], L["Request a fresh token price from the server."])

	local syncBtn = self:Button(footer, L["Sync"], 72, function()
		UI:ToggleSyncPanel()
	end)
	syncBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -8, 0)
	self:SetTooltip(syncBtn, L["Sync"], L["Open the peer sync panel - see what history you've shared and gained."])

	-- Import: paste a seed string from the website to fill the chart on day one.
	local importBtn = self:Button(footer, L["Import"], 72, function()
		ns:OpenImport()
	end)
	importBtn:SetPoint("RIGHT", syncBtn, "LEFT", -8, 0)
	self:SetTooltip(importBtn, L["Import History"], L["Seed the chart with history from kkthnx.com/wow/token."])

	-- Compact 12/24h clock toggle. Label shows the current mode; clicking flips
	-- it. SettingChanged -> Refresh keeps the label in sync with /tt clock too.
	local clockBtn = self:Button(footer, ns.db.clock24 and L["24h"] or L["12h"], 46, function()
		ns:SetSetting("clock24", not ns.db.clock24)
	end)
	clockBtn:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)
	self.clockBtn = clockBtn

	self:ApplyTheme()
	self:SelectTab(self.activeTab)
	self:Refresh()
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
-- Paint the tab strip for the current activeTab: active one accented, the rest
-- neutral, and only the active panel shown. Pure styling + visibility, no
-- content refresh - so it's cheap to replay after a theme swap.
function UI:StyleTabs()
	for i, def in ipairs(self.tabDefs) do
		local active = (i == self.activeTab)
		def.panel:SetShown(active)
		local btn = self.tabButtons[i]
		UI:StyleButtonToggle(btn, active)
	end
end

function UI:SelectTab(index)
	self.activeTab = index
	self:StyleTabs()
	local def = self.tabDefs[index]
	if def and def.refresh then
		def.refresh()
	end
end

-- Footer status only (cheap; keeps "Last update" aging without redrawing the chart).
function UI:RefreshStatus()
	if not self.frame or not self.frame:IsShown() or not self.statusText then
		return
	end
	local stats = ns.Analysis:Stats()
	self.statusText:SetText(
		("%s: %s   %s   %s: %d / %d"):format(
			L["Last update"],
			F.AgoString(ns.Data.lastUpdate),
			F.Sep,
			L["Samples"],
			stats.samples,
			ns.db.maxSamples
		)
	)
end

local function armStatusTicker()
	if statusTicker then
		return
	end
	statusTicker = C_Timer.NewTicker(60, function()
		UI:RefreshStatus()
	end)
end

-- ---------------------------------------------------------------------------
-- Refresh: header + status + active tab. Cheap, and a no-op while the window is
-- hidden - a closed window has nothing to repaint, and Show() always refreshes
-- on the way up, so a hidden /tt clock or DataUpdated costs nothing.
-- ---------------------------------------------------------------------------
function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	local stats = ns.Analysis:Stats()

	self.subtitle:SetText(("%s  %s  %s %s"):format(L["WoW Token"], F.Sep, L["Region"], F.GetRegionName()))

	if stats.current then
		self.priceText:SetText(F.FormatGold(stats.current))
		-- Headline the day-over-day net change (vs previous close); fall back to
		-- the sample-to-sample delta only until there's a prior close.
		local cAbs = stats.netAbs or stats.changeAbs
		local cPct = stats.netPct or stats.changePct
		local r, g, b = F.TrendColor(cAbs)
		self.priceText:SetTextColor(r, g, b)

		if cAbs and cAbs ~= 0 then
			self.arrow:Show()
			F.SetArrow(self.arrow, cAbs > 0)
			self.arrow:SetVertexColor(r, g, b)
			self.changeText:SetText(
				("%s%s  (%s)"):format(cAbs > 0 and "+" or "", F.FormatGold(math.abs(cAbs)), F.FormatPct(cPct))
			)
			self.changeText:SetTextColor(r, g, b)
		else
			self.arrow:Hide()
			self.changeText:SetText(L["No change"])
			self.changeText:SetTextColor(C.Neutral[1], C.Neutral[2], C.Neutral[3])
		end
	else
		self.priceText:SetText(F.EmDash)
		self.arrow:Hide()
		self.changeText:SetText(L["Waiting for first price..."])
	end

	self.dayRange:Update(stats.dayLow, stats.dayHigh, stats.current)
	self:RefreshStatus()
	armStatusTicker()

	if self.clockBtn then
		self.clockBtn.label:SetText(ns.db.clock24 and L["24h"] or L["12h"])
		self:SetTooltip(
			self.clockBtn,
			L["Clock"],
			ns.db.clock24 and L["Showing 24-hour time. Click for 12-hour (AM/PM)."]
				or L["Showing 12-hour time. Click for 24-hour."]
		)
	end

	local def = self.tabDefs[self.activeTab]
	if def and def.refresh then
		def.refresh()
	end
end

-- ---------------------------------------------------------------------------
-- Show / hide / toggle
-- ---------------------------------------------------------------------------
function UI:Show()
	self:Build()
	self.frame:Show()
	ns.db.window.shown = true
	self:Refresh()
	-- Opening the window is a great moment to ask for a fresh number.
	ns.Data:RequestUpdate()
end

function UI:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

function UI:Toggle()
	if self.frame and self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

-- ---------------------------------------------------------------------------
-- Reactions
-- ---------------------------------------------------------------------------
ns:On("DataUpdated", function()
	UI:Refresh() -- self-guards while hidden
end)

-- Per-key reactions to a live setting change. A palette swap is the only thing
-- that needs a full repaint (ApplyTheme replays every themed closure) + tab
-- restyle; everything else falls through to the shared header + active-tab
-- redraw below, which re-pulls the new value. Add a key here when a setting
-- needs extra work beyond a plain refresh - no if-chain to grow.
local settingReactions = {
	palette = function()
		UI:ApplyTheme()
		UI:StyleTabs()
	end,
}

ns:On("SettingChanged", function(key)
	if not UI.frame then
		return
	end
	local react = settingReactions[key]
	if react then
		react()
	end
	UI:Refresh()
end)

ns:OnLogin(function()
	if ns.db.window.shown then
		C_Timer.After(0.5, function()
			UI:Show()
		end)
	end
end)
