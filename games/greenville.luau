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

--// Tune fields
local ENGINE_FIELDS = {
    "IdleRPM", "PeakRPM", "EqPoint", "PeakSharpness", "CurveMult",
    "ThrotAccel", "ThrotDecel", "RevAccel", "RevDecay", "RevBounce",
    "Flywheel", "InclineComp"
}

local BOOST_FIELDS = {
    "T_Boost", "T_Efficiency", "T_Size",
    "S_Boost", "S_Efficiency", "S_Sensitivity"
}

local TRANSMISSION_FIELDS = {
    "Config", "FDMult", "AutoUpThresh", "AutoDownThresh", "ShiftThrot",
    "ShiftUpTime", "ShiftDnTime", "ClutchEngage", "ClutchRPMMult"
}

local DIFFERENTIAL_FIELDS = {
    "DifferentialType", "TorqueVector",
    "FDiffSlipThres", "FDiffLockThres", "RDiffSlipThres", "RDiffLockThres",
    "FDiffPower", "FDiffCoast", "FDiffPreload",
    "RDiffPower", "RDiffCoast", "RDiffPreload"
}

local SUSPENSION_FIELDS = {
    "WeightDist", "CGHeight", "FWheelDensity", "RWheelDensity",
    "FCamber", "RCamber", "FCaster", "RCaster", "FToe", "RToe",
    "FSusDamping", "RSusDamping", "FSusStiffness", "RSusStiffness",
    "FAntiRoll", "RAntiRoll", "FSusLength", "RSusLength",
    "FPreCompress", "RPreCompress", "FExtensionLim", "RExtensionLim",
    "FCompressLim", "RCompressLim", "FGyroDamp", "RGyroDamp"
}

local STEERING_FIELDS = {
    "SteerRatio", "LockToLock", "Ackerman", "SteerSpeed",
    "ReturnSpeed", "SteerDecay", "MinSteer", "MSteerExp"
}

local BRAKE_FIELDS = {"BrakeBias", "PBrakeBias", "EBrakeForce"}
local ASSIST_FIELDS = {
    "ABSEnabled", "ABSThreshold", "TCSEnabled",
    "TCSThreshold", "TCSGradient", "TCSLimit"
}

local CORE_FIELDS = {
    "Horsepower", "E_Horsepower", "Redline", "ClutchTol",
    "TurboEnabled", "Turbochargers", "Superchargers",
    "FinalDrive", "Ratios", "BrakeForce", "PBrakeForce", "Weight"
}

local TUNE_GROUPS = {
    ENGINE_FIELDS, BOOST_FIELDS, TRANSMISSION_FIELDS, DIFFERENTIAL_FIELDS,
    SUSPENSION_FIELDS, STEERING_FIELDS, BRAKE_FIELDS, ASSIST_FIELDS
}

local ORIGINAL_TUNE_FIELDS = {}

for _, field in ipairs(CORE_FIELDS) do
    table.insert(ORIGINAL_TUNE_FIELDS, field)
end

for _, fields in ipairs(TUNE_GROUPS) do
    for _, field in ipairs(fields) do
        table.insert(ORIGINAL_TUNE_FIELDS, field)
    end
end

local GRIP_FIELDS = {
    "Friction_DryRoad", "Friction_DryDirt", "Friction_DryGrass",
    "Friction_WetRoad", "Friction_WetDirt", "Friction_WetGrass"
}

local GRIP_DEFAULTS = {
    Friction_DryRoad = 0.5,
    Friction_DryDirt = 0.4,
    Friction_DryGrass = 0.4,
    Friction_WetRoad = 0.35,
    Friction_WetDirt = 0.35,
    Friction_WetGrass = 0.2
}

