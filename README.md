# xanhub UI Library Guide

This guide explains how to load **xanhub**, build menus, use every control type, change values from code, manage configs, show warnings and notifications, and unload everything cleanly.

The matching complete example is `xanhub-example.luau`.

## 1. Loading xanhub

```lua
local library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/PPainez/idk/refs/heads/main/ui.luau",
    true
))()

assert(type(library) == "table", "xanhub failed to load")
library:SetTitle("xanhub")
```

Loading the file only returns the library. A visible menu requires controls to be created and then `library:Init()` to be called.

## 2. Menu hierarchy

Every normal menu follows this structure:

```text
Library
└── Tab
    └── Column
        └── Section
            └── Control
```

Basic setup:

```lua
local mainTab = library:AddTab("Main", 1)
local leftColumn = mainTab:AddColumn()
local section = leftColumn:AddSection("Examples")

section:AddButton({
    text = "Example Button",
    callback = function()
        print("clicked")
    end,
})

local initialized, initError = library:Init()
if not initialized and not (library.base and library.main and library.base.Parent) then
    error(tostring(initError))
end

library:SetOpen(true)
```

`AddTab(title, order)` uses the optional numeric `order` to control tab order. Two columns are the normal layout, although a tab can contain more.

## 3. Common control options

Most controls accept these fields:

| Field | Meaning |
|---|---|
| `text` | Visible control name. |
| `flag` | Key used in `library.flags`. Defaults to `text`. |
| `callback` | Function called when the value changes or the button is clicked. |
| `tip` | Tooltip shown while hovering. |
| `canInit` | Set to `false` to register a control without rendering it. |
| `skipflag` | Prevents the value from being saved in configs. |

Read a control value through either the option object or `library.flags`:

```lua
print(library.flags["Example Toggle"])
print(myToggle.state)
print(mySlider.value)
```

Use unique flags. Two controls sharing one flag overwrite the same entry.

## 4. Labels and dividers

```lua
local label = section:AddLabel("Current status: ready")
section:AddDivider("Controls")

-- Change a label later:
label.Text = "Current status: running"
```

## 5. Buttons

```lua
local button = section:AddButton({
    text = "Example Button",
    tip = "Runs a callback once.",
    callback = function()
        print("button clicked")
    end,
})
```

Buttons support nested binds and colors:

```lua
button:AddBind({
    text = "nil",
    key = Enum.KeyCode.V,
    nomouse = true,
    callback = function(state)
        print(state)
    end,
})

button:AddColor({
    text = "nil",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        print(color)
    end,
})
```

Using `text = "nil"` is useful for compact nested controls.

## 6. Toggles

```lua
local toggle = section:AddToggle({
    text = "Example Toggle",
    flag = "Example Toggle",
    state = false,
    callback = function(state)
        print("enabled:", state)
    end,
})
```

Use `style = 2` for the alternate visual style.

Change it from code:

```lua
toggle:SetState(true)
toggle:SetState(false, true) -- second argument suppresses the callback
```

A toggle can have nested colors, binds, lists, and sliders:

```lua
toggle:AddColor({...})
toggle:AddBind({...})
toggle:AddList({...})
toggle:AddSlider({...})
```

## 7. Sliders

```lua
local slider = section:AddSlider({
    text = "Volume",
    flag = "Volume",
    min = 0,
    max = 100,
    value = 50,
    float = 1,
    suffix = "%",
    callback = function(value)
        print(value)
    end,
})
```

`float` is the step size. Examples: `1`, `0.5`, or `0.05`.

`textpos = 2` enables the alternate text placement.

Set a slider from code:

```lua
slider:SetValue(75)
slider:SetValue(75, true) -- suppress callback
```

A slider can contain nested color and bind controls.

## 8. Text boxes

```lua
local box = section:AddBox({
    text = "Name",
    flag = "Name",
    value = "xanhub",
    callback = function(value, enterPressed)
        print(value, enterPressed)
    end,
})
```

