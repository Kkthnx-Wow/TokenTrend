-- ---------------------------------------------------------------------------
-- TokenTrend - Chart tab: line chart (LibGraph) + candlesticks (textures).
-- ---------------------------------------------------------------------------
-- Two render routes, both wired up:
--   * Line mode uses LibGraph-2.0 to plot price + moving averages.
--   * Candle mode is hand-rolled from pooled Texture rectangles (axis-aligned,
--     so no rotation math - candles are honest vertical bars).

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F
local UI = ns.UI

local Graph = LibStub and LibStub("LibGraph-2.0", true)
local Hover = UI.ChartHover

local floor = math.floor
local max = math.max
local min = math.min
local abs = math.abs
local format = string.format
local unpack = unpack -- hot: called per candle in the render loop

-- Plot insets: room for the price gutter (left) and date axis (bottom).
local GUTTER_L, GUTTER_B, PAD_T, PAD_R = 54, 18, 16, 10

-- Moving-average line colors (price itself uses the palette accent).
local MA7_COLOR = { 0.98, 0.72, 0.18, 1 } -- amber
local MA30_COLOR = { 0.58, 0.64, 0.72, 1 } -- slate

-- ---------------------------------------------------------------------------
-- Local chart state (built once)
-- ---------------------------------------------------------------------------
local chart = {}

local function styleToggle(btn, active)
	local p = ns:Palette()
	if active then
		btn.label:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
		btn:SetBackdropBorderColor(p.accent[1], p.accent[2], p.accent[3], 1)
		btn:SetBackdropColor(p.accent[1], p.accent[2], p.accent[3], 0.18)
	else
		btn.label:SetTextColor(p.text[1], p.text[2], p.text[3])
		btn:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
		btn:SetBackdropColor(p.panel[1], p.panel[2], p.panel[3], 1)
	end
end

-- ---------------------------------------------------------------------------
-- Coordinate mapping inside the plot rect
-- ---------------------------------------------------------------------------
local function valueToY(plotH, v, vmin, vmax)
	if vmax <= vmin then
		return plotH * 0.5
	end
	return (v - vmin) / (vmax - vmin) * plotH
end

-- ---------------------------------------------------------------------------
-- Axis labels
-- ---------------------------------------------------------------------------
local function updateAxisLabels(vmin, vmax, tStart, tEnd)
	-- Y: 5 evenly spaced price labels mapped to the plot height.
	local plotH = chart.plot:GetHeight()
	for i = 1, 5 do
		local frac = (i - 1) / 4
		local v = vmin + (vmax - vmin) * frac
		local fs = chart.yLabels[i]
		fs:SetText(F.FormatGoldShort(F.Round(v)))
		fs:ClearAllPoints()
		fs:SetPoint("RIGHT", chart.plot, "BOTTOMLEFT", -4, plotH * frac)
	end
	-- X: oldest (left) / midpoint / newest (right).
	chart.xLabels[1]:SetText(F.DateString(tStart))
	chart.xLabels[2]:SetText(F.DateString(floor((tStart + tEnd) / 2)))
	chart.xLabels[3]:SetText(F.DateString(tEnd))
end