--// Current settings
local settings = {
    Enabled = true,
    Horsepower = 200,
    Redline = 10000,
    Turbochargers = 0,
    Superchargers = 0,
    PerformanceGearbox = false,
    UpgradedBrakes = false,
    Lightweight = false,

    AdvancedEngine = false,
    IdleRPM = 700,
    PeakRPM = 6200,
    EqPoint = 3150,
    PeakSharpness = 12.5,
    CurveMult = 0.06,
    ThrotAccel = 1,
    ThrotDecel = 1,
    RevAccel = 250,
    RevDecay = 75,
    RevBounce = 500,
    Flywheel = 250,
    InclineComp = 2.7,

    AdvancedBoost = false,
    T_Boost = 13.5,
    T_Efficiency = 6,
    T_Size = 45,
    S_Boost = 8,
    S_Efficiency = 8.5,
    S_Sensitivity = 0.05,

    AdvancedTransmission = false,
    Config = "FWD",
    FDMult = 1.3,
    AutoUpThresh = 150,
    AutoDownThresh = 1400,
    ShiftThrot = 15,
    ShiftUpTime = 0.3,
    ShiftDnTime = 0.2,
    ClutchEngage = 95,
    ClutchRPMMult = 1,

    AdvancedDifferential = false,
    DifferentialType = "Old",
    TorqueVector = 0,
    FDiffSlipThres = 50,
    FDiffLockThres = 50,
    RDiffSlipThres = 80,
    RDiffLockThres = 20,
    FDiffPower = 30,
    FDiffCoast = 10,
    FDiffPreload = 10,
    RDiffPower = 40,
    RDiffCoast = 20,
    RDiffPreload = 20,

    AdvancedSuspension = false,
    WeightDist = 50,
    CGHeight = 1.4,
    FWheelDensity = 0.1,
    RWheelDensity = 0.1,
    FCamber = -1,
    RCamber = -1,
    FCaster = 0,
    RCaster = 0,
    FToe = 0,
    RToe = 0,
    FSusDamping = 245,
    RSusDamping = 245,
    FSusStiffness = 6000,
    RSusStiffness = 6000,
    FAntiRoll = 25,
    RAntiRoll = 25,
    FSusLength = 2.2,
    RSusLength = 2.2,
    FPreCompress = 0.3,
    RPreCompress = 0.3,
    FExtensionLim = 0.3,
    RExtensionLim = 0.3,
    FCompressLim = 0.5,
    RCompressLim = 0.5,
    FGyroDamp = 100,
    RGyroDamp = 100,

    AdvancedSteering = false,
    SteerRatio = 15,
    LockToLock = 3.41,
    Ackerman = 1.2,
    SteerSpeed = 0.06,
    ReturnSpeed = 0.1,
    SteerDecay = 165,
    MinSteer = 10,
    MSteerExp = 1,

    AdvancedBrakes = false,
    BrakeBias = 0.56,
    PBrakeBias = 0,
    EBrakeForce = 0,

    AdvancedAssists = false,
    ABSEnabled = true,
    ABSThreshold = 20,
    TCSEnabled = false,
    TCSThreshold = 20,
    TCSGradient = 20,
    TCSLimit = 10,

    CustomGrip = false,
    Friction_DryRoad = GRIP_DEFAULTS.Friction_DryRoad,
    Friction_DryDirt = GRIP_DEFAULTS.Friction_DryDirt,
    Friction_DryGrass = GRIP_DEFAULTS.Friction_DryGrass,
    Friction_WetRoad = GRIP_DEFAULTS.Friction_WetRoad,
    Friction_WetDirt = GRIP_DEFAULTS.Friction_WetDirt,
    Friction_WetGrass = GRIP_DEFAULTS.Friction_WetGrass
}

local GROUP_SETTINGS = {
    AdvancedEngine = ENGINE_FIELDS,
    AdvancedBoost = BOOST_FIELDS,
    AdvancedTransmission = TRANSMISSION_FIELDS,
    AdvancedDifferential = DIFFERENTIAL_FIELDS,
    AdvancedSuspension = SUSPENSION_FIELDS,
    AdvancedSteering = STEERING_FIELDS,
    AdvancedBrakes = BRAKE_FIELDS,
    AdvancedAssists = ASSIST_FIELDS
}

