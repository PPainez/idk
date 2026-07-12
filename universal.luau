--[[
    xanhub | Universal

    Runs through main/loader.luau or standalone.
    General client-side movement, visual, ESP, and utility tools.
    No anti-cheat bypass, remote abuse, or game-specific hooks are included.
]]

local runtime = ...
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(runtime) ~= "table" then
    runtime = env.XANHUB_RUNTIME
end

local DEFAULT_UI_URL = "https://raw.githubusercontent.com/PPainez/idk/refs/heads/main/ui.luau"
local UI_URL = type(runtime) == "table" and runtime.uiUrl or DEFAULT_UI_URL

local function acquireLibrary()
    if type(runtime) == "table"
        and type(runtime.library) == "table"
        and not runtime.library.unloaded then
        return runtime.library
    end

    local source = game:HttpGet(UI_URL, true)
    local chunk, compileError = loadstring(source)
    assert(chunk, "[xanhub universal] UI compile failed: " .. tostring(compileError))

    local loaded = chunk()
    assert(type(loaded) == "table", "[xanhub universal] UI library returned an invalid value")

    runtime = type(runtime) == "table" and runtime or {}
    runtime.library = loaded
    runtime.uiUrl = UI_URL
    runtime.placeId = game.PlaceId
    runtime.universeId = game.GameId
    env.XANHUB_RUNTIME = runtime
    return loaded
end

local library = acquireLibrary()
library:SetTitle("xanhub | Universal")
library:SetAccent(Color3.fromRGB(0, 170, 255))
library:SetTweening(false)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local state = {
    unloading = false,
    connections = {},
    original = {},
    esp = {},
    overlays = {},
    fly = {},
    noclipOriginal = setmetatable({}, {__mode = "k"}),
    movementOriginal = setmetatable({}, {__mode = "k"}),
    effectOriginal = setmetatable({}, {__mode = "k"}),
}

local function notify(message, duration)
    if library and library.SendNotification then
        library:SendNotification(duration or 2, tostring(message))
    else
        print("[xanhub universal] " .. tostring(message))
    end
end

