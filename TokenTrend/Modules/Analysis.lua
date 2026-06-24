-- ---------------------------------------------------------------------------
-- TokenTrend - Analysis: turn a flat list of {t,p} into something tradeable.
-- ---------------------------------------------------------------------------
-- History is appended chronologically (Data.lua only ever pushes/refines the
-- tail), so everything in here can assume ascending time order. No re-sorting.

local _, ns = ...

local Analysis = {}
ns.Analysis = Analysis

local floor = math.floor
local huge = math.huge
local date = date
local time = time
local wipe = wipe

local DAY = 86400
local HOUR = 3600

local function history()
	return ns.Data:GetHistory()
end

-- ---------------------------------------------------------------------------
-- Revision-aware memoization
-- ---------------------------------------------------------------------------
-- Every public aggregate here is a pure function of the (append-only) history,
-- which only changes when Data:Record runs and bumps Data.revision. So we cache
-- each result and only recompute once the revision moves. This kills the
-- redundant O(n) passes a refresh used to make - the header and the Stats tab
-- both call Stats(); DayStats(), History and Chart all want day candles; a theme
-- toggle re-refreshes without any new data. Up to two scalar args are keyed
-- (e.g. Candles(group, days), MovingAverage(window)); nil results are treated as
-- cheap misses and simply recompute while history is empty.
local function memoize(fn)
	local cache = {}
	local cachedRev = -1
	local NIL = {} -- Lua tables cannot use nil as an index (Stats(), Volatility*(), etc.)
	local function key(v)
		return v == nil and NIL or v
	end
	return function(self, a, b)
		local rev = ns.Data.revision or 0
		if rev ~= cachedRev then
			wipe(cache)
			cachedRev = rev
		end
		if b ~= nil then
			local slot = cache[key(a)]
			if not slot then
				slot = {}
				cache[key(a)] = slot
			end
			local v = slot[key(b)]
			if v == nil then
				v = fn(self, a, b)
				slot[key(b)] = v
			end
			return v
		end
		local ka = key(a)
		local v = cache[ka]
		if v == nil then
			v = fn(self, a, b)
			cache[ka] = v
		end
		return v
	end
end

-- ---------------------------------------------------------------------------
-- Range helpers
-- ---------------------------------------------------------------------------
-- Index of the first point with t >= cutoff (linear from the tail; ranges are
-- usually the recent slice so walking back is cheap).
local function firstIndexSince(h, cutoff)
	for i = #h, 1, -1 do
		if h[i].t < cutoff then
			return i + 1
		end
	end
	return 1
end

-- Returns the slice of history within the last `days` (0/nil = everything).
function Analysis:Slice(days)
	local h = history()
	if not days or days <= 0 then
		return h, 1, #h
	end
	local cutoff = time() - days * DAY
	return h, firstIndexSince(h, cutoff), #h
end

-- ---------------------------------------------------------------------------
-- Low / high / average over a trailing window (in days)
-- ---------------------------------------------------------------------------
local function extremesRaw(self, days)
	local h, lo, hi = self:Slice(days)
	if hi < lo then return nil, nil, nil, 0 end
	local minP, maxP, sum, n = huge, -huge, 0, 0
	for i = lo, hi do
		local p = h[i].p
		if p < minP then minP = p end
		if p > maxP then maxP = p end
		sum = sum + p
		n = n + 1
	end
	if n == 0 then return nil, nil, nil, 0 end
	return minP, maxP, floor(sum / n + 0.5), n
end

local extremesMemo = memoize(function(self, days)
	local minP, maxP, avg, n = extremesRaw(self, days)
	return { minP, maxP, avg, n }
end)

function Analysis:Extremes(days)
	local packed = extremesMemo(self, days)
	return packed[1], packed[2], packed[3], packed[4]
end

-- ---------------------------------------------------------------------------
-- Moving average series. For each sample, average all samples in the trailing
-- `windowDays`. Two-pointer keeps it O(n) instead of O(n*window).
-- Returns an array of {t, p} aligned to the input points.
-- ---------------------------------------------------------------------------
function Analysis:MovingAverage(windowDays)
	local h = history()
	local n = #h
	local out = {}
	if n == 0 then return out end

	local windowSec = windowDays * DAY
	local left = 1
	local sum = 0

	for right = 1, n do
		sum = sum + h[right].p
		-- Evict points that fell out of the trailing window.
		while h[right].t - h[left].t > windowSec do
			sum = sum - h[left].p
			left = left + 1
		end
		local count = right - left + 1
		out[right] = { t = h[right].t, p = sum / count }
	end

	return out
end
Analysis.MovingAverage = memoize(Analysis.MovingAverage)

-- ---------------------------------------------------------------------------
-- Candlestick aggregation: group samples into hour/day buckets.
-- Each candle = { t = bucketStart, o, h, l, c, n }.
-- ---------------------------------------------------------------------------
local function bucketStart(t, group)
	if group == "hour" then
		return floor(t / HOUR) * HOUR
	end
	-- Daily candles align to *local* midnight so "a day" matches the player's
	-- clock, not UTC. date('*t') is local; time() reads it back as local.
	local d = date("*t", t)
	d.hour, d.min, d.sec = 0, 0, 0
	return time(d)
end

