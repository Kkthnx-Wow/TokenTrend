-- ---------------------------------------------------------------------------
-- TokenTrend - Locale (enUS, the default fallback).
-- ---------------------------------------------------------------------------
-- Every user-facing string lives here. No raw literals in UI code.

local _, ns = ...

local L = {}
ns.L = L

-- Safety net: a read of an undefined key returns the key text itself instead of
-- nil. A stray L["Typo"] then shows readable English rather than erroring inside
-- a SetText/format call, and untranslated keys in future locales degrade to
-- enUS. (Blizzard uses the same __index-fallback trick on its own string tables.)
setmetatable(L, {
	__index = function(_, key)
		return key
	end,
})

-- General
L["TokenTrend"] = "TokenTrend"
L["WoW Token"] = "WoW Token"
L["Region"] = "Region"
L["Last update"] = "Last update"
L["Never"] = "Never"
L["just now"] = "just now"
L["Refresh"] = "Refresh"
L["Close"] = "Close"
L["No data yet"] = "No data yet"
L["Waiting for first price..."] = "Waiting for first price..."
L["No data in the selected range."] = "No data in the selected range."
L["Collecting price history - the chart fills in as new prices are recorded."] = "Collecting price history - the chart fills in as new prices are recorded."

-- Header / price
L["Current Price"] = "Current Price"
L["Change"] = "Change"
L["No change"] = "No change"

-- Tabs
L["Chart"] = "Chart"
L["Stats"] = "Stats"
L["Volatility"] = "Volatility"
L["History"] = "History"

-- History (OHLC) table
L["Historical Data"] = "Historical Data"
L["Date"] = "Date"
L["Chg %"] = "Chg %"
L["Page %d / %d"] = "Page %d / %d"
L["%d-%d of %d"] = "%d-%d of %d"

-- Chart controls
L["Line"] = "Line"
L["Candles"] = "Candles"
L["Hourly"] = "Hourly"
L["Daily"] = "Daily"
L["MA7"] = "MA7"
L["MA30"] = "MA30"
L["7D"] = "7D"
L["30D"] = "30D"
L["90D"] = "90D"
L["All"] = "All"
L["Price"] = "Price"
L["7-day moving average"] = "7-day moving average"
L["30-day moving average"] = "30-day moving average"
L["Range"] = "Range"

-- Stats labels
L["Open"] = "Open"
L["High"] = "High"
L["Low"] = "Low"
L["Close"] = "Close"
L["7-Day Low"] = "7-Day Low"
L["7-Day High"] = "7-Day High"
L["30-Day Low"] = "30-Day Low"
L["30-Day High"] = "30-Day High"
L["All-Time Low"] = "All-Time Low"
L["All-Time High"] = "All-Time High"
L["7-Day Avg"] = "7-Day Avg"
L["30-Day Avg"] = "30-Day Avg"
L["Samples"] = "Samples"
L["Tracking since"] = "Tracking since"
L["Previous Close"] = "Previous Close"
L["Day Range"] = "Day Range"

-- Valuation (30-day range gauge)
L["30-Day Range"] = "30-Day Range"
L["Cheap"] = "Cheap"
L["Fair value"] = "Fair value"
L["Expensive"] = "Expensive"
L["above 30-day low"] = "above 30-day low"
L["Trend"] = "Trend"
L["Rising"] = "Rising"
L["Falling"] = "Falling"
L["Flat"] = "Flat"

-- Alerts / signals
L["BUY SIGNAL"] = "BUY SIGNAL"
L["At or near a 30-day low. Good time to buy."] = "At or near a 30-day low. Good time to buy."
L["Token is at a 30-day low (%s)."] = "Token is at a 30-day low (%s)."
L["Cheapest hours of the day"] = "Cheapest hours of the day"
L["Cheapest days of the week"] = "Cheapest days of the week"
L["Best time to buy"] = "Best time to buy"
L["Worst time to buy"] = "Worst time to buy"
L["Not enough history yet. Keep playing - data builds over time."] = "Not enough history yet. Keep playing - data builds over time."

-- Settings / palette
L["Theme"] = "Theme"
L["The Terminal"] = "The Terminal"
L["Lunar Exchange"] = "Lunar Exchange"

-- Slash command feedback
L["Commands:"] = "Commands:"
L["/tt - toggle the window"] = "/tt - toggle the window"
L["/tt show - open the window"] = "/tt show - open the window"
L["/tt hide - close the window"] = "/tt hide - close the window"
L["/tt theme - cycle color theme"] = "/tt theme - cycle color theme"
L["/tt refresh - request a fresh price"] = "/tt refresh - request a fresh price"
L["Theme set to %s."] = "Theme set to %s."

-- Day-of-week short names (Sunday-first, matches date('*t').wday)
L["DAY_1"] = "Sun"
L["DAY_2"] = "Mon"
L["DAY_3"] = "Tue"
L["DAY_4"] = "Wed"
L["DAY_5"] = "Thu"
L["DAY_6"] = "Fri"
L["DAY_7"] = "Sat"