local function addConnection(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(state.connections, connection)
    return connection
end

local function disconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid(character)
    character = character or getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
    character = character or getCharacter()
    return character and (
        character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
    )
end

local function option(flag)
    return library.options and library.options[flag]
end

local function setToggle(flag, enabled)
    local control = option(flag)
    if control and type(control.SetState) == "function" then
        control:SetState(enabled == true)
    else
        library.flags[flag] = enabled == true
    end
end

local function toggle(flag)
    setToggle(flag, library.flags[flag] ~= true)
end

local function safeClipboard(text)
    local setter = type(setclipboard) == "function" and setclipboard
        or type(toclipboard) == "function" and toclipboard
        or nil

    if not setter then
        notify("Clipboard is unavailable", 3)
        return false
    end

    local ok = pcall(setter, tostring(text))
    notify(ok and "Copied to clipboard" or "Clipboard failed", ok and 2 or 3)
    return ok
end

local function createRounded(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 6)
    corner.Parent = parent
    return corner
end

local function createOverlayRoot()
    if state.overlays.root and state.overlays.root.Parent then
        return state.overlays.root
    end

    local root = Instance.new("Frame")
    root.Name = "UniversalOverlay"
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundTransparency = 1
    root.BorderSizePixel = 0
    root.Active = false
    root.ZIndex = 500
    root.Parent = library.base
    state.overlays.root = root
    return root
end

local function tween(object, properties, duration)
    local ok, result = pcall(function()
        local animation = TweenService:Create(
            object,
            TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            properties
        )
        animation:Play()
        return animation
    end)
    if not ok then
        for property, value in pairs(properties) do
            pcall(function()
                object[property] = value
            end)
        end
    end
    return ok and result or nil
end

-- UI -------------------------------------------------------------------------

local homeTab = library:AddTab("Home", 1)
local playerTab = library:AddTab("Player", 2)
local visualsTab = library:AddTab("Visuals", 3)
local worldTab = library:AddTab("World", 4)
local utilityTab = library:AddTab("Utility", 5)
local bindsTab = library:AddTab("Keybinds", 6)

local homeLeft = homeTab:AddColumn()
local homeRight = homeTab:AddColumn()
local playerLeft = playerTab:AddColumn()
local playerRight = playerTab:AddColumn()
local visualsLeft = visualsTab:AddColumn()
local visualsRight = visualsTab:AddColumn()
local worldLeft = worldTab:AddColumn()
local worldRight = worldTab:AddColumn()
local utilityLeft = utilityTab:AddColumn()
local utilityRight = utilityTab:AddColumn()
local bindsLeft = bindsTab:AddColumn()
local bindsRight = bindsTab:AddColumn()

local intro = homeLeft:AddSection("xanhub Universal")
intro:AddLabel("Loaded for: " .. tostring(game.Name))
intro:AddLabel("Place ID: " .. tostring(game.PlaceId))
intro:AddLabel("Universe ID: " .. tostring(game.GameId))
intro:AddLabel("General client tools with complete unload restoration")

local quick = homeRight:AddSection("Quick Actions")
quick:AddButton({
    text = "Copy Place ID",
    callback = function()
        safeClipboard(game.PlaceId)
    end,
})
quick:AddButton({
    text = "Copy Job ID",
    callback = function()
        safeClipboard(game.JobId)
    end,
})
quick:AddButton({
    text = "Rejoin Server",
    callback = function()
        notify("Rejoining...")
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
        if not ok then
            pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
        end
    end,
})

local runtimeSection = homeRight:AddSection("Runtime")
local runtimeStatus = runtimeSection:AddLabel("Status: initializing")
runtimeSection:AddButton({
    text = "Print Active Flags",
    callback = function()
        for flag, value in pairs(library.flags) do
            if value == true then
                print("[xanhub active]", flag)
            end
        end
    end,
})

-- Movement module ------------------------------------------------------------

local movementSection = playerLeft:AddSection("Movement")
movementSection:AddToggle({
    text = "Walk Speed Override [RISK]",
    flag = "Universal Speed Enabled",
    state = false,
})
movementSection:AddSlider({
    text = "Walk Speed",
    flag = "Universal Walk Speed",
    min = 8,
    max = 250,
    value = 32,
    float = 1,
})
movementSection:AddToggle({
    text = "Jump Override [RISK]",
    flag = "Universal Jump Enabled",
    state = false,
})
movementSection:AddSlider({
    text = "Jump Power",
    flag = "Universal Jump Power",
    min = 20,
    max = 250,
    value = 70,
    float = 1,
})
movementSection:AddToggle({
    text = "Infinite Jump [RISK]",
    flag = "Universal Infinite Jump",
    state = false,
})

local advancedMovement = playerRight:AddSection("Advanced Movement")
advancedMovement:AddToggle({
    text = "Fly [RISK]",
    flag = "Universal Fly",
    state = false,
})
advancedMovement:AddSlider({
    text = "Fly Speed",
    flag = "Universal Fly Speed",
    min = 10,
    max = 300,
    value = 70,
    float = 5,
})
advancedMovement:AddToggle({
    text = "Noclip [RISK]",
    flag = "Universal Noclip",
    state = false,
})
advancedMovement:AddToggle({
    text = "Ctrl + Click Teleport [RISK]",
    flag = "Universal Click Teleport",
    state = false,
})
advancedMovement:AddLabel("Risk features are client-side and may be detected by games")

local function setupMovementRuntime()
    local movementConnection
    local infiniteJumpConnection
    local clickTeleportConnection

    local function rememberHumanoid(humanoid)
        if humanoid and not state.movementOriginal[humanoid] then
            state.movementOriginal[humanoid] = {
                WalkSpeed = humanoid.WalkSpeed,
                JumpPower = humanoid.JumpPower,
                JumpHeight = humanoid.JumpHeight,
                UseJumpPower = humanoid.UseJumpPower,
                AutoRotate = humanoid.AutoRotate,
                PlatformStand = humanoid.PlatformStand,
            }
        end
    end

    local function restoreHumanoid(humanoid)
        local original = humanoid and state.movementOriginal[humanoid]
        if humanoid and original and humanoid.Parent then
            pcall(function()
                humanoid.WalkSpeed = original.WalkSpeed
                humanoid.JumpPower = original.JumpPower
                humanoid.JumpHeight = original.JumpHeight
                humanoid.UseJumpPower = original.UseJumpPower
                humanoid.AutoRotate = original.AutoRotate
                humanoid.PlatformStand = original.PlatformStand
            end)
        end
    end

    movementConnection = addConnection(RunService.Heartbeat, function()
        if state.unloading then
            return
        end

        local humanoid = getHumanoid()
        if not humanoid then
            return
        end

        rememberHumanoid(humanoid)

        if library.flags["Universal Speed Enabled"] then
            humanoid.WalkSpeed = tonumber(library.flags["Universal Walk Speed"]) or 32
        elseif not library.flags["Universal Fly"] then
            local original = state.movementOriginal[humanoid]
            if original then
                humanoid.WalkSpeed = original.WalkSpeed
            end
        end

        if library.flags["Universal Jump Enabled"] then
            local value = tonumber(library.flags["Universal Jump Power"]) or 70
            if humanoid.UseJumpPower then
                humanoid.JumpPower = value
            else
                humanoid.JumpHeight = math.max(7.2, value / 7)
            end
        else
            local original = state.movementOriginal[humanoid]
            if original then
                humanoid.JumpPower = original.JumpPower
                humanoid.JumpHeight = original.JumpHeight
            end
        end
    end)

    infiniteJumpConnection = addConnection(UserInputService.JumpRequest, function()
        if library.flags["Universal Infinite Jump"] then
            local humanoid = getHumanoid()
            if humanoid then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    local mouse = LocalPlayer:GetMouse()
    clickTeleportConnection = addConnection(mouse.Button1Down, function()
        if not library.flags["Universal Click Teleport"]
            or not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            return
        end

        local root = getRoot()
        if root and mouse.Hit then
            root.CFrame = mouse.Hit + Vector3.new(0, 3, 0)
        end
    end)

    library:AddCleanup(function()
        disconnect(movementConnection)
        disconnect(infiniteJumpConnection)
        disconnect(clickTeleportConnection)
        for humanoid in pairs(state.movementOriginal) do
            restoreHumanoid(humanoid)
        end
    end)
end

local function setupFlyRuntime()
    local flyConnection

    local function stopFly()
        disconnect(flyConnection)
        flyConnection = nil

        if state.fly.velocity then
            pcall(function()
                state.fly.velocity:Destroy()
            end)
        end
        if state.fly.gyro then
            pcall(function()
                state.fly.gyro:Destroy()
            end)
        end

        local humanoid = getHumanoid()
        if humanoid then
            local original = state.movementOriginal[humanoid]
            humanoid.PlatformStand = original and original.PlatformStand or false
            humanoid.AutoRotate = original and original.AutoRotate or true
        end

        state.fly.velocity = nil
        state.fly.gyro = nil
    end

    local function startFly()
        stopFly()

        local root = getRoot()
        local humanoid = getHumanoid()
        if not root or not humanoid then
            setToggle("Universal Fly", false)
            return
        end

        if not state.movementOriginal[humanoid] then
            state.movementOriginal[humanoid] = {
                WalkSpeed = humanoid.WalkSpeed,
                JumpPower = humanoid.JumpPower,
                JumpHeight = humanoid.JumpHeight,
                UseJumpPower = humanoid.UseJumpPower,
                AutoRotate = humanoid.AutoRotate,
                PlatformStand = humanoid.PlatformStand,
            }
        end

        local velocity = Instance.new("BodyVelocity")
        velocity.Name = "xanhub_fly_velocity"
        velocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        velocity.Velocity = Vector3.zero
        velocity.Parent = root

        local gyro = Instance.new("BodyGyro")
        gyro.Name = "xanhub_fly_gyro"
        gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
        gyro.P = 30000
        gyro.CFrame = root.CFrame
        gyro.Parent = root

        state.fly.velocity = velocity
        state.fly.gyro = gyro
        humanoid.PlatformStand = true
        humanoid.AutoRotate = false

        flyConnection = addConnection(RunService.RenderStepped, function()
            if state.unloading or not library.flags["Universal Fly"] then
                return
            end

            local camera = Workspace.CurrentCamera
            local currentRoot = getRoot()
            if not camera or not currentRoot or velocity.Parent ~= currentRoot then
                setToggle("Universal Fly", false)
                return
            end

            local direction = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.new(0, 1, 0) end

            local speed = tonumber(library.flags["Universal Fly Speed"]) or 70
            velocity.Velocity = direction.Magnitude > 0 and direction.Unit * speed or Vector3.zero
            gyro.CFrame = CFrame.lookAt(currentRoot.Position, currentRoot.Position + camera.CFrame.LookVector)
        end)
    end

    local flyOption = option("Universal Fly")
    if flyOption then
        flyOption.callback = function(enabled)
            if enabled then
                startFly()
            else
                stopFly()
            end
        end
    end

    library:AddCleanup(stopFly)
end

local function setupNoclipRuntime()
    local connection

    local function restore()
        for part, canCollide in pairs(state.noclipOriginal) do
            if part and part.Parent then
                pcall(function()
                    part.CanCollide = canCollide
                end)
            end
            state.noclipOriginal[part] = nil
        end
    end

    connection = addConnection(RunService.Stepped, function()
        if not library.flags["Universal Noclip"] then
            restore()
            return
        end

        local character = getCharacter()
        if not character then
            return
        end

        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("BasePart") then
                if state.noclipOriginal[object] == nil then
                    state.noclipOriginal[object] = object.CanCollide
                end
                object.CanCollide = false
            end
        end
    end)

    local control = option("Universal Noclip")
    if control then
        control.callback = function(enabled)
            if not enabled then
                restore()
            end
        end
    end

    library:AddCleanup(function()
        disconnect(connection)
        restore()
    end)
end

-- ESP module -----------------------------------------------------------------

local espSection = visualsLeft:AddSection("Player ESP")
espSection:AddToggle({text = "Enabled", flag = "Universal ESP", state = false})
espSection:AddToggle({text = "Highlights", flag = "Universal ESP Highlights", state = true})
espSection:AddToggle({text = "Names", flag = "Universal ESP Names", state = true})
espSection:AddToggle({text = "Health Bar", flag = "Universal ESP Health", state = true})
espSection:AddToggle({text = "Distance", flag = "Universal ESP Distance", state = true})
espSection:AddToggle({text = "Team Check", flag = "Universal ESP Team Check", state = false})
espSection:AddSlider({
    text = "Maximum Distance",
    flag = "Universal ESP Max Distance",
    min = 50,
    max = 2000,
    value = 650,
    float = 10,
    suffix = " studs",
})
espSection:AddColor({
    text = "ESP Color",
    flag = "Universal ESP Color",
    color = Color3.fromRGB(0, 170, 255),
})

local function setupESPRuntime()
    local updateConnection
    local playerRemovingConnection
    local accumulator = 0

    local function destroyEntry(player)
        local entry = state.esp[player]
        if not entry then
            return
        end
        for _, object in pairs(entry) do
            if typeof(object) == "Instance" then
                pcall(function()
                    object:Destroy()
                end)
            end
        end
        state.esp[player] = nil
    end

    local function createEntry(player, character)
        destroyEntry(player)

        local highlight = Instance.new("Highlight")
        highlight.Name = "xanhub_universal_highlight"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.12
        highlight.Adornee = character
        highlight.Parent = character

        local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
        if not root then
            highlight:Destroy()
            return nil
        end

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "xanhub_universal_billboard"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.MaxDistance = 3000
        billboard.Size = UDim2.fromOffset(180, 54)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.7, 0)
        billboard.Parent = character

        local card = Instance.new("Frame")
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.fromScale(0.5, 0.5)
        card.Size = UDim2.fromOffset(170, 46)
        card.BackgroundColor3 = Color3.fromRGB(9, 12, 18)
        card.BackgroundTransparency = 0.16
        card.BorderSizePixel = 0
        card.Parent = billboard
        createRounded(card, 7)

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 170, 255)
        stroke.Transparency = 0.22
        stroke.Thickness = 1
        stroke.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.fromOffset(9, 4)
        nameLabel.Size = UDim2.new(1, -18, 0, 18)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = player.DisplayName
        nameLabel.TextColor3 = Color3.fromRGB(245, 247, 255)
        nameLabel.TextSize = 13
        nameLabel.Font = Enum.Font.Code
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = card

        local distanceLabel = Instance.new("TextLabel")
        distanceLabel.AnchorPoint = Vector2.new(1, 0)
        distanceLabel.Position = UDim2.new(1, -9, 0, 4)
        distanceLabel.Size = UDim2.fromOffset(58, 18)
        distanceLabel.BackgroundTransparency = 1
        distanceLabel.Text = "0m"
        distanceLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
        distanceLabel.TextSize = 11
        distanceLabel.Font = Enum.Font.Code
        distanceLabel.TextXAlignment = Enum.TextXAlignment.Right
        distanceLabel.Parent = card

        local barBackground = Instance.new("Frame")
        barBackground.Position = UDim2.fromOffset(9, 30)
        barBackground.Size = UDim2.new(1, -18, 0, 7)
        barBackground.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
        barBackground.BorderSizePixel = 0
        barBackground.Parent = card
        createRounded(barBackground, 4)

        local healthFill = Instance.new("Frame")
        healthFill.Size = UDim2.fromScale(1, 1)
        healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
        healthFill.BorderSizePixel = 0
        healthFill.Parent = barBackground
        createRounded(healthFill, 4)

        local entry = {
            character = character,
            highlight = highlight,
            billboard = billboard,
            card = card,
            stroke = stroke,
            name = nameLabel,
            distance = distanceLabel,
            healthBackground = barBackground,
            health = healthFill,
        }
        state.esp[player] = entry
        return entry
    end

    local function setVisible(entry, visible)
        if entry.highlight then entry.highlight.Enabled = visible and library.flags["Universal ESP Highlights"] == true end
        if entry.billboard then entry.billboard.Enabled = visible end
    end

    local function update()
        local enabled = library.flags["Universal ESP"] == true
        local localRoot = getRoot()
        local maxDistance = tonumber(library.flags["Universal ESP Max Distance"]) or 650
        local color = typeof(library.flags["Universal ESP Color"]) == "Color3"
            and library.flags["Universal ESP Color"]
            or Color3.fromRGB(0, 170, 255)

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local character = player.Character
                local humanoid = getHumanoid(character)
                local root = getRoot(character)
                local entry = state.esp[player]

                if character and root and humanoid and humanoid.Health > 0 then
                    if not entry or entry.character ~= character then
                        entry = createEntry(player, character)
                    end
                elseif entry then
                    destroyEntry(player)
                    entry = nil
                end

                if entry then
                    local sameTeam = library.flags["Universal ESP Team Check"]
                        and LocalPlayer.Team ~= nil
                        and player.Team == LocalPlayer.Team
                    local distance = localRoot and (localRoot.Position - root.Position).Magnitude or math.huge
                    local visible = enabled and not sameTeam and distance <= maxDistance
                    setVisible(entry, visible)

                    if visible then
                        entry.highlight.FillColor = color
                        entry.highlight.OutlineColor = color
                        entry.stroke.Color = color
                        entry.name.Visible = library.flags["Universal ESP Names"] == true
                        entry.distance.Visible = library.flags["Universal ESP Distance"] == true
                        entry.healthBackground.Visible = library.flags["Universal ESP Health"] == true
                        entry.distance.Text = tostring(math.floor(distance + 0.5)) .. "m"

                        local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                        entry.health.BackgroundColor3 = Color3.fromHSV(ratio * 0.33, 0.78, 1)
                        tween(entry.health, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.12)
                    end
                end
            end
        end
    end

    updateConnection = addConnection(RunService.Heartbeat, function(deltaTime)
        accumulator += deltaTime
        if accumulator >= 0.1 then
            accumulator = 0
            update()
        end
    end)

    playerRemovingConnection = addConnection(Players.PlayerRemoving, destroyEntry)

    local control = option("Universal ESP")
    if control then
        control.callback = function(enabled)
            if not enabled then
                for _, entry in pairs(state.esp) do
                    setVisible(entry, false)
                end
            end
        end
    end

    library:AddCleanup(function()
        disconnect(updateConnection)
        disconnect(playerRemovingConnection)
        local players = {}
        for player in pairs(state.esp) do
            table.insert(players, player)
        end
        for _, player in ipairs(players) do
            destroyEntry(player)
        end
    end)
