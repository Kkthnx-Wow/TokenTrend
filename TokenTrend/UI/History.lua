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
local tsort = table.sort

local ROWS = 12 -- visible rows per page

-- Column model. Date is left-aligned; the numeric columns are right-aligned and
-- evenly split the remaining width (see positionCells). Click a header to sort.
local COLUMNS = {
	{ key = "date", label = L["Date"], justify = "LEFT", sortable = true },
	{ key = "close", label = L["Close"], justify = "RIGHT", sortable = true },
	{ key = "open", label = L["Open"], justify = "RIGHT", sortable = false },
	{ key = "high", label = L["High"], justify = "RIGHT", sortable = false },
	{ key = "low", label = L["Low"], justify = "RIGHT", sortable = false },
	{ key = "chg", label = L["Chg %"], justify = "RIGHT", sortable = true },
}

local hist = { page = 1, laidOutWidth = nil, sortCol = "date", sortAsc = false, layoutPending = false }
local orderCache = { rev = -1, group = nil, sortCol = nil, sortAsc = nil, order = nil }
local refresh -- forward-declared; clickSort runs before the function body below is assigned

local function setPagerEnabled(btn, on)
	btn:SetEnabled(on)
	btn:SetAlpha(on and 1 or 0.35)
end

-- ---------------------------------------------------------------------------
-- Column layout: place a row's (or the header's) cells across width W.
-- ---------------------------------------------------------------------------
local function columnMetrics(W)
	local pad = 6
	local dateRight = W * 0.26
	local numW = (W - pad - dateRight) / (#COLUMNS - 1)
	return pad, dateRight, numW
end

local function positionCells(cells, W)
	local pad, dateRight, numW = columnMetrics(W)
	for i, fs in ipairs(cells) do
		fs:ClearAllPoints()
		fs:SetJustifyH(COLUMNS[i].justify)
		if i == 1 then
			fs:SetPoint("LEFT", fs:GetParent(), "LEFT", pad, 0)
		else
			fs:SetPoint("RIGHT", fs:GetParent(), "LEFT", dateRight + numW * (i - 1), 0)
		end
	end
end

local function positionHeaders(W)
	local pad, dateRight, numW = columnMetrics(W)
	for i, hdr in ipairs(hist.headerBtns) do
		hdr:ClearAllPoints()
		hdr:SetHeight(22)
		if i == 1 then
			hdr:SetPoint("TOPLEFT", hdr:GetParent(), "TOPLEFT", pad, 0)
			hdr:SetWidth(dateRight - pad)
		else
			hdr:SetPoint("TOPLEFT", hdr:GetParent(), "TOPLEFT", dateRight + numW * (i - 2), 0)
			hdr:SetWidth(numW)
		end
		hdr.label:SetJustifyH(COLUMNS[i].justify)
		hdr.label:ClearAllPoints()
		if COLUMNS[i].justify == "RIGHT" then
			hdr.label:SetPoint("RIGHT", hdr, "RIGHT", -2, 0)
		elseif COLUMNS[i].justify == "LEFT" then
			hdr.label:SetPoint("LEFT", hdr, "LEFT", 0, 0)
		else
			hdr.label:SetPoint("CENTER")
		end
	end
end

local function layoutColumns(W)
	if hist.headerBtns then
		positionHeaders(W)
	end
	for r = 1, ROWS do
		positionCells(hist.rows[r].cells, W)
	end
end

-- Build a display order (indices into the candles array) for the active sort.
local function sortedOrder(candles)
	local rev = ns.Data.revision or 0
	local group = ns.db.historyGroup
	if orderCache.rev == rev and orderCache.group == group
		and orderCache.sortCol == hist.sortCol and orderCache.sortAsc == hist.sortAsc then
		return orderCache.order
	end

	local order = {}
	local n = #candles
	for i = 1, n do
		order[i] = i
	end
	local col, asc = hist.sortCol, hist.sortAsc
	local chgCache = {}

	local function chgPct(j)
		local cached = chgCache[j]
		if cached ~= nil then
			return cached
		end
		local cd = candles[j]
		local prev = (j > 1) and candles[j - 1].c or cd.o
		cached = prev ~= 0 and ((cd.c - prev) / prev) or 0
		chgCache[j] = cached
		return cached
	end

	tsort(order, function(a, b)
		local ca, cb = candles[a], candles[b]
		local va, vb
		if col == "close" then
			va, vb = ca.c, cb.c
		elseif col == "chg" then
			va, vb = chgPct(a), chgPct(b)
		else
			va, vb = ca.t, cb.t
		end
		if va == vb then
			return a < b
		end
		if asc then
			return va < vb
		end
		return va > vb
	end)

	orderCache.rev = rev
	orderCache.group = group
	orderCache.sortCol = hist.sortCol
	orderCache.sortAsc = hist.sortAsc
	orderCache.order = order
	return order
end

local function styleSortHeaders()
	local p = ns:Palette()
	for i, col in ipairs(COLUMNS) do
		local hdr = hist.headerBtns[i]
		if not hdr then
			return
		end
		local active = col.sortable and hist.sortCol == col.key
		local label = col.label
		if active then
			-- ASCII carets: WoW's STANDARD_TEXT_FONT lacks Unicode arrow glyphs.
			label = label .. (hist.sortAsc and " ^" or " v")
			hdr.label:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
		else
			hdr.label:SetTextColor(p.muted[1], p.muted[2], p.muted[3])
		end
		hdr.label:SetText(label)
	end
end

local function clickSort(colKey)
	if hist.sortCol == colKey then
		hist.sortAsc = not hist.sortAsc
	else
		hist.sortCol = colKey
		hist.sortAsc = (colKey ~= "date")
	end
	orderCache.rev = -1
	hist.page = 1
	refresh()
end

-- ---------------------------------------------------------------------------
-- Fill one row from a candle. Close + Chg% are colored by the day-over-day
-- move (close vs the previous candle's close), matching the ticker's green/red.
-- ---------------------------------------------------------------------------
local function fillRow(row, cd, prevClose, rowIndex, p)
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
refresh = function()
	UI:StyleButtonToggle(hist.btnDay, ns.db.historyGroup == "day")
	UI:StyleButtonToggle(hist.btnHour, ns.db.historyGroup == "hour")

	local candles = ns.Analysis:Candles(ns.db.historyGroup, 0)
	local order = sortedOrder(candles)
	local total = #order
	local p = ns:Palette()

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
		if not hist.layoutPending then
			hist.layoutPending = true
			C_Timer.After(0, function()
				hist.layoutPending = false
				refresh()
			end)
		end
		return
	end
	if hist.laidOutWidth ~= W then
		layoutColumns(W)
		hist.laidOutWidth = W
	end

	local totalPages = max(ceil(total / ROWS), 1)
	hist.page = F.Clamp(hist.page, 1, totalPages)
	styleSortHeaders()

	local firstRank = (hist.page - 1) * ROWS + 1
	for r = 1, ROWS do
		local rank = firstRank + (r - 1)
		local row = hist.rows[r]
		if rank <= total then
			local j = order[rank]
			local prevClose = (j > 1) and candles[j - 1].c or candles[j].o
			fillRow(row, candles[j], prevClose, r, p)
			row:Show()
		else
			row:Hide()
		end
	end

	local shownTo = min(firstRank + ROWS - 1, total)
	hist.pageText:SetText(format(L["%d-%d of %d"], firstRank, shownTo, total))
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

	hist.headerBtns = {}
	for i, col in ipairs(COLUMNS) do
		local hdr = CreateFrame("Button", nil, headerRow)
		hdr:SetHeight(22)
		hdr.label = hdr:CreateFontString(nil, "OVERLAY")
		hdr.label:SetFont(C.Font, 11, "")
		hdr.label:SetPoint("CENTER")
		hdr.label:SetText(col.label)
		if col.sortable then
			hdr:SetScript("OnClick", function()
				clickSort(col.key)
			end)
			hdr:SetScript("OnEnter", function(self)
				self.label:SetAlpha(0.75)
			end)
			hdr:SetScript("OnLeave", function(self)
				self.label:SetAlpha(1)
			end)
			UI:SetTooltip(hdr, col.label, L["Click to sort this column."])
		end
		hist.headerBtns[i] = hdr
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

tinsert(UI.tabDefs, { id = "history", label = L["History"], tip = L["Browse price history. Click column headers to sort."], build = build })
