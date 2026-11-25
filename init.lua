--- === AudioShortlist ===
---
--- A menu bar item that lists the audio devices you use, under names you choose, and makes the
--- one you pick the macOS default output or input. Everything else that is connected stays one
--- level down, under "Other outputs" and "Other inputs", built live each time the menu opens.
---
--- It only changes which device macOS uses by default; it never touches the audio stream.
---
--- With no configuration it lists every connected output and input. Example configuration:
--- ```
--- hs.loadSpoon("AudioShortlist")
--- spoon.AudioShortlist:configure({
---     outputs = {
---         { label = "Desk speakers", name = "External Headphones" },
---         { label = "Laptop", name = "MacBook Pro Speakers" },
---     },
---     inputs = {
---         { label = "Podcast mic", name = "Yeti Stereo Microphone" },
---         { label = "Dock headset", uid = "TS3 Plus" },  -- a fragment of the CoreAudio UID
---     },
--- }):start()
--- ```
---
--- Download: [https://github.com/johntrandall/AudioShortlist.spoon/releases/latest/download/AudioShortlist.spoon.zip](https://github.com/johntrandall/AudioShortlist.spoon/releases/latest/download/AudioShortlist.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "AudioShortlist"
obj.version = "1.0.0"
obj.author = "John Randall"
obj.homepage = "https://github.com/johntrandall/AudioShortlist.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- The one page this Spoon ever opens: the Sound pane of System Settings.
local SOUND_SETTINGS_URL = "x-apple.systempreferences:com.apple.Sound-Settings.extension"

local core = dofile(hs.spoons.resourcePath("core.lua"))

--- AudioShortlist.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
obj.logger = hs.logger.new("AudioShortlist")

--- AudioShortlist:init()
--- Method
--- Sets the default configuration. Called by `hs.loadSpoon()`; it does not create the menu bar item, `AudioShortlist:start()` does.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AudioShortlist object
function obj:init()
    self.config = core.configure({})
    return self
end

--- AudioShortlist:configure(options)
--- Method
--- Sets the configuration. Options not given keep their defaults. Raises an error naming the first bad option, and changes nothing, if any option is unknown or of the wrong type.
---
--- Parameters:
---  * options - A table with any of these keys:
---   * outputs - A list of favourite outputs, in menu order. Each is a table with `label` (what the menu shows) and either `name` (the device's exact macOS name) or `uid` (a fragment of its CoreAudio UID, for devices whose names are not unique). Default: empty, which lists every connected output.
---   * inputs - A list of favourite inputs, in the same form. Default: empty, which lists every connected input.
---   * alertSoundsFollowOutput - Boolean; choosing an output also makes it the device for alert sounds. Default: true.
---   * showMute - Boolean; show the "Mute output" row. Default: true.
---   * showOtherOutputs - Boolean; show the "Other outputs" submenu when outputs has favourites. Default: true.
---   * showOtherInputs - Boolean; show the "Other inputs" submenu when inputs has favourites. Default: true.
---   * showSoundSettings - Boolean; show the "Sound Settings…" row. Default: true.
---   * showTransport - Boolean; show "(USB)", "(Bluetooth)" and so on after names in the Other submenus. Default: true.
---   * title - String; text to show in the menu bar instead of an icon, such as "🔊". Default: nil (icons).
---   * mutedTitle - String; text while the output is muted. Default: the title.
---   * icon - String; a macOS system image name or the path of an image file, used as a template image. Default: "NSTouchBarAudioOutputVolumeHighTemplate".
---   * mutedIcon - String; the icon while the output is muted. Default: "NSTouchBarAudioOutputMuteTemplate".
---   * tooltip - String. Default: "Audio devices".
---   * autosaveName - String; the name macOS uses to keep the item's place in the menu bar. Default: "AudioShortlist".
---   * watch - "poll", "global" or "none": how the icon follows mute and device changes made outside the menu. "poll" checks every `pollInterval` seconds; "global" uses `hs.audiodevice.watcher`, which has one callback for all of Hammerspoon, so it replaces any callback another Spoon or your config has set. Default: "poll".
---   * pollInterval - Number of seconds between checks when watch is "poll"; at least 0.5. Default: 2.
---
--- Returns:
---  * The AudioShortlist object
---
--- Notes:
---  * Changing the configuration of a running menu takes effect at once.
function obj:configure(options)
    local config, err = core.configure(options)
    if not config then error("AudioShortlist: " .. err, 2) end
    self.config = config
    if self.item then self:stop():start() end
    return self
end

local function snapshot(devices)
    local out = {}
    for _, device in ipairs(devices or {}) do
        table.insert(out, { name = device:name(), uid = device:uid(), transport = device:transportType() })
    end
    return out
end

-- The current devices and defaults, as plain tables for core.lua.
local function readState()
    local output, input = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
    return {
        outputs = snapshot(hs.audiodevice.allOutputDevices()),
        inputs = snapshot(hs.audiodevice.allInputDevices()),
        default_output = output and output:uid() or nil,
        default_input = input and input:uid() or nil,
        muted = output and output:muted() or false,
    }
end

function obj:_makeDefault(kind, uid)
    local device = (kind == "output") and hs.audiodevice.findOutputByUID(uid) or hs.audiodevice.findInputByUID(uid)
    if not device then return "device is gone" end
    local ok
    if kind == "output" then
        ok = device:setDefaultOutputDevice()
        if ok and self.config.alertSoundsFollowOutput then device:setDefaultEffectDevice() end
    else
        ok = device:setDefaultInputDevice()
    end
    self:refresh()
    if not ok then return "macOS refused the change" end
    return "ok"
end

-- Turn the data actions from core.lua into menu callbacks.
function obj:_attach(menu)
    for _, item in ipairs(menu) do
        local action = item.action
        item.action = nil
        if action then
            if action.op == "select" then
                item.fn = function() self:_makeDefault(action.kind, action.uid) end
            elseif action.op == "toggleMute" then
                item.fn = function() self:toggleMute() end
            elseif action.op == "openSoundSettings" then
                item.fn = function() hs.urlevent.openURL(SOUND_SETTINGS_URL) end
            end
        end
        if item.menu then self:_attach(item.menu) end
    end
    return menu
end

function obj:_buildMenu()
    return self:_attach(core.buildMenu(self.config, readState()))
end

local function image(nameOrPath)
    return hs.image.imageFromName(nameOrPath) or hs.image.imageFromPath(nameOrPath)
end

--- AudioShortlist:refresh()
--- Method
--- Updates the menu bar icon or title to the current mute state. The menu itself is rebuilt every time it opens and needs no refresh.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AudioShortlist object
function obj:refresh()
    if not self.item then return self end
    local output = hs.audiodevice.defaultOutputDevice()
    local muted = output and output:muted() or false
    self._last = (output and output:uid() or "") .. (muted and ":muted" or "")
    local config = self.config
    if config.title then
        self.item:setIcon(nil)
        self.item:setTitle(muted and (config.mutedTitle or config.title) or config.title)
        return self
    end
    local icon = image(muted and config.mutedIcon or config.icon)
    if icon then
        self.item:setTitle(nil)
        self.item:setIcon(icon:setSize({ w = 18, h = 18 }), true)
    else
        self.logger.w("icon not found: " .. tostring(muted and config.mutedIcon or config.icon))
        self.item:setIcon(nil)
        self.item:setTitle(muted and "♪×" or "♪")
    end
    return self
end

function obj:_startWatching()
    local mode = self.config.watch
    if mode == "poll" then
        self._timer = hs.timer.doEvery(self.config.pollInterval, function()
            local output = hs.audiodevice.defaultOutputDevice()
            local now = (output and output:uid() or "") .. ((output and output:muted()) and ":muted" or "")
            if now ~= self._last then self:refresh() end
        end)
    elseif mode == "global" then
        self.logger.i("taking the hs.audiodevice.watcher callback (watch = \"global\")")
        hs.audiodevice.watcher.setCallback(function() self:refresh() end)
        hs.audiodevice.watcher.start()
        self._ownsGlobalWatcher = true
    end
end

function obj:_stopWatching()
    if self._timer then self._timer:stop(); self._timer = nil end
    if self._ownsGlobalWatcher then
        hs.audiodevice.watcher.setCallback(nil)
        self._ownsGlobalWatcher = nil
    end
end

--- AudioShortlist:start()
--- Method
--- Creates the menu bar item and starts following mute and device changes.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AudioShortlist object
---
--- Notes:
---  * The item is created with its autosave name in the same call. Set afterwards, macOS has already placed the item as new, and menu bar managers such as Ice or Thaw file it as hidden on every reload.
function obj:start()
    -- A second hs.loadSpoon() makes a fresh object; remove the old one's icon instead of leaving two.
    local previous = rawget(_G, "__AudioShortlistRunning")
    if previous and previous ~= self then pcall(function() previous:stop() end) end
    if self.item then self:stop() end
    self.item = hs.menubar.new(true, self.config.autosaveName)
    if not self.item then
        self.logger.e("could not create the menu bar item")
        return self
    end
    rawset(_G, "__AudioShortlistRunning", self)
    self.item:setTooltip(self.config.tooltip)
    self.item:setMenu(function() return self:_buildMenu() end)
    self:refresh()
    self:_startWatching()
    return self
end

--- AudioShortlist:stop()
--- Method
--- Removes the menu bar item and stops following changes.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AudioShortlist object
function obj:stop()
    self:_stopWatching()
    if self.item then self.item:delete(); self.item = nil end
    if rawget(_G, "__AudioShortlistRunning") == self then rawset(_G, "__AudioShortlistRunning", nil) end
    return self
end

--- AudioShortlist:status()
--- Method
--- Describes the current default output and input, with their labels when they are favourites.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string of two lines, such as "output: Laptop [MacBook Pro Speakers]"
function obj:status()
    return core.status(self.config, readState())
end

--- AudioShortlist:describe()
--- Method
--- Returns the menu as it would open now, as text: one row per line, "* " before a ticked row, submenus indented by four spaces.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string
---
--- Notes:
---  * For scripts and agents that cannot see the menu: `hs -c 'return spoon.AudioShortlist:describe()' </dev/null`
function obj:describe()
    return core.describe(core.buildMenu(self.config, readState()))
end

--- AudioShortlist:select(kind, label)
--- Method
--- Makes a device the default, by the label the menu shows for it.
---
--- Parameters:
---  * kind - "output" or "input"
---  * label - A favourite's label, or, when that kind has no favourites, a connected device's name as the menu shows it
---
--- Returns:
---  * "ok", or a short reason the switch did not happen ("not connected: …", "no such label: …")
function obj:select(kind, label)
    local uid, err = core.resolveSelect(self.config, readState(), kind, label)
    if not uid then return err end
    return self:_makeDefault(kind, uid)
end

--- AudioShortlist:toggleMute()
--- Method
--- Mutes or unmutes the default output device.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AudioShortlist object
function obj:toggleMute()
    local device = hs.audiodevice.defaultOutputDevice()
    if device then device:setMuted(not device:muted()) end
    return self:refresh()
end

function obj:_next(kind)
    local uid = core.nextDevice(self.config, readState(), kind)
    if uid then self:_makeDefault(kind, uid) end
    return self
end

--- AudioShortlist:showMenu()
--- Method
--- Opens the menu under the menu bar item, or at the mouse pointer when the item is not in the menu bar.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AudioShortlist object
function obj:showMenu()
    if not self.item then return self end
    local frame = self.item:frame()
    local point = frame and { x = frame.x, y = frame.y + frame.h } or hs.mouse.absolutePosition()
    self.item:popupMenu(point)
    return self
end

--- AudioShortlist:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for AudioShortlist.
---
--- Parameters:
---  * mapping - A table with any of these keys, each a hotkey spec such as `{ {"ctrl", "alt"}, "m" }`:
---   * toggleMute - Mute or unmute the default output
---   * nextOutput - Switch to the next connected output in the main list
---   * nextInput - Switch to the next connected input in the main list
---   * showMenu - Open the menu
---
--- Returns:
---  * The AudioShortlist object
function obj:bindHotkeys(mapping)
    hs.spoons.bindHotkeysToSpec({
        toggleMute = function() self:toggleMute() end,
        nextOutput = function() self:_next("output") end,
        nextInput = function() self:_next("input") end,
        showMenu = function() self:showMenu() end,
    }, mapping)
    return self
end

return obj
