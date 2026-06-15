-- ---------------------------------------------------------------------------
-- TokenTrend - Stats tab: headline metrics + time-of-day volatility heatmaps.
-- ---------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F
local UI = ns.UI

local format = string.format

local stats = {}

-- Blend cheapest(green) -> priciest(red) by a 0..1 fraction.
local function heatColor(frac)
	local g, r = C.Bull, C.Bear
	return r[1] * frac + g[1] * (1 - frac), r[2] * frac + g[2] * (1 - frac), r[3] * frac + g[3] * (1 - frac)
end

-- ---------------------------------------------------------------------------
-- Metric rows (left column)
-- ---------------------------------------------------------------------------
local function makeRow(parent, anchor, labelText)
	local label = UI:Text(parent, "OVERLAY", C.Font, 12, "", "muted")
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -7)
	label:SetText(labelText)

	local value = UI:Text(parent, "OVERLAY", C.Font, 12, "", "text")
	value:SetPoint("LEFT", label, "LEFT", 130, 0)
	return { label = label, value = value, anchor = label }
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function setVal(row, text, r, g, b)
	row.value:SetText(text or "\226\128\148")
	if r then
		row.value:SetTextColor(r, g, b)
	else
		local p = ns:Palette()
		row.value:SetTextColor(p.text[1], p.text[2], p.text[3])
	end
end

-- Where does the current price sit inside the 30-day range, and is that
-- cheap/fair/expensive? Drives the range bar + verdict tag.
local function updateFairValue(s)
	local lo, hi, cur = s.low30, s.high30, s.current
	if not (lo and hi and cur) or hi <= lo then
		stats.fairTitle:Hide()
		stats.fairBar.frame:Hide()
		stats.fairVerdict:Hide()
		return
	end
	stats.fairTitle:Show()
	stats.fairBar.frame:Show()
	stats.fairVerdict:Show()
	stats.fairBar:Update(lo, hi, cur, true)

	local frac = (cur - lo) / (hi - lo)
	local word, cr, cg, cb
	if frac <= 0.25 then
		word, cr, cg, cb = L["Cheap"], C.Bull[1], C.Bull[2], C.Bull[3]
	elseif frac >= 0.75 then
		word, cr, cg, cb = L["Expensive"], C.Bear[1], C.Bear[2], C.Bear[3]
	else
		word, cr, cg, cb = L["Fair value"], C.Neutral[1], C.Neutral[2], C.Neutral[3]
	end
	local pctAbove = (lo ~= 0) and ((cur - lo) / lo * 100) or 0
	stats.fairVerdict:SetText(format("%s  \194\183  %d%% %s", word, F.Round(pctAbove), L["above 30-day low"]))
	stats.fairVerdict:SetTextColor(cr, cg, cb)
end

local function refreshStrip(container, cells, values, labels)
	local w = container:GetWidth()
	if w <= 0 then
		return false
	end
	local n = #cells
	local cellW = w / n

	-- Find min/max across populated buckets for the heat scale.
	local lo, hi = math.huge, -math.huge
	for i = 0, n - 1 do
		local v = values[i]
		if v then
			if v < lo then
				lo = v
			end
			if v > hi then
				hi = v
			end
		end
	end
	local span = (hi > lo) and (hi - lo) or 1

	for i = 0, n - 1 do
		local cell = cells[i + 1]
		cell:ClearAllPoints()
		cell:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", i * cellW + 1, 14)
		cell:SetSize(cellW - 2, container:GetHeight() - 16)
		local v = values[i]
		if v then
			local frac = (v - lo) / span
			cell.bg:SetColorTexture(heatColor(frac))
			cell.bg:SetAlpha(0.85)
			cell.value = v
		else
			local p = ns:Palette()
			cell.bg:SetColorTexture(p.border[1], p.border[2], p.border[3])
			cell.bg:SetAlpha(0.18)
			cell.value = nil
		end
		cell.tip = labels[i + 1]
	end
	return true
end

