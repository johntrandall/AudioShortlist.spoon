-- AudioShortlist core: the logic of the menu, in plain Lua with no Hammerspoon calls.
--
-- init.lua turns Hammerspoon's audio devices into plain snapshots ({ name, uid, transport })
-- and hands them here; this file decides what the menu shows and returns it as a table whose
-- actions are data ({ op = "select", kind = "output", uid = "..." }), not functions. Keeping
-- Hammerspoon out of this file is what lets tests/run.lua check it with a plain `lua`.
--
-- SPDX-License-Identifier: MIT

local core = {}

core.KINDS = { "output", "input" }

-- Every option the Spoon accepts, with its default. AudioShortlist:configure() refuses any other key.
core.DEFAULTS = {
    outputs = {},                  -- favourite outputs: { { label = "...", name = "..." | uid = "..." }, ... }
    inputs = {},                   -- favourite inputs, same shape
    alertSoundsFollowOutput = true, -- choosing an output also makes it the alert-sound device
    showMute = true,               -- the "Mute output" row
    showOtherOutputs = true,       -- the "Other outputs" submenu (connected outputs that are not favourites)
    showOtherInputs = true,        -- the "Other inputs" submenu
    showSoundSettings = true,      -- the "Sound Settings…" row
    showTransport = true,          -- "(USB)", "(Bluetooth)"… after a device's name in the Other submenus
    title = nil,                   -- text for the menu bar instead of an icon, e.g. "🔊"; nil uses icons
    mutedTitle = nil,              -- text while the output is muted; defaults to title
    icon = "NSTouchBarAudioOutputVolumeHighTemplate", -- system image name or image file path
    mutedIcon = "NSTouchBarAudioOutputMuteTemplate",
    tooltip = "Audio devices",
    autosaveName = "AudioShortlist",    -- keeps the icon's place in the menu bar across reloads
    watch = "poll",                -- how the icon follows changes made elsewhere: "poll", "global", or "none"
    pollInterval = 2,              -- seconds between checks when watch = "poll"
}

local TYPES = {
    outputs = "table", inputs = "table", alertSoundsFollowOutput = "boolean", showMute = "boolean",
    showOtherOutputs = "boolean", showOtherInputs = "boolean", showSoundSettings = "boolean",
    showTransport = "boolean", title = "string", mutedTitle = "string", icon = "string",
    mutedIcon = "string", tooltip = "string", autosaveName = "string", watch = "string",
    pollInterval = "number",
}

local WATCH_MODES = { poll = true, global = true, none = true }

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function validEntry(entry, where)
    if type(entry) ~= "table" then return nil, where .. " must be a table" end
    for key in pairs(entry) do
        if key ~= "label" and key ~= "name" and key ~= "uid" then
            return nil, where .. ": unknown key '" .. tostring(key) .. "'"
        end
    end
    if type(entry.label) ~= "string" or entry.label == "" then
        return nil, where .. ": label must be a non-empty string"
    end
    local byName, byUID = entry.name ~= nil, entry.uid ~= nil
    if byName == byUID then return nil, where .. ": give exactly one of name or uid" end
    local value = byName and entry.name or entry.uid
    if type(value) ~= "string" or value == "" then
        return nil, where .. ": " .. (byName and "name" or "uid") .. " must be a non-empty string"
    end
    return { label = entry.label, name = entry.name, uid = entry.uid }
end

