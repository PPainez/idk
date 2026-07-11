--[[
    xanhub complete example

    This file demonstrates the public xanhub UI library API and every control type.
    Replace UI_URL only if you move the library to another repository.
]]

local UI_URL = "https://raw.githubusercontent.com/PPainez/idk/refs/heads/main/ui.luau"

local source = game:HttpGet(UI_URL, true)
local chunk, compileError = loadstring(source)
assert(chunk, "[xanhub] Library compile failed: " .. tostring(compileError))

local library = chunk()
assert(type(library) == "table", "[xanhub] Library did not return a table")

-- Keep the visible brand exactly "xanhub".
library:SetTitle("xanhub")
library:SetAccent(Color3.fromRGB(0, 170, 255))
library:SetTweening(false) -- safest default for broad executor compatibility

-- Demonstrates cleanup registration and removal.
local removedCleanup = library:AddCleanup(function()
    print("[xanhub] This cleanup was removed and should not run")
end)
library:RemoveCleanup(removedCleanup)

library:AddCleanup(function()
    print("[xanhub] Example resources cleaned up")
end)

-- Reusable warnings.
local infoWarning = library:AddWarning({
    text = "This is a standard xanhub warning.",
})

local confirmWarning = library:AddWarning({
    type = "confirm",
    text = "Do you want to confirm this example action?",
})

-- MAIN TAB -------------------------------------------------------------------
local mainTab = library:AddTab("Main", 1)
local mainLeft = mainTab:AddColumn()
local mainRight = mainTab:AddColumn()

local welcomeSection = mainLeft:AddSection("xanhub")
local liveLabel = welcomeSection:AddLabel("Ready to initialize")
welcomeSection:AddDivider("Examples")

welcomeSection:AddButton({
    text = "Send Notification",
    tip = "Shows the built-in notification system.",
    callback = function()
        library:SendNotification(3, "xanhub notification example")
    end,
})

welcomeSection:AddButton({
    text = "Show Warning",
    callback = function()
        infoWarning:Show()
    end,
})

welcomeSection:AddButton({
    text = "Show Confirmation",
    callback = function()
        local accepted = confirmWarning:Show()
        library:SendNotification(2, accepted and "Action confirmed" or "Action cancelled")
    end,
})

welcomeSection:AddButton({
    text = "Run Protected Callback",
    tip = "Demonstrates library:Invoke().",
    callback = function()
        local ok, result = library:Invoke(function(a, b)
            return a + b
        end, 20, 22)
        print("[xanhub] Invoke result:", ok, result)
    end,
})

local menuSection = mainLeft:AddSection("Menu")

menuSection:AddButton({
    text = "Hide For 2 Seconds",
    callback = function()
        library:SetOpen(false)
        task.delay(2, function()
            if not library.unloaded then
                library:SetOpen(true)
            end
        end)
    end,
})

menuSection:AddButton({
    text = "Toggle Twice",
    tip = "Demonstrates library:Toggle() without leaving the menu hidden.",
    callback = function()
        library:Toggle()
        task.delay(1, function()
            if not library.unloaded then
                library:Toggle()
            end
        end)
    end,
})

menuSection:AddButton({
    text = "Close / Open",
    tip = "Demonstrates library:Close(). The second call reopens it.",
    callback = function()
        library:Close()
        task.delay(1, function()
            if not library.unloaded then
                library:Close()
            end
        end)
    end,
})

local statusSection = mainRight:AddSection("Status")

statusSection:AddButton({
    text = "Print Status",
    callback = function()
        local status = library:GetStatus()
        print("[xanhub] Brand:", status.brand)
        print("[xanhub] Version:", status.version)
        print("[xanhub] Initialized:", status.initialized)
        print("[xanhub] Ready:", library:Ready())
        print("[xanhub] Open:", status.open)
        print("[xanhub] Parent:", status.parent)
        print("[xanhub] Last init error:", status.lastInitError)
    end,
})

statusSection:AddButton({
    text = "Print Flags",
    callback = function()
        for flag, value in pairs(library.flags) do
            print("[xanhub flag]", flag, value)
        end
    end,
})