local function refresh()
	local s = ns.Analysis:Stats()

	setVal(stats.rows.current, F.FormatGold(s.current))
	if s.current then
		local r, g, b = F.TrendColor(s.changeAbs)
		setVal(stats.rows.current, F.FormatGold(s.current), r, g, b)
	end

	if s.changeAbs and s.changeAbs ~= 0 then
		local r, g, b = F.TrendColor(s.changeAbs)
		setVal(stats.rows.change, format("%s%s (%s)", s.changeAbs > 0 and "+" or "", F.FormatGold(math.abs(s.changeAbs)), F.FormatPct(s.changePct)), r, g, b)
	else
		setVal(stats.rows.change, L["No change"], C.Neutral[1], C.Neutral[2], C.Neutral[3])
	end

	-- Key Data: previous (calendar-day) close + today's low-high range.
	setVal(stats.rows.prevClose, F.FormatGold(s.prevClose))
	setVal(stats.rows.dayRange, (s.dayLow and s.dayHigh)
		and format("%s - %s", F.FormatGold(s.dayLow), F.FormatGold(s.dayHigh)) or nil)

	setVal(stats.rows.low7, F.FormatGold(s.low7), C.Bull[1], C.Bull[2], C.Bull[3])
	setVal(stats.rows.high7, F.FormatGold(s.high7), C.Bear[1], C.Bear[2], C.Bear[3])
	setVal(stats.rows.avg7, F.FormatGold(s.avg7))
	setVal(stats.rows.low30, F.FormatGold(s.low30), C.Bull[1], C.Bull[2], C.Bull[3])
	setVal(stats.rows.high30, F.FormatGold(s.high30), C.Bear[1], C.Bear[2], C.Bear[3])
	setVal(stats.rows.avg30, F.FormatGold(s.avg30))
	setVal(stats.rows.lowAll, F.FormatGold(s.lowAll), C.Bull[1], C.Bull[2], C.Bull[3])
	setVal(stats.rows.highAll, F.FormatGold(s.highAll), C.Bear[1], C.Bear[2], C.Bear[3])
	setVal(stats.rows.samples, tostring(s.samples))
	setVal(stats.rows.since, s.since and F.DateString(s.since) or "\226\128\148")

	updateFairValue(s)

	-- Volatility heatmaps. Need at least a little history to be meaningful.
	if s.samples < 6 then
		stats.empty:Show()
		stats.hourStrip:Hide()
		stats.weekStrip:Hide()
		stats.hourTitle:Hide()
		stats.weekTitle:Hide()
		stats.bestText:Hide()
		return
	end
	stats.empty:Hide()
	stats.hourStrip:Show()
	stats.weekStrip:Show()
	stats.hourTitle:Show()
	stats.weekTitle:Show()
	stats.bestText:Show()

	if stats.hourStrip:GetWidth() <= 0 then
		C_Timer.After(0, refresh)
		return
	end

	local hours = ns.Analysis:VolatilityByHour()
	local hourLabels = {}
	for i = 0, 23 do
		hourLabels[i + 1] = format("%02d:00", i)
	end
	refreshStrip(stats.hourStrip, stats.hourCells, hours, hourLabels)

	local days = ns.Analysis:VolatilityByWeekday()
	local dayLabels = {}
	for i = 0, 6 do
		dayLabels[i + 1] = L["DAY_" .. (i + 1)]
	end
	refreshStrip(stats.weekStrip, stats.weekCells, days, dayLabels)

	-- Cheapest hour + day callout.
	local bestHour, bestHourVal
	for i = 0, 23 do
		if hours[i] and (not bestHourVal or hours[i] < bestHourVal) then
			bestHourVal, bestHour = hours[i], i
		end
	end
	local bestDay, bestDayVal
	for i = 0, 6 do
		if days[i] and (not bestDayVal or days[i] < bestDayVal) then
			bestDayVal, bestDay = days[i], i
		end
	end
	if bestHour and bestDay then
		stats.bestText:SetText(format("%s: %s %02d:00  \194\183  ~%s", L["Best time to buy"], L["DAY_" .. (bestDay + 1)], bestHour, F.FormatGold(F.Round(bestHourVal))))
	else
		stats.bestText:SetText("")
	end