-- ---------------------------------------------------------------------------
-- Line mode (LibGraph). LibGraph wants { {x, y}, ... }; we use days-from-start
-- for X so the numbers stay small and the grid math stays sane.
-- ---------------------------------------------------------------------------
local function renderLine(h, lo, hi)
	local g = chart.graph
	if not g then
		return false
	end
	g:ResetData()

	local t0 = h[lo].t
	local tEnd = h[hi].t
	local p = ns:Palette()

	-- Collect everything we'll plot so the Y axis frames all of it.
	local vmin, vmax = math.huge, -math.huge
	local function track(series, a, b)
		for i = a, b do
			local v = series[i].p
			if v < vmin then
				vmin = v
			end
			if v > vmax then
				vmax = v
			end
		end
	end
	track(h, lo, hi)

	-- Price series (downsampled so we don't draw thousands of segments).
	local priceSlice = ns.Analysis:Resample(h, lo, hi, 150)
	local pricePts = {}
	for i = 1, #priceSlice do
		pricePts[#pricePts + 1] = { (priceSlice[i].t - t0) / 86400, priceSlice[i].p }
	end

	-- Moving averages computed over full history, then clipped to the window.
	local ma7Pts, ma30Pts
	if ns.db.showMA7 then
		local ma = ns.Analysis:MovingAverage(7)
		track(ma, lo, hi)
		local slice = ns.Analysis:Resample(ma, lo, hi, 150)
		ma7Pts = {}
		for i = 1, #slice do
			ma7Pts[#ma7Pts + 1] = { (slice[i].t - t0) / 86400, slice[i].p }
		end
	end
	if ns.db.showMA30 then
		local ma = ns.Analysis:MovingAverage(30)
		track(ma, lo, hi)
		local slice = ns.Analysis:Resample(ma, lo, hi, 150)
		ma30Pts = {}
		for i = 1, #slice do
			ma30Pts[#ma30Pts + 1] = { (slice[i].t - t0) / 86400, slice[i].p }
		end
	end

	-- Pad the value range ~4% so lines don't kiss the frame edges.
	local span = max(vmax - vmin, 1)
	vmin = vmin - span * 0.04
	vmax = vmax + span * 0.04

	-- One sample so far? A single point can't be a line, so draw it as a flat
	-- reference line across the plot. It's honest (price hasn't moved yet for
	-- us) and far friendlier than an empty box.
	local xmax
	if #pricePts >= 2 then
		xmax = max((tEnd - t0) / 86400, 0.01)
	else
		pricePts[2] = { 1, pricePts[1][2] }
		xmax = 1
	end
	g:SetXAxis(0, xmax)
	g:SetYAxis(vmin, vmax)
	g:SetGridSpacing(max(xmax / 6, 0.001), (vmax - vmin) / 4)
	g:SetAxisColor({ p.border[1], p.border[2], p.border[3], 0.9 })
	g:SetGridColor({ p.border[1], p.border[2], p.border[3], 0.18 })

	-- Draw MAs first (underneath), price on top.
	if ma30Pts and #ma30Pts >= 2 then
		g:AddDataSeries(ma30Pts, MA30_COLOR)
	end
	if ma7Pts and #ma7Pts >= 2 then
		g:AddDataSeries(ma7Pts, MA7_COLOR)
	end
	g:AddDataSeries(pricePts, { p.accent[1], p.accent[2], p.accent[3], 1 })

	updateAxisLabels(vmin, vmax, t0, tEnd)

	-- Stash what the hover crosshair needs to map cursor -> nearest data point.
	-- vmin/vmax are the *padded* values fed to SetYAxis, so the marker lands
	-- exactly on the plotted line.
	chart.hoverData = {
		mode = "line",
		h = h,
		lo = lo,
		hi = hi,
		t0 = t0,
		xmax = xmax,
		vmin = vmin,
		vmax = vmax,
	}
	chart.hoverKey = nil -- force the readout to rebuild if we re-render mid-hover
	return true, vmin, vmax
end

-- ---------------------------------------------------------------------------
-- Candle mode (pooled textures)
-- ---------------------------------------------------------------------------
local function renderCandles(candles)
	local plot = chart.plot
	local plotW, plotH = plot:GetWidth(), plot:GetHeight()
	chart.candlePool:ReleaseAll()

	-- Fit as many recent candles as the width allows (min ~3px per slot).
	local maxFit = max(floor(plotW / 3), 1)
	local startIdx = max(#candles - maxFit + 1, 1)
	local n = #candles - startIdx + 1
	if n < 1 then
		return false
	end

	local vmin, vmax = math.huge, -math.huge
	for i = startIdx, #candles do
		if candles[i].l < vmin then
			vmin = candles[i].l
		end
		if candles[i].h > vmax then
			vmax = candles[i].h
		end
	end
	local span = max(vmax - vmin, 1)
	vmin = vmin - span * 0.04
	vmax = vmax + span * 0.04

	local slot = plotW / n
	local bodyW = max(slot * 0.62, 1)

	for k = 0, n - 1 do
		local cd = candles[startIdx + k]
		local xc = (k + 0.5) * slot
		local bull = cd.c >= cd.o
		local r, g, b = unpack(bull and C.Bull or C.Bear)

		-- Wick: thin full-range line.
		local wick = chart.candlePool:Acquire()
		wick:SetColorTexture(r, g, b, 0.9)
		local yLow = valueToY(plotH, cd.l, vmin, vmax)
		local yHigh = valueToY(plotH, cd.h, vmin, vmax)
		wick:SetSize(max(slot * 0.12, 1), max(yHigh - yLow, 1))
		wick:ClearAllPoints()
		wick:SetPoint("BOTTOM", plot, "BOTTOMLEFT", xc, yLow)

		-- Body: open->close rectangle.
		local body = chart.candlePool:Acquire()
		body:SetColorTexture(r, g, b, 1)
		local yo = valueToY(plotH, cd.o, vmin, vmax)
		local yc = valueToY(plotH, cd.c, vmin, vmax)
		local bottom = min(yo, yc)
		body:SetSize(bodyW, max(abs(yc - yo), 1.5))
		body:ClearAllPoints()
		body:SetPoint("BOTTOM", plot, "BOTTOMLEFT", xc, bottom)
	end

	updateAxisLabels(vmin, vmax, candles[startIdx].t, candles[#candles].t)

	chart.hoverData = {
		mode = "candle",
		candles = candles,
		startIdx = startIdx,
		n = n,
		vmin = vmin,
		vmax = vmax,
		group = ns.db.candleGroup,
	}
	chart.hoverKey = nil
	return true
end

-- ---------------------------------------------------------------------------
-- Refresh dispatcher
-- ---------------------------------------------------------------------------
local function refresh()
	-- Sync toggle button styling with current settings.
	styleToggle(chart.btnLine, ns.db.chartMode == "line")
	styleToggle(chart.btnCandle, ns.db.chartMode == "candle")
	styleToggle(chart.btnMA7, ns.db.showMA7)
	styleToggle(chart.btnMA30, ns.db.showMA30)
	styleToggle(chart.btnHour, ns.db.candleGroup == "hour")
	styleToggle(chart.btnDay, ns.db.candleGroup == "day")
	for days, btn in pairs(chart.rangeBtns) do
		styleToggle(btn, ns.db.rangeDays == days)
	end
	-- MA toggles only make sense in line mode; group toggles only in candle.
	chart.btnMA7:SetShown(ns.db.chartMode == "line")
	chart.btnMA30:SetShown(ns.db.chartMode == "line")
	chart.btnHour:SetShown(ns.db.chartMode == "candle")
	chart.btnDay:SetShown(ns.db.chartMode == "candle")

	local h, lo, hi = ns.Analysis:Slice(ns.db.rangeDays)
	-- One point is enough to plot now (line mode draws it as a flat reference).
	local nInRange = (hi >= lo) and (hi - lo + 1) or 0
	local hasData = nInRange >= 1

	-- Buy-signal banner.
	local low = false
	if ns.db.alertOn30dLow then
		low = ns.Analysis:Is30DayLow()
	end
	chart.banner:SetShown(low and hasData)

	if not hasData then
		-- Distinguish "no price ever" from "nothing in this time range".
		chart.empty:SetText(#h == 0 and L["Waiting for first price..."] or L["No data in the selected range."])
		chart.empty:Show()
		chart.hint:Hide()
		chart.graph:Hide()
		chart.candlePool:ReleaseAll()
		chart.hoverData = nil
		Hover.Hide(chart)
		for i = 1, 5 do
			chart.yLabels[i]:SetText("")
		end
		for i = 1, 3 do
			chart.xLabels[i]:SetText("")
		end
		return
	end
	chart.empty:Hide()
	-- While history is sparse, explain why the chart looks flat/short.
	chart.hint:SetShown(nInRange < 3)

	-- Plot rect may not be laid out yet on the very first open; defer a frame.
	if chart.plot:GetWidth() <= 0 then
		C_Timer.After(0, refresh)
		return
	end

	if ns.db.chartMode == "candle" then
		chart.graph:Hide()
		renderCandles(ns.Analysis:Candles(ns.db.candleGroup, ns.db.rangeDays))
	else
		chart.candlePool:ReleaseAll()
		chart.graph:Show()
		renderLine(h, lo, hi)
	end
end
chart.refresh = refresh

-- ---------------------------------------------------------------------------
-- Build the Chart tab
-- ---------------------------------------------------------------------------
local function build(panel)
	-- Controls row -----------------------------------------------------------
	local controls = CreateFrame("Frame", nil, panel)
	controls:SetPoint("TOPLEFT")
	controls:SetPoint("TOPRIGHT")
	controls:SetHeight(24)

	local function set(key, value)
		return function()
			ns:SetSetting(key, value)
		end
	end

	chart.btnLine = UI:Button(controls, L["Line"], 60, set("chartMode", "line"))
	chart.btnLine:SetPoint("LEFT", 0, 0)
	UI:SetTooltip(chart.btnLine, L["Line"], L["Draw price as a line over time."])
	chart.btnCandle = UI:Button(controls, L["Candles"], 66, set("chartMode", "candle"))
	chart.btnCandle:SetPoint("LEFT", chart.btnLine, "RIGHT", 4, 0)
	UI:SetTooltip(chart.btnCandle, L["Candles"], L["Draw open/high/low/close candlesticks."])

	chart.btnMA7 = UI:Button(controls, L["MA7"], 48, function()
		ns:SetSetting("showMA7", not ns.db.showMA7)
	end)
	chart.btnMA7:SetPoint("LEFT", chart.btnCandle, "RIGHT", 12, 0)
	UI:SetTooltip(chart.btnMA7, L["MA7"], L["Toggle the 7-day moving average overlay."])
	chart.btnMA30 = UI:Button(controls, L["MA30"], 54, function()
		ns:SetSetting("showMA30", not ns.db.showMA30)
	end)
	chart.btnMA30:SetPoint("LEFT", chart.btnMA7, "RIGHT", 4, 0)
	UI:SetTooltip(chart.btnMA30, L["MA30"], L["Toggle the 30-day moving average overlay."])

	chart.btnHour = UI:Button(controls, L["Hourly"], 60, set("candleGroup", "hour"))
	chart.btnHour:SetPoint("LEFT", chart.btnCandle, "RIGHT", 12, 0)
	UI:SetTooltip(chart.btnHour, L["Hourly"], L["Group candles into one-hour buckets."])
	chart.btnDay = UI:Button(controls, L["Daily"], 54, set("candleGroup", "day"))
	chart.btnDay:SetPoint("LEFT", chart.btnHour, "RIGHT", 4, 0)
	UI:SetTooltip(chart.btnDay, L["Daily"], L["Group candles into one-day buckets."])

	-- Range buttons, right-aligned.
	chart.rangeBtns = {}
	local ranges = { { 7, L["7D"] }, { 30, L["30D"] }, { 90, L["90D"] }, { 0, L["All"] } }
	local prev
	for i = #ranges, 1, -1 do
		local days, lbl = ranges[i][1], ranges[i][2]
		local b = UI:Button(controls, lbl, 42, set("rangeDays", days))
		if prev then
			b:SetPoint("RIGHT", prev, "LEFT", -4, 0)
		else
			b:SetPoint("RIGHT", 0, 0)
		end
		prev = b
		chart.rangeBtns[days] = b
		UI:SetTooltip(b, lbl, days > 0 and format(L["Show the last %d days."], days) or L["Show the entire recorded history."])
	end

	-- Plot area --------------------------------------------------------------
	local plotArea = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	plotArea:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -6)
	plotArea:SetPoint("BOTTOMRIGHT")
	UI:Skin(plotArea, "plot")
	chart.plotArea = plotArea

	-- The actual data rect, inset for axis gutters.
	local plot = CreateFrame("Frame", nil, plotArea)
	plot:SetPoint("TOPLEFT", GUTTER_L, -PAD_T)
	plot:SetPoint("BOTTOMRIGHT", -PAD_R, GUTTER_B)
	plot:SetClipsChildren(true)
	chart.plot = plot

	-- LibGraph instance lives inside the plot rect.
	if Graph then
		local g = Graph:CreateGraphLine(nil, plot, "TOPLEFT", "TOPLEFT", 0, 0, 100, 100)
		g:ClearAllPoints()
		g:SetAllPoints(plot)
		g:SetXAxis(0, 1)
		g:SetYAxis(0, 1)
		chart.graph = g
	else
		-- LibGraph missing? Make a dummy so refresh() never nil-errors.
		chart.graph = CreateFrame("Frame", nil, plot)
		chart.graph.ResetData = function() end
		chart.graph.SetXAxis = function() end
		chart.graph.SetYAxis = function() end
		chart.graph.SetGridSpacing = function() end
		chart.graph.SetAxisColor = function() end
		chart.graph.SetGridColor = function() end
		chart.graph.AddDataSeries = function() end
	end

	-- Candle texture pool.
	chart.candlePool = F.CreatePool(function()
		return plot:CreateTexture(nil, "ARTWORK")
	end, function(t)
		t:Hide()
		t:ClearAllPoints()
	end)
	-- Re-show on acquire is implicit (textures show when SetColorTexture'd), but
	-- be explicit so recycled ones reappear.
	local origAcquire = chart.candlePool.Acquire
	function chart.candlePool:Acquire()
		local t = origAcquire(self)
		t:Show()
		return t
	end

	-- Axis label font strings.
	chart.yLabels = {}
	for i = 1, 5 do
		chart.yLabels[i] = UI:Text(plotArea, "OVERLAY", C.Font, 10, "", "muted")
	end
	chart.xLabels = {}
	for i = 1, 3 do
		local fs = UI:Text(plotArea, "OVERLAY", C.Font, 10, "", "muted")
		fs:SetPoint(i == 1 and "LEFT" or i == 3 and "RIGHT" or "CENTER", plot, i == 1 and "BOTTOMLEFT" or i == 3 and "BOTTOMRIGHT" or "BOTTOM", i == 1 and 0 or i == 3 and 0 or 0, -11)
		chart.xLabels[i] = fs
	end

	-- "No data" message.
	chart.empty = UI:Text(plotArea, "OVERLAY", C.Font, 13, "", "muted")
	chart.empty:SetPoint("CENTER")
	chart.empty:SetText(L["Waiting for first price..."])

	-- Sparse-history hint, tucked along the bottom of the plot.
	chart.hint = UI:Text(plotArea, "OVERLAY", C.Font, 11, "", "muted")
	chart.hint:SetPoint("BOTTOM", plot, "BOTTOM", 0, 6)
	chart.hint:SetText(L["Collecting price history - the chart fills in as new prices are recorded."])
	chart.hint:Hide()

	-- Buy-signal banner across the top of the plot.
	local banner = CreateFrame("Frame", nil, plotArea, "BackdropTemplate")
	banner:SetBackdrop(UI.BACKDROP)
	banner:SetPoint("TOP", plot, "TOP", 0, -4)
	banner:SetSize(220, 22)
	banner:SetFrameLevel(plotArea:GetFrameLevel() + 10)
	banner:Hide()
	local bannerArrow = banner:CreateTexture(nil, "OVERLAY")
	bannerArrow:SetSize(24, 24)
	bannerArrow:SetPoint("LEFT", 8, 1)
	F.SetArrow(bannerArrow, true)
	bannerArrow:SetVertexColor(1, 1, 1)
	local bannerText = banner:CreateFontString(nil, "OVERLAY")
	bannerText:SetFont(C.Font, 12, "")
	bannerText:SetShadowOffset(1, -1)
	bannerText:SetPoint("LEFT", bannerArrow, "RIGHT", 4, -1)
	bannerText:SetText(L["BUY SIGNAL"] .. "  \194\183  " .. L["At or near a 30-day low. Good time to buy."])
	bannerText:SetTextColor(1, 1, 1)
	banner:SetWidth(bannerText:GetStringWidth() + 40)
	UI:OnTheme(function()
		banner:SetBackdropColor(C.Bull[1], C.Bull[2], C.Bull[3], 0.9)
		banner:SetBackdropBorderColor(C.Bull[1], C.Bull[2], C.Bull[3], 1)
	end)
	chart.banner = banner

	-- Hover layer ------------------------------------------------------------
	Hover.Install(chart, plot, plotArea)

	return refresh
end

-- Register the tab (Main builds it lazily).
tinsert(UI.tabDefs, { id = "chart", label = L["Chart"], tip = L["Price over time with moving averages and candlesticks."], build = build })
