-- Tests for core.lua: configuration checks, device matching, the menu table, status, select and
-- next-device logic. They need only a Lua 5.4 or later interpreter, no Hammerspoon:
--     lua tests/run.lua
-- What they cannot reach (the menu bar item, the icon, real devices) is covered by tests/manual.md.
--
-- SPDX-License-Identifier: MIT

package.path = "./?.lua;" .. package.path
local core = require("core")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(actual, expected, what)
    if actual ~= expected then
        error((what or "value") .. ":\n--- expected\n" .. tostring(expected) .. "\n--- actual\n" .. tostring(actual), 2)
    end
end
local function lines(...) return table.concat({ ... }, "\n") end

-- A fixture made of invented devices; none of them is anyone's real setup.
local function fixture()
    return {
        outputs = {
            { name = "Studio Display Speakers", uid = "AppleUSBAudioEngine:Apple:Studio:1111:2", transport = "USB" },
            { name = "Built-in Speakers", uid = "BuiltInSpeakerDevice", transport = "Built-in" },
            { name = "Monitor", uid = "DisplayPort:AAA1", transport = "DisplayPort" },
            { name = "Monitor", uid = "DisplayPort:AAA2", transport = "DisplayPort" },
            { name = "Dock Headphones", uid = "AppleUSBAudioEngine:Acme:Dock 9000 Audio:2222:1", transport = "USB" },
        },
        inputs = {
            { name = "Built-in Microphone", uid = "BuiltInMicrophoneDevice", transport = "Built-in" },
            { name = "Dock Microphone", uid = "AppleUSBAudioEngine:Acme:Dock 9000 Audio:2222:2", transport = "USB" },
            { name = "Virtual Mic", uid = "VirtualMic_UID", transport = "Virtual" },
        },
        default_output = "BuiltInSpeakerDevice",
        default_input = "VirtualMic_UID",
        muted = false,
    }
end

local favourites = {
    outputs = {
        { label = "Dock", uid = "Dock 9000 Audio" },
        { label = "Laptop", name = "Built-in Speakers" },
        { label = "Bluetooth headphones", name = "Headphones X" },
    },
    inputs = {
        { label = "Laptop mic", name = "Built-in Microphone" },
        { label = "Dock headset", uid = "Dock 9000 Audio" },
    },
}

-- Configuration -----------------------------------------------------------------------------