-- Merge `options` over the defaults and check every value. Returns the full configuration, or
-- nil and a message naming the first problem. Nothing is half-applied.
function core.configure(options)
    if options ~= nil and type(options) ~= "table" then return nil, "configuration must be a table" end
    local config = copy(core.DEFAULTS)
    for key, value in pairs(options or {}) do
        local expected = TYPES[key]
        if not expected then return nil, "unknown option '" .. tostring(key) .. "'" end
        if type(value) ~= expected then
            return nil, "option '" .. key .. "' must be a " .. expected .. ", got " .. type(value)
        end
        config[key] = value
    end
    for _, list in ipairs({ "outputs", "inputs" }) do
        local entries, labels = {}, {}
        for i, entry in ipairs(config[list]) do
            local clean, err = validEntry(entry, list .. "[" .. i .. "]")
            if not clean then return nil, err end
            if labels[clean.label] then return nil, list .. ": label '" .. clean.label .. "' is used twice" end
            labels[clean.label] = true
            entries[i] = clean
        end
        config[list] = entries
    end
    if not WATCH_MODES[config.watch] then return nil, "option 'watch' must be \"poll\", \"global\" or \"none\"" end
    if config.pollInterval < 0.5 then return nil, "option 'pollInterval' must be at least 0.5 seconds" end
    return config
end

local function favourites(config, kind)
    return kind == "output" and config.outputs or config.inputs
end

-- True when a favourite entry names this device: by exact name, or by a fragment of its UID
-- (for devices whose names are not unique, or whose UID changes with the port they use).
function core.matches(entry, device)
    if entry.uid then return (device.uid or ""):find(entry.uid, 1, true) ~= nil end
    return device.name == entry.name
end

local function findDevice(devices, entry)
    for _, device in ipairs(devices) do
        if core.matches(entry, device) then return device end
    end
    return nil
end

local function isFavourite(config, kind, device)
    for _, entry in ipairs(favourites(config, kind)) do
        if core.matches(entry, device) then return true end
    end
    return false
end

-- Display names for a list of devices, with " #2", " #3"… added where names repeat (several
-- monitors of one model all report the same name).
local function displayNames(devices, withTransport)
    local seen, names = {}, {}
    for i, device in ipairs(devices) do
        local name = device.name or device.uid or "Unknown device"
        seen[name] = (seen[name] or 0) + 1
        local shown = seen[name] > 1 and (name .. " #" .. seen[name]) or name
        local transport = device.transport
        if withTransport and transport and transport ~= "" and transport ~= "UNKNOWN" then
            shown = shown .. "  (" .. transport .. ")"
        end
        names[i] = shown
    end
    return names
end

local function selectAction(kind, uid) return { op = "select", kind = kind, uid = uid } end

-- The rows for one kind's main list: favourites when any are configured, otherwise every
-- connected device of that kind.
local function mainRows(config, state, kind)
    local devices, current, rows = state[kind .. "s"] or {}, state["default_" .. kind], {}
    local entries = favourites(config, kind)
    if #entries == 0 then
        local names = displayNames(devices, false)
        for i, device in ipairs(devices) do
            table.insert(rows, { title = names[i], checked = device.uid == current, action = selectAction(kind, device.uid) })
        end
        if #rows == 0 then rows = { { title = "None connected", disabled = true } } end
        return rows
    end
    for _, entry in ipairs(entries) do
        local device = findDevice(devices, entry)
        if device then
            table.insert(rows, { title = entry.label, checked = device.uid == current, action = selectAction(kind, device.uid) })
        else
            table.insert(rows, { title = entry.label .. "  (not connected)", disabled = true })
        end
    end
    return rows
end

-- Connected devices of this kind that are not favourites, read from the snapshot each time.
local function otherRows(config, state, kind)
    local others, current = {}, state["default_" .. kind]
    for _, device in ipairs(state[kind .. "s"] or {}) do
        if not isFavourite(config, kind, device) then table.insert(others, device) end
    end
    local names, rows = displayNames(others, config.showTransport), {}
    for i, device in ipairs(others) do
        table.insert(rows, { title = names[i], checked = device.uid == current, action = selectAction(kind, device.uid) })
    end
    if #rows == 0 then rows = { { title = "None", disabled = true } } end
    return rows
end

