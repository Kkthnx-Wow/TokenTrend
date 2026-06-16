-- ---------------------------------------------------------------------------
-- TokenTrend - Shared helpers (ns.F): formatting, secret guards, math, pools.
-- ---------------------------------------------------------------------------

local _, ns = ...

local F = {}
ns.F = F

-- File-scope locals for the hot globals (per the optimization guide).
local floor = math.floor
local abs = math.abs
local format = string.format
local time = time
local date = date
local issecretvalue = issecretvalue
local BreakUpLargeNumbers = BreakUpLargeNumbers
local GetCurrentRegion = GetCurrentRegion
local C_Texture = C_Texture

-- ---------------------------------------------------------------------------
-- Secret-value discipline (Midnight 12.0)
-- ---------------------------------------------------------------------------
-- The token price *shouldn't* be secret (it's region economy data, not a live
-- combat read), but money APIs carry a SecretWhenInCombat predicate. So we
-- guard before any arithmetic/compare rather than trust it and eat a tantrum.
function F.IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

function F.NotSecret(v)
	return not (issecretvalue and issecretvalue(v))
end

-- ---------------------------------------------------------------------------
-- Math
-- ---------------------------------------------------------------------------
function F.Round(n)
	return floor(n + 0.5)
end

function F.Clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Formatting. Prices are stored as whole gold internally, so display is easy.
-- ---------------------------------------------------------------------------
local function commaNumber(n)
	n = floor(n + 0.5)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n)
	end
	local s = tostring(n)
	local k
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end
F.Comma = commaNumber

-- Token market price arrives in copper. 1g = 10000c. We only care about gold.
function F.CopperToGold(copper)
	return floor(copper / 10000)
end

-- Whole-gold value -> "1,234,567g". Returns em dash for nil so the UI never
-- prints "nilg" at people.
function F.FormatGold(gold)
	if not gold then
		return "\226\128\148"
	end -- em dash
	return commaNumber(gold) .. "g"
end

-- Compact gold for tight axis labels: 1.23M / 845K / 999.
function F.FormatGoldShort(gold)
	if not gold then
		return "\226\128\148"
	end
	if gold >= 1000000 then
		return format("%.2fMg", gold / 1000000)
	elseif gold >= 1000 then
		return format("%.0fKg", gold / 1000)
	end
	return commaNumber(gold) .. "g"
end

-- Signed percentage delta, e.g. "+2.4%" / "-1.1%".
function F.FormatPct(delta)
	if not delta then
		return ""
	end
	return format("%+.1f%%", delta)
end

-- "3h 12m ago" style relative time, kept compact.
function F.AgoString(ts)
	if not ts then
		return ns.L["Never"]
	end
	local d = time() - ts
	if d < 60 then
		return ns.L["just now"]
	end
	if d < 3600 then
		return format("%dm ago", floor(d / 60))
	end
	if d < 86400 then
		return format("%dh %dm ago", floor(d / 3600), floor((d % 3600) / 60))
	end
	return format("%dd %dh ago", floor(d / 86400), floor((d % 86400) / 3600))
end

function F.DateString(ts)
	if not ts then
		return ""
	end
	return date("%b %d", ts)
end

-- ---------------------------------------------------------------------------
-- Time of day. Honors the 12h/24h setting (ns.db.clock24; default = 24h).
-- ---------------------------------------------------------------------------
local function use24h()
	return not (ns.db and ns.db.clock24 == false)
end

-- Hour-of-day (0-23) -> label.
--   style "hm"   -> "14:00" / "2:00 PM"
--   style "tick" -> "14"    / "2a" / "2p"  (compact axis tick)
function F.FormatHour(hour, style)
	hour = hour % 24
	if use24h() then
		return (style == "tick") and format("%02d", hour) or format("%02d:00", hour)
	end
	local h12 = hour % 12
	if h12 == 0 then
		h12 = 12
	end
	if style == "tick" then
		return format("%d%s", h12, hour < 12 and "a" or "p")
	end
	return format("%d:00 %s", h12, hour < 12 and "AM" or "PM")
end

