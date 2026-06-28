<div align="center">
# TokenTrend

**A financial-terminal for the WoW Token — chart the price, read the trend, and time your buys like a market.**

*Stock-market-grade tooling for a single number: what your region's WoW Token costs right now, and where it's been.*

<img width="256" height="256" alt="New Project (3)" src="https://github.com/user-attachments/assets/b0468d4d-8255-469a-88d0-b8c2dd2a29b9" />

</div>

---

## Overview

**TokenTrend** turns the WoW Token's market price into a proper trading terminal. It quietly samples the price while you play, banks the history in SavedVariables, and renders it as line charts, candlesticks, moving averages, and volatility heatmaps — so "is now a good time to buy?" becomes a glance, not a guess.

Because addons only run while you're logged in, TokenTrend can't see the past. It builds your price history one sample at a time; the longer you play, the richer your charts get.

- **Terminal-grade, not toy** — candlesticks, moving averages, OHLC tables, and a buy signal, all from live data.
- **Region-aware** — the token economy is region-wide, so history is keyed by region and shared across your characters (and, optionally, your guild).
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
| `/tt sync` | Toggle peer history sharing (on by default) |
| `/tt clock` | Toggle 12- / 24-hour time (24-hour by default) |

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
- **12 / 24-hour time** — every time-of-day readout (chart hover, History table, volatility hours) follows your preference. Flip it live with the compact footer clock button or `/tt clock` (24-hour by default).

### Quality of Life

- **Peer history sync** — backfill your offline gaps by trading price samples with guildmates and groupmates. See **[Peer Sync](#peer-sync)** below for the full picture.
- **Minimap button** — left-click to toggle, drag to reposition.
- **Slash commands** — full `/tt` command set (see above).
- **Lean saves** — samples are committed at most once per 20 minutes and capped per region, so your SavedVariables stay small.

---

## Peer Sync

Because addons only run while you're logged in, you can only record the token price during your own play sessions — every hour you're offline is a hole in your chart. **Peer Sync fills those holes** by swapping price history with other TokenTrend users, so your charts, candles, and volatility heatmaps are rich from the first session instead of after weeks of solo collecting.

> **It can't change *today's* price.** The current market price is a server value — identical for everyone in your region. Sync only enriches the **history behind** that number; it never touches the live price.

### What syncs with whom

- **Scope:** your **guild** and your **party/raid**. WoW has no global addon channel, so reach is bounded to people you're actually grouped or guilded with.
- **Region-scoped:** the token economy is region-wide, so peers only accept data tagged for the **same region**. Cross-region messages are dropped.
- **On by default**, toggled any time with `/tt sync` or the panel's Enable/Disable button.

### How peers exchange data

Each addon advertises a compact per-day **coverage manifest** (how many samples it holds for each day, plus a checksum). A peer compares it to its own coverage, **requests only the days it's missing**, and the other side streams back just those samples. Everything flows through a **throttled, disconnect-safe send queue** so a busy guild can't get you booted for chat flooding.

### Trust & anti-poisoning

Sync uses a deliberately conservative "basic" trust model:

- **Insert-only merge** — incoming samples only fill **empty** time-slots. Your own first-hand readings are **never overwritten** by a peer's.
- **Plausibility bounds** — prices outside a sane range (roughly 1k–100M gold) are rejected as garbage.
- **No time travel** — future-dated samples are refused.
- **Same-region only** and a **per-peer session budget** cap how much any single peer can hand you.

### Safety & courtesy

- **Instance-safe** — every send and receive stands down while you're inside a dungeon, raid, or other instance (addon comms are blocked there in Midnight 12.0).
- **Quiet** — roster changes are debounced, re-advertisements are rate-limited, and there's no global spam.

### The Sync panel

The footer **Sync** button opens a popover showing, at a glance:

- **Status** with an **Enable / Disable** toggle.
- **Samples gained this session.**
- **Backfilled from** — peers whose data filled your gaps.
- **Shared with** — peers you helped in return.

---

## Configuration

Most things are controlled inline from the window itself:

- **Theme** — `/tt theme`, or the **Theme** button in the footer.
- **Chart mode / range / moving averages** — the toggle row above the chart.
- **History grouping** — Daily / Hourly toggles on the History tab.
- **Peer sync** — `/tt sync` toggles history sharing on/off (on by default).
- **Clock** — `/tt clock`, or the **24h / 12h** button in the footer.

All toggles apply **live** — TokenTrend re-themes and re-renders without a `/reload`.

---

## How It Works

1. **Fetch** — `C_WowTokenPublic.UpdateMarketPrice()` asks the server for an update; the `TOKEN_MARKET_PRICE_UPDATED` event then lets us read the value with `C_WowTokenPublic.GetCurrentMarketPrice()`. A `C_Timer` ticker keeps the heartbeat going.
2. **Store** — each price is logged with a timestamp into `TokenTrendDB`, keyed by **region**. Samples are committed at most once per 20 minutes and capped at 6000 points per region to keep the save file lean.
3. **Analyze** — moving averages (sliding window, O(n)), candle aggregation, trailing lows/highs, and hour/weekday volatility buckets are computed on demand and **memoized** against a data-revision counter, so nothing recomputes until a new price actually lands.
4. **Render** — the line view uses LibGraph; candlesticks are hand-drawn axis-aligned texture rectangles from a reusable pool.
5. **Sync** *(optional)* — over WoW's addon channels (guild + party/raid; there is no global channel), peers exchange a compact per-day coverage **manifest**, request only the days they're missing, and stream back the buckets — delivered through a throttled, disconnect-safe send queue and merged insert-only.

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
│   ├── Data.lua        # token polling + history recording + peer merge
│   ├── Analysis.lua    # MAs, candles, lows/highs, volatility (memoized)
│   └── Sync.lua        # peer-to-peer history backfill over addon channels
├── UI/
│   ├── Main.lua        # window chrome, theming, header, tabs, footer
│   ├── SyncPanel.lua   # footer Sync popover (status, gained, peers)
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
