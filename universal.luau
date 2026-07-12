--[[
    xanhub | multi-game loader

    Repository layout:
      /ui.luau
      /loader.luau
      /universal.luau
      /games/<game-file>.luau

    Add featured games in FEATURED_PLACES or FEATURED_UNIVERSES below.
    Game scripts receive the runtime table as their first argument and can also
    read it from getgenv().XANHUB_RUNTIME.
]]

local REPOSITORY_ROOT = "https://raw.githubusercontent.com/PPainez/idk/refs/heads/main"
local UI_URL = REPOSITORY_ROOT .. "/ui.luau"
local MAIN_ROOT = REPOSITORY_ROOT
local UNIVERSAL_URL = MAIN_ROOT .. "/universal.luau"

-- Place-specific scripts. This is the usual table to edit.
local FEATURED_PLACES = {
    -- [1234567890] = {name = "Gakuran", file = "gakuran.luau"},
}

-- Optional universe-wide scripts. Useful when one game has several places.
local FEATURED_UNIVERSES = {
    -- [1234567890] = {name = "Example Universe", file = "example.luau"},
}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local env = (type(getgenv) == "function" and getgenv()) or _G

local function safeDestroy(object)
    if object then
        pcall(function()
            object:Destroy()
        end)
    end
end

local function resolveGuiParent()
    local candidates = {
        type(gethui) == "function" and gethui or nil,
        type(get_hidden_gui) == "function" and get_hidden_gui or nil,
        type(gethiddengui) == "function" and gethiddengui or nil,
    }

    for _, getter in ipairs(candidates) do
        if getter then
            local ok, result = pcall(getter)
            if ok and typeof(result) == "Instance" then
                return result
            end
        end
    end

    local ok, core = pcall(function()
        return CoreGui
    end)
    if ok and core then
        return core
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function createLoaderGui()
    local previous = resolveGuiParent():FindFirstChild("xanhub_loader")
    safeDestroy(previous)

    local gui = Instance.new("ScreenGui")
    gui.Name = "xanhub_loader"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    elseif type(protectgui) == "function" then
        pcall(protectgui, gui)
    end

    gui.Parent = resolveGuiParent()

    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(3, 5, 9)
    backdrop.BackgroundTransparency = 0.12
    backdrop.BorderSizePixel = 0
    backdrop.Parent = gui

    local backgroundGradient = Instance.new("UIGradient")
    backgroundGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(3, 6, 12)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(7, 12, 22)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 3, 7)),
    })
    backgroundGradient.Rotation = 25
    backgroundGradient.Parent = backdrop

    local glow = Instance.new("Frame")
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    glow.Position = UDim2.fromScale(0.5, 0.5)
    glow.Size = UDim2.fromOffset(580, 300)
    glow.BackgroundColor3 = Color3.fromRGB(0, 145, 255)
    glow.BackgroundTransparency = 0.9
    glow.BorderSizePixel = 0
    glow.Parent = backdrop

    local glowCorner = Instance.new("UICorner")
    glowCorner.CornerRadius = UDim.new(1, 0)
    glowCorner.Parent = glow

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(500, 230)
    panel.BackgroundColor3 = Color3.fromRGB(11, 14, 21)
    panel.BackgroundTransparency = 0.02
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Parent = backdrop

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 12)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(45, 55, 74)
    panelStroke.Transparency = 0.25
    panelStroke.Thickness = 1
    panelStroke.Parent = panel

    local panelGradient = Instance.new("UIGradient")
    panelGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 32)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 11, 17)),
    })
    panelGradient.Rotation = 90
    panelGradient.Parent = panel

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(1, 0, 0, 3)
    accent.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    accent.BorderSizePixel = 0
    accent.Parent = panel

    local accentGradient = Instance.new("UIGradient")
    accentGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 100, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 210, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 70, 255)),
    })
    accentGradient.Parent = accent

    local brand = Instance.new("TextLabel")
    brand.Position = UDim2.fromOffset(28, 24)
    brand.Size = UDim2.new(1, -56, 0, 44)
    brand.BackgroundTransparency = 1
    brand.RichText = true
    brand.Text = '<font color="rgb(0,170,255)">xan</font><font color="rgb(245,247,255)">hub</font>'
    brand.TextColor3 = Color3.fromRGB(245, 247, 255)
    brand.TextSize = 31
    brand.Font = Enum.Font.Code
    brand.TextXAlignment = Enum.TextXAlignment.Left
    brand.Parent = panel

    local subtitle = Instance.new("TextLabel")
    subtitle.Position = UDim2.fromOffset(30, 66)
    subtitle.Size = UDim2.new(1, -60, 0, 22)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "universal multi-game loader"
    subtitle.TextColor3 = Color3.fromRGB(130, 143, 166)
    subtitle.TextSize = 14
    subtitle.Font = Enum.Font.Code
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = panel

    local status = Instance.new("TextLabel")
    status.Position = UDim2.fromOffset(30, 112)
    status.Size = UDim2.new(1, -100, 0, 24)
    status.BackgroundTransparency = 1
    status.Text = "Starting..."
    status.TextColor3 = Color3.fromRGB(222, 228, 240)
    status.TextSize = 15
    status.Font = Enum.Font.Code
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Parent = panel

    local percent = Instance.new("TextLabel")
    percent.AnchorPoint = Vector2.new(1, 0)
    percent.Position = UDim2.new(1, -30, 0, 112)
    percent.Size = UDim2.fromOffset(58, 24)
    percent.BackgroundTransparency = 1
    percent.Text = "0%"
    percent.TextColor3 = Color3.fromRGB(0, 170, 255)
    percent.TextSize = 15
    percent.Font = Enum.Font.Code
    percent.TextXAlignment = Enum.TextXAlignment.Right
    percent.Parent = panel

    local barBackground = Instance.new("Frame")
    barBackground.Position = UDim2.fromOffset(30, 150)
    barBackground.Size = UDim2.new(1, -60, 0, 12)
    barBackground.BackgroundColor3 = Color3.fromRGB(25, 30, 41)
    barBackground.BorderSizePixel = 0
    barBackground.Parent = panel

    local barBackgroundCorner = Instance.new("UICorner")
    barBackgroundCorner.CornerRadius = UDim.new(1, 0)
    barBackgroundCorner.Parent = barBackground

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    bar.BorderSizePixel = 0
    bar.ClipsDescendants = true
    bar.Parent = barBackground

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local barGradient = Instance.new("UIGradient")
    barGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 110, 255)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(0, 220, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 90, 255)),
    })
    barGradient.Parent = bar

    local footer = Instance.new("TextLabel")
    footer.Position = UDim2.fromOffset(30, 182)
    footer.Size = UDim2.new(1, -60, 0, 22)
    footer.BackgroundTransparency = 1
    footer.Text = "Place " .. tostring(game.PlaceId) .. "  •  Universe " .. tostring(game.GameId)
    footer.TextColor3 = Color3.fromRGB(91, 102, 122)
    footer.TextSize = 12
    footer.Font = Enum.Font.Code
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.TextTruncate = Enum.TextTruncate.AtEnd
    footer.Parent = panel

    local dots = {}
    for index = 1, 3 do
        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Position = UDim2.new(1, -30 - ((3 - index) * 13), 0, 194)
        dot.Size = UDim2.fromOffset(5, 5)
        dot.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
        dot.BackgroundTransparency = 0.65
        dot.BorderSizePixel = 0
        dot.Parent = panel
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot
        dots[index] = dot
    end

    local scale = Instance.new("UIScale")
    scale.Parent = panel

    local function updateScale()
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        scale.Scale = math.clamp(math.min((viewport.X - 32) / 500, (viewport.Y - 32) / 230, 1), 0.58, 1)
    end

    updateScale()
    local viewportConnection
    if workspace.CurrentCamera then
        viewportConnection = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
    end

    local alive = true
    task.spawn(function()
        local phase = 0
        while alive and gui.Parent do
            phase += RunService.RenderStepped:Wait() * 2.5
            glow.BackgroundTransparency = 0.91 + math.sin(phase) * 0.025
            barGradient.Offset = Vector2.new(((phase * 0.15) % 2) - 1, 0)
            for index, dot in ipairs(dots) do
                dot.BackgroundTransparency = 0.25 + 0.65 * math.abs(math.sin(phase + index * 0.8))
            end
        end
    end)

    local currentTween
    local function setProgress(value, message, color)
        value = math.clamp(tonumber(value) or 0, 0, 1)
        status.Text = tostring(message or status.Text)
        percent.Text = tostring(math.floor(value * 100 + 0.5)) .. "%"
        if color then
            status.TextColor3 = color
            percent.TextColor3 = color
        end

        if currentTween then
            pcall(function()
                currentTween:Cancel()
            end)
        end

        local ok, tween = pcall(function()
            return TweenService:Create(
                bar,
                TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                {Size = UDim2.new(value, 0, 1, 0)}
            )
        end)

        if ok and tween then
            currentTween = tween
            tween:Play()
        else
            bar.Size = UDim2.new(value, 0, 1, 0)
        end
    end

    local function close(success)
        alive = false
        if viewportConnection then
            pcall(function()
                viewportConnection:Disconnect()
            end)
            viewportConnection = nil
        end
        setProgress(1, success and "Ready" or "Loader stopped", success and Color3.fromRGB(120, 235, 170) or Color3.fromRGB(255, 95, 105))
        task.wait(success and 0.25 or 1.4)

        local ok, tween = pcall(function()
            return TweenService:Create(
                backdrop,
                TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {BackgroundTransparency = 1}
            )
        end)
        if ok and tween then
            tween:Play()
        end

        local panelTweenOk, panelTween = pcall(function()
            return TweenService:Create(
                panel,
                TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In),
                {Position = UDim2.fromScale(0.5, 0.54)}
            )
        end)
        if panelTweenOk and panelTween then
            panelTween:Play()
        end

        task.wait(0.34)
        safeDestroy(gui)
    end

    return {
        gui = gui,
        setProgress = setProgress,
        close = close,
    }
