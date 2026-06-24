-- ---------------------------------------------------------------------------
-- TokenTrend - Data: ask Blizzard for the token price, log it over time.
-- ---------------------------------------------------------------------------
-- The addon only runs while you're logged in, so the historical database is
-- built one sample at a time and persisted in SavedVariables. We can't backfill
-- the past - we can only stop missing the future.

local _, ns = ...
local F = ns.F

local Data = {}
ns.Data = Data

-- File-scope locals for the token API + hot globals.
local C_WowTokenPublic = C_WowTokenPublic
local C_Timer = C_Timer
local time = time
local floor = math.floor
local tsort = table.sort

local function byTime(a, b) return a.t < b.t end

Data.current = nil -- latest gold price this session (display)
Data.lastUpdate = nil -- when we last got a price
-- Bumped on every history mutation. Analysis memoizes its O(n) aggregates
-- against this, so nothing recomputes until a new price actually lands.
Data.revision = 0

-- ---------------------------------------------------------------------------
-- History storage (per region)
-- ---------------------------------------------------------------------------
function Data:GetStore()
	local region = F.GetRegionName()
	local regions = ns.sv.regions
	local store = regions[region]
	if not store then
		store = { history = {} }
		regions[region] = store
	end
	return store
end

function Data:GetHistory()
	return self:GetStore().history
end

-- Drop the oldest points once we blow past the cap. Shift-in-place keeps the
-- array contiguous (no gaps -> # stays O(1)-ish and LibGraph stays happy).
local function prune(h, cap)
	local excess = #h - cap
	if excess <= 0 then return end
	for i = 1, #h - excess do
		h[i] = h[i + excess]
	end
	for i = #h, #h - excess + 1, -1 do
		h[i] = nil
	end
end

-- Commit a price into history. Within sampleInterval we just refine the most
-- recent point's value (so the "current candle" tracks the live price) instead
-- of spamming near-duplicate rows into the save file. Returns true when history
-- actually changed (new row or refined price).
function Data:Record(gold)
	local h = self:GetHistory()
	local now = time()
	local last = h[#h]

	if last and (now - last.t) < ns.db.sampleInterval then
		if last.p == gold then
			return false
		end
		last.p = gold
	else
		h[#h + 1] = { t = now, p = gold }
		prune(h, ns.db.maxSamples)
	end

	self.revision = self.revision + 1
	return true
end

-- Merge externally-sourced samples (peer sync) into history. Insert-only and
-- bucketed by sampleInterval: a bucket we already hold always wins, so our own
-- first-hand readings are never overwritten by a peer's. Sorts + prunes once at
-- the end and bumps the revision a single time. Returns how many new points
-- actually landed (0 = nothing new, no UI churn).
function Data:Merge(points)
	if not points or #points == 0 then return 0 end

	local h = self:GetHistory()
	local iv = ns.db.sampleInterval

	-- Buckets we already cover (own data or previously merged).
	local have = {}
	for i = 1, #h do
		have[floor(h[i].t / iv)] = true
	end

	local added = 0
	for i = 1, #points do
		local pt = points[i]
		local b = floor(pt.t / iv)
		if not have[b] then
			have[b] = true
			h[#h + 1] = { t = pt.t, p = pt.p }
			added = added + 1
		end
	end

	if added == 0 then return 0 end

	-- Backfilled points are older than the live tail, so re-order before pruning.
	tsort(h, byTime)
	prune(h, ns.db.maxSamples)

	self.revision = self.revision + 1
	ns:Fire("DataUpdated")
	return added
end

-- ---------------------------------------------------------------------------
-- API plumbing
-- ---------------------------------------------------------------------------
-- TOKEN_MARKET_PRICE_UPDATED fires after a successful UpdateMarketPrice().
-- We read the cached value, guard the (theoretically) secret money, store it.
function Data:OnPriceUpdated()
	if not C_WowTokenPublic or not C_WowTokenPublic.GetCurrentMarketPrice then
		return
	end

	local copper = C_WowTokenPublic.GetCurrentMarketPrice()
	if not copper then return end

	-- Money can be secret in combat. Don't do math on a sealed envelope -
	-- we'll just catch the next (non-secret) update.
	if F.IsSecret(copper) then return end

	local prev = self.current
	local gold = F.CopperToGold(copper)
	if gold <= 0 then return end

	self.current = gold
	self.lastUpdate = time()
	local changed = self:Record(gold)

	if changed or prev ~= gold then
		ns:Fire("DataUpdated")
	end
end

-- Politely poke Blizzard for a fresh price (throttled internally by them).
function Data:RequestUpdate()
	if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
		C_WowTokenPublic.UpdateMarketPrice()
	end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
ns:OnLogin(function()
	ns:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED", function()
		Data:OnPriceUpdated()
	end)

	-- Kick off an immediate request, then keep a steady heartbeat. The price
	-- rarely moves fast, so a periodic ticker is plenty - no OnUpdate needed.
	Data:RequestUpdate()
	Data.ticker = C_Timer.NewTicker(ns.db.pollInterval, function()
		Data:RequestUpdate()
	end)

	-- Sometimes the value is already cached and no event fires for us, so grab
	-- it once shortly after login as a belt-and-suspenders read.
	C_Timer.After(2, function()
		Data:OnPriceUpdated()
	end)
end)