--// Cached vehicle information
local cachedCar = nil
local cachedTune = nil
local cachedWheels = nil
local originalTune = nil
local originalGrip = nil
local running = true
local lastError = nil
local controls = {}
local nilAttribute = {}
local syncAdvancedControls = function() end

local function cloneTable(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}

    for key, value in pairs(source) do
        copy[key] = cloneTable(value)
    end

    return copy
end

local function saveOriginalTune(tune)
    local original = {}

    for _, field in ipairs(ORIGINAL_TUNE_FIELDS) do
        original[field] = cloneTable(tune[field])
    end

    return original
end

local function saveOriginalGrip(wheels)
    local original = {
        Friction_UseLocalValues = wheels:GetAttribute("Friction_UseLocalValues")
    }

    if original.Friction_UseLocalValues == nil then
        original.Friction_UseLocalValues = nilAttribute
    end

    for _, attribute in ipairs(GRIP_FIELDS) do
        local value = wheels:GetAttribute(attribute)
        original[attribute] = value == nil and nilAttribute or value
    end

    return original
end

local function restoreTuneFields(tune, fields)
    if not originalTune then
        return
    end

    for _, field in ipairs(fields) do
        tune[field] = cloneTable(originalTune[field])
    end
end

local function setAttributeIfChanged(instance, attribute, value)
    if instance:GetAttribute(attribute) ~= value then
        instance:SetAttribute(attribute, value)
    end
end

local function restoreGrip()
    if not cachedWheels or not cachedWheels.Parent or not originalGrip then
        return
    end

    local useLocal = originalGrip.Friction_UseLocalValues
    setAttributeIfChanged(
        cachedWheels,
        "Friction_UseLocalValues",
        useLocal == nilAttribute and nil or useLocal
    )

    for _, attribute in ipairs(GRIP_FIELDS) do
        local value = originalGrip[attribute]
        setAttributeIfChanged(cachedWheels, attribute, value == nilAttribute and nil or value)
    end
end

local function restoreCurrentTune()
    if cachedTune and originalTune then
        restoreTuneFields(cachedTune, ORIGINAL_TUNE_FIELDS)
    end

    restoreGrip()
end

local function refreshWheelCache()
    if not cachedCar then
        return nil, false
    end

    local wheels = cachedCar:FindFirstChild("Wheels")

    if wheels and wheels ~= cachedWheels then
        cachedWheels = wheels
        originalGrip = saveOriginalGrip(wheels)
        return wheels, true
    end

    return cachedWheels, false
end

local function getTune()
    local carName = player.Name .. "-Car"
    local car = sessionVehicles:FindFirstChild(carName)

    if not car then
        return nil, "Could not find " .. carName
    end

    if car ~= cachedCar or not cachedTune then
        if car ~= cachedCar then
            cachedCar = nil
            cachedTune = nil
            cachedWheels = nil
            originalTune = nil
            originalGrip = nil
        end

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

        cachedCar = car
        cachedTune = result
        originalTune = saveOriginalTune(result)
        refreshWheelCache()
        syncAdvancedControls()
    end

    local _, discoveredWheels = refreshWheelCache()

    if discoveredWheels then
        syncAdvancedControls()
    end

    return cachedTune
end

local function applyTuneGroup(tune, toggleSetting, fields)
    if not settings[toggleSetting] then
        restoreTuneFields(tune, fields)
        return
    end

    for _, field in ipairs(fields) do
        tune[field] = cloneTable(settings[field])
    end
end

local function applyGrip()
    local wheels = refreshWheelCache()

    if not wheels then
        return
    end

    if not settings.CustomGrip then
        restoreGrip()
        return
    end

    setAttributeIfChanged(wheels, "Friction_UseLocalValues", true)

    for _, attribute in ipairs(GRIP_FIELDS) do
        setAttributeIfChanged(wheels, attribute, settings[attribute])
    end
end