end

-- Local visuals module -------------------------------------------------------

local localVisuals = visualsRight:AddSection("Local Visuals")
localVisuals:AddSlider({
    text = "Field of View",
    flag = "Universal FOV",
    min = 50,
    max = 120,
    value = 70,
    float = 1,
})
localVisuals:AddToggle({text = "Crosshair", flag = "Universal Crosshair", state = false})
localVisuals:AddSlider({text = "Crosshair Size", flag = "Universal Crosshair Size", min = 4, max = 30, value = 9, float = 1})
localVisuals:AddSlider({text = "Crosshair Gap", flag = "Universal Crosshair Gap", min = 0, max = 18, value = 4, float = 1})
localVisuals:AddColor({text = "Crosshair Color", flag = "Universal Crosshair Color", color = Color3.fromRGB(0, 170, 255)})
localVisuals:AddToggle({text = "Coordinates", flag = "Universal Coordinates", state = false})

local function setupOverlayRuntime()
    local renderConnection
    local root = createOverlayRoot()
    local crosshair = {}

    for index = 1, 4 do
        local line = Instance.new("Frame")
        line.Name = "CrosshairLine" .. index
        line.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
        line.BorderSizePixel = 0
        line.Visible = false
        line.ZIndex = 510
        line.Parent = root
        crosshair[index] = line
    end

    local coordinates = Instance.new("TextLabel")
    coordinates.AnchorPoint = Vector2.new(0.5, 1)
    coordinates.Position = UDim2.new(0.5, 0, 1, -22)
    coordinates.Size = UDim2.fromOffset(360, 28)
    coordinates.BackgroundColor3 = Color3.fromRGB(9, 12, 18)
    coordinates.BackgroundTransparency = 0.18
    coordinates.BorderSizePixel = 0
    coordinates.TextColor3 = Color3.fromRGB(235, 240, 250)
    coordinates.TextSize = 13
    coordinates.Font = Enum.Font.Code
    coordinates.Visible = false
    coordinates.ZIndex = 510
    coordinates.Parent = root
    createRounded(coordinates, 7)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 170, 255)
    stroke.Transparency = 0.35
    stroke.Parent = coordinates

    renderConnection = addConnection(RunService.RenderStepped, function()
        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end

        camera.FieldOfView = tonumber(library.flags["Universal FOV"]) or 70

        local showCrosshair = library.flags["Universal Crosshair"] == true
        local viewport = camera.ViewportSize
        local center = viewport / 2
        local size = tonumber(library.flags["Universal Crosshair Size"]) or 9
        local gap = tonumber(library.flags["Universal Crosshair Gap"]) or 4
        local color = typeof(library.flags["Universal Crosshair Color"]) == "Color3"
            and library.flags["Universal Crosshair Color"]
            or Color3.fromRGB(0, 170, 255)

        for _, line in ipairs(crosshair) do
            line.Visible = showCrosshair
            line.BackgroundColor3 = color
        end

        if showCrosshair then
            crosshair[1].Position = UDim2.fromOffset(center.X - 1, center.Y - gap - size)
            crosshair[1].Size = UDim2.fromOffset(2, size)
            crosshair[2].Position = UDim2.fromOffset(center.X - 1, center.Y + gap)
            crosshair[2].Size = UDim2.fromOffset(2, size)
            crosshair[3].Position = UDim2.fromOffset(center.X - gap - size, center.Y - 1)
            crosshair[3].Size = UDim2.fromOffset(size, 2)
            crosshair[4].Position = UDim2.fromOffset(center.X + gap, center.Y - 1)
            crosshair[4].Size = UDim2.fromOffset(size, 2)
        end

        local showCoordinates = library.flags["Universal Coordinates"] == true
        coordinates.Visible = showCoordinates
        if showCoordinates then
            local characterRoot = getRoot()
            if characterRoot then
                coordinates.Text = string.format(
                    "X %.1f   Y %.1f   Z %.1f",
                    characterRoot.Position.X,
                    characterRoot.Position.Y,
                    characterRoot.Position.Z
                )
            else
                coordinates.Text = "Position unavailable"
            end
        end
    end)

    state.overlays.coordinates = coordinates
    state.overlays.crosshair = crosshair

    library:AddCleanup(function()
        disconnect(renderConnection)
        pcall(function()
            root:Destroy()
        end)
    end)