Set it from code:

```lua
box:SetValue("new text")
```

The callback's second argument indicates whether focus was lost by pressing Enter.

## 9. Keybinds

Toggle-mode bind:

```lua
local bind = section:AddBind({
    text = "Toggle Bind",
    flag = "Toggle Bind",
    key = Enum.KeyCode.V,
    mode = "toggle",
    nomouse = true,
    callback = function(state)
        print(state)
    end,
})
```

Hold-mode bind:

```lua
section:AddBind({
    text = "Hold Bind",
    key = Enum.KeyCode.B,
    mode = "hold",
    nomouse = true,
    callback = function(state, deltaTime)
        if state ~= nil then
            print("pressed/released:", state)
        elseif deltaTime then
            -- Called every rendered frame while held.
        end
    end,
})
```

Change the key from code:

```lua
bind:SetKey(Enum.KeyCode.J)
bind:SetKey("none")
```

`nomouse = true` prevents mouse buttons from being selected as the bind.

## 10. Dropdown lists

Single-select list:

```lua
local list = section:AddList({
    text = "Mode",
    flag = "Mode",
    values = {"Alpha", "Beta", "Gamma"},
    value = "Alpha",
    max = 4,
    callback = function(value)
        print(value)
    end,
})
```

Multiselect list:

```lua
local multi = section:AddList({
    text = "Options",
    values = {"One", "Two", "Three"},
    value = {One = true, Two = false, Three = true},
    multiselect = true,
    callback = function(values)
        print(values.One, values.Two, values.Three)
    end,
})
```

Runtime methods:

```lua
list:SetValue("Beta")
list:AddValue("Custom")
list:RemoveValue("Custom")
list:Close()

multi:SetValue({One = false, Two = true, Three = true})
```

A list can contain nested color and bind controls.

## 11. Color pickers and transparency

```lua
local color = section:AddColor({
    text = "Example Color",
    flag = "Example Color",
    color = Color3.fromRGB(0, 170, 255),
    trans = 0.25,
    callback = function(newColor)
        print(newColor)
    end,
    calltrans = function(value)
        print("transparency slider:", value)
    end,
})
```

Programmatic methods:

```lua
color:SetColor(Color3.fromRGB(40, 100, 255))
color:SetColor({0.2, 0.4, 1})
color:SetTrans(0.5)
color:Close()
```

Color tables use normalized values from `0` to `1`, not `0` to `255`.

A color picker can contain another nested color picker.

## 12. Nested controls

Nested controls keep related options beside one main feature.

```lua
local feature = section:AddToggle({
    text = "Feature",
    callback = function(state)
        print(state)
    end,
})

feature:AddColor({
    text = "nil",
    color = Color3.fromRGB(0, 170, 255),
})

feature:AddBind({
    text = "nil",
    key = Enum.KeyCode.N,
})

feature:AddList({
    text = "nil",
    values = {"Low", "High"},
    value = "Low",
})

feature:AddSlider({
    text = "nil",
    min = 0,
    max = 10,
    value = 5,
})
```

Supported combinations:

- Toggle: color, bind, list, slider
- Button: bind, color
- Slider: color, bind
- List: color, bind
- Color: color

For the cleanest layout, place a full-width nested list or nested slider on its own parent control. Compact nested colors and binds can share one parent because they are positioned along the right side.

## 13. Sections and dynamic titles

```lua
local dynamicSection = column:AddSection("Original")
dynamicSection:SetTitle("Changed")
```

## 14. Warnings

Standard warning:

```lua
local warning = library:AddWarning({
    text = "Something happened.",
})

warning:Show()
```

`warning:Close()` exists for internal/manual cleanup, but normally `Show()` should be allowed to finish from the warning button. Closing a visible warning before an answer can leave the waiting `Show()` call unresolved.

Confirmation warning:

```lua
local confirmation = library:AddWarning({
    type = "confirm",
    text = "Continue?",
})

local accepted = confirmation:Show()
print(accepted)
```