-- "Jun 15  14:30" / "Jun 15  2:30 PM" (date + time-of-day with minutes)
function F.FormatDateTime(t)
	local d = date("*t", t)
	if use24h() then
		return format("%s  %02d:%02d", date("%b %d", t), d.hour, d.min)
	end
	local h12 = d.hour % 12
	if h12 == 0 then
		h12 = 12
	end
	return format("%s  %d:%02d %s", date("%b %d", t), h12, d.min, d.hour < 12 and "AM" or "PM")
end

-- "Jun 15  14:00" / "Jun 15  2:00 PM" (hour bucket, no minutes)
function F.FormatDateHour(t)
	return format("%s  %s", date("%b %d", t), F.FormatHour(date("*t", t).hour, "hm"))
end

-- "06/15 14:00" / "06/15 2:00 PM" (compact prefix for the dense History table)
function F.FormatShortDateHour(t)
	local d = date("*t", t)
	return format("%02d/%02d %s", d.month, d.day, F.FormatHour(d.hour, "hm"))
end

-- ---------------------------------------------------------------------------
-- Region. The token economy is region-wide, so this is our history bucket key.
-- ---------------------------------------------------------------------------
local REGION_NAMES = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

function F.GetRegionName()
	local id = GetCurrentRegion and GetCurrentRegion() or 1
	return REGION_NAMES[id] or ("Region" .. tostring(id))
end

-- ---------------------------------------------------------------------------
-- Token icon. The "wow-token-gold" atlas is the gold-coin token art. Atlases
-- aren't guaranteed to resolve everywhere (and the TOC can't use them at all),
-- so we probe it and fall back to the classic ICONS file if it's missing.
-- ---------------------------------------------------------------------------
local TOKEN_ATLAS = "wow-token-gold"
local TOKEN_FALLBACK = "Interface\\ICONS\\wow_token01"

function F.SetTokenIcon(tex)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TOKEN_ATLAS) then
		tex:SetAtlas(TOKEN_ATLAS)
		return true
	end
	tex:SetTexture(TOKEN_FALLBACK)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border
	return false
end

-- Trend arrows. The glue atlases look far cleaner than the old scroll arrows,
-- but glue/FrameGeneral art doesn't always resolve in the live UI, so we probe
-- and fall back. Vertex color still tints either path.
local ARROW_UP = "poi-door-arrow-up"
local ARROW_DOWN = "poi-door-arrow-down"

function F.SetArrow(tex, isUp)
	local atlas = isUp and ARROW_UP or ARROW_DOWN
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		tex:SetAtlas(atlas, false)
		tex:SetSize(16, 16)
		return true
	end
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetTexture(isUp and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
	return false
end

-- ---------------------------------------------------------------------------
-- Color helpers
-- ---------------------------------------------------------------------------
-- Pick bull/bear/neutral from a signed delta. Returns r,g,b.
function F.TrendColor(delta)
	local C = ns.C
	if not delta or abs(delta) < 1e-9 then
		return C.Neutral[1], C.Neutral[2], C.Neutral[3]
	elseif delta > 0 then
		return C.Bull[1], C.Bull[2], C.Bull[3]
	else
		return C.Bear[1], C.Bear[2], C.Bear[3]
	end
end

function F.Hex(c)
	return format("%02x%02x%02x", floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
end

-- ---------------------------------------------------------------------------
-- Tiny object pool. Used by the candlestick renderer so we recycle textures
-- instead of allocating a fresh army of them on every chart refresh.
-- ---------------------------------------------------------------------------
function F.CreatePool(create, reset)
	local pool = { active = {}, free = {}, create = create, reset = reset }

	function pool:Acquire()
		local obj = tremove(self.free)
		if not obj then
			obj = self.create()
		end
		self.active[#self.active + 1] = obj
		return obj
	end

	function pool:ReleaseAll()
		for i = #self.active, 1, -1 do
			local obj = self.active[i]
			if self.reset then
				self.reset(obj)
			end
			self.free[#self.free + 1] = obj
			self.active[i] = nil
		end
	end

	return pool
end