end
stats.refresh = refresh

-- ---------------------------------------------------------------------------
-- Build the Stats tab
-- ---------------------------------------------------------------------------
local function buildStrip(parent, count)
	local container = CreateFrame("Frame", nil, parent)
	local cells = {}
	for i = 1, count do
		local cell = CreateFrame("Frame", nil, container)
		cell.bg = cell:CreateTexture(nil, "ARTWORK")
		cell.bg:SetAllPoints()
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", function(self)
			if not self.value then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.tip)
			GameTooltip:AddLine(F.FormatGold(F.Round(self.value)), 1, 1, 1)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", GameTooltip_Hide or function()
			GameTooltip:Hide()
		end)
		cells[i] = cell
	end
	return container, cells
end

local function build(panel)
	-- Left column: metrics --------------------------------------------------
	local left = CreateFrame("Frame", nil, panel)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(250)

	local heading = UI:Text(left, "OVERLAY", C.Font, 13, "", "accent")
	heading:SetShadowOffset(1, -1)
	heading:SetPoint("TOPLEFT", 2, -2)
	heading:SetText(L["Stats"])

	stats.rows = {}
	local r = makeRow(left, heading, L["Current Price"])
	stats.rows.current = r
	r = makeRow(left, r.anchor, L["Change"])
	stats.rows.change = r
	r = makeRow(left, r.anchor, L["Previous Close"])
	stats.rows.prevClose = r
	r = makeRow(left, r.anchor, L["Day Range"])
	stats.rows.dayRange = r
	r = makeRow(left, r.anchor, L["7-Day Low"])
	stats.rows.low7 = r
	r = makeRow(left, r.anchor, L["7-Day High"])
	stats.rows.high7 = r
	r = makeRow(left, r.anchor, L["7-Day Avg"])
	stats.rows.avg7 = r
	r = makeRow(left, r.anchor, L["30-Day Low"])
	stats.rows.low30 = r
	r = makeRow(left, r.anchor, L["30-Day High"])
	stats.rows.high30 = r
	r = makeRow(left, r.anchor, L["30-Day Avg"])
	stats.rows.avg30 = r
	r = makeRow(left, r.anchor, L["All-Time Low"])
	stats.rows.lowAll = r
	r = makeRow(left, r.anchor, L["All-Time High"])
	stats.rows.highAll = r
	r = makeRow(left, r.anchor, L["Samples"])
	stats.rows.samples = r
	r = makeRow(left, r.anchor, L["Tracking since"])
	stats.rows.since = r

	-- Divider.
	local divider = panel:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 8, 0)
	divider:SetWidth(1)
	UI:OnTheme(function(p)
		divider:SetColorTexture(p.border[1], p.border[2], p.border[3], 0.8)
	end)

	-- Right column: volatility ----------------------------------------------
	local right = CreateFrame("Frame", nil, panel)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 18, 0)
	right:SetPoint("BOTTOMRIGHT")

	stats.hourTitle = UI:Text(right, "OVERLAY", C.Font, 13, "", "accent")
	stats.hourTitle:SetShadowOffset(1, -1)
	stats.hourTitle:SetPoint("TOPLEFT", 0, -2)
	stats.hourTitle:SetText(L["Cheapest hours of the day"])

	local hourStrip, hourCells = buildStrip(right, 24)
	-- Top-left tracks the title; right edge spans to the panel. Fixed height.
	hourStrip:SetPoint("TOPLEFT", stats.hourTitle, "BOTTOMLEFT", 0, -8)
	hourStrip:SetPoint("RIGHT", right, "RIGHT", 0, 0)
	hourStrip:SetHeight(74)
	stats.hourStrip, stats.hourCells = hourStrip, hourCells

	-- Hour ticks (every 6h). Positioned for real in layoutTicks (needs strip
	-- width); we just create + stash them here.
	stats.hourTicks = {}
	for _, hr in ipairs({ 0, 6, 12, 18 }) do
		local t = UI:Text(right, "OVERLAY", C.Font, 9, "", "muted")
		t:SetText(format("%02d", hr))
		t.__hr = hr
		stats.hourTicks[#stats.hourTicks + 1] = t
	end

	stats.weekTitle = UI:Text(right, "OVERLAY", C.Font, 13, "", "accent")
	stats.weekTitle:SetShadowOffset(1, -1)
	stats.weekTitle:SetPoint("TOPLEFT", hourStrip, "BOTTOMLEFT", 0, -22)
	stats.weekTitle:SetText(L["Cheapest days of the week"])

	local weekStrip, weekCells = buildStrip(right, 7)
	weekStrip:SetPoint("TOPLEFT", stats.weekTitle, "BOTTOMLEFT", 0, -8)
	weekStrip:SetPoint("RIGHT", right, "RIGHT", 0, 0)
	weekStrip:SetHeight(50)
	stats.weekStrip, stats.weekCells = weekStrip, weekCells

	-- Weekday labels under each cell.
	stats.weekTicks = {}
	for i = 0, 6 do
		local t = UI:Text(right, "OVERLAY", C.Font, 9, "", "muted")
		t:SetText(L["DAY_" .. (i + 1)])
		stats.weekTicks[i + 1] = t
	end

	stats.bestText = UI:Text(right, "OVERLAY", C.Font, 12, "", "text")
	stats.bestText:SetShadowOffset(1, -1)
	stats.bestText:SetPoint("TOPLEFT", weekStrip, "BOTTOMLEFT", 0, -16)

	-- Valuation: where the current price sits inside the 30-day range.
	stats.fairTitle = UI:Text(right, "OVERLAY", C.Font, 13, "", "accent")
	stats.fairTitle:SetShadowOffset(1, -1)
	stats.fairTitle:SetPoint("TOPLEFT", stats.bestText, "BOTTOMLEFT", 0, -18)
	stats.fairTitle:SetText(L["30-Day Range"])

	stats.fairBar = UI:RangeBar(right)
	stats.fairBar.frame:SetPoint("TOPLEFT", stats.fairTitle, "BOTTOMLEFT", 0, -10)
	stats.fairBar.frame:SetWidth(420) -- refined to the column width in layoutTicks

	stats.fairVerdict = UI:Text(right, "OVERLAY", C.Font, 12, "", "text")
	stats.fairVerdict:SetShadowOffset(1, -1)
	stats.fairVerdict:SetPoint("TOPLEFT", stats.fairBar.frame, "BOTTOMLEFT", 0, -6)

	stats.empty = UI:Text(right, "OVERLAY", C.Font, 12, "", "muted")
	stats.empty:SetShadowOffset(1, -1)
	stats.empty:SetPoint("TOPLEFT", stats.hourTitle, "BOTTOMLEFT", 0, -20)
	stats.empty:SetWidth(360)
	stats.empty:SetJustifyH("LEFT")
	stats.empty:SetText(L["Not enough history yet. Keep playing - data builds over time."])

	-- Position weekday labels after layout (needs strip width).
	stats.layoutTicks = function()
		local w = weekStrip:GetWidth()
		if w <= 0 then
			return
		end
		local cw = w / 7
		for i = 0, 6 do
			local t = stats.weekTicks[i + 1]
			t:ClearAllPoints()
			t:SetPoint("TOP", weekStrip, "BOTTOMLEFT", (i + 0.5) * cw, -2)
		end
		local hw = hourStrip:GetWidth()
		local hcw = hw / 24
		for _, t in ipairs(stats.hourTicks) do
			t:ClearAllPoints()
			t:SetPoint("TOP", hourStrip, "BOTTOMLEFT", (t.__hr + 0.5) * hcw, -2)
		end

		local rw = right:GetWidth()
		if rw > 0 then
			stats.fairBar.frame:SetWidth(rw)
		end
	end

	return function()
		refresh()
		if stats.layoutTicks then
			stats.layoutTicks()
		end
	end
end

tinsert(UI.tabDefs, { id = "stats", label = L["Stats"], build = build })