statusSection:AddButton({
    text = "Print Accent RGB",
    callback = function()
        local r, g, b = library.round(library:GetAccent())
        print(string.format("[xanhub] Accent: %d, %d, %d", r, g, b))
        print("[xanhub] Brand markup:", library:FormatBrand("xanhub"))
        print("[xanhub] Title markup:", library:FormatTitle("xanhub"))
    end,
})

statusSection:AddButton({
    text = "Refresh Branding",
    callback = function()
        library:SetTitle("xanhub")
        library:RefreshBranding()
    end,
})

local accentSection = mainRight:AddSection("Accent")

accentSection:AddButton({
    text = "Electric Blue",
    callback = function()
        library:SetAccent(Color3.fromRGB(0, 170, 255))
    end,
})

accentSection:AddButton({
    text = "Deep Blue",
    callback = function()
        library:SetAccent(Color3.fromRGB(35, 90, 255))
    end,
})

accentSection:AddColor({
    text = "Custom Accent",
    flag = "Example Custom Accent",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        library:SetAccent(color)
    end,
})

accentSection:AddToggle({
    text = "UI Tweening",
    flag = "Example UI Tweening",
    state = false,
    tip = "Leave disabled if your environment rejects GUI tweens.",
    callback = function(state)
        library:SetTweening(state)
    end,
})

-- CONTROLS TAB ---------------------------------------------------------------
local controlsTab = library:AddTab("Controls", 2)
local controlsLeft = controlsTab:AddColumn()
local controlsRight = controlsTab:AddColumn()

local basicControls = controlsLeft:AddSection("Basic Controls")

local exampleToggle = basicControls:AddToggle({
    text = "Example Toggle",
    flag = "Example Toggle",
    state = false,
    tip = "A regular toggle with a callback.",
    callback = function(state)
        print("[xanhub] Toggle:", state)
    end,
})

basicControls:AddToggle({
    text = "Styled Toggle",
    flag = "Example Styled Toggle",
    state = true,
    style = 2,
    callback = function(state)
        print("[xanhub] Styled toggle:", state)
    end,
})

basicControls:AddButton({
    text = "Example Button",
    tip = "A normal button callback.",
    callback = function()
        library:SendNotification("Example button clicked")
    end,
})

local exampleSlider = basicControls:AddSlider({
    text = "Example Slider",
    flag = "Example Slider",
    min = 0,
    max = 100,
    value = 50,
    float = 1,
    suffix = "%",
    callback = function(value)
        print("[xanhub] Slider:", value)
    end,
})

basicControls:AddSlider({
    text = "Decimal Slider",
    flag = "Example Decimal Slider",
    min = 0,
    max = 2,
    value = 1,
    float = 0.05,
    suffix = "x",
    textpos = 2,
    callback = function(value)
        print("[xanhub] Decimal slider:", value)
    end,
})

local inputControls = controlsLeft:AddSection("Input Controls")

local exampleBox = inputControls:AddBox({
    text = "Example Textbox",
    flag = "Example Textbox",
    value = "xanhub",
    tip = "Callback receives the text and whether Enter was pressed.",
    callback = function(value, enterPressed)
        print("[xanhub] Textbox:", value, "Enter:", enterPressed)
    end,
})

local toggleBind = inputControls:AddBind({
    text = "Toggle Bind",
    flag = "Example Toggle Bind",
    key = Enum.KeyCode.V,
    mode = "toggle",
    nomouse = true,
    callback = function(state)
        print("[xanhub] Toggle bind:", state)
    end,
})

inputControls:AddBind({
    text = "Hold Bind",
    flag = "Example Hold Bind",
    key = Enum.KeyCode.B,
    mode = "hold",
    nomouse = true,
    callback = function(state, deltaTime)
        if state ~= nil then
            print("[xanhub] Hold bind state:", state)
        elseif deltaTime then
            -- Called each rendered frame while the key is held.
        end
    end,
})

local listControls = controlsRight:AddSection("Lists")

local exampleList = listControls:AddList({
    text = "Example Dropdown",
    flag = "Example Dropdown",
    values = {"Alpha", "Beta", "Gamma"},
    value = "Alpha",
    max = 4,
    callback = function(value)
        print("[xanhub] Dropdown:", value)
    end,
})