local function applyTune()
    if not settings.Enabled then
        return true
    end

    local tune, tuneError = getTune()

    if not tune then
        return false, tuneError
    end

    tune.Horsepower = settings.Horsepower
    tune.E_Horsepower = settings.Horsepower
    tune.Redline = settings.Redline
    tune.ClutchTol = 10000
    applyTuneGroup(tune, "AdvancedEngine", ENGINE_FIELDS)

    if settings.AdvancedEngine then
        tune.PeakRPM = math.min(tune.PeakRPM, tune.Redline)
        tune.IdleRPM = math.min(tune.IdleRPM, tune.PeakRPM)
        tune.EqPoint = math.min(tune.EqPoint, tune.Redline)
    end

    tune.Turbochargers = math.floor(settings.Turbochargers)
    tune.Superchargers = math.floor(settings.Superchargers)
    tune.TurboEnabled = settings.Turbochargers > 0
    applyTuneGroup(tune, "AdvancedBoost", BOOST_FIELDS)

    if settings.PerformanceGearbox then
        tune.FinalDrive = 2.5
        tune.Ratios = {3.7, 0, 2.84, 1.55, 1.00, 0.65}
    else
        tune.FinalDrive = originalTune.FinalDrive
        tune.Ratios = cloneTable(originalTune.Ratios)
    end

    applyTuneGroup(tune, "AdvancedTransmission", TRANSMISSION_FIELDS)
    applyTuneGroup(tune, "AdvancedDifferential", DIFFERENTIAL_FIELDS)

    tune.Weight = settings.Lightweight and 3 or originalTune.Weight
    applyTuneGroup(tune, "AdvancedSuspension", SUSPENSION_FIELDS)
    applyTuneGroup(tune, "AdvancedSteering", STEERING_FIELDS)

    if settings.UpgradedBrakes then
        tune.BrakeForce = 10000000000000
        tune.PBrakeForce = 10000000000000
    else
        tune.BrakeForce = originalTune.BrakeForce
        tune.PBrakeForce = originalTune.PBrakeForce
    end

    applyTuneGroup(tune, "AdvancedBrakes", BRAKE_FIELDS)
    applyTuneGroup(tune, "AdvancedAssists", ASSIST_FIELDS)
    applyGrip()

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

--// Menu helpers
local function flagName(key)
    return "Greenville " .. key
end

local function addToggle(section, key, text, flag)
    controls[key] = section:AddToggle({
        text = text,
        flag = flag or flagName(key),
        state = settings[key],
        callback = function(enabled)
            settings[key] = enabled
            applySafely()
        end
    })
end

local function addSlider(section, spec)
    local key = spec[1]
    controls[key] = section:AddSlider({
        text = spec[2],
        flag = spec.flag or flagName(key),
        min = spec[3],
        max = spec[4],
        value = settings[key],
        float = spec[5],
        suffix = spec[6] or "",
        callback = function(value)
            settings[key] = value
            applySafely()
        end
    })
end

local function addSliders(section, specs)
    for _, spec in ipairs(specs) do
        addSlider(section, spec)
    end
end

local function addList(section, key, text, values)
    controls[key] = section:AddList({
        text = text,
        flag = flagName(key),
        values = values,
        value = settings[key],
        max = #values,
        callback = function(value)
            settings[key] = value
            applySafely()
        end
    })
end

local function setControlValue(key, value)
    local control = controls[key]

    if not control then
        settings[key] = cloneTable(value)
        return
    end

    if type(value) == "boolean" and control.SetState then
        control:SetState(value, true)
        settings[key] = control.state
    elseif control.SetValue then
        control:SetValue(cloneTable(value), true)
        settings[key] = cloneTable(control.value)
    end
end

syncAdvancedControls = function()
    if originalTune then
        for toggleSetting, fields in pairs(GROUP_SETTINGS) do
            if not settings[toggleSetting] then
                for _, field in ipairs(fields) do
                    local value = originalTune[field]

                    if value ~= nil then
                        setControlValue(field, value)
                    end
                end
            end
        end
    end

    if originalGrip and not settings.CustomGrip then
        for _, attribute in ipairs(GRIP_FIELDS) do
            local value = originalGrip[attribute]

            if value == nilAttribute or value == nil then
                value = GRIP_DEFAULTS[attribute]
            end

            setControlValue(attribute, value)
        end
    end