`Show()` waits until the user selects an answer.

## 15. Notifications

```lua
library:SendNotification(3, "Saved successfully")
library:SendNotification("Uses the default duration")
```

The first form is `duration, message`. The second form accepts only a message.

## 16. Branding and accent

```lua
library:SetTitle("xanhub")
library:SetAccent(Color3.fromRGB(0, 170, 255))

local color = library:GetAccent()
local r, g, b = library.round(color)
print(r, g, b)
```

Brand formatting helpers:

```lua
local brandRichText = library:FormatBrand("xanhub")
local titleRichText = library:FormatTitle("xanhub")
```

Register a custom label so `xan` follows the accent while `hub` remains white:

```lua
local label = library:Create("TextLabel", {
    RichText = true,
    Text = library:FormatBrand("xanhub"),
    Parent = library.base,
})

library:RegisterBrandLabel(label, "xanhub")
library:RefreshBranding()
```

Register a raw GUI object as accent-colored:

```lua
local line = library:Create("Frame", {
    BackgroundColor3 = library:GetAccent(),
    Parent = library.main,
})

library:AddThemeObject(line)
```

## 17. Open, close, and status

```lua
library:SetOpen(true)
library:SetOpen(false)
library:Toggle()
library:Close() -- toggles the current state

print(library:IsInitialized())
print(library:Ready())

local status = library:GetStatus()
print(status.brand)
print(status.version)
print(status.initialized)
print(status.open)
print(status.unloaded)
print(status.parent)
print(status.lastInitError)
```

The built-in open/close bind is **Insert** unless changed in the Settings tab.

## 18. Initialization aliases

These three methods point to the same initialization behavior:

```lua
library:Init()
library:Initialize()
library:Start()
```

Only one is required. Repeated calls after successful initialization are safe.

Robust initialization check:

```lua
local initialized, initError = library:Init()
if not initialized and not (library.base and library.main and library.base.Parent) then
    error("xanhub initialization failed: " .. tostring(initError))
end
```

## 19. Config API

Config support depends on filesystem functions supplied by the runtime.

```lua
if library.capabilities.filesystem then
    library:CreateConfig("default")
    library:SaveConfig("default")
    library:LoadConfig("default")

    local configs = library:GetConfigs()
    for _, name in ipairs(configs) do
        print(name)
    end

    library:DeleteConfig("default")
end
```

Config methods:

| Method | Purpose |
|---|---|
| `GetConfigs()` | Returns saved config names. |
| `CreateConfig(name)` | Creates an empty config. |
| `SaveConfig(name)` | Saves eligible UI values. |
| `LoadConfig(name)` | Applies saved values. |
| `DeleteConfig(name)` | Deletes a config when supported. |

Use `skipflag = true` for controls that should not be saved, such as the config-name box or config selector.

## 20. Cleanup and unload

Register feature cleanup immediately after creating a feature:

```lua
local connection = game:GetService("RunService").Heartbeat:Connect(function()
    -- feature loop
end)

library:AddCleanup(function()
    connection:Disconnect()
end)
```

Remove a cleanup callback before unload:

```lua
local cleanup = library:AddCleanup(function()
    print("cleanup")
end)

library:RemoveCleanup(cleanup)
```

Unload everything:

```lua
library:Unload()
```

`library:Destroy()` is an alias of `library:Unload()`.

During unload, the library disables active toggles, runs custom cleanup callbacks, disconnects registered connections, and destroys registered instances.

## 21. Connections and callbacks

Register a connection so unload disconnects it automatically:

```lua
library:AddConnection(
    game:GetService("UserInputService").InputBegan,
    "MyNamedConnection",
    function(input)
        print(input.KeyCode)
    end
)
```

The name is optional:

```lua
library:AddConnection(signal, function()
    print("fired")
end)
```

Run any callback safely:

```lua
local ok, result = library:Invoke(function(a, b)
    return a + b
end, 10, 20)

print(ok, result)
```

