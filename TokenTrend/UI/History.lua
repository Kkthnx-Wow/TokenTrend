-- ---------------------------------------------------------------------------
-- TokenTrend - History tab: a paginated OHLC table, NASDAQ "Historical Data"
-- style. Rows are virtualized (a fixed pool of ROWS frames, repopulated per
-- page) so a long history costs the same as a short one.
-- ---------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local C = ns.C
local F = ns.F
local UI = ns.UI

local format = string.format
local date = date
local ceil = math.ceil
local max = math.max
local min = math.min

local ROWS = 12 -- visible rows per page

-- Column model. Date is left-aligned; the numeric columns are right-aligned and
-- evenly split the remaining width (see positionCells).
local COLUMNS = {
	{ key = "date", label = L["Date"], justify = "LEFT" },
	{ key = "close", label = L["Close"], justify = "RIGHT" },
	{ key = "open", label = L["Open"], justify = "RIGHT" },
	{ key = "high", label = L["High"], justify = "RIGHT" },
	{ key = "low", label = L["Low"], justify = "RIGHT" },
	{ key = "chg", label = L["Chg %"], justify = "RIGHT" },
}

local hist = { page = 1, laidOutWidth = nil }

-- ---------------------------------------------------------------------------
-- Toggle + pager styling (mirrors the chart's toggle look)
-- ---------------------------------------------------------------------------
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

local function setPagerEnabled(btn, on)
	btn:SetEnabled(on)
	btn:SetAlpha(on and 1 or 0.35)
end

-- ---------------------------------------------------------------------------
-- Column layout: place a row's (or the header's) cells across width W.
-- ---------------------------------------------------------------------------
local function positionCells(cells, W)
	local pad = 6
	local dateRight = W * 0.26
	local numW = (W - pad - dateRight) / (#COLUMNS - 1)
	for i, fs in ipairs(cells) do
		fs:ClearAllPoints()
		fs:SetJustifyH(COLUMNS[i].justify)
		if i == 1 then
			fs:SetPoint("LEFT", fs:GetParent(), "LEFT", pad, 0)
		else
			-- Right edge of column i sits at dateRight + numW*(i-1) from the left.
			fs:SetPoint("RIGHT", fs:GetParent(), "LEFT", dateRight + numW * (i - 1), 0)
		end
	end
end

local function layoutColumns(W)
	positionCells(hist.headerCells, W)
	for r = 1, ROWS do
		positionCells(hist.rows[r].cells, W)
	end
end

-- ---------------------------------------------------------------------------
-- Fill one row from a candle. Close + Chg% are colored by the day-over-day
-- move (close vs the previous candle's close), matching the ticker's green/red.
-- ---------------------------------------------------------------------------
local function fillRow(row, cd, prevClose, rowIndex)
	local p = ns:Palette()
	-- Zebra striping for readability (every other row a faint wash).
	row.bg:SetColorTexture(p.text[1], p.text[2], p.text[3], (rowIndex % 2 == 0) and 0.04 or 0)

	local cells = row.cells
	cells[1]:SetText(ns.db.historyGroup == "hour"
		and F.FormatShortDateHour(cd.t) or date("%m/%d/%Y", cd.t))
	cells[1]:SetTextColor(p.muted[1], p.muted[2], p.muted[3])

	local delta = cd.c - prevClose
	local cr, cg, cb = F.TrendColor(delta)
	cells[2]:SetText(F.Comma(cd.c))
	cells[2]:SetTextColor(cr, cg, cb)

	cells[3]:SetText(F.Comma(cd.o))
	cells[3]:SetTextColor(p.text[1], p.text[2], p.text[3])
	cells[4]:SetText(F.Comma(cd.h))
	cells[4]:SetTextColor(p.text[1], p.text[2], p.text[3])
	cells[5]:SetText(F.Comma(cd.l))
	cells[5]:SetTextColor(p.text[1], p.text[2], p.text[3])

	local pct = prevClose ~= 0 and (delta / prevClose * 100) or 0
	cells[6]:SetText(F.FormatPct(pct))
	cells[6]:SetTextColor(cr, cg, cb)
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function refresh()
	styleToggle(hist.btnDay, ns.db.historyGroup == "day")
	styleToggle(hist.btnHour, ns.db.historyGroup == "hour")

	local candles = ns.Analysis:Candles(ns.db.historyGroup, 0)
	local total = #candles

	if total == 0 then
		hist.empty:Show()
		hist.pageText:SetText("")
		setPagerEnabled(hist.btnPrev, false)
		setPagerEnabled(hist.btnNext, false)
		for r = 1, ROWS do
			hist.rows[r]:Hide()
		end
		return
	end
	hist.empty:Hide()

	-- Plot rect may not be laid out yet on first open; defer a frame.
	local W = hist.rows[1]:GetWidth()
	if W <= 0 then
		C_Timer.After(0, refresh)
		return
	end
	if hist.laidOutWidth ~= W then
		layoutColumns(W)
		hist.laidOutWidth = W
	end

	local totalPages = max(ceil(total / ROWS), 1)
	hist.page = F.Clamp(hist.page, 1, totalPages)

	-- Newest row first (NASDAQ shows most-recent at the top).
	local firstNewest = (hist.page - 1) * ROWS + 1
	for r = 1, ROWS do
		local newestRank = firstNewest + (r - 1)
		local j = total - newestRank + 1 -- map newest-rank -> ascending array index
		local row = hist.rows[r]
		if j >= 1 then
			local prevClose = (j > 1) and candles[j - 1].c or candles[j].o
			fillRow(row, candles[j], prevClose, r)
			row:Show()
		else
			row:Hide()
		end
	end

	local shownTo = min(firstNewest + ROWS - 1, total)
	hist.pageText:SetText(format(L["%d-%d of %d"], firstNewest, shownTo, total))
	setPagerEnabled(hist.btnPrev, hist.page > 1)
	setPagerEnabled(hist.btnNext, hist.page < totalPages)
end
hist.refresh = refresh

local function gotoPage(p)
	hist.page = p
	refresh()
end

local function setGroup(g)
	if ns.db.historyGroup == g then return end
	hist.page = 1
	hist.laidOutWidth = nil -- date column width is identical, but be safe
	ns:SetSetting("historyGroup", g) -- fires SettingChanged -> UI refresh
end

-- ---------------------------------------------------------------------------
-- Build the History tab
-- ---------------------------------------------------------------------------
local function build(panel)
	-- Controls row: Daily/Hourly (left) + pager (right). ------------------
	local controls = CreateFrame("Frame", nil, panel)
	controls:SetPoint("TOPLEFT")
	controls:SetPoint("TOPRIGHT")
	controls:SetHeight(24)

	hist.btnDay = UI:Button(controls, L["Daily"], 60, function() setGroup("day") end)
	hist.btnDay:SetPoint("LEFT", 0, 0)
	UI:SetTooltip(hist.btnDay, L["Daily"], L["Show one row per day (daily OHLC)."])
	hist.btnHour = UI:Button(controls, L["Hourly"], 60, function() setGroup("hour") end)
	hist.btnHour:SetPoint("LEFT", hist.btnDay, "RIGHT", 4, 0)
	UI:SetTooltip(hist.btnHour, L["Hourly"], L["Show one row per hour (hourly OHLC)."])

	hist.btnNext = UI:Button(controls, ">", 28, function() gotoPage(hist.page + 1) end)
	hist.btnNext:SetPoint("RIGHT", 0, 0)
	UI:SetTooltip(hist.btnNext, L["Next page"], L["Show older entries."])
	hist.pageText = UI:Text(controls, "OVERLAY", C.Font, 11, "", "muted")
	hist.pageText:SetPoint("RIGHT", hist.btnNext, "LEFT", -10, 0)
	hist.pageText:SetJustifyH("RIGHT")
	hist.btnPrev = UI:Button(controls, "<", 28, function() gotoPage(hist.page - 1) end)
	hist.btnPrev:SetPoint("RIGHT", hist.pageText, "LEFT", -10, 0)
	UI:SetTooltip(hist.btnPrev, L["Previous page"], L["Show newer entries."])

	-- Header row ----------------------------------------------------------
	local headerRow = CreateFrame("Frame", nil, panel)
	headerRow:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -4)
	headerRow:SetPoint("TOPRIGHT", controls, "BOTTOMRIGHT", 0, -4)
	headerRow:SetHeight(22)

	local underline = headerRow:CreateTexture(nil, "ARTWORK")
	underline:SetPoint("BOTTOMLEFT")
	underline:SetPoint("BOTTOMRIGHT")
	underline:SetHeight(1)
	UI:OnTheme(function(p)
		underline:SetColorTexture(p.border[1], p.border[2], p.border[3], 0.8)
	end)

	hist.headerCells = {}
	for i = 1, #COLUMNS do
		local fs = UI:Text(headerRow, "OVERLAY", C.Font, 11, "", "muted")
		fs:SetText(COLUMNS[i].label)
		hist.headerCells[i] = fs
	end

	-- Data rows (fixed pool, repopulated per page) ------------------------
	hist.rows = {}
	local prev = headerRow
	for r = 1, ROWS do
		local row = CreateFrame("Frame", nil, panel)
		row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
		row:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0)
		row:SetHeight(20)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.cells = {}
		for c = 1, #COLUMNS do
			local fs = row:CreateFontString(nil, "OVERLAY")
			fs:SetFont(C.Font, 12, "")
			row.cells[c] = fs
		end
		hist.rows[r] = row
		prev = row
	end

	hist.empty = UI:Text(panel, "OVERLAY", C.Font, 13, "", "muted")
	hist.empty:SetPoint("TOP", headerRow, "BOTTOM", 0, -30)
	hist.empty:SetText(L["Waiting for first price..."])

	return refresh
end

tinsert(UI.tabDefs, { id = "history", label = L["History"], tip = L["Browse the full price history as a sortable table."], build = build })
