-- ---------------------------------------------------------------------------
-- TokenTrend - Chart hover layer: crosshair, marker, and readout tooltip.
-- ---------------------------------------------------------------------------
-- Kept separate from Chart.lua so the main chart file can focus on controls
-- and rendering. This owns the only chart OnUpdate, and it self-arms only while
-- the mouse is over the plot.

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F
local UI = ns.UI

local floor = math.floor
local max = math.max
local format = string.format
local date = date
local GetCursorPosition = GetCursorPosition

local Hover = {}
UI.ChartHover = Hover

-- Binary search for the history index whose timestamp is closest to t.
local function nearestIndex(h, a, b, t)
	if a >= b then
		return a
	end
	local lo, hi = a, b
	while lo < hi do
		local mid = floor((lo + hi) / 2)
		if h[mid].t < t then
			lo = mid + 1
		else
			hi = mid
		end
	end
	if lo > a and (t - h[lo - 1].t) <= (h[lo].t - t) then
		return lo - 1
	end
	return lo
end

function Hover.Hide(chart)
	chart.hoverKey = nil
	if not chart.crossV then
		return
	end
	chart.crossV:Hide()
	chart.marker:Hide()
	chart.tip:Hide()
end

local function showCross(chart, x)
	local p = ns:Palette()
	local plot = chart.plot
	chart.crossV:ClearAllPoints()
	chart.crossV:SetPoint("BOTTOM", plot, "BOTTOMLEFT", x, 0)
	chart.crossV:SetSize(1, plot:GetHeight())
	chart.crossV:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 0.5)
	chart.crossV:Show()
end

local function showMarker(chart, x, y)
	local p = ns:Palette()
	chart.marker:ClearAllPoints()
	chart.marker:SetPoint("CENTER", chart.plot, "BOTTOMLEFT", x, y)
	chart.marker:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 1)
	chart.marker:Show()
end

local function showTip(chart, x, y, title, body)
	local tip = chart.tip
	tip.title:SetText(title)
	tip.body:SetText(body)
	local w = max(tip.title:GetStringWidth(), tip.body:GetStringWidth()) + 16
	local h = tip.title:GetStringHeight() + tip.body:GetStringHeight() + 15
	tip:SetSize(w, h)

	local plot = chart.plot
	local plotW, plotH = plot:GetWidth(), plot:GetHeight()
	local cx = F.Clamp(x, w / 2, plotW - w / 2)
	tip:ClearAllPoints()
	-- Prefer above the point; flip below if it would clip the top.
	if y + h + 14 > plotH then
		tip:SetPoint("TOP", plot, "BOTTOMLEFT", cx, y - 8)
	else
		tip:SetPoint("BOTTOM", plot, "BOTTOMLEFT", cx, y + 12)
	end
	tip:Show()
end

