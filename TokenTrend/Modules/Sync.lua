-- ---------------------------------------------------------------------------
-- TokenTrend - Sync: peer-to-peer history backfill over addon channels.
-- ---------------------------------------------------------------------------
-- The *current* token price is identical for everyone in a region (it's a
-- server value), so syncing can't make "now" more accurate. What it CAN do is
-- fill the gaps in your timeline using samples guildmates/groupmates recorded
-- while you were offline - so charts, candles and volatility are rich from the
-- first session instead of after weeks of solo collecting.
--
-- Reach is bounded by the game itself: there is NO global channel, only GUILD,
-- PARTY and RAID. In-instance addon comms are blocked in Midnight (12.0), so
-- every send and receive bails while you're inside an instance.
--
-- Protocol - each message is self-contained, so there's nothing to reassemble:
--   HEY|proto|region                     "I'm here, please advertise" (broadcast)
--   MAN|proto|region|day:n:sum|...        coverage manifest             (broadcast)
--   REQ|proto|region|day|day|...          "send me these days"          (whisper)
--   DAT|proto|region|bucket:price|...     the goods                     (whisper)
--
-- Trust model is "basic": same-region only, plausibility-bounded prices, and an
-- insert-only merge that never overwrites your own first-hand samples.
-- ---------------------------------------------------------------------------

local _, ns = ...
local F = ns.F

local Sync = {}
ns.Sync = Sync

local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local time = time
local floor = math.floor
local format = string.format
local tconcat = table.concat
local wipe = wipe
local strsplit = strsplit
local tonumber = tonumber
local UnitName = UnitName
local GetNormalizedRealmName = GetNormalizedRealmName
local IsInGuild = IsInGuild
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance

local PREFIX = "TKTR"
local PROTO = 1
local DAY = 86400
local MAX_MSG = 230 -- conservative addon-message payload budget (chars)
local CKSUM = 65521 -- prime modulus for the cheap per-day checksum
local MIN_GOLD = 1000 -- plausibility floor (reject obvious garbage)
local MAX_GOLD = 100000000 -- plausibility ceiling (~100M, headroom for inflation)
local SEND_PERIOD = 0.4 -- seconds between queued sends (disconnect-safe)
local DEBOUNCE = 8 -- seconds to coalesce roster churn before broadcasting
local REBROADCAST = 900 -- periodic manifest (15m) so long sessions converge
local PEER_BUDGET = 3000 -- max samples we'll serve a single peer per session
local HEY_COOLDOWN = 60 -- min seconds between HEY-triggered re-broadcasts

-- ---------------------------------------------------------------------------
-- Bucketing. A "bucket" is a sampleInterval-wide slot; a "day" is a calendar
-- day index. Both are derived from the stored sample timestamps.
-- ---------------------------------------------------------------------------
local bmap, bmapRev = {}, -1

-- bucket -> price, rebuilt only when the history revision changes.
local function bucketMap()
	local rev = ns.Data.revision or 0
	if rev ~= bmapRev then
		wipe(bmap)
		local h = ns.Data:GetHistory()
		local iv = ns.db.sampleInterval
		for i = 1, #h do
			bmap[floor(h[i].t / iv)] = h[i].p
		end
		bmapRev = rev
	end
	return bmap
end

-- day -> { n = count, s = sum-of-buckets mod prime }. The (n, s) pair lets a
-- peer spot days where it can help us even when our counts happen to match.
-- Memoized against the history revision: a flurry of incoming manifests in a
-- big guild all reuse one computation until our own data actually changes.
local digest, digestRev = {}, -1
local function buildDigest()
	local rev = ns.Data.revision or 0
	if rev ~= digestRev then
		wipe(digest)
		local bm = bucketMap()
		local iv = ns.db.sampleInterval
		for b in pairs(bm) do
			local d = floor((b * iv) / DAY)
			local e = digest[d]
			if not e then
				e = { n = 0, s = 0 }
				digest[d] = e
			end
			e.n = e.n + 1
			e.s = (e.s + b) % CKSUM
		end
		digestRev = rev
	end
	return digest
end

-- ---------------------------------------------------------------------------
-- Outbound queue. Addon messages are rate-limited by the server (flooding gets
-- you disconnected), so everything funnels through a steady drip.
-- ---------------------------------------------------------------------------
local q, qHead, qTail, qTicker = {}, 1, 0, nil

