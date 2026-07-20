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
local chart = { layoutPending = false }

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
	UI:StyleButtonToggle(chart.btnLine, ns.db.chartMode == "line")
	UI:StyleButtonToggle(chart.btnCandle, ns.db.chartMode == "candle")
	UI:StyleButtonToggle(chart.btnMA7, ns.db.showMA7)
	UI:StyleButtonToggle(chart.btnMA30, ns.db.showMA30)
	UI:StyleButtonToggle(chart.btnHour, ns.db.candleGroup == "hour")
	UI:StyleButtonToggle(chart.btnDay, ns.db.candleGroup == "day")
	for days, btn in pairs(chart.rangeBtns) do
		UI:StyleButtonToggle(btn, ns.db.rangeDays == days)
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
	chart.buyBanner:SetShown(low and hasData)

	local high = false
	if ns.db.alertOn30dHigh then
		high = ns.Analysis:Is30DayHigh()
	end
	-- Buy takes priority if both somehow qualify (tolerance overlap on a flat range).
	chart.sellBanner:SetShown(high and hasData and not low)

	-- MA legend only in line mode when at least one MA is on.
	local showLegend = ns.db.chartMode == "line" and (ns.db.showMA7 or ns.db.showMA30)
	chart.legend:SetShown(showLegend and hasData)
	if chart.refreshLegend then
		chart.refreshLegend()
	end

	if not hasData then
		-- Distinguish "no price ever" from "nothing in this time range".
		chart.empty:SetText(#h == 0 and L["Waiting for first price..."] or L["No data in the selected range."])
		chart.empty:Show()
		-- Offer the import shortcut only when the whole history is empty, not when
		-- the current range filter just happens to hide existing data.
		if chart.emptyImport then
			chart.emptyImport:SetShown(#h == 0)
		end
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
	if chart.emptyImport then
		chart.emptyImport:Hide()
	end
	-- While history is sparse, explain why the chart looks flat/short.
	chart.hint:SetShown(nInRange < 3)

	-- Plot rect may not be laid out yet on the very first open; defer a frame.
	if chart.plot:GetWidth() <= 0 then
		if not chart.layoutPending then
			chart.layoutPending = true
			C_Timer.After(0, function()
				chart.layoutPending = false
				refresh()
			end)
		end
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
	chart.empty:SetPoint("CENTER", 0, 10)
	chart.empty:SetText(L["Waiting for first price..."])

	-- Import shortcut, shown under the empty message so a brand-new user with a
	-- blank chart has an obvious next step instead of just waiting.
	chart.emptyImport = UI:Button(plotArea, L["Import History"], 130, function()
		ns:OpenImport()
	end)
	chart.emptyImport:SetPoint("TOP", chart.empty, "BOTTOM", 0, -10)
	chart.emptyImport:Hide()
	UI:SetTooltip(chart.emptyImport, L["Import History"], L["Seed the chart with history from kkthnx.com/wow/token."])

	-- Sparse-history hint, tucked along the bottom of the plot.
	chart.hint = UI:Text(plotArea, "OVERLAY", C.Font, 11, "", "muted")
	chart.hint:SetPoint("BOTTOM", plot, "BOTTOM", 0, 6)
	chart.hint:SetText(L["Collecting price history - the chart fills in as new prices are recorded."])
	chart.hint:Hide()

	-- Buy-signal banner (NASDAQ-style callout at a 30-day low).
	local buyBanner = CreateFrame("Frame", nil, plotArea, "BackdropTemplate")
	buyBanner:SetBackdrop(UI.BACKDROP)
	buyBanner:SetPoint("TOP", plot, "TOP", 0, -4)
	buyBanner:SetSize(220, 22)
	buyBanner:SetFrameLevel(plotArea:GetFrameLevel() + 10)
	buyBanner:Hide()
	local buyArrow = buyBanner:CreateTexture(nil, "OVERLAY")
	buyArrow:SetSize(24, 24)
	buyArrow:SetPoint("LEFT", 8, 1)
	F.SetArrow(buyArrow, true)
	buyArrow:SetVertexColor(1, 1, 1)
	local buyText = buyBanner:CreateFontString(nil, "OVERLAY")
	buyText:SetFont(C.Font, 12, "")
	buyText:SetShadowOffset(1, -1)
	buyText:SetPoint("LEFT", buyArrow, "RIGHT", 4, -1)
	buyText:SetText(L["BUY SIGNAL"] .. "  " .. F.Sep .. "  " .. L["At or near a 30-day low. Good time to buy."])
	buyText:SetTextColor(1, 1, 1)
	buyBanner:SetWidth(buyText:GetStringWidth() + 40)
	UI:OnTheme(function()
		buyBanner:SetBackdropColor(C.Bull[1], C.Bull[2], C.Bull[3], 0.9)
		buyBanner:SetBackdropBorderColor(C.Bull[1], C.Bull[2], C.Bull[3], 1)
	end)
	chart.buyBanner = buyBanner

	-- Sell-signal banner (symmetric: near a 30-day high).
	local sellBanner = CreateFrame("Frame", nil, plotArea, "BackdropTemplate")
	sellBanner:SetBackdrop(UI.BACKDROP)
	sellBanner:SetPoint("TOP", plot, "TOP", 0, -4)
	sellBanner:SetSize(220, 22)
	sellBanner:SetFrameLevel(plotArea:GetFrameLevel() + 10)
	sellBanner:Hide()
	local sellArrow = sellBanner:CreateTexture(nil, "OVERLAY")
	sellArrow:SetSize(24, 24)
	sellArrow:SetPoint("LEFT", 8, 1)
	F.SetArrow(sellArrow, false)
	sellArrow:SetVertexColor(1, 1, 1)
	local sellText = sellBanner:CreateFontString(nil, "OVERLAY")
	sellText:SetFont(C.Font, 12, "")
	sellText:SetShadowOffset(1, -1)
	sellText:SetPoint("LEFT", sellArrow, "RIGHT", 4, -1)
	sellText:SetText(L["SELL SIGNAL"] .. "  " .. F.Sep .. "  " .. L["At or near a 30-day high. Good time to sell."])
	sellText:SetTextColor(1, 1, 1)
	sellBanner:SetWidth(sellText:GetStringWidth() + 40)
	UI:OnTheme(function()
		sellBanner:SetBackdropColor(C.Bear[1], C.Bear[2], C.Bear[3], 0.9)
		sellBanner:SetBackdropBorderColor(C.Bear[1], C.Bear[2], C.Bear[3], 1)
	end)
	chart.sellBanner = sellBanner

	-- Line-chart legend (price + moving averages).
	local legend = CreateFrame("Frame", nil, plotArea)
	legend:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 2)
	legend:SetHeight(14)
	legend:Hide()
	chart.legend = legend
	local legendItems = {
		{ label = L["Price"], color = function() return ns:Palette().accent end, always = true },
		{ label = L["MA7"], color = function() return MA7_COLOR end, key = "showMA7" },
		{ label = L["MA30"], color = function() return MA30_COLOR end, key = "showMA30" },
	}
	local prevDot
	for i, item in ipairs(legendItems) do
		local row = CreateFrame("Frame", nil, legend)
		row:SetHeight(14)
		if prevDot then
			row:SetPoint("LEFT", prevDot, "RIGHT", 10, 0)
		else
			row:SetPoint("LEFT", 0, 0)
		end
		local dot = row:CreateTexture(nil, "ARTWORK")
		dot:SetSize(8, 8)
		dot:SetPoint("LEFT", 0, 0)
		row.dot = dot
		row.key = item.key
		local lbl = row:CreateFontString(nil, "OVERLAY")
		lbl:SetFont(C.Font, 10, "")
		lbl:SetPoint("LEFT", dot, "RIGHT", 4, 0)
		lbl:SetText(item.label)
		row.label = lbl
		UI:OnTheme(function(p)
			local c = item.color()
			dot:SetColorTexture(c[1], c[2], c[3], 1)
			lbl:SetTextColor(p.muted[1], p.muted[2], p.muted[3])
		end)
		prevDot = row
		chart["legendRow" .. i] = row
	end
	chart.refreshLegend = function()
		for i, item in ipairs(legendItems) do
			local row = chart["legendRow" .. i]
			if row then
				local show = item.always or (item.key and ns.db[item.key])
				row:SetShown(show)
			end
		end
	end

	-- Hover layer ------------------------------------------------------------
	Hover.Install(chart, plot, plotArea)

	return refresh
end

-- Register the tab (Main builds it lazily).
tinsert(UI.tabDefs, { id = "chart", label = L["Chart"], tip = L["Price over time with moving averages and candlesticks."], build = build })