local function onHoverUpdate(plot, chart)
	local data = chart.hoverData
	local width, height = plot:GetWidth(), plot:GetHeight()
	if not data or width <= 0 or not plot:GetLeft() then
		return Hover.Hide(chart)
	end

	local rx = (GetCursorPosition() / plot:GetEffectiveScale()) - plot:GetLeft()
	if rx < 0 or rx > width then
		return Hover.Hide(chart)
	end

	if data.mode == "candle" then
		local n = data.n
		local slot = width / n
		local k = F.Clamp(floor(rx / slot), 0, n - 1)
		-- Still parked on the same candle? Crosshair's already placed - bail out
		-- before any date()/format()/SetText churn. (No per-frame garbage.)
		if chart.hoverKey == k then
			return
		end
		chart.hoverKey = k
		local cd = data.candles[data.startIdx + k]
		if not cd then
			return Hover.Hide(chart)
		end
		local xc = (k + 0.5) * slot
		showCross(chart, xc)
		chart.marker:Hide()
		local title = data.group == "hour" and date("%b %d  %H:00", cd.t) or date("%b %d", cd.t)
		local body = format("%s   %s\n%s   %s\n%s   %s\n%s   %s", L["Open"], F.FormatGold(cd.o), L["High"], F.FormatGold(cd.h), L["Low"], F.FormatGold(cd.l), L["Close"], F.FormatGold(cd.c))
		showTip(chart, xc, height * 0.6, title, body)
	elseif data.lo == data.hi then
		-- Single sample drawn as a flat line: the marker rides the cursor, so we
		-- reposition every frame (cheap, no allocation). Only one sample exists,
		-- so this transient state is short-lived anyway.
		local pt = data.h[data.lo]
		local spanV = data.vmax - data.vmin
		local py = spanV > 0 and ((pt.p - data.vmin) / spanV) * height or height * 0.5
		showCross(chart, rx)
		showMarker(chart, rx, py)
		showTip(chart, rx, py, date("%b %d  %H:%M", pt.t), F.FormatGold(pt.p))
	else
		local h = data.h
		local t = data.t0 + (rx / width) * data.xmax * 86400
		local idx = nearestIndex(h, data.lo, data.hi, t)
		-- Same nearest point as last frame -> nothing to redraw.
		if chart.hoverKey == idx then
			return
		end
		chart.hoverKey = idx
		local pt = h[idx]
		if not pt then
			return Hover.Hide(chart)
		end
		local px = ((pt.t - data.t0) / 86400 / data.xmax) * width
		local spanV = data.vmax - data.vmin
		local py = spanV > 0 and ((pt.p - data.vmin) / spanV) * height or height * 0.5
		showCross(chart, px)
		showMarker(chart, px, py)
		showTip(chart, px, py, date("%b %d  %H:%M", pt.t), F.FormatGold(pt.p))
	end
end

function Hover.Install(chart, plot, plotArea)
	-- Crosshair + marker live on an overlay frame parented to the plot so they
	-- render ABOVE the LibGraph line and the candle textures (child regions of
	-- plot would otherwise paint under the graph frame).
	local overlay = CreateFrame("Frame", nil, plot)
	overlay:SetAllPoints(plot)
	overlay:SetFrameLevel(chart.graph:GetFrameLevel() + 5)
	chart.overlay = overlay

	chart.crossV = overlay:CreateTexture(nil, "OVERLAY")
	chart.crossV:Hide()
	chart.marker = overlay:CreateTexture(nil, "OVERLAY")
	chart.marker:SetSize(7, 7)
	chart.marker:Hide()

	-- Readout tooltip. Parented to plotArea (not the clipping plot) so it can
	-- sit above the top edge when needed.
	local tip = CreateFrame("Frame", nil, plotArea, "BackdropTemplate")
	tip:SetBackdrop(UI.BACKDROP)
	tip:SetFrameLevel(plotArea:GetFrameLevel() + 30)
	tip.title = tip:CreateFontString(nil, "OVERLAY")
	tip.title:SetFont(C.Font, 11, "")
	tip.title:SetShadowOffset(1, -1)
	tip.title:SetPoint("TOPLEFT", 8, -6)
	tip.title:SetJustifyH("LEFT")
	tip.body = tip:CreateFontString(nil, "OVERLAY")
	tip.body:SetFont(C.Font, 11, "")
	tip.body:SetShadowOffset(1, -1)
	tip.body:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -3)
	tip.body:SetJustifyH("LEFT")
	tip:Hide()
	chart.tip = tip

	UI:OnTheme(function()
		local p = ns:Palette()
		tip:SetBackdropColor(p.panel[1], p.panel[2], p.panel[3], 0.95)
		tip:SetBackdropBorderColor(p.accent[1], p.accent[2], p.accent[3], 1)
		tip.title:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
		tip.body:SetTextColor(p.text[1], p.text[2], p.text[3])
	end)

	-- Gate the per-frame hover read on mouse-over (idle otherwise).
	plot:EnableMouse(true)
	plot:SetScript("OnEnter", function()
		plot:SetScript("OnUpdate", function(self)
			onHoverUpdate(self, chart)
		end)
	end)
	plot:SetScript("OnLeave", function()
		plot:SetScript("OnUpdate", nil)
		Hover.Hide(chart)
	end)
end
