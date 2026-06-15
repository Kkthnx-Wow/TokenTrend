<div align="center">

# TokenTrend

**A financial-terminal for the WoW Token — chart the price, read the trend, and time your buys like a market.**

*Stock-market-grade tooling for a single number: what your region's WoW Token costs right now, and where it's been.*

</div>

---

## Overview

**TokenTrend** turns the WoW Token's market price into a proper trading terminal. It quietly samples the price while you play, banks the history in SavedVariables, and renders it as line charts, candlesticks, moving averages, and volatility heatmaps — so "is now a good time to buy?" becomes a glance, not a guess.

Because addons only run while you're logged in, TokenTrend can't see the past. It builds your price history one sample at a time; the longer you play, the richer your charts get.

- **Terminal-grade, not toy** — candlesticks, moving averages, OHLC tables, and a buy signal, all from live data.
- **Region-aware** — the token economy is region-wide, so history is keyed by region and shared across your characters.
- **Performance-first** — event-driven sampling, memoized analysis, pooled textures, and a hover readout that idles when the mouse isn't on the plot.
- **Midnight-ready** — every price read is guarded against secret values, so nothing errors in combat.

---

## Installation

**Manual**
1. Download the latest release and extract the `TokenTrend` folder into `World of Warcraft\_retail_\Interface\AddOns`.
2. Restart the game (or `/reload` if you're already in-game).
3. Open the window with `/tt`. The first price lands within a few seconds; charts fill in as history accumulates.

There's nothing to configure to get started — TokenTrend begins recording the moment it loads.

---

## Getting Started

| Command | Description |
| --- | --- |
| `/tt` or `/tokentrend` | Toggle the window |
| `/tt show` | Open the window |
| `/tt hide` | Close the window |
| `/tt theme` | Cycle the color theme |
| `/tt refresh` | Request a fresh price from the server |

You can also **left-click** the minimap button to toggle the window, and **drag** it around the minimap ring to reposition it.

---

## Features

### Live Price
- **Price header** — the current token price with a bull/bear arrow showing the **net change vs the previous close** (the day-over-day move), color-coded green/red/neutral.
- **Day Range bar** — a centered low↔high gauge marking where today's price sits between its own low and high.

### Charts
- **Line chart** — price plotted with **LibGraph-2.0**, with optional **7-day** and **30-day moving averages** overlaid so you can instantly see whether the current price is above or below its historical norm.
- **Candlestick charts** — group raw samples into **hourly** or **daily** Open/High/Low/Close candles, hand-drawn from pooled textures (green = bullish, red = bearish).
- **Hover readout** — a crosshair snaps to the nearest sample as you move across the plot: date + price in line mode, full OHLC in candle mode. It arms only while the mouse is over the chart, so it costs nothing at rest.
- **Range selector** — view the last 7 / 30 / 90 days or all of history.

### Signals & Timing
- **Buy signal** — a green banner + arrow fires when the price drops to (or within 1% of) a **30-day low**.
- **Volatility heatmaps** — time-of-day and day-of-week grids showing which **hours** and **weekdays** historically offer the cheapest prices, with a **"best time to buy"** callout.
- **30-Day Range gauge** — where the current price sits inside its 30-day band, tagged **Cheap / Fair value / Expensive**.

### Stats & History
- **Stats panel** — previous close, day range, 7-day / 30-day / all-time low, high and average, sample count, and tracking-start date.
- **Historical Data table** — a paginated **OHLC table** (date, close, open, high, low, day-over-day %), daily or hourly, newest first — NASDAQ "Historical Data" style. Rows are virtualized, so a long history costs the same as a short one.

### Appearance
- **Two themes** — *The Terminal* (cyan on charcoal, default) and *Lunar Exchange* (blue on silver). Swap live with `/tt theme` — no reload.
- **Themed chrome** — custom close button, footer controls, and a token-gold brand icon, all skinned to match the active palette.

### Quality of Life
- **Minimap button** — left-click to toggle, drag to reposition.
- **Slash commands** — full `/tt` command set (see above).
- **Lean saves** — samples are committed at most once per 20 minutes and capped per region, so your SavedVariables stay small.

---

## Configuration

Most things are controlled inline from the window itself:

- **Theme** — `/tt theme`, or the **Theme** button in the footer.
- **Chart mode / range / moving averages** — the toggle row above the chart.
- **History grouping** — Daily / Hourly toggles on the History tab.

All toggles apply **live** — TokenTrend re-themes and re-renders without a `/reload`.

---

## How It Works

1. **Fetch** — `C_WowTokenPublic.UpdateMarketPrice()` asks the server for an update; the `TOKEN_MARKET_PRICE_UPDATED` event then lets us read the value with `C_WowTokenPublic.GetCurrentMarketPrice()`. A `C_Timer` ticker keeps the heartbeat going.
2. **Store** — each price is logged with a timestamp into `TokenTrendDB`, keyed by **region**. Samples are committed at most once per 20 minutes and capped at 6000 points per region to keep the save file lean.
3. **Analyze** — moving averages (sliding window, O(n)), candle aggregation, trailing lows/highs, and hour/weekday volatility buckets are computed on demand and **memoized** against a data-revision counter, so nothing recomputes until a new price actually lands.
4. **Render** — the line view uses LibGraph; candlesticks are hand-drawn axis-aligned texture rectangles from a reusable pool.

### Midnight (12.0) note

Money values can be *secret* in combat. TokenTrend guards every price read with `issecretvalue()` and simply skips a sample rather than doing arithmetic on a sealed value — it'll catch the next clean update.

---

## Layout

```
TokenTrend/
├── TokenTrend.toc
├── Core/
│   ├── Namespace.lua   # namespace, palettes, tiny event/signal engine
│   ├── Locales/enUS.lua
│   ├── Util.lua        # formatting, secret guards, math, object pool
│   ├── Config.lua      # defaults + SavedVariables init/migration
│   └── Core.lua        # init glue + slash commands
├── Modules/
│   ├── Data.lua        # token polling + history recording
│   └── Analysis.lua    # MAs, candles, lows/highs, volatility (memoized)
├── UI/
│   ├── Main.lua        # window chrome, theming, header, tabs, footer
│   ├── ChartHover.lua  # chart crosshair, marker, and hover readout
│   ├── Chart.lua       # line (LibGraph) + candlestick rendering
│   ├── Stats.lua       # metrics + volatility heatmaps
│   ├── History.lua     # paginated OHLC table
│   └── Minimap.lua     # minimap button
└── Libs/
    └── LibGraph-2.0/
```

---

## Requirements

- World of Warcraft Retail (Midnight, interface `120007`).
- **LibGraph-2.0** is bundled — no separate install needed.

---

## Credits

TokenTrend stands on the shoulders of others, borrowed with respect:

- **Cryect / Xinhuan** — [LibGraph-2.0](https://www.wowace.com/projects/libgraph-2-0), the line-charting engine.
- **NASDAQ** — inspiration for the Historical Data table, Day Range bar, and valuation gauges.
- **Blizzard** — the `C_WowTokenPublic` API and the FrameXML patterns this is built on.

---

## License

LibGraph-2.0 © Cryect / Xinhuan, used under its original license. TokenTrend code is free to use and modify.

<div align="center">

Built for traders, tinkerers, and gold-makers. **GLHF.**

</div>
