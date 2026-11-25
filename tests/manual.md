# Manual tests

What `tests/run.lua` cannot reach: the menu bar item, the icon, macOS itself and real devices. Run these on a Mac with Hammerspoon before a release, and record the result in the release notes. Every `hs` command needs `</dev/null`, or it waits for input and never returns.

| # | Check | How | Expected |
|---|---|---|---|
| 1 | Loads with no configuration | `hs.loadSpoon("AudioShortlist"); spoon.AudioShortlist:start()` and reload | One speaker icon; `describe()` lists every connected device, no Other submenus |
| 2 | Favourites | configure two outputs and two inputs, one of them unplugged | `describe()` shows labels in order, the unplugged one as "(not connected)", the rest under Other |
| 3 | Switch input | `select("input", <label>)`, then back | `ok` both times; `status()` follows; System Settings › Sound agrees |
| 4 | Switch output | `select("output", <label>)`, then back | `ok`; alert sounds move too unless `alertSoundsFollowOutput = false` |
| 5 | Bad input to `select()` | `select("speaker", "x")`, `select("output", 42)` | `kind must be "output" or "input"`, `label must be a string`; nothing changes |
| 6 | Bad configuration | `configure({ colour = "red" })` | error naming `colour`; the running menu stays as it was |
| 7 | Mute follows outside changes | press the mute key with `watch = "poll"` | icon changes within `pollInterval` seconds |
| 8 | One icon after reloads | reload Hammerspoon twice; also call `start()` twice | exactly one icon |
| 9 | Icon keeps its place | drag the icon (Command-drag) somewhere, reload | it stays there, also with a menu bar manager such as Ice or Thaw |
| 10 | Release archive installs | unzip `AudioShortlist.spoon.zip` into an empty `~/.hammerspoon/Spoons/` and run check 1 | as check 1 |
| 11 | Menu by eye | click the icon | the rows `describe()` printed, with ticks, separators and submenus |