end

--// Tuning
local tuningTab = library:AddTab("Tuning", 1)
local engineColumn = tuningTab:AddColumn()
local engineSection = engineColumn:AddSection("Engine Tuning")

controls.Enabled = engineSection:AddToggle({
    text = "Enable Tune",
    flag = "Tune Enabled",
    state = settings.Enabled,
    callback = function(enabled)
        settings.Enabled = enabled

        if enabled then
            applySafely()
        else
            restoreCurrentTune()
        end
    end
})

addSlider(engineSection, {"Horsepower", "Horsepower", 0, 2000, 10, " HP", flag = "Horsepower"})
addSlider(engineSection, {"Redline", "Redline", 3000, 16000, 100, " RPM", flag = "Redline"})
addToggle(engineSection, "Lightweight", "Lightweight Chassis", "Lightweight Chassis")

local curveSection = engineColumn:AddSection("Power Curve")
addToggle(curveSection, "AdvancedEngine", "Custom Power Curve")
addSliders(curveSection, {
    {"IdleRPM", "Idle RPM", 400, 2500, 50, " RPM"},
    {"PeakRPM", "Peak RPM", 2000, 16000, 100, " RPM"},
    {"EqPoint", "Curve Balance", 500, 12000, 50, " RPM"},
    {"PeakSharpness", "Peak Sharpness", 1, 30, 0.5},
    {"CurveMult", "Curve Multiplier", 0.01, 0.25, 0.01}
})

local responseSection = engineColumn:AddSection("Engine Response")
addSliders(responseSection, {
    {"ThrotAccel", "Throttle Rise", 0.05, 3, 0.05},
    {"ThrotDecel", "Throttle Fall", 0.05, 3, 0.05},
    {"RevAccel", "Rev Acceleration", 25, 1000, 25},
    {"RevDecay", "Rev Decay", 10, 500, 5},
    {"RevBounce", "Limiter Bounce", 0, 1500, 50, " RPM"},
    {"Flywheel", "Flywheel", 25, 1500, 25},
    {"InclineComp", "Incline Compensation", 0, 10, 0.1}
})

local boostColumn = tuningTab:AddColumn()
local boostSection = boostColumn:AddSection("Forced Induction")
addSlider(boostSection, {"Turbochargers", "Turbochargers", 0, 4, 1, "", flag = "Turbochargers"})
addSlider(boostSection, {"Superchargers", "Superchargers", 0, 2, 1, "", flag = "Superchargers"})

local boostCalibration = boostColumn:AddSection("Boost Calibration")
addToggle(boostCalibration, "AdvancedBoost", "Custom Boost")
addSliders(boostCalibration, {
    {"T_Boost", "Turbo Boost", 0, 60, 0.5, " PSI"},
    {"T_Efficiency", "Turbo Efficiency", 0, 10, 0.1},
    {"T_Size", "Turbo Size", 10, 100, 1},
    {"S_Boost", "Supercharger Boost", 0, 40, 0.5, " PSI"},
    {"S_Efficiency", "Supercharger Efficiency", 0, 10, 0.1},
    {"S_Sensitivity", "Supercharger Response", 0.01, 1, 0.01}
})

local actionSection = boostColumn:AddSection("Garage")
actionSection:AddButton({text = "Apply Current Setup", callback = applySafely})
actionSection:AddButton({
    text = "Restore Stock Tune",
    callback = function()
        settings.Enabled = false

        if controls.Enabled and controls.Enabled.SetState then
            controls.Enabled:SetState(false)
        else
            restoreCurrentTune()
        end
    end
})

