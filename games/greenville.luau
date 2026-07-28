--// Services
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local sessionVehicles = workspace:WaitForChild("SessionVehicles")

--// UI Library
local runtime = ...
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(runtime) ~= "table" then
    runtime = env.XANHUB_RUNTIME
end

local library = type(runtime) == "table" and runtime.library or nil

if type(library) ~= "table" or library.unloaded then
    library = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/PPainez/idk/main/ui.luau",
        true
    ))()
end

if type(runtime) == "table" then
    runtime.library = library
    runtime.edition = "greenville"
    env.XANHUB_RUNTIME = runtime
end
library:SetTitle("Tuning Garage")

--// Current settings
local settings = {
    Enabled = true,

    Horsepower = 200,
    Redline = 10000,

    Turbochargers = 0,
    Superchargers = 0,

    PerformanceGearbox = false,
    UpgradedBrakes = false,
    Lightweight = false
}

--// Cached vehicle information
local cachedCar = nil
local cachedTune = nil
local originalTune = nil
local running = true
local lastError = nil

local function cloneTable(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = cloneTable(value)
        else
            copy[key] = value
        end
    end

    return copy
end

local function saveOriginalTune(tune)
    return {
        Horsepower = tune.Horsepower,
        E_Horsepower = tune.E_Horsepower,
        Redline = tune.Redline,
        ClutchTol = tune.ClutchTol,

        TurboEnabled = tune.TurboEnabled,
        Turbochargers = tune.Turbochargers,
        Superchargers = tune.Superchargers,

        FinalDrive = tune.FinalDrive,
        Ratios = cloneTable(tune.Ratios),

        BrakeForce = tune.BrakeForce,
        PBrakeForce = tune.PBrakeForce,

        Weight = tune.Weight
    }
end

local function restoreCurrentTune()
    if not cachedTune or not originalTune then
        return
    end

    cachedTune.Horsepower = originalTune.Horsepower
    cachedTune.E_Horsepower = originalTune.E_Horsepower
    cachedTune.Redline = originalTune.Redline
    cachedTune.ClutchTol = originalTune.ClutchTol

    cachedTune.TurboEnabled = originalTune.TurboEnabled
    cachedTune.Turbochargers = originalTune.Turbochargers
    cachedTune.Superchargers = originalTune.Superchargers

    cachedTune.FinalDrive = originalTune.FinalDrive
    cachedTune.Ratios = cloneTable(originalTune.Ratios)

    cachedTune.BrakeForce = originalTune.BrakeForce
    cachedTune.PBrakeForce = originalTune.PBrakeForce

    cachedTune.Weight = originalTune.Weight
end

local function getTune()
    local carName = player.Name .. "-Car"
    local car = sessionVehicles:FindFirstChild(carName)

    if not car then
        return nil, "Could not find " .. carName
    end

    -- Refresh cache whenever the player spawns another vehicle
    if car ~= cachedCar then
        cachedCar = car
        cachedTune = nil
        originalTune = nil

        local tuneModule = car:FindFirstChild("A-Chassis Tune", true)

        if not tuneModule then
            return nil, "A-Chassis Tune was not found"
        end

        if not tuneModule:IsA("ModuleScript") then
            return nil, "A-Chassis Tune is not a ModuleScript"
        end

        local success, result = pcall(require, tuneModule)

        if not success then
            return nil, "Failed to require tune: " .. tostring(result)
        end

        if type(result) ~= "table" then
            return nil, "Tune module did not return a table"
        end

        cachedTune = result
        originalTune = saveOriginalTune(result)
    end

    return cachedTune
end

local function applyTune()
    if not settings.Enabled then
        return true
    end

    local tune, tuneError = getTune()

    if not tune then
        return false, tuneError
    end

    -- Engine
    tune.Horsepower = settings.Horsepower
    tune.E_Horsepower = settings.Horsepower
    tune.Redline = settings.Redline
    tune.ClutchTol = 10000

    -- Forced induction
    tune.Turbochargers = settings.Turbochargers
    tune.Superchargers = settings.Superchargers
    tune.TurboEnabled = settings.Turbochargers > 0

    -- Transmission
    if settings.PerformanceGearbox then
        tune.FinalDrive = 2.5
        tune.Ratios = {
            3.7, -- Reverse
            0,   -- Neutral
            2.84,
            1.55,
            1.00,
            0.65
        }
    else
        tune.FinalDrive = originalTune.FinalDrive
        tune.Ratios = cloneTable(originalTune.Ratios)
    end

    -- Brakes
    if settings.UpgradedBrakes then
        tune.BrakeForce = 10000000000000
        tune.PBrakeForce = 10000000000000
    else
        tune.BrakeForce = originalTune.BrakeForce
        tune.PBrakeForce = originalTune.PBrakeForce
    end

    -- Weight
    if settings.Lightweight then
        tune.Weight = 3
    else
        tune.Weight = originalTune.Weight
    end

    return true
end

local function applySafely()
    local callSuccess, applied, applyError = pcall(applyTune)

    if not callSuccess then
        applyError = applied
        applied = false
    end

    if applied == false then
        applyError = tostring(applyError)

        if lastError ~= applyError then
            lastError = applyError
            warn("[Tuning Garage] " .. applyError)
        end
    else
        lastError = nil
    end
end

--// Menu
local tuningTab = library:AddTab("Tuning", 1)

local engineColumn = tuningTab:AddColumn()
local engineSection = engineColumn:AddSection("Engine Tuning")

engineSection:AddToggle({
    text = "Enable Tune",
    flag = "Tune Enabled",
    state = true,

    callback = function(enabled)
        settings.Enabled = enabled

        if enabled then
            applySafely()
        else
            restoreCurrentTune()
        end
    end
})

engineSection:AddSlider({
    text = "Horsepower",
    flag = "Horsepower",
    min = 0,
    max = 1200,
    value = settings.Horsepower,
    suffix = " HP",

    callback = function(value)
        settings.Horsepower = value
        applySafely()
    end
})

engineSection:AddSlider({
    text = "Redline",
    flag = "Redline",
    min = 4000,
    max = 12000,
    value = settings.Redline,
    suffix = " RPM",
    float = 100,

    callback = function(value)
        settings.Redline = value
        applySafely()
    end
})

engineSection:AddToggle({
    text = "Lightweight Chassis",
    flag = "Lightweight Chassis",
    state = false,

    callback = function(enabled)
        settings.Lightweight = enabled
        applySafely()
    end
})

local gearboxSection = engineColumn:AddSection("Transmission")

gearboxSection:AddToggle({
    text = "Performance Gearbox",
    flag = "Performance Gearbox",
    state = false,

    callback = function(enabled)
        settings.PerformanceGearbox = enabled
        applySafely()
    end
})

local boostColumn = tuningTab:AddColumn()
local boostSection = boostColumn:AddSection("Forced Induction")

boostSection:AddSlider({
    text = "Turbochargers",
    flag = "Turbochargers",
    min = 0,
    max = 4,
    value = settings.Turbochargers,
    float = 1,

    callback = function(value)
        settings.Turbochargers = math.floor(value)
        applySafely()
    end
})

boostSection:AddSlider({
    text = "Superchargers",
    flag = "Superchargers",
    min = 0,
    max = 2,
    value = settings.Superchargers,
    float = 1,

    callback = function(value)
        settings.Superchargers = math.floor(value)
        applySafely()
    end
})

local modificationSection = boostColumn:AddSection("Modifications")

modificationSection:AddToggle({
    text = "Upgraded Brakes",
    flag = "Upgraded Brakes",
    state = false,

    callback = function(enabled)
        settings.UpgradedBrakes = enabled
        applySafely()
    end
})

modificationSection:AddButton({
    text = "Apply Tune",

    callback = function()
        -- Clear cache so it finds the current vehicle again
        cachedCar = nil
        cachedTune = nil
        originalTune = nil

        applySafely()
    end
})

modificationSection:AddButton({
    text = "Restore Stock Tune",

    callback = function()
        settings.Enabled = false

        local toggle = library.options["Tune Enabled"]

        if toggle and toggle.SetState then
            toggle:SetState(false)
        else
            restoreCurrentTune()
        end
    end
})

-- Restore the vehicle when the UI unloads
library:AddCleanup(function()
    running = false
    restoreCurrentTune()
end)

library:Init()

-- Continuously reapply values, matching the original script's behavior
task.spawn(function()
    while running and not library.unloaded do
        if settings.Enabled then
            applySafely()
        end

        task.wait(0.1)
    end
end)