local function drain()
	if qHead > qTail then
		wipe(q)
		qHead, qTail = 1, 0
		if qTicker then
			qTicker:Cancel()
			qTicker = nil
		end
		return
	end
	local item = q[qHead]
	q[qHead] = nil
	qHead = qHead + 1
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, item.m, item.c, item.t)
	end
end

local function enqueue(channel, target, msg)
	qTail = qTail + 1
	q[qTail] = { c = channel, t = target, m = msg }
	if not qTicker then
		qTicker = C_Timer.NewTicker(SEND_PERIOD, drain)
	end
end

-- ---------------------------------------------------------------------------
-- Channels + framing
-- ---------------------------------------------------------------------------
local function groupChannel()
	if IsInInstance() then return nil end -- comms blocked in instances (12.0)
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

-- Send to everyone we can reach: guild and (if grouped, non-instance) the party.
local function broadcast(msg)
	if IsInGuild() then enqueue("GUILD", nil, msg) end
	local gch = groupChannel()
	if gch then enqueue(gch, nil, msg) end
end

-- Pack a list of short items into as few messages as fit, handing each finished
-- message to dispatch(msg). Every message re-states the type/proto/region
-- header so receivers can treat them independently.
local function chunk(typ, items, dispatch)
	local header = format("%s|%d|%s|", typ, PROTO, F.GetRegionName())
	local buf, len = {}, #header
	local function flush()
		if #buf > 0 then
			dispatch(header .. tconcat(buf, "|"))
			wipe(buf)
			len = #header
		end
	end
	for i = 1, #items do
		local it = items[i]
		if len + #it + 1 > MAX_MSG and #buf > 0 then
			flush()
		end
		buf[#buf + 1] = it
		len = len + #it + 1
	end
	flush()
end

-- ---------------------------------------------------------------------------
-- Self-identification (CHAT_MSG_ADDON echoes our own broadcasts back to us).
-- ---------------------------------------------------------------------------
local playerFull
local function isSelf(sender)
	if not playerFull then
		local n = UnitName("player") or ""
		local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
		playerFull = n .. "-" .. r
	end
	return sender == playerFull or sender == (UnitName("player") or "")
end

-- ---------------------------------------------------------------------------
-- Outgoing: HEY + manifest
-- ---------------------------------------------------------------------------
function Sync:Hello()
	if not ns.db.sync or IsInInstance() then return end
	if not (IsInGuild() or groupChannel()) then return end
	broadcast(format("HEY|%d|%s", PROTO, F.GetRegionName()))
end

function Sync:Broadcast()
	if not ns.db.sync or IsInInstance() then return end
	if not (IsInGuild() or groupChannel()) then return end -- nobody to talk to

	local cover = buildDigest()
	local items = {}
	for d, e in pairs(cover) do
		items[#items + 1] = format("%d:%d:%d", d, e.n, e.s)
	end
	if #items == 0 then return end -- nothing recorded yet; we listen instead
	chunk("MAN", items, broadcast)
end

local pending
local function scheduleBroadcast()
	if pending or not ns.db.sync then return end
	pending = true
	C_Timer.After(DEBOUNCE, function()
		pending = false
		Sync:Broadcast()
	end)
end
Sync.Schedule = scheduleBroadcast

-- ---------------------------------------------------------------------------
-- Incoming handlers
-- ---------------------------------------------------------------------------
local requested = {} -- "sender\0day" -> true, so we ask each peer once per session
local lastHeyReply = 0

-- Session ledger, surfaced by the UI's Sync panel. `from`/`to` are
-- sender -> sample-count maps; gained/sent are the running totals.
local stats = { from = {}, to = {}, gained = 0, sent = 0, lastFrom = nil, lastTo = nil }
function Sync:Stats()
	return stats
end

-- A peer told us what it has. Request the days where it can fill our gaps.
local function handleManifest(sender, parts)
	local mine = buildDigest()
	local want = {}
	for i = 4, #parts do
		local ds, ns_, ss = strsplit(":", parts[i])
		local d, n, s = tonumber(ds), tonumber(ns_), tonumber(ss)
		if d and n and s then
			local me = mine[d]
			-- They can help if we lack the day, they have more points, or the
			-- counts tie but the contents differ (different buckets).
			local need = (not me) or (n > me.n) or (n == me.n and s ~= me.s)
			local key = sender .. "\0" .. d
			if need and not requested[key] then
				requested[key] = true
				want[#want + 1] = ds
			end
		end
	end
	if #want > 0 then
		chunk("REQ", want, function(m) enqueue("WHISPER", sender, m) end)
	end
end

-- A peer asked for specific days. Serve the buckets we hold for them.
local function handleRequest(sender, parts)
	local bm = bucketMap()
	local iv = ns.db.sampleInterval
	local budget = PEER_BUDGET - (stats.to[sender] or 0)
	if budget <= 0 then return end

	local items = {}
	for i = 4, #parts do
		local d = tonumber(parts[i])
		if d then
			local lo = floor((d * DAY) / iv)
			local hi = floor(((d + 1) * DAY) / iv)
			for b = lo, hi do
				local p = bm[b]
				if p then
					items[#items + 1] = format("%d:%d", b, floor(p + 0.5))
					budget = budget - 1
					if budget <= 0 then break end
				end
			end
		end
		if budget <= 0 then break end
	end

	if #items > 0 then
		stats.to[sender] = (stats.to[sender] or 0) + #items
		stats.sent = stats.sent + #items
		stats.lastTo = time()
		chunk("DAT", items, function(m) enqueue("WHISPER", sender, m) end)
	end
end

-- A peer sent samples. Validate (basic) and merge the buckets we're missing.
local function handleData(sender, parts)
	local iv = ns.db.sampleInterval
	local now = time()
	local points = {}
	for i = 4, #parts do
		local bs, ps = strsplit(":", parts[i])
		local b, p = tonumber(bs), tonumber(ps)
		if b and p and p >= MIN_GOLD and p <= MAX_GOLD then
			local t = b * iv
			if t > 0 and t <= now + iv then -- never accept future-dated points
				points[#points + 1] = { t = t, p = p }
			end
		end
	end
	if #points > 0 then
		local added = ns.Data:Merge(points)
		if added > 0 then
			stats.from[sender] = (stats.from[sender] or 0) + added
			stats.gained = stats.gained + added
			stats.lastFrom = time()
		end
	end
end

local function onAddonMsg(_, prefix, msg, _, sender)
	if prefix ~= PREFIX or not ns.db.sync or IsInInstance() then return end
	if not msg or msg == "" or isSelf(sender) then return end

	local parts = { strsplit("|", msg) }
	if tonumber(parts[2]) ~= PROTO then return end -- protocol mismatch
	if parts[3] ~= F.GetRegionName() then return end -- different region: not ours

	local typ = parts[1]
	if typ == "MAN" then
		handleManifest(sender, parts)
	elseif typ == "REQ" then
		handleRequest(sender, parts)
	elseif typ == "DAT" then
		handleData(sender, parts)
	elseif typ == "HEY" then
		-- A peer just logged in and wants manifests. Re-advertise, but rate-limit
		-- so a busy guild login window can't make us broadcast on a loop.
		local now = time()
		if now - lastHeyReply >= HEY_COOLDOWN then
			lastHeyReply = now
			scheduleBroadcast()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Toggle (wired to /tt sync)
-- ---------------------------------------------------------------------------
function Sync:SetEnabled(on)
	on = on and true or false
	ns:SetSetting("sync", on)
	if on then
		scheduleBroadcast()
		C_Timer.After(2, function() Sync:Hello() end)
	end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
ns:OnLogin(function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	end

	ns:RegisterEvent("CHAT_MSG_ADDON", onAddonMsg)
	-- Group changes re-advertise (debounced); a guild membership change too. We
	-- deliberately skip GUILD_ROSTER_UPDATE - it fires constantly and the
	-- periodic re-broadcast + HEY pings cover guildmates logging in.
	ns:RegisterEvent("GROUP_ROSTER_UPDATE", scheduleBroadcast)
	ns:RegisterEvent("PLAYER_GUILD_UPDATE", scheduleBroadcast)

	-- Settle, then ping for manifests and advertise our own coverage.
	C_Timer.After(5, function()
		Sync:Hello()
		scheduleBroadcast()
	end)

	C_Timer.NewTicker(REBROADCAST, function()
		Sync:Broadcast()
	end)

	ns:On("DataUpdated", function()
		if ns.db.sync then
			scheduleBroadcast()
		end
	end)
end)