--// Suspension
local suspensionTab = library:AddTab("Suspension", 2)
local frontColumn = suspensionTab:AddColumn()
local frontSection = frontColumn:AddSection("Front Suspension")
addToggle(frontSection, "AdvancedSuspension", "Custom Suspension")
addSliders(frontSection, {
    {"FSusStiffness", "Spring Stiffness", 500, 30000, 100},
    {"FSusDamping", "Spring Damping", 25, 2000, 5},
    {"FAntiRoll", "Anti-Roll", 0, 200, 1},
    {"FSusLength", "Ride Length", 0.5, 6, 0.05},
    {"FPreCompress", "Pre-Compression", 0, 2, 0.05},
    {"FExtensionLim", "Extension Limit", 0, 2, 0.05},
    {"FCompressLim", "Compression Limit", 0, 2, 0.05},
    {"FCamber", "Camber", -10, 10, 0.1, " deg"},
    {"FCaster", "Caster", -10, 20, 0.1, " deg"},
    {"FToe", "Toe", -5, 5, 0.1, " deg"},
    {"FWheelDensity", "Wheel Density", 0.01, 5, 0.01},
    {"FGyroDamp", "Gyro Damping", 0, 1000, 10}
})

local rearColumn = suspensionTab:AddColumn()
local rearSection = rearColumn:AddSection("Rear Suspension")
addSliders(rearSection, {
    {"RSusStiffness", "Spring Stiffness", 500, 30000, 100},
    {"RSusDamping", "Spring Damping", 25, 2000, 5},
    {"RAntiRoll", "Anti-Roll", 0, 200, 1},
    {"RSusLength", "Ride Length", 0.5, 6, 0.05},
    {"RPreCompress", "Pre-Compression", 0, 2, 0.05},
    {"RExtensionLim", "Extension Limit", 0, 2, 0.05},
    {"RCompressLim", "Compression Limit", 0, 2, 0.05},
    {"RCamber", "Camber", -10, 10, 0.1, " deg"},
    {"RCaster", "Caster", -10, 20, 0.1, " deg"},
    {"RToe", "Toe", -5, 5, 0.1, " deg"},
    {"RWheelDensity", "Wheel Density", 0.01, 5, 0.01},
    {"RGyroDamp", "Gyro Damping", 0, 1000, 10}
})

local balanceSection = rearColumn:AddSection("Chassis Balance")
addSliders(balanceSection, {
    {"WeightDist", "Front Weight", 0, 100, 1, "%"},
    {"CGHeight", "Center of Gravity", -2, 5, 0.05}
})

--// Drivetrain
local drivetrainTab = library:AddTab("Drivetrain", 3)
local transmissionColumn = drivetrainTab:AddColumn()
local transmissionSection = transmissionColumn:AddSection("Transmission")
addToggle(transmissionSection, "PerformanceGearbox", "Performance Gearbox", "Performance Gearbox")
addToggle(transmissionSection, "AdvancedTransmission", "Custom Transmission")
addList(transmissionSection, "Config", "Drivetrain", {"FWD", "RWD", "AWD"})
addSliders(transmissionSection, {
    {"FDMult", "Final Drive Multiplier", 0.25, 4, 0.05},
    {"ShiftUpTime", "Upshift Time", 0.05, 2, 0.05, "s"},
    {"ShiftDnTime", "Downshift Time", 0.05, 2, 0.05, "s"},
    {"ShiftThrot", "Shift Throttle Cut", 0, 100, 1, "%"},
    {"AutoUpThresh", "Auto Upshift Offset", 0, 3000, 25, " RPM"},
    {"AutoDownThresh", "Auto Downshift Offset", 0, 4000, 25, " RPM"},
    {"ClutchEngage", "Clutch Engagement", 0, 100, 1, "%"},
    {"ClutchRPMMult", "Clutch RPM Multiplier", 0.1, 3, 0.05}
})

local differentialColumn = drivetrainTab:AddColumn()
local differentialSection = differentialColumn:AddSection("Differential")
addToggle(differentialSection, "AdvancedDifferential", "Custom Differential")
addList(differentialSection, "DifferentialType", "Differential Model", {"Old", "New"})
addSliders(differentialSection, {
    {"TorqueVector", "Torque Vector", -100, 100, 1, "%"},
    {"FDiffSlipThres", "Front Slip Threshold", 0, 100, 1, "%"},
    {"FDiffLockThres", "Front Lock Threshold", 0, 100, 1, "%"},
    {"RDiffSlipThres", "Rear Slip Threshold", 0, 100, 1, "%"},
    {"RDiffLockThres", "Rear Lock Threshold", 0, 100, 1, "%"}
})

