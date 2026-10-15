# TokenTrend

A price terminal for the WoW Token. Chart the price, read the trend, and time your buys.

## What it does

- Records the WoW Token price while you play and draws it as line charts, candlesticks, moving averages, and heatmaps.
- Flags 30-day lows with a buy banner and labels the current price as Cheap, Fair value, or Expensive.
- Shares history across all your characters in the same region, and can fill offline gaps by syncing with guildmates.
- Seeds a fresh install with real price history from [kkthnx.com/wow/token](https://kkthnx.com/wow/token). Addons cannot reach the internet, so a short copy-paste string bridges the two.
- Stays light on your game with event-based sampling, cached math, and a capped save file.

## Get it

Download the latest release from the [Releases](https://github.com/Kkthnx-Wow/TokenTrend/releases) page and drop the `TokenTrend` folder into `World of Warcraft/_retail_/Interface/AddOns`.

## Quick start

1. Install the addon and restart the game, or `/reload`.
2. Open the window with `/tt`. The first price shows up within seconds.
3. To start with a full chart: type `/tt url`, open the page it gives you, copy your region's string, then paste it with `/tt import`.
4. Cycle color themes with `/tt theme`. Everything else runs from the window.

## Support the work

Free forever. If it saved you time, chip in:

- [Ko-fi](https://ko-fi.com/kkthnx)
- [Buy Me a Coffee](https://buymeacoffee.com/kkthnx)
- [PayPal](https://www.paypal.com/paypalme/kkthnxtv)

Every bit goes back into building more.

## Community

- Glitch Haven Discord: https://discord.gg/FaVGhTYmck
- Website: https://kkthnx.com

## License

Released under the MIT License. LibGraph-2.0 ships bundled under its own original license. See LICENSE for details.