Callback errors are caught and reported instead of breaking the full menu.

## 22. Low-level instance creation

`library:Create()` creates a Roblox instance and registers it for automatic destruction:

```lua
local frame = library:Create("Frame", {
    Size = UDim2.new(0, 100, 0, 30),
    BackgroundColor3 = library:GetAccent(),
    Parent = library.base,
})
```

Use `library:Create()` rather than `Instance.new()` for custom UI that should be removed by `Unload()`.

## 23. Safe tweening

Tweening is disabled by default for compatibility.

```lua
library:SetTweening(true)

library:SafeTween(frame, TweenInfo.new(0.25), {
    Position = UDim2.new(0.5, 0, 0.5, 0),
})
```

When tweening is disabled or unsupported, `SafeTween` applies the target properties directly.

## 24. Recommended feature pattern

```lua
local enabled = false
local connection

local function stopFeature()
    enabled = false
    if connection then
        connection:Disconnect()
        connection = nil
    end
end

local toggle = section:AddToggle({
    text = "Example Feature",
    flag = "Example Feature",
    state = false,
    callback = function(state)
        stopFeature()
        enabled = state

        if enabled then
            connection = game:GetService("RunService").Heartbeat:Connect(function()
                -- feature code
            end)
        end
    end,
})

library:AddCleanup(stopFeature)
```

This pattern ensures the feature stops when the toggle is disabled and when the full UI is unloaded.

## 25. Complete public API summary

### Library methods

- `AddTab(title, order)`
- `AddWarning(options)`
- `AddConnection(signal, [name], callback)`
- `AddCleanup(callback)`
- `RemoveCleanup(callback)`
- `AddThemeObject(instance)`
- `Create(className, properties)`
- `Invoke(callback, ...)`
- `SafeTween(instance, tweenInfo, properties)`
- `SetTweening(enabled)`
- `SetAccent(color)`
- `GetAccent()`
- `SetTitle(title)`
- `FormatBrand(text)`
- `FormatTitle(text)`
- `RegisterBrandLabel(label, text, formatAsTitle)`
- `RefreshBranding()`
- `SetOpen(state)`
- `Close()`
- `Toggle()`
- `IsInitialized()`
- `Ready()`
- `GetStatus()`
- `Init()` / `Initialize()` / `Start()`
- `SendNotification(duration, message)`
- `GetConfigs()`
- `CreateConfig(name)`
- `SaveConfig(name)`
- `LoadConfig(name)`
- `DeleteConfig(name)`
- `Unload()` / `Destroy()`
- `round(value, step)`

### Section methods

- `AddLabel(text)`
- `AddDivider(text)`
- `AddButton(options)`
- `AddToggle(options)`
- `AddSlider(options)`
- `AddBox(options)`
- `AddBind(options)`
- `AddList(options)`
- `AddColor(options)`
- `SetTitle(title)`

### Option methods

Depending on control type:

- `SetState(state, noCallback)`
- `SetValue(value, noCallback)`
- `SetKey(key)`
- `SetColor(color, noCallback)`
- `SetTrans(value)`
- `AddValue(value, state)`
- `RemoveValue(value)`
- `Close()`
- Nested `AddColor`, `AddBind`, `AddList`, and `AddSlider`

## 26. Troubleshooting

### The console says the library loaded but no menu appears

Loading is only the first step. Add tabs and controls, then call `library:Init()`.

### The menu is hidden

```lua
library:SetOpen(true)
```

Press **Insert** to toggle it through the built-in bind.

### A tween error appears

Keep tweening disabled:

```lua
library:SetTweening(false)
```

### Config buttons do not work

Check:

```lua
print(library.capabilities.filesystem)
print(library.capabilities.deletefile)
```

Some environments do not expose filesystem functions.

### A feature continues after unload

Register all loops, events, and created resources through `AddCleanup`, `AddConnection`, or `Create`.