local multiList = listControls:AddList({
    text = "Multi Dropdown",
    flag = "Example Multi Dropdown",
    values = {"One", "Two", "Three"},
    value = {One = true, Two = false, Three = true},
    multiselect = true,
    max = 4,
    callback = function(values)
        for name, selected in pairs(values) do
            print("[xanhub] Multi:", name, selected)
        end
    end,
})

listControls:AddButton({
    text = "Add Custom List Value",
    callback = function()
        exampleList:AddValue("Custom")
        exampleList:SetValue("Custom")
    end,
})

listControls:AddButton({
    text = "Remove Custom List Value",
    callback = function()
        exampleList:RemoveValue("Custom")
    end,
})

local colorControls = controlsRight:AddSection("Colors")

local exampleColor = colorControls:AddColor({
    text = "Example Color",
    flag = "Example Color",
    color = Color3.fromRGB(0, 170, 255),
    trans = 0.25,
    callback = function(color)
        print("[xanhub] Color:", color)
    end,
    calltrans = function(value)
        print("[xanhub] Transparency slider value:", value)
    end,
})

colorControls:AddColor({
    text = "Second Color",
    flag = "Example Second Color",
    color = {0.15, 0.35, 1},
    callback = function(color)
        print("[xanhub] Second color:", color)
    end,
})

-- NESTED CONTROLS TAB --------------------------------------------------------
local nestedTab = library:AddTab("Nested", 3)
local nestedLeft = nestedTab:AddColumn()
local nestedRight = nestedTab:AddColumn()

local nestedToggleSection = nestedLeft:AddSection("Toggle Sub-controls")
local nestedToggle = nestedToggleSection:AddToggle({
    text = "Feature With Color And Bind",
    flag = "Nested Feature",
    state = false,
    callback = function(state)
        print("[xanhub] Nested feature:", state)
    end,
})

nestedToggle:AddColor({
    text = "nil",
    flag = "Nested Toggle Color",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        print("[xanhub] Nested toggle color:", color)
    end,
})

nestedToggle:AddBind({
    text = "nil",
    flag = "Nested Toggle Bind",
    key = Enum.KeyCode.N,
    nomouse = true,
    callback = function(state)
        print("[xanhub] Nested toggle bind:", state)
    end,
})

local toggleWithList = nestedToggleSection:AddToggle({
    text = "Feature With List",
    flag = "Nested List Feature",
    state = false,
    callback = function(state)
        print("[xanhub] Nested list feature:", state)
    end,
})

toggleWithList:AddList({
    text = "nil",
    flag = "Nested Toggle List",
    values = {"Low", "Medium", "High"},
    value = "Medium",
    callback = function(value)
        print("[xanhub] Nested toggle list:", value)
    end,
})

local toggleWithSlider = nestedToggleSection:AddToggle({
    text = "Feature With Slider",
    flag = "Nested Slider Feature",
    state = false,
    callback = function(state)
        print("[xanhub] Nested slider feature:", state)
    end,
})

toggleWithSlider:AddSlider({
    text = "nil",
    flag = "Nested Toggle Slider",
    min = 0,
    max = 10,
    value = 5,
    callback = function(value)
        print("[xanhub] Nested toggle slider:", value)
    end,
})

local nestedButtonSection = nestedLeft:AddSection("Button Sub-controls")
local nestedButton = nestedButtonSection:AddButton({
    text = "Button With Options",
    callback = function()
        print("[xanhub] Nested button clicked")
    end,
})

nestedButton:AddBind({
    text = "nil",
    flag = "Nested Button Bind",
    key = Enum.KeyCode.M,
    nomouse = true,
    callback = function(state)
        print("[xanhub] Nested button bind:", state)
    end,
})

nestedButton:AddColor({
    text = "nil",
    flag = "Nested Button Color",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        print("[xanhub] Nested button color:", color)
    end,
})

local nestedSliderSection = nestedRight:AddSection("Slider Sub-controls")
local nestedSlider = nestedSliderSection:AddSlider({
    text = "Slider With Options",
    flag = "Nested Main Slider",
    min = 0,
    max = 100,
    value = 25,
    callback = function(value)
        print("[xanhub] Nested main slider:", value)
    end,
})

nestedSlider:AddColor({
    text = "nil",
    flag = "Nested Slider Color",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        print("[xanhub] Nested slider color:", color)
    end,
})