end

-- Lighting / world module ----------------------------------------------------

local lightingSection = worldLeft:AddSection("Lighting")
lightingSection:AddToggle({text = "Fullbright", flag = "Universal Fullbright", state = false})
lightingSection:AddToggle({text = "Remove Fog", flag = "Universal Remove Fog", state = false})
lightingSection:AddToggle({text = "Disable Post Effects", flag = "Universal Disable Effects", state = false})
lightingSection:AddToggle({text = "Disable Shadows", flag = "Universal Disable Shadows", state = false})

local performanceSection = worldRight:AddSection("Performance")
performanceSection:AddToggle({text = "Performance Mode", flag = "Universal Performance Mode", state = false})
performanceSection:AddToggle({text = "Disable Particles", flag = "Universal Disable Particles", state = false})
performanceSection:AddSlider({text = "FPS Cap", flag = "Universal FPS Cap", min = 30, max = 360, value = 144, float = 1})
performanceSection:AddButton({
    text = "Apply FPS Cap",
    callback = function()
        if type(setfpscap) == "function" then
            pcall(setfpscap, tonumber(library.flags["Universal FPS Cap"]) or 144)
            notify("FPS cap applied")
        else
            notify("setfpscap is unavailable", 3)
        end
    end,
})

local function setupWorldRuntime()
    state.original.lighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ExposureCompensation = Lighting.ExposureCompensation,
        GlobalShadows = Lighting.GlobalShadows,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
    }

    local particleOriginal = setmetatable({}, {__mode = "k"})
    local descendantConnection
    local heartbeatConnection
    local accumulator = 0

    local function rememberEffect(effect)
        if state.effectOriginal[effect] ~= nil then
            return
        end
        if effect:IsA("PostEffect") then
            state.effectOriginal[effect] = effect.Enabled
        elseif effect:IsA("Atmosphere") then
            state.effectOriginal[effect] = {
                Density = effect.Density,
                Haze = effect.Haze,
                Glare = effect.Glare,
            }
        end
    end

    local function isParticle(object)
        return object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles")
    end

    local function setParticle(object, disabled)
        if not isParticle(object) then
            return
        end
        if particleOriginal[object] == nil then
            particleOriginal[object] = object.Enabled
        end
        object.Enabled = not disabled and particleOriginal[object] or false
    end

    local function applyLighting()
        local original = state.original.lighting
        local fullbright = library.flags["Universal Fullbright"] == true
        local removeFog = library.flags["Universal Remove Fog"] == true
        local disableEffects = library.flags["Universal Disable Effects"] == true
        local disableShadows = library.flags["Universal Disable Shadows"] == true
            or library.flags["Universal Performance Mode"] == true

        Lighting.Brightness = fullbright and 3 or original.Brightness
        Lighting.ClockTime = fullbright and 14 or original.ClockTime
        Lighting.Ambient = fullbright and Color3.fromRGB(255, 255, 255) or original.Ambient
        Lighting.OutdoorAmbient = fullbright and Color3.fromRGB(255, 255, 255) or original.OutdoorAmbient
        Lighting.ExposureCompensation = fullbright and 0 or original.ExposureCompensation
        Lighting.GlobalShadows = disableShadows and false or original.GlobalShadows
        Lighting.FogStart = removeFog and 0 or original.FogStart
        Lighting.FogEnd = removeFog and 1000000 or original.FogEnd

        for _, effect in ipairs(Lighting:GetChildren()) do
            rememberEffect(effect)
            local saved = state.effectOriginal[effect]
            if effect:IsA("PostEffect") then
                effect.Enabled = disableEffects and false or saved
            elseif effect:IsA("Atmosphere") and type(saved) == "table" then
                effect.Density = removeFog and 0 or saved.Density
                effect.Haze = removeFog and 0 or saved.Haze
                effect.Glare = removeFog and 0 or saved.Glare
            end
        end

        pcall(function()
            settings().Rendering.QualityLevel = library.flags["Universal Performance Mode"]
                and Enum.QualityLevel.Level01
                or Enum.QualityLevel.Automatic
        end)
    end

    descendantConnection = addConnection(Workspace.DescendantAdded, function(object)
        if library.flags["Universal Disable Particles"] or library.flags["Universal Performance Mode"] then
            pcall(setParticle, object, true)
        end
    end)

    heartbeatConnection = addConnection(RunService.Heartbeat, function(deltaTime)
        accumulator += deltaTime
        if accumulator < 0.35 then
            return
        end
        accumulator = 0
        applyLighting()

        local disableParticles = library.flags["Universal Disable Particles"] == true
            or library.flags["Universal Performance Mode"] == true
        for object in pairs(particleOriginal) do
            if object and object.Parent then
                object.Enabled = disableParticles and false or particleOriginal[object]
            end
        end
    end)

    for _, object in ipairs(Workspace:GetDescendants()) do
        if isParticle(object) then
            particleOriginal[object] = object.Enabled
        end
    end

    library:AddCleanup(function()
        disconnect(descendantConnection)
        disconnect(heartbeatConnection)

        local original = state.original.lighting
        for property, value in pairs(original) do
            pcall(function()
                Lighting[property] = value
            end)
        end

        for effect, saved in pairs(state.effectOriginal) do
            if effect and effect.Parent then
                pcall(function()
                    if effect:IsA("PostEffect") then
                        effect.Enabled = saved
                    elseif effect:IsA("Atmosphere") and type(saved) == "table" then
                        effect.Density = saved.Density
                        effect.Haze = saved.Haze
                        effect.Glare = saved.Glare
                    end
                end)
            end
        end

        for object, enabled in pairs(particleOriginal) do
            if object and object.Parent then
                pcall(function()
                    object.Enabled = enabled
                end)
            end
        end

        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        end)
    end)
