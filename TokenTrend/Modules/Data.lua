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
-- of spamming near-duplicate rows into the save file.
function Data:Record(gold)
	local h = self:GetHistory()
	local now = time()
	local last = h[#h]

	if last and (now - last.t) < ns.db.sampleInterval then
		last.p = gold
	else
		h[#h + 1] = { t = now, p = gold }
		prune(h, ns.db.maxSamples)
	end

	-- History changed (refined tail or new row): invalidate analysis memos.
	self.revision = self.revision + 1
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

	local gold = F.CopperToGold(copper)
	if gold <= 0 then return end

	self.current = gold
	self.lastUpdate = time()
	self:Record(gold)

	ns:Fire("DataUpdated")
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
