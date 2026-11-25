# AudioShortlist.spoon

A Hammerspoon Spoon that puts a short, named list of your own audio devices in the macOS menu bar, with everything else one level down.

[![Release](https://img.shields.io/github/v/release/johntrandall/AudioShortlist.spoon)](https://github.com/johntrandall/AudioShortlist.spoon/releases/latest) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## In plain terms

A Mac with a dock, a few monitors and a webcam can list a dozen sound devices, most of which you never use, and macOS cannot hide any of them or rename them. AudioShortlist gives you a menu with only the speakers and microphones you actually switch between, under names you choose, such as "Desk speakers" or "Podcast mic". The rest are still there, in a submenu.

- **Faster switching:** your three or four devices are the whole first menu, not lost in a list of twelve.
- **Clear names:** "Headset on the dock" instead of "Microphone In".
- **Nothing to keep up to date:** a new device you plug in appears by itself under "Other outputs" or "Other inputs".
- **No risk to your sound:** it only tells macOS which device to use, exactly as System Settings does, and never sits in the audio path.

## What it does

AudioShortlist adds one menu bar item. Its menu lists your favourite outputs and your favourite inputs, each under your label, with a tick on the current default and "(not connected)" on a favourite that is unplugged. Below them are "Mute output", the submenus "Other outputs" and "Other inputs" (every connected device that is not a favourite, read live when the menu opens), and "Sound Settings…". Choosing a device makes it the macOS default; an output also becomes the device for alert sounds, unless you turn that off.

With no configuration at all, it lists every connected output and input.

## Why it exists

The Sound item in the macOS menu bar lists every device and offers no way to hide or rename one. Paid switchers such as SoundSource can, and several free menu bar apps exist, but each is a separate app with its own update cycle, and some route audio through themselves. AudioShortlist is a few hundred lines of Lua inside Hammerspoon, which many Mac users already run, and it only changes the default device. Two other Spoons work with audio devices in different ways: [AudioPilot.spoon](https://github.com/hugoh/AudioPilot.spoon) switches automatically by a priority list, and the official [MicMute](https://github.com/Hammerspoon/Spoons/tree/master/Source/MicMute.spoon) mutes the microphone. Neither gives you a filtered menu.

## Install

Requires [Hammerspoon](https://www.hammerspoon.org) (tested with 1.1.1 on macOS 15).

Download [AudioShortlist.spoon.zip](https://github.com/johntrandall/AudioShortlist.spoon/releases/latest/download/AudioShortlist.spoon.zip), unzip it, and double-click `AudioShortlist.spoon`; Hammerspoon installs it into `~/.hammerspoon/Spoons/`. Or from a terminal:

```bash
git clone https://github.com/johntrandall/AudioShortlist.spoon.git ~/.hammerspoon/Spoons/AudioShortlist.spoon
```

## Quick start

Add this to `~/.hammerspoon/init.lua` and reload Hammerspoon:

```lua
hs.loadSpoon("AudioShortlist")
spoon.AudioShortlist:start()
```

A speaker icon appears in the menu bar, listing every connected device. To find the names to put in your favourites, ask it from a terminal (the `</dev/null` matters: without it `hs` waits for input and never returns):

```bash
hs -c 'return spoon.AudioShortlist:describe()' </dev/null
```

```text
  Output
* MacBook Pro Speakers
  External Headphones
  LG HDR 4K
----
  Input
* MacBook Pro Microphone
  Yeti Stereo Microphone
----
  Mute output
  Sound Settings…
```

Then name your favourites:

```lua
hs.loadSpoon("AudioShortlist")
spoon.AudioShortlist:configure({
    outputs = {
        { label = "Desk speakers", name = "External Headphones" },
        { label = "Laptop", name = "MacBook Pro Speakers" },
    },
    inputs = {
        { label = "Podcast mic", name = "Yeti Stereo Microphone" },
        { label = "Laptop mic", name = "MacBook Pro Microphone" },
    },
}):start()
```

## Configuration

`configure()` takes a table; every key is optional. A misspelt or mistyped option stops the load with an error naming it, rather than being ignored.

| Option | Default | What it does |
|---|---|---|
| `outputs` | `{}` | Favourite outputs, in menu order. Empty lists every connected output. |
| `inputs` | `{}` | Favourite inputs, in menu order. Empty lists every connected input. |
| `alertSoundsFollowOutput` | `true` | Choosing an output also moves alert sounds to it. |
| `showMute` | `true` | Show the "Mute output" row. |
| `showOtherOutputs` | `true` | Show "Other outputs" (only when `outputs` has favourites). |
| `showOtherInputs` | `true` | Show "Other inputs" (only when `inputs` has favourites). |
| `showSoundSettings` | `true` | Show "Sound Settings…". |
| `showTransport` | `true` | Show "(USB)", "(Bluetooth)" and so on in the Other submenus. |
| `title` | `nil` | Text instead of an icon, such as `"🔊"`. |
| `mutedTitle` | `title` | Text while the output is muted. |
| `icon` | `"NSTouchBarAudioOutputVolumeHighTemplate"` | A macOS system image name or an image file path. |
| `mutedIcon` | `"NSTouchBarAudioOutputMuteTemplate"` | The icon while the output is muted. |
| `tooltip` | `"Audio devices"` | The menu bar item's tooltip. |
| `autosaveName` | `"AudioShortlist"` | The name macOS uses to keep the icon's place in the menu bar. |
| `watch` | `"poll"` | How the icon follows mute and device changes made elsewhere: `"poll"`, `"global"` or `"none"`. |
| `pollInterval` | `2` | Seconds between checks when `watch` is `"poll"` (at least 0.5). |

**Favourites.** Each entry has a `label` and exactly one of:

- `name`: the device's exact macOS name, as `describe()` shows it.
- `uid`: a fragment of the device's CoreAudio UID. Use it when several devices share a name (identical monitors), or when a dock's UID changes with the port it is plugged into. Read UIDs with `hs -c 'for _,d in ipairs(hs.audiodevice.allOutputDevices()) do print(d:name(), d:uid()) end' </dev/null`.

**Watching for changes.** The icon shows mute state, so it has to notice when you mute from the keyboard or another app. `hs.audiodevice.watcher` would do that instantly, but it holds a single callback for all of Hammerspoon, and setting it would silently replace any other Spoon's or your own. So the default is `"poll"`: a timer reads the default output and its mute state every two seconds and redraws only when they change. Choose `"global"` if nothing else in your setup uses `hs.audiodevice.watcher`, or `"none"` to update only on the menu's own actions.

**Hotkeys.**

```lua
spoon.AudioShortlist:bindHotkeys({
    toggleMute = { { "ctrl", "alt", "cmd" }, "m" },
    nextOutput = { { "ctrl", "alt", "cmd" }, "o" },
    nextInput = { { "ctrl", "alt", "cmd" }, "i" },
    showMenu = { { "ctrl", "alt", "cmd" }, "a" },
})
```

`nextOutput` and `nextInput` step through the connected devices of the first list and wrap round.

## Scripting

Every method that reads or changes state also works from a terminal, which is how you can drive it from scripts:

```bash
hs -c 'return spoon.AudioShortlist:status()' </dev/null
hs -c 'return spoon.AudioShortlist:select("output", "Laptop")' </dev/null
```

```text
output: Desk speakers [External Headphones]
input: Podcast mic [Yeti Stereo Microphone]
ok
```

`select()` accepts only `"output"` or `"input"` and a label that is in the menu at that moment, and answers `ok`, `not connected: …` or `no such label: …`. Full method reference: [docs.json](docs.json), or the Hammerspoon console's `hs.doc`.

## Keeping the icon where you put it

If you use a menu bar manager (Ice, Bartender, Thaw), a Hammerspoon item can land in the hidden section on every reload. The cause is an item created first and given its autosave name afterwards: macOS has already placed it as new. AudioShortlist creates its item with the autosave name in the same call (`hs.menubar.new(true, "AudioShortlist")`), so after you drag it where you want it once, it stays. The same rule applies to any Hammerspoon menu bar item of your own.

## Status / Roadmap

Version 1.0: in daily use by its author on one Mac (macOS 15, Hammerspoon 1.1.1). The menu logic has automated tests; the menu bar item itself has been checked by hand ([tests/manual.md](tests/manual.md)).

- Volume control in the menu is not planned; the macOS volume keys already do that.
- Pull requests welcome for a per-device "set as input and output together" option.

## Contributing

Issues and pull requests are welcome at [github.com/johntrandall/AudioShortlist.spoon](https://github.com/johntrandall/AudioShortlist.spoon/issues). Please include the output of `describe()` and your Hammerspoon and macOS versions in a bug report.

For a change, run `make test` (needs `lua` 5.4 or later; `brew install lua`) and, if you changed a doc comment, `make docs` (needs Hammerspoon running). The menu logic is in `core.lua`, which has no Hammerspoon calls so that it can be tested with a plain `lua`; `init.lua` is the Hammerspoon layer.

## License

MIT; see [LICENSE](LICENSE).