-- The whole menu for a snapshot. `state` is
--   { outputs = {devices}, inputs = {devices}, default_output = uid, default_input = uid, muted = bool }
function core.buildMenu(config, state)
    local menu = { { title = "Output", disabled = true } }
    for _, row in ipairs(mainRows(config, state, "output")) do table.insert(menu, row) end
    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Input", disabled = true })
    for _, row in ipairs(mainRows(config, state, "input")) do table.insert(menu, row) end
    local tail = {}
    if config.showMute then
        table.insert(tail, { title = "Mute output", checked = state.muted == true, action = { op = "toggleMute" } })
    end
    if config.showOtherOutputs and #config.outputs > 0 then
        table.insert(tail, { title = "Other outputs", menu = otherRows(config, state, "output") })
    end
    if config.showOtherInputs and #config.inputs > 0 then
        table.insert(tail, { title = "Other inputs", menu = otherRows(config, state, "input") })
    end
    if config.showSoundSettings then
        table.insert(tail, { title = "Sound Settings…", action = { op = "openSoundSettings" } })
    end
    if #tail > 0 then
        table.insert(menu, { title = "-" })
        for _, row in ipairs(tail) do table.insert(menu, row) end
    end
    return menu
end

-- The menu as text, one row per line, "* " marking a ticked row and four spaces per submenu level.
function core.describe(menu)
    local lines = {}
    local function walk(items, indent)
        for _, item in ipairs(items) do
            if item.title == "-" then
                table.insert(lines, indent .. "----")
            else
                table.insert(lines, indent .. (item.checked and "* " or "  ") .. item.title)
                if item.menu then walk(item.menu, indent .. "    ") end
            end
        end
    end
    walk(menu, "")
    return table.concat(lines, "\n")
end

-- One line per kind: the current default device, with its favourite label when it has one.
function core.status(config, state)
    local lines = {}
    for _, kind in ipairs(core.KINDS) do
        local current, text = state["default_" .. kind], "none"
        for _, device in ipairs(state[kind .. "s"] or {}) do
            if device.uid == current then
                text = device.name or device.uid
                for _, entry in ipairs(favourites(config, kind)) do
                    if core.matches(entry, device) then text = entry.label .. " [" .. text .. "]"; break end
                end
                break
            end
        end
        table.insert(lines, kind .. ": " .. text)
    end
    return table.concat(lines, "\n")
end

-- The UID to switch to for a label as the menu shows it. Accepts only "output" or "input" and a
-- label string that is in the menu right now: a favourite's label, or, when that kind has no
-- favourites, a connected device's displayed name. Returns uid, or nil and a reason.
function core.resolveSelect(config, state, kind, label)
    if kind ~= "output" and kind ~= "input" then return nil, "kind must be \"output\" or \"input\"" end
    if type(label) ~= "string" then return nil, "label must be a string" end
    local devices, entries = state[kind .. "s"] or {}, favourites(config, kind)
    if #entries == 0 then
        local names = displayNames(devices, false)
        for i, device in ipairs(devices) do
            if names[i] == label then return device.uid end
        end
        return nil, "no such device: " .. label
    end
    for _, entry in ipairs(entries) do
        if entry.label == label then
            local device = findDevice(devices, entry)
            if not device then return nil, "not connected: " .. label end
            return device.uid
        end
    end
    return nil, "no such label: " .. label
end

-- The next connected device in the main list after the current default, wrapping round; for
-- the nextOutput / nextInput hotkeys. Returns uid, or nil when there is nothing to move to.
function core.nextDevice(config, state, kind)
    local devices, entries, candidates = state[kind .. "s"] or {}, favourites(config, kind), {}
    if #entries == 0 then
        for _, device in ipairs(devices) do table.insert(candidates, device.uid) end
    else
        for _, entry in ipairs(entries) do
            local device = findDevice(devices, entry)
            if device then table.insert(candidates, device.uid) end
        end
    end
    if #candidates == 0 then return nil end
    local current = state["default_" .. kind]
    for i, uid in ipairs(candidates) do
        if uid == current then return candidates[(i % #candidates) + 1] end
    end
    return candidates[1]
end

return core