nestedSlider:AddBind({
    text = "nil",
    flag = "Nested Slider Bind",
    key = Enum.KeyCode.K,
    nomouse = true,
    callback = function(state)
        print("[xanhub] Nested slider bind:", state)
    end,
})

local nestedListSection = nestedRight:AddSection("List Sub-controls")
local nestedList = nestedListSection:AddList({
    text = "List With Options",
    flag = "Nested Main List",
    values = {"First", "Second", "Third"},
    value = "First",
    callback = function(value)
        print("[xanhub] Nested main list:", value)
    end,
})

nestedList:AddColor({
    text = "nil",
    flag = "Nested List Color",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        print("[xanhub] Nested list color:", color)
    end,
})

nestedList:AddBind({
    text = "nil",
    flag = "Nested List Bind",
    key = Enum.KeyCode.L,
    nomouse = true,
    callback = function(state)
        print("[xanhub] Nested list bind:", state)
    end,
})

local nestedColorSection = nestedRight:AddSection("Color Sub-control")
local nestedColor = nestedColorSection:AddColor({
    text = "Color With Secondary Color",
    flag = "Nested Main Color",
    color = Color3.fromRGB(0, 170, 255),
    callback = function(color)
        print("[xanhub] Nested main color:", color)
    end,
})

nestedColor:AddColor({
    text = "nil",
    flag = "Nested Secondary Color",
    color = Color3.fromRGB(255, 255, 255),
    callback = function(color)
        print("[xanhub] Nested secondary color:", color)
    end,
})

-- API TAB --------------------------------------------------------------------
local apiTab = library:AddTab("API", 4)
local apiLeft = apiTab:AddColumn()
local apiRight = apiTab:AddColumn()

local settersSection = apiLeft:AddSection("Programmatic Setters")

settersSection:AddButton({
    text = "Set Toggle On",
    callback = function()
        exampleToggle:SetState(true)
    end,
})

settersSection:AddButton({
    text = "Set Toggle Off Silently",
    callback = function()
        exampleToggle:SetState(false, true)
    end,
})

settersSection:AddButton({
    text = "Set Slider To 75",
    callback = function()
        exampleSlider:SetValue(75)
    end,
})

settersSection:AddButton({
    text = "Set Textbox Value",
    callback = function()
        exampleBox:SetValue("changed by code")
    end,
})

settersSection:AddButton({
    text = "Set Dropdown To Beta",
    callback = function()
        exampleList:SetValue("Beta")
    end,
})

settersSection:AddButton({
    text = "Set Multi Dropdown",
    callback = function()
        multiList:SetValue({One = false, Two = true, Three = true})
    end,
})

settersSection:AddButton({
    text = "Set Bind To J",
    callback = function()
        toggleBind:SetKey(Enum.KeyCode.J)
    end,
})

settersSection:AddButton({
    text = "Set Color And Transparency",
    callback = function()
        exampleColor:SetColor(Color3.fromRGB(50, 100, 255))
        if exampleColor.SetTrans then
            exampleColor:SetTrans(0.5)
        end
    end,
})

settersSection:AddButton({
    text = "Close Open Popups",
    callback = function()
        pcall(function() exampleList:Close() end)
        pcall(function() multiList:Close() end)
        if exampleColor.mainHolder then
            pcall(function() exampleColor:Close() end)
        end
    end,
})

local dynamicSection = apiLeft:AddSection("Dynamic Section")
local renamed = false

dynamicSection:AddButton({
    text = "Rename This Section",
    callback = function()
        renamed = not renamed
        dynamicSection:SetTitle(renamed and "Renamed Section" or "Dynamic Section")
    end,
})

local customSection = apiRight:AddSection("Low-level API")
local customBadge
local badgeMoved = false

customSection:AddButton({
    text = "Move Custom Badge",
    callback = function()
        if customBadge then
            badgeMoved = not badgeMoved
            library:SafeTween(customBadge, TweenInfo.new(0.25), {
                Position = badgeMoved
                    and UDim2.new(0, 18, 1, -50)
                    or UDim2.new(0, 18, 1, -82),
            })
        end
    end,
})

customSection:AddButton({
    text = "Print Initialization State",
    callback = function()
        print("[xanhub] IsInitialized:", library:IsInitialized())
        print("[xanhub] Ready:", library:Ready())
    end,
})