function Analysis:Candles(group, days)
	local h, lo, hi = self:Slice(days)
	local candles = {}
	if hi < lo then return candles end

	local cur
	for i = lo, hi do
		local p = h[i].p
		local bStart = bucketStart(h[i].t, group)
		if not cur or cur.t ~= bStart then
			cur = { t = bStart, o = p, h = p, l = p, c = p, n = 1 }
			candles[#candles + 1] = cur
		else
			if p > cur.h then cur.h = p end
			if p < cur.l then cur.l = p end
			cur.c = p
			cur.n = cur.n + 1
		end
	end

	return candles
end
Analysis.Candles = memoize(Analysis.Candles)

-- ---------------------------------------------------------------------------
-- Downsample a {t,p} series to at most `maxPoints` for the line chart, so we
-- don't ask LibGraph to draw thousands of segments. Keeps first + last.
-- ---------------------------------------------------------------------------
function Analysis:Resample(series, fromIdx, toIdx, maxPoints)
	local out = {}
	local count = toIdx - fromIdx + 1
	if count <= 0 then return out end
	if count <= maxPoints then
		for i = fromIdx, toIdx do
			out[#out + 1] = series[i]
		end
		return out
	end
	local stride = count / maxPoints
	for k = 0, maxPoints - 1 do
		out[#out + 1] = series[floor(fromIdx + k * stride)]
	end
	out[#out + 1] = series[toIdx] -- always pin the latest point
	return out
end

-- ---------------------------------------------------------------------------
-- Buy signal: are we at (or within tolerance of) the 30-day low?
-- ---------------------------------------------------------------------------
function Analysis:Is30DayLow()
	local cur = ns.Data.current
	if not cur then return false, nil end
	local low30 = select(1, self:Extremes(30))
	if not low30 then return false, nil end
	local tol = ns.db.lowAlertTolerance or 0
	return cur <= low30 * (1 + tol), low30
end

-- Sell signal: at (or within tolerance of) the 30-day high?
function Analysis:Is30DayHigh()
	local cur = ns.Data.current
	if not cur then return false, nil end
	local _, high30 = self:Extremes(30)
	if not high30 then return false, nil end
	local tol = ns.db.highAlertTolerance or 0
	return cur >= high30 * (1 - tol), high30
end

-- NASDAQ-style trend: current price vs the 7-day average.
function Analysis:Trend()
	local cur = ns.Data.current
	if not cur then return "flat", nil end
	local _, _, avg7 = self:Extremes(7)
	if not avg7 or avg7 == 0 then return "flat", nil end
	local pct = (cur - avg7) / avg7
	if pct > 0.005 then
		return "rising", pct
	elseif pct < -0.005 then
		return "falling", pct
	end
	return "flat", pct
end

-- ---------------------------------------------------------------------------
-- "Key Data" for today: today's OHLC and the prior day's close, so the UI can
-- show a Previous Close and a Day Range like a real ticker. Built from daily
-- candles (cheap: candles are aggregated, not the raw history).
-- ---------------------------------------------------------------------------
function Analysis:DayStats()
	local candles = self:Candles("day", 0)
	local n = #candles
	if n == 0 then return nil end
	local today = candles[n]
	local prev = candles[n - 1]
	return {
		open = today.o,
		high = today.h,
		low = today.l,
		close = today.c,
		prevClose = prev and prev.c or nil,
	}
end

-- ---------------------------------------------------------------------------
-- Headline stats for the Stats tab + header.
-- ---------------------------------------------------------------------------
function Analysis:Stats()
	local h = history()
	local n = #h
	local s = { samples = n }
	if n == 0 then return s end

	s.current = ns.Data.current or h[n].p
	s.since = h[1].t

	-- Change vs the previous distinct sample (our "session" delta).
	if n >= 2 then
		local prev = h[n - 1].p
		s.changeAbs = s.current - prev
		s.changePct = prev ~= 0 and (s.changeAbs / prev * 100) or 0
	else
		s.changeAbs, s.changePct = 0, 0
	end

	s.low7, s.high7, s.avg7 = self:Extremes(7)
	s.low30, s.high30, s.avg30 = self:Extremes(30)
	s.lowAll, s.highAll = self:Extremes(0)

	-- Day "key data" + net change vs the previous calendar-day close (the move
	-- a ticker headlines). Falls back to the sample delta only if there's no
	-- prior close yet (first day of tracking).
	local day = self:DayStats()
	if day then
		s.dayLow, s.dayHigh, s.prevClose = day.low, day.high, day.prevClose
		if day.prevClose and day.prevClose ~= 0 then
			s.netAbs = s.current - day.prevClose
			s.netPct = s.netAbs / day.prevClose * 100
		end
	end

	return s
end
Analysis.Stats = memoize(Analysis.Stats)

-- ---------------------------------------------------------------------------
-- Time-of-day / day-of-week volatility. Buckets are average price; cheaper
-- bucket = better time to buy. We return averages plus the overall mean so the
-- UI can color relative to "normal".
-- ---------------------------------------------------------------------------
local function bucketize(getKey, size)
	local h = history()
	local sums, counts = {}, {}
	for i = 0, size - 1 do sums[i], counts[i] = 0, 0 end

	local total, totalN = 0, 0
	for i = 1, #h do
		local key = getKey(h[i].t)
		sums[key] = sums[key] + h[i].p
		counts[key] = counts[key] + 1
		total = total + h[i].p
		totalN = totalN + 1
	end

	local out = {}
	for i = 0, size - 1 do
		out[i] = counts[i] > 0 and (sums[i] / counts[i]) or nil
	end
	local mean = totalN > 0 and (total / totalN) or nil
	return out, mean, totalN
end

function Analysis:VolatilityByHour()
	return bucketize(function(t)
		return tonumber(date("%H", t)) -- 0..23, local hour
	end, 24)
end
Analysis.VolatilityByHour = memoize(Analysis.VolatilityByHour)

function Analysis:VolatilityByWeekday()
	-- date('*t').wday is 1=Sunday..7=Saturday; shift to 0-based bucket.
	return bucketize(function(t)
		return date("*t", t).wday - 1
	end, 7)
end
Analysis.VolatilityByWeekday = memoize(Analysis.VolatilityByWeekday)