test("no configuration gives the defaults", function()
    local config = assert(core.configure(nil))
    eq(#config.outputs, 0); eq(config.watch, "poll"); eq(config.autosaveName, "AudioShortlist")
    eq(config.alertSoundsFollowOutput, true)
end)

test("defaults are not shared between configurations", function()
    local a = assert(core.configure({ outputs = { { label = "A", name = "A" } } }))
    local b = assert(core.configure({}))
    eq(#a.outputs, 1); eq(#b.outputs, 0); eq(#core.DEFAULTS.outputs, 0)
end)

test("configuration is refused, with a reason", function()
    local cases = {
        { "x", "configuration must be a table" },
        { { colour = "red" }, "unknown option 'colour'" },
        { { showMute = "yes" }, "option 'showMute' must be a boolean, got string" },
        { { watch = "sometimes" }, "option 'watch' must be \"poll\", \"global\" or \"none\"" },
        { { pollInterval = 0.1 }, "option 'pollInterval' must be at least 0.5 seconds" },
        { { outputs = { "Built-in" } }, "outputs[1] must be a table" },
        { { outputs = { { name = "A" } } }, "outputs[1]: label must be a non-empty string" },
        { { outputs = { { label = "A" } } }, "outputs[1]: give exactly one of name or uid" },
        { { outputs = { { label = "A", name = "A", uid = "B" } } }, "outputs[1]: give exactly one of name or uid" },
        { { inputs = { { label = "A", uid = "" } } }, "inputs[1]: uid must be a non-empty string" },
        { { inputs = { { label = "A", name = "A", fn = print } } }, "inputs[1]: unknown key 'fn'" },
        { { inputs = { { label = "A", name = "A" }, { label = "A", name = "B" } } }, "inputs: label 'A' is used twice" },
    }
    for i, case in ipairs(cases) do
        local config, err = core.configure(case[1])
        eq(config, nil, "case " .. i .. " config"); eq(err, case[2], "case " .. i .. " message")
    end
end)

-- Matching -----------------------------------------------------------------------------------

test("a name must match exactly; a uid matches as a plain fragment", function()
    local dev = { name = "Built-in Speakers", uid = "Acme:Dock (2.0) [x]+:7" }
    eq(core.matches({ name = "Built-in Speakers" }, dev), true)
    eq(core.matches({ name = "Built-in" }, dev), false)
    eq(core.matches({ uid = "Dock (2.0) [x]+" }, dev), true, "pattern characters are literal")
    eq(core.matches({ uid = "dock" }, dev), false, "case matters")
    eq(core.matches({ uid = "x" }, { name = "No uid" }), false)
end)

-- The menu -----------------------------------------------------------------------------------

test("favourites first, unplugged favourites disabled, the rest under Other", function()
    local config = assert(core.configure(favourites))
    eq(core.describe(core.buildMenu(config, fixture())), lines(
        "  Output",
        "  Dock",
        "* Laptop",
        "  Bluetooth headphones  (not connected)",
        "----",
        "  Input",
        "  Laptop mic",
        "  Dock headset",
        "----",
        "  Mute output",
        "  Other outputs",
        "      Studio Display Speakers  (USB)",
        "      Monitor  (DisplayPort)",
        "      Monitor #2  (DisplayPort)",
        "  Other inputs",
        "    * Virtual Mic  (Virtual)",
        "  Sound Settings…"))
end)

test("with no favourites every connected device is listed and the Other submenus are left out", function()
    local config = assert(core.configure({}))
    local state = fixture(); state.muted = true
    eq(core.describe(core.buildMenu(config, state)), lines(
        "  Output",
        "  Studio Display Speakers",
        "* Built-in Speakers",
        "  Monitor",
        "  Monitor #2",
        "  Dock Headphones",
        "----",
        "  Input",
        "  Built-in Microphone",
        "  Dock Microphone",
        "* Virtual Mic",
        "----",
        "* Mute output",
        "  Sound Settings…"))
end)

test("rows can be switched off, and transport can be hidden", function()
    local options = { showMute = false, showSoundSettings = false, showOtherOutputs = false, showTransport = false }
    for k, v in pairs(favourites) do options[k] = v end
    local config = assert(core.configure(options))
    eq(core.describe(core.buildMenu(config, fixture())), lines(
        "  Output", "  Dock", "* Laptop", "  Bluetooth headphones  (not connected)", "----",
        "  Input", "  Laptop mic", "  Dock headset", "----",
        "  Other inputs", "    * Virtual Mic"))
    local bare = assert(core.configure({ showMute = false, showSoundSettings = false }))
    local text = core.describe(core.buildMenu(bare, { outputs = {}, inputs = {} }))
    eq(text, lines("  Output", "  None connected", "----", "  Input", "  None connected"), "no trailing separator")
end)

test("menu actions are data naming the device by uid", function()
    local config = assert(core.configure(favourites))
    local menu = core.buildMenu(config, fixture())
    eq(menu[2].action.op, "select"); eq(menu[2].action.kind, "output")
    eq(menu[2].action.uid, "AppleUSBAudioEngine:Acme:Dock 9000 Audio:2222:1")
    eq(menu[4].action, nil, "an unplugged favourite has no action")
    eq(menu[4].disabled, true)
    for _, item in ipairs(menu) do
        if item.action then
            local op = item.action.op
            assert(op == "select" or op == "toggleMute" or op == "openSoundSettings", "unexpected op " .. tostring(op))
        end
    end
end)

-- Status, select, next -----------------------------------------------------------------------

test("status names the default and its favourite label", function()
    local config = assert(core.configure(favourites))
    eq(core.status(config, fixture()), "output: Laptop [Built-in Speakers]\ninput: Virtual Mic")
    local state = fixture(); state.default_output = nil
    eq(core.status(config, state), "output: none\ninput: Virtual Mic")
end)

test("select accepts only a kind and a label that the menu shows", function()
    local config = assert(core.configure(favourites))
    local state = fixture()
    eq(core.resolveSelect(config, state, "output", "Dock"), "AppleUSBAudioEngine:Acme:Dock 9000 Audio:2222:1")
    eq(select(2, core.resolveSelect(config, state, "output", "Bluetooth headphones")), "not connected: Bluetooth headphones")
    eq(select(2, core.resolveSelect(config, state, "output", "Studio Display Speakers")), "no such label: Studio Display Speakers")
    eq(select(2, core.resolveSelect(config, state, "speaker", "Dock")), "kind must be \"output\" or \"input\"")
    eq(select(2, core.resolveSelect(config, state, "output", 42)), "label must be a string")
    eq(select(2, core.resolveSelect(config, state, "output", nil)), "label must be a string")
    local all = assert(core.configure({}))
    eq(core.resolveSelect(all, state, "output", "Monitor #2"), "DisplayPort:AAA2")
    eq(select(2, core.resolveSelect(all, state, "output", "Nope")), "no such device: Nope")
end)

test("next device cycles through connected favourites and wraps", function()
    local config = assert(core.configure(favourites))
    local state = fixture()
    eq(core.nextDevice(config, state, "output"), "AppleUSBAudioEngine:Acme:Dock 9000 Audio:2222:1", "Laptop -> Dock (wraps, skips unplugged)")
    state.default_output = "AppleUSBAudioEngine:Acme:Dock 9000 Audio:2222:1"
    eq(core.nextDevice(config, state, "output"), "BuiltInSpeakerDevice")
    eq(core.nextDevice(config, state, "input"), "BuiltInMicrophoneDevice", "current not a favourite -> first")
    eq(core.nextDevice(config, { outputs = {}, inputs = {} }, "output"), nil)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