local modernDifferential = differentialColumn:AddSection("Modern Differential")
addSliders(modernDifferential, {
    {"FDiffPower", "Front Power Lock", 0, 100, 1, "%"},
    {"FDiffCoast", "Front Coast Lock", 0, 100, 1, "%"},
    {"FDiffPreload", "Front Preload", 0, 100, 1, "%"},
    {"RDiffPower", "Rear Power Lock", 0, 100, 1, "%"},
    {"RDiffCoast", "Rear Coast Lock", 0, 100, 1, "%"},
    {"RDiffPreload", "Rear Preload", 0, 100, 1, "%"}
})

--// Handling
local handlingTab = library:AddTab("Handling", 4)
local steeringColumn = handlingTab:AddColumn()
local steeringSection = steeringColumn:AddSection("Steering")
addToggle(steeringSection, "AdvancedSteering", "Custom Steering")
addSliders(steeringSection, {
    {"SteerRatio", "Steering Ratio", 5, 30, 0.1},
    {"LockToLock", "Lock to Lock", 1, 6, 0.01, " turns"},
    {"Ackerman", "Ackerman", 0, 2, 0.05},
    {"SteerSpeed", "Steering Speed", 0.01, 1, 0.01},
    {"ReturnSpeed", "Return Speed", 0.01, 1, 0.01},
    {"SteerDecay", "Speed Decay", 0, 500, 5},
    {"MinSteer", "Minimum Steering", 0, 100, 1, "%"},
    {"MSteerExp", "Steering Exponent", 0.1, 4, 0.1}
})

local brakeSection = steeringColumn:AddSection("Brakes")
addToggle(brakeSection, "UpgradedBrakes", "Upgraded Brakes", "Upgraded Brakes")
addToggle(brakeSection, "AdvancedBrakes", "Custom Brake Balance")
addSliders(brakeSection, {
    {"BrakeBias", "Front Brake Bias", 0, 1, 0.01},
    {"PBrakeBias", "Parking Brake Bias", 0, 1, 0.01},
    {"EBrakeForce", "Electric Brake Force", 0, 10000, 100}
})

local gripColumn = handlingTab:AddColumn()
local assistSection = gripColumn:AddSection("Driver Assists")
addToggle(assistSection, "AdvancedAssists", "Custom Driver Assists")
addToggle(assistSection, "ABSEnabled", "ABS")
addSlider(assistSection, {"ABSThreshold", "ABS Threshold", 0, 100, 1})
addToggle(assistSection, "TCSEnabled", "Traction Control")
addSliders(assistSection, {
    {"TCSThreshold", "TCS Threshold", 0, 100, 1},
    {"TCSGradient", "TCS Gradient", 0, 100, 1},
    {"TCSLimit", "TCS Limit", 0, 100, 1}
})

local gripSection = gripColumn:AddSection("Tire Grip")
addToggle(gripSection, "CustomGrip", "Custom Tire Grip")
addSliders(gripSection, {
    {"Friction_DryRoad", "Dry Road", 0, 3, 0.05},
    {"Friction_WetRoad", "Wet Road", 0, 3, 0.05},
    {"Friction_DryDirt", "Dry Dirt", 0, 3, 0.05},
    {"Friction_WetDirt", "Wet Dirt", 0, 3, 0.05},
    {"Friction_DryGrass", "Dry Grass", 0, 3, 0.05},
    {"Friction_WetGrass", "Wet Grass", 0, 3, 0.05}
})

library:AddCleanup(function()
    running = false
    restoreCurrentTune()
end)

library:Init()

task.spawn(function()
    while running and not library.unloaded do
        if settings.Enabled then
            applySafely()
        end

        task.wait(0.1)
    end
end)