end

local function fetchSource(url, attempts)
    attempts = attempts or 3
    local lastError

    for attempt = 1, attempts do
        local ok, result = pcall(function()
            return game:HttpGet(url, true)
        end)
        if ok and type(result) == "string" and #result > 20 then
            return result
        end
        lastError = result
        task.wait(0.35 * attempt)
    end

    return nil, tostring(lastError or "request failed")
end

local function compileSource(source, name)
    local chunk, compileError = loadstring(source)
    if not chunk then
        return nil, tostring(compileError)
    end
    return chunk
end

local function resolveFeaturedGame()
    return FEATURED_PLACES[game.PlaceId] or FEATURED_UNIVERSES[game.GameId]
end

local loader = createLoaderGui()

local function fail(message)
    warn("[xanhub loader] " .. tostring(message))
    loader.setProgress(1, tostring(message), Color3.fromRGB(255, 95, 105))
    loader.close(false)
end

local ok, fatalError = xpcall(function()
    if not game:IsLoaded() then
        loader.setProgress(0.08, "Waiting for the game...")
        game.Loaded:Wait()
    end

    loader.setProgress(0.16, "Preparing runtime...")

    local previousRuntime = env.XANHUB_RUNTIME
    if type(previousRuntime) == "table" then
        previousRuntime.unloading = true
        local previousLibrary = previousRuntime.library
        if type(previousLibrary) == "table" and type(previousLibrary.Unload) == "function" then
            pcall(function()
                previousLibrary:Unload()
            end)
        end
    end

    loader.setProgress(0.30, "Loading xanhub UI...")
    local uiSource, uiError = fetchSource(UI_URL)
    assert(uiSource, "UI request failed: " .. tostring(uiError))

    loader.setProgress(0.43, "Compiling interface...")
    local uiChunk, uiCompileError = compileSource(uiSource, "xanhub/ui.luau")
    assert(uiChunk, "UI compile failed: " .. tostring(uiCompileError))

    local library = uiChunk()
    assert(type(library) == "table", "UI library returned an invalid value")

    local runtime = {
        version = "1.0.0",
        repositoryRoot = REPOSITORY_ROOT,
        mainRoot = MAIN_ROOT,
        uiUrl = UI_URL,
        universalUrl = UNIVERSAL_URL,
        library = library,
        placeId = game.PlaceId,
        universeId = game.GameId,
        startedAt = os.clock(),
        unloading = false,
    }

    env.XANHUB_RUNTIME = runtime

    loader.setProgress(0.56, "Detecting game...")
    local featured = resolveFeaturedGame()
    local targetUrl
    local targetName

    if featured then
        targetName = tostring(featured.name or featured.file or "Featured Game")
        targetUrl = MAIN_ROOT .. "/games/" .. tostring(featured.file)
        runtime.featured = true
        runtime.gameName = targetName
        runtime.gameFile = featured.file
        loader.setProgress(0.67, "Featured game found: " .. targetName)
    else
        targetName = "Universal"
        targetUrl = UNIVERSAL_URL
        runtime.featured = false
        runtime.gameName = "Universal"
        loader.setProgress(0.67, "No featured script; using Universal")
    end

    loader.setProgress(0.76, "Downloading " .. targetName .. "...")
    local targetSource, targetError = fetchSource(targetUrl)

    if not targetSource and featured then
        warn("[xanhub loader] Featured script failed, falling back to Universal: " .. tostring(targetError))
        runtime.featured = false
        runtime.gameName = "Universal"
        targetName = "Universal"
        targetUrl = UNIVERSAL_URL
        loader.setProgress(0.80, "Featured script unavailable; loading Universal")
        targetSource, targetError = fetchSource(targetUrl)
    end

    assert(targetSource, targetName .. " request failed: " .. tostring(targetError))

    loader.setProgress(0.88, "Compiling " .. targetName .. "...")
    local targetChunk, targetCompileError = compileSource(targetSource, "xanhub/" .. targetName)
    assert(targetChunk, targetName .. " compile failed: " .. tostring(targetCompileError))

    loader.setProgress(0.95, "Starting " .. targetName .. " menu...")
    local executed, executionError = xpcall(function()
        return targetChunk(runtime)
    end, debug.traceback)
    assert(executed, targetName .. " runtime failed: " .. tostring(executionError))

    loader.setProgress(1, targetName .. " loaded")
    loader.close(true)
end, debug.traceback)

if not ok then
    fail(fatalError)
end
