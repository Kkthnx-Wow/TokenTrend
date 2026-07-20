-- ---------------------------------------------------------------------------
-- TokenTrend - Import: seed history from a copy/paste string.
-- ---------------------------------------------------------------------------
-- New installs start with an empty chart, because the addon can only record
-- while you're logged in. kkthnx.com/wow/token hands out a short string built
-- from real recorded history (the same Blizzard-sourced data the site shows).
-- Pasting it here backfills the chart on day one.
--
-- Wire format (matches the site encoder exactly):
--   "<ver>;<REGION>;<t0>;<p0>;<dt1>,<dp1>;<dt2>,<dp2>;..."
--   - ver     protocol version (currently 1), plain base-10
--   - REGION  US / EU / KR / TW (must match the player's own region)
--   - t0/p0   first point: absolute unix seconds + whole gold, base36
--   - dtN,dpN each later point as base36 deltas from the previous point.
--             dt is always positive; dp may be negative ("-" prefix).
--
-- Parsing uses gmatch, NOT strsplit: a 500-sample seed is ~500 fields, and
-- WoW's strsplit truncates/misbehaves on inputs that large. gmatch streams the
-- fields with no count limit.
--
-- Decoded points ({ t = seconds, p = gold }) go straight to Data:Merge, which
-- validates ranges, buckets by sampleInterval, refuses to overwrite your own
-- first-hand samples, then sorts and prunes. So import is insert-only and safe
-- to run more than once - re-pasting never clobbers real data you recorded.
-- ---------------------------------------------------------------------------

local _, ns = ...
local F = ns.F

local Import = {}
ns.Import = Import

local tonumber = tonumber
local format = string.format
local gmatch = string.gmatch
local gsub = string.gsub
local strsub = string.sub
local SEED_VER = 1

-- Plausibility guard, mirrored from Sync so a corrupt paste can't inject junk.
local MIN_GOLD = 1000
local MAX_GOLD = 100000000

-- base36 -> integer. Accepts an optional leading '-'. Returns nil on anything
-- that isn't a clean base36 token, so a mangled field is skipped, not fatal.
local function from36(s)
	if not s or s == "" then return nil end
	local neg = false
	if strsub(s, 1, 1) == "-" then
		neg = true
		s = strsub(s, 2)
	end
	-- tonumber(_, 36) is lenient; validate the charset ourselves first.
	if s == "" or s:find("[^0-9a-zA-Z]") then return nil end
	local n = tonumber(s, 36)
	if not n then return nil end
	return neg and -n or n
end

-- Split on a single-char separator using gmatch (no field-count ceiling).
-- Captures every run between separators, including empty ones, so field
-- positions stay stable.
local function splitFields(str, sep)
	local out, n = {}, 0
	-- Pattern: greedily grab non-sep chars. We add a trailing sep so the final
	-- field is captured too.
	for field in gmatch(str .. sep, "([^" .. sep .. "]*)" .. sep) do
		n = n + 1
		out[n] = field
	end
	return out, n
end

-- Parse a seed string into { region = "US", points = { {t=,p=}, ... } }.
-- Returns nil + reason on malformed input.
function Import:Decode(str)
	if type(str) ~= "string" then
		return nil, ns.L["Nothing to import."]
	end

	-- Strip ALL whitespace (a paste can wrap or carry stray spaces/newlines).
	-- Safe because the format has no spaces in it.
	str = gsub(str, "%s", "")
	if str == "" then
		return nil, ns.L["Nothing to import."]
	end

	local fields, nfields = splitFields(str, ";")
	-- Minimum viable: ver, region, t0, p0 = 4 fields.
	if nfields < 4 then
		return nil, ns.L["That doesn't look like a valid seed string."]
	end

	if tonumber(fields[1]) ~= SEED_VER then
		return nil, ns.L["This seed is from a different version. Grab a fresh one."]
	end

	local region = fields[2]
	if not region or region == "" then
		return nil, ns.L["That doesn't look like a valid seed string."]
	end
	region = region:upper()

	local t = from36(fields[3])
	local p = from36(fields[4])
	if not t or not p then
		return nil, ns.L["That doesn't look like a valid seed string."]
	end

	local points = {}
	if p >= MIN_GOLD and p <= MAX_GOLD then
		points[1] = { t = t, p = p }
	end

	-- Remaining fields are "dt,dp" delta pairs.
	for i = 5, nfields do
		local field = fields[i]
		if field and field ~= "" then
			local ds, ps = field:match("^([^,]+),(.+)$")
			local dt, dp = from36(ds), from36(ps)
			if dt and dp then
				t = t + dt
				p = p + dp
				if p >= MIN_GOLD and p <= MAX_GOLD then
					points[#points + 1] = { t = t, p = p }
				end
			end
		end
	end

	return { region = region, points = points }
end

-- Decode + merge. Returns added, total, region on success; nil + reason on
-- failure. Enforces same-region, since the token economy is per region.
function Import:Apply(str)
	local decoded, err = self:Decode(str)
	if not decoded then
		return nil, err
	end

	local total = #decoded.points
	if total == 0 then
		return nil, ns.L["That seed has no data in it."]
	end

	local mine = F.GetRegionName()
	if decoded.region ~= mine then
		return nil, format(ns.L["That seed is for %s, but you're on %s."], decoded.region, mine)
	end

	local added = ns.Data:Merge(decoded.points)
	return added, total, decoded.region
end

return Import