local configSection = apiRight:AddSection("Config API")
local configName = configSection:AddBox({
    text = "Config Name",
    flag = "Example Config Name",
    value = "example",
    skipflag = true,
})

local configList = configSection:AddList({
    text = "Available Configs",
    flag = "Example Config List",
    values = {},
    value = "",
    max = 5,
    skipflag = true,
})

local function refreshConfigList()
    local configs = library:GetConfigs()

    for index = #configList.values, 1, -1 do
        local name = configList.values[index]
        if not table.find(configs, name) then
            configList:RemoveValue(name)
        end
    end

    for _, name in ipairs(configs) do
        configList:AddValue(name)
    end

    if #configs > 0 then
        configList:SetValue(configs[1], true)
    end

    return configs
end

configSection:AddButton({
    text = "Refresh Configs",
    callback = function()
        local configs = refreshConfigList()
        library:SendNotification(2, "Found " .. tostring(#configs) .. " config(s)")
    end,
})

configSection:AddButton({
    text = "Create Config",
    callback = function()
        local ok, err = library:CreateConfig(configName.value)
        library:SendNotification(2, ok and "Config created" or tostring(err))
        refreshConfigList()
    end,
})

configSection:AddButton({
    text = "Save Config",
    callback = function()
        local name = configList.value ~= "" and configList.value or configName.value
        local ok = library:SaveConfig(name)
        library:SendNotification(2, ok and "Config saved" or "Config save unavailable")
        refreshConfigList()
    end,
})

configSection:AddButton({
    text = "Load Config",
    callback = function()
        local ok = library:LoadConfig(configList.value)
        library:SendNotification(2, ok and "Config loaded" or "Config could not be loaded")
    end,
})

configSection:AddButton({
    text = "Delete Config",
    callback = function()
        local name = configList.value
        local ok, err = library:DeleteConfig(name)
        library:SendNotification(2, ok and "Config deleted" or tostring(err))
        refreshConfigList()
    end,
})

local unloadSection = apiRight:AddSection("Unload")

unloadSection:AddButton({
    text = "Unload xanhub",
    callback = function()
        library:Unload()
    end,
})

unloadSection:AddButton({
    text = "Destroy Alias",
    tip = "library:Destroy() is an alias of library:Unload().",
    callback = function()
        library:Destroy()
    end,
})

-- INITIALIZE -----------------------------------------------------------------
local initialized, initError = library:Init()
if not initialized and not (library.base and library.main and library.base.Parent) then
    error("[xanhub] Initialization failed: " .. tostring(initError))
end

-- Init aliases are safe to call after initialization and simply return the library.
library:Initialize()
library:Start()
library:SetOpen(true)

-- Demonstrates library:Create(), RegisterBrandLabel(), AddThemeObject(),
-- AddConnection(), SafeTween(), and raw instance cleanup through the library.
customBadge = library:Create("TextButton", {
    Name = "xanhub_example_badge",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 18, 1, -82),
    Size = UDim2.new(0, 110, 0, 28),
    BackgroundColor3 = library.palette.surfaceRaised,
    BorderColor3 = library.palette.border,
    AutoButtonColor = false,
    RichText = true,
    Text = library:FormatBrand("xanhub"),
    TextSize = 16,
    Font = Enum.Font.GothamSemibold,
    TextColor3 = Color3.new(1, 1, 1),
    Parent = library.base,
})

library:RegisterBrandLabel(customBadge, "xanhub")

local badgeAccent = library:AddThemeObject(library:Create("Frame", {
    Position = UDim2.new(0, 0, 1, -2),
    Size = UDim2.new(1, 0, 0, 2),
    BackgroundColor3 = library:GetAccent(),
    BorderSizePixel = 0,
    Parent = customBadge,
}))

library:AddConnection(customBadge.MouseButton1Click, "ExampleBadgeClick", function()
    library:Toggle()
end)

library:AddCleanup(function()
    customBadge = nil
    badgeAccent = nil
end)

liveLabel.Text = "xanhub initialized successfully"
library:RefreshBranding()
refreshConfigList()
library:SendNotification(3, "xanhub loaded")

print("[xanhub] Example loaded")
print("[xanhub] Press Insert to open or close the menu")
