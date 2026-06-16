# Changelog

All notable changes to TokenTrend are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-15

### Added
- Initial release.
- WoW Token price tracking via `C_WowTokenPublic.UpdateMarketPrice()` /
  `GetCurrentMarketPrice()`, with per-region history persisted in SavedVariables.
- Live price header with bull/bear change arrow showing the net change vs the
  previous close (day-over-day move), plus a centered Day Range bar.
- Line chart (LibGraph-2.0) with optional 7-day and 30-day moving averages.
- Candlestick charts (hourly / daily) drawn from pooled textures.
- Hover crosshair + readout: snaps to the nearest sample (date + price in line
  mode, full OHLC in candle mode).
- 30-day-low buy signal banner.
- Historical Data tab: paginated OHLC table (date, close, open, high, low,
  day-over-day %), daily or hourly, newest first - NASDAQ "Historical Data" style.
- Time-of-day and day-of-week volatility heatmaps with a "best time to buy" callout.
- Stats panel: 7d/30d/all-time low, high, average; previous close; day range;
  sample count; tracking-start date; plus a 30-Day Range gauge with a
  Cheap / Fair value / Expensive valuation verdict.
- Two color themes — The Terminal (default) and Lunar Exchange — switchable live.
- 12- or 24-hour time display across the chart hover, History table, and Stats
  volatility hours, toggled live via a compact footer button or `/tt clock`
  (24-hour by default).
- Peer history sync: backfill the gaps from when you were offline by exchanging
  price samples with guild and party/raid members in your region. Insert-only
  merge (your own readings always win), plausibility-bounded, instance-safe, and
  toggleable with `/tt sync` (on by default).
- Sync panel: a footer **Sync** button opens a popover showing on/off status (with
  an Enable/Disable toggle), samples gained this session, and who you've
  backfilled from / shared with.
- Hover tooltips on every button (tabs, footer controls, chart/history toggles,
  close, and the sync toggle) explaining what each one does.
- Minimap button and `/tt` slash commands.
- Midnight (12.0) secret-value guards on all price reads; sync stands down inside
  instances, where addon comms are blocked.
