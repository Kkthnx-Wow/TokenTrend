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

-- Sync panel
L["Sync"] = "Sync"
L["Peer Sync"] = "Peer Sync"
L["Status"] = "Status"
L["Enabled"] = "Enabled"
L["Disabled"] = "Disabled"
L["Enable"] = "Enable"
L["Disable"] = "Disable"
L["Backfilled from"] = "Backfilled from"
L["Shared with"] = "Shared with"
L["Gained this session: %s"] = "Gained this session: %s"
L["samples"] = "samples"
L["Nobody yet"] = "Nobody yet"
L["...and %d more"] = "...and %d more"

-- Slash command feedback
L["Commands:"] = "Commands:"
L["/tt - toggle the window"] = "/tt - toggle the window"
L["/tt show - open the window"] = "/tt show - open the window"
L["/tt hide - close the window"] = "/tt hide - close the window"
L["/tt theme - cycle color theme"] = "/tt theme - cycle color theme"
L["/tt refresh - request a fresh price"] = "/tt refresh - request a fresh price"
L["/tt sync - toggle history sharing"] = "/tt sync - toggle history sharing"
L["/tt clock - toggle 12/24-hour time"] = "/tt clock - toggle 12/24-hour time"
L["Theme set to %s."] = "Theme set to %s."
L["History sharing enabled."] = "History sharing enabled."
L["History sharing disabled."] = "History sharing disabled."
L["Clock set to %s."] = "Clock set to %s."

-- Clock / time format
L["24h"] = "24h"
L["12h"] = "12h"
L["24-hour"] = "24-hour"
L["12-hour"] = "12-hour"

-- Button tooltips (title -> body). Titles reuse existing label keys above.
L["Clock"] = "Clock"
L["Next page"] = "Next page"
L["Previous page"] = "Previous page"
L["Close the window. Type /tt to reopen."] = "Close the window. Type /tt to reopen."
L["Cycle between the color themes."] = "Cycle between the color themes."
L["Request a fresh token price from the server."] = "Request a fresh token price from the server."
L["Open the peer sync panel - see what history you've shared and gained."] = "Open the peer sync panel - see what history you've shared and gained."
L["Showing 24-hour time. Click for 12-hour (AM/PM)."] = "Showing 24-hour time. Click for 12-hour (AM/PM)."
L["Showing 12-hour time. Click for 24-hour."] = "Showing 12-hour time. Click for 24-hour."
L["Draw price as a line over time."] = "Draw price as a line over time."
L["Draw open/high/low/close candlesticks."] = "Draw open/high/low/close candlesticks."
L["Toggle the 7-day moving average overlay."] = "Toggle the 7-day moving average overlay."
L["Toggle the 30-day moving average overlay."] = "Toggle the 30-day moving average overlay."
L["Group candles into one-hour buckets."] = "Group candles into one-hour buckets."
L["Group candles into one-day buckets."] = "Group candles into one-day buckets."
L["Show the last %d days."] = "Show the last %d days."
L["Show the entire recorded history."] = "Show the entire recorded history."
L["Show one row per day (daily OHLC)."] = "Show one row per day (daily OHLC)."
L["Show one row per hour (hourly OHLC)."] = "Show one row per hour (hourly OHLC)."
L["Show older entries."] = "Show older entries."
L["Show newer entries."] = "Show newer entries."
L["Close this panel."] = "Close this panel."
L["Stop sharing and receiving price history."] = "Stop sharing and receiving price history."
L["Share price history with guild and group members to fill gaps."] = "Share price history with guild and group members to fill gaps."

-- Tab tooltips
L["Price over time with moving averages and candlesticks."] = "Price over time with moving averages and candlesticks."
L["Highs, lows, averages, and best times to buy."] = "Highs, lows, averages, and best times to buy."
L["Browse the full price history as a sortable table."] = "Browse the full price history as a sortable table."

-- Day-of-week short names (Sunday-first, matches date('*t').wday)
L["DAY_1"] = "Sun"
L["DAY_2"] = "Mon"
L["DAY_3"] = "Tue"
L["DAY_4"] = "Wed"
L["DAY_5"] = "Thu"
L["DAY_6"] = "Fri"
L["DAY_7"] = "Sat"