end

-- Utility module -------------------------------------------------------------

local utilitySection = utilityLeft:AddSection("Quality of Life")
utilitySection:AddToggle({text = "Anti-AFK", flag = "Universal Anti AFK", state = false})
utilitySection:AddToggle({text = "Hide Roblox Interface", flag = "Universal Hide CoreGui", state = false})
utilitySection:AddButton({
    text = "Reset Character",
    callback = function()
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.Health = 0
        end
    end,
})

local serverSection = utilityRight:AddSection("Server")
serverSection:AddButton({
    text = "Copy Server Join Data",
    callback = function()
        safeClipboard(string.format("PlaceId=%s\nJobId=%s", game.PlaceId, game.JobId))
    end,
})
serverSection:AddButton({
    text = "Rejoin Current Server",
    callback = function()
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    end,
})
serverSection:AddLabel("Featured games are configured in main/loader.luau")

local function setupUtilityRuntime()
    local antiAfkConnection
    local coreOriginal = {}
    local coreTypes = {
        Enum.CoreGuiType.Backpack,
        Enum.CoreGuiType.Chat,
        Enum.CoreGuiType.Health,
        Enum.CoreGuiType.PlayerList,
        Enum.CoreGuiType.EmotesMenu,
    }

    for _, coreType in ipairs(coreTypes) do
        local ok, enabled = pcall(function()
            return StarterGui:GetCoreGuiEnabled(coreType)
        end)
        if ok then
            coreOriginal[coreType] = enabled
        end
    end

    local antiAfkOption = option("Universal Anti AFK")
    if antiAfkOption then
        antiAfkOption.callback = function(enabled)
            disconnect(antiAfkConnection)
            antiAfkConnection = nil
            if enabled then
                antiAfkConnection = LocalPlayer.Idled:Connect(function()
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new(0, 0))
                    end)
                end)
            end
        end
    end

    local coreOption = option("Universal Hide CoreGui")
    if coreOption then
        coreOption.callback = function(hidden)
            for _, coreType in ipairs(coreTypes) do
                pcall(function()
                    StarterGui:SetCoreGuiEnabled(coreType, hidden and false or coreOriginal[coreType])
                end)
            end
        end
    end

    library:AddCleanup(function()
        disconnect(antiAfkConnection)
        for _, coreType in ipairs(coreTypes) do
            pcall(function()
                StarterGui:SetCoreGuiEnabled(coreType, coreOriginal[coreType])
            end)
        end
    end)
