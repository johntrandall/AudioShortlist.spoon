# Changelog

All notable changes to AudioShortlist.spoon. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-25

### Added

- Menu bar item listing favourite outputs and inputs under your own labels, with a tick on the current default and "(not connected)" on an unplugged favourite.
- "Other outputs" and "Other inputs" submenus, built live from the connected devices that are not favourites; repeated device names are numbered (#2, #3).
- With no favourites configured, every connected device is listed.
- `configure()` with checked options: favourites matched by exact name or by a CoreAudio UID fragment, rows that can be switched off, title text or template icons, autosave name, and how the icon follows outside changes (`poll`, `global` or `none`).
- `status()`, `describe()`, `select()`, `toggleMute()`, `showMenu()` and `bindHotkeys()` (toggleMute, nextOutput, nextInput, showMenu).
- Tests of the menu logic that run with a plain `lua` (`make test`), and a manual test sheet for the menu bar item.

[1.0.0]: https://github.com/johntrandall/AudioShortlist.spoon/releases/tag/v1.0.0
