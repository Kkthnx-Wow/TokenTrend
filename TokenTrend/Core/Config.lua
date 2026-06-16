-- ---------------------------------------------------------------------------
-- TokenTrend - Defaults, SavedVariables init, and schema migration.
-- ---------------------------------------------------------------------------

local addonName, ns = ...

-- Defaults live on the namespace; they are the source of truth for the schema.
ns.defaults = {
	schemaVersion = 1,

	palette = "terminal", -- "terminal" | "lunar"

	-- Time display. true = 24-hour ("14:00"); false = 12-hour ("2:00 PM").
	clock24 = true,

	-- Polling + recording cadence. Token price updates server-side roughly
	-- every ~20 min, so we *request* often but only *commit* a history point
	-- once per sampleInterval to keep SavedVariables lean.
	pollInterval = 600, -- seconds between UpdateMarketPrice() requests (10m)
	sampleInterval = 1200, -- min seconds between committed history points (20m)
	maxSamples = 6000, -- hard cap per region (~80 days at 20m cadence)

	-- Chart state.
	chartMode = "line", -- "line" | "candle"
	candleGroup = "day", -- "hour" | "day"
	rangeDays = 30, -- visible window; 0 = all history
	showMA7 = true,
	showMA30 = true,

	-- History (OHLC table) state.
	historyGroup = "day", -- "hour" | "day" grouping for the table

	-- Alerts.
	alertOn30dLow = true,
	lowAlertTolerance = 0.01, -- treat "within 1% of 30d low" as a buy signal

	-- Peer sync: share price history with guild + group members to backfill the
	-- gaps from when you were offline. On by default; /tt sync toggles it.
	sync = true,

	-- Window geometry. width/height are fixed design constants (the window has
	-- no resize grip); only point/x/y are persisted as user state.
	window = {
		point = "CENTER",
		relPoint = "CENTER",
		x = 0,
		y = 0,
		width = 760,
		height = 500,
		shown = false,
	},

	-- Minimap button.
	minimap = {
		hide = false,
		angle = 215,
	},
}

-- Merge defaults into a saved table: fill missing keys, repair type drift,
-- recurse into nested tables. Keys the user has that aren't in defaults are
-- left alone (forward-compat for older clients reading newer saves).
local function copyDefaults(src, dst)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = copyDefaults(v, type(dst[k]) == "table" and dst[k] or {})
		elseif dst[k] == nil or type(dst[k]) ~= type(v) then
			dst[k] = v
		end
	end
	return dst
end

local function migrate(sv)
	-- Future schema bumps land here. v1 is the baseline, nothing to do yet.
	sv.settings.schemaVersion = ns.defaults.schemaVersion
end

local function initDB()
	TokenTrendDB = TokenTrendDB or {}
	local sv = TokenTrendDB

	sv.settings = copyDefaults(ns.defaults, sv.settings or {})
	sv.regions = sv.regions or {} -- [regionName] = { history = { {t=,p=}, ... } }

	migrate(sv)

	-- Local aliases everything else uses.
	ns.sv = sv
	ns.db = sv.settings
end

-- DB is guaranteed populated when ADDON_LOADED fires for us, and that's before
-- PLAYER_LOGIN, so the login queue can safely assume ns.db exists.
ns:RegisterEvent("ADDON_LOADED", function(_, loaded)
	if loaded == addonName then
		initDB()
	end
end)