end

-- Keybinds -------------------------------------------------------------------

local movementBinds = bindsLeft:AddSection("Movement")
movementBinds:AddBind({
    text = "Toggle Fly",
    flag = "Universal Bind Fly",
    key = "X",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Fly", enabled == true)
    end,
})
movementBinds:AddBind({
    text = "Toggle Noclip",
    flag = "Universal Bind Noclip",
    key = "N",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Noclip", enabled == true)
    end,
})

local visualBinds = bindsRight:AddSection("Visuals")
visualBinds:AddBind({
    text = "Toggle ESP",
    flag = "Universal Bind ESP",
    key = "H",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal ESP", enabled == true)
    end,
})
visualBinds:AddBind({
    text = "Toggle Crosshair",
    flag = "Universal Bind Crosshair",
    key = "C",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Crosshair", enabled == true)
    end,
})
visualBinds:AddLabel("Menu and panic binds are available in Settings")

-- Initialize -----------------------------------------------------------------

local initialized, initError = library:Init()
assert(initialized, "[xanhub universal] initialization failed: " .. tostring(initError))

createOverlayRoot()
setupMovementRuntime()
setupFlyRuntime()
setupNoclipRuntime()
setupESPRuntime()
setupOverlayRuntime()
setupWorldRuntime()
setupUtilityRuntime()

state.original.cameraFov = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70

library:AddCleanup(function()
    state.unloading = true
    if type(runtime) == "table" then
        runtime.unloading = true
    end

    local camera = Workspace.CurrentCamera
    if camera then
        camera.FieldOfView = state.original.cameraFov or 70
    end

    for _, connection in ipairs(state.connections) do
        disconnect(connection)
    end
    table.clear(state.connections)

    if state.overlays.root then
        pcall(function()
            state.overlays.root:Destroy()
        end)
        state.overlays.root = nil
    end
end)

library:SetOpen(true)
library:selectTab(homeTab)
runtimeStatus.Text = "Status: ready | Universal"
notify("Universal menu loaded", 2)
print("[xanhub] Universal loaded for place", game.PlaceId)

return {
    library = library,
    runtime = runtime,
    state = state,
}
