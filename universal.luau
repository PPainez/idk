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
library:SetTweening(true)

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
espSection:AddToggle({text = "Highlights", flag = "Universal ESP Highlights", state = false})
espSection:AddToggle({text = "Names", flag = "Universal ESP Names", state = true})
espSection:AddToggle({text = "Health Bar", flag = "Universal ESP Health", state = true})
espSection:AddToggle({text = "Distance", flag = "Universal ESP Distance", state = true})
espSection:AddToggle({text = "Team Check", flag = "Universal ESP Team Check", state = false})
espSection:AddSlider({
    text = "ESP Scale",
    flag = "Universal ESP Scale",
    min = 50,
    max = 110,
    value = 78,
    float = 1,
    suffix = "%",
})
espSection:AddSlider({
    text = "Fade Start",
    flag = "Universal ESP Fade Start",
    min = 50,
    max = 1200,
    value = 250,
    float = 10,
    suffix = " studs",
})
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

        if entry.highlight then
            pcall(function()
                entry.highlight:Destroy()
            end)
        end

        if entry.billboard then
            pcall(function()
                entry.billboard:Destroy()
            end)
        end

        state.esp[player] = nil
    end

    local function createEntry(player, character)
        destroyEntry(player)

        local root = character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")
            or character:FindFirstChild("Head")

        if not root then
            return nil
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "xanhub_universal_highlight"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.92
        highlight.OutlineTransparency = 0.28
        highlight.Adornee = character
        highlight.Enabled = false
        highlight.Parent = character

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "xanhub_universal_billboard"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.MaxDistance = 2000
        billboard.Size = UDim2.fromOffset(156, 38)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.15, 0)
        billboard.Enabled = false
        billboard.Parent = character

        local card = Instance.new("Frame")
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.fromScale(0.5, 0.5)
        card.Size = UDim2.fromOffset(150, 34)
        card.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
        card.BackgroundTransparency = 0.18
        card.BorderSizePixel = 0
        card.ClipsDescendants = true
        card.Parent = billboard
        createRounded(card, 6)

        local scale = Instance.new("UIScale")
        scale.Scale = 0.78
        scale.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 170, 255)
        stroke.Transparency = 0.28
        stroke.Thickness = 1
        stroke.Parent = card

        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 2, 1, 0)
        accent.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
        accent.BorderSizePixel = 0
        accent.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.fromOffset(8, 3)
        nameLabel.Size = UDim2.new(1, -52, 0, 15)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = player.DisplayName
        nameLabel.TextColor3 = Color3.fromRGB(245, 247, 255)
        nameLabel.TextSize = 12
        nameLabel.Font = Enum.Font.Code
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = card

        local distanceLabel = Instance.new("TextLabel")
        distanceLabel.AnchorPoint = Vector2.new(1, 0)
        distanceLabel.Position = UDim2.new(1, -7, 0, 3)
        distanceLabel.Size = UDim2.fromOffset(42, 15)
        distanceLabel.BackgroundTransparency = 1
        distanceLabel.Text = "0m"
        distanceLabel.TextColor3 = Color3.fromRGB(160, 170, 190)
        distanceLabel.TextSize = 10
        distanceLabel.Font = Enum.Font.Code
        distanceLabel.TextXAlignment = Enum.TextXAlignment.Right
        distanceLabel.Parent = card

        local barBackground = Instance.new("Frame")
        barBackground.Position = UDim2.fromOffset(8, 25)
        barBackground.Size = UDim2.new(1, -16, 0, 3)
        barBackground.BackgroundColor3 = Color3.fromRGB(28, 33, 43)
        barBackground.BorderSizePixel = 0
        barBackground.Parent = card
        createRounded(barBackground, 2)

        local healthFill = Instance.new("Frame")
        healthFill.Size = UDim2.fromScale(1, 1)
        healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
        healthFill.BorderSizePixel = 0
        healthFill.Parent = barBackground
        createRounded(healthFill, 2)

        local entry = {
            character = character,
            root = root,
            highlight = highlight,
            billboard = billboard,
            scale = scale,
            card = card,
            stroke = stroke,
            accent = accent,
            name = nameLabel,
            distance = distanceLabel,
            healthBackground = barBackground,
            health = healthFill,
            currentScale = 0.78,
            displayedHealth = 1,
        }

        state.esp[player] = entry
        return entry
    end

    local function setVisible(entry, visible)
        if entry.highlight then
            entry.highlight.Enabled = visible and library.flags["Universal ESP Highlights"] == true
        end
        if entry.billboard then
            entry.billboard.Enabled = visible
        end
    end

    local function update()
        if state.unloading then
            return
        end

        local enabled = library.flags["Universal ESP"] == true
        local localRoot = getRoot()
        local maxDistance = math.max(50, tonumber(library.flags["Universal ESP Max Distance"]) or 650)
        local fadeStart = math.clamp(
            tonumber(library.flags["Universal ESP Fade Start"]) or 250,
            0,
            maxDistance - 1
        )
        local baseScale = math.clamp(
            (tonumber(library.flags["Universal ESP Scale"]) or 78) / 100,
            0.5,
            1.1
        )
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
                    if not entry or entry.character ~= character or entry.root ~= root then
                        entry = createEntry(player, character)
                    end
                elseif entry then
                    destroyEntry(player)
                    entry = nil
                end

                if entry then
                    local sameTeam = library.flags["Universal ESP Team Check"] == true
                        and LocalPlayer.Team ~= nil
                        and player.Team == LocalPlayer.Team
                    local distance = localRoot and (localRoot.Position - root.Position).Magnitude or math.huge
                    local visible = enabled and not sameTeam and distance <= maxDistance
                    setVisible(entry, visible)

                    if visible then
                        local fade = math.clamp((distance - fadeStart) / math.max(1, maxDistance - fadeStart), 0, 1)
                        local opacity = 1 - (fade * 0.72)
                        local distanceScale = math.clamp(1 - (distance / maxDistance) * 0.64, 0.34, 1)
                        local wantedScale = baseScale * distanceScale
                        entry.currentScale += (wantedScale - entry.currentScale) * 0.24
                        entry.scale.Scale = entry.currentScale
                        entry.billboard.MaxDistance = maxDistance

                        entry.highlight.FillColor = color
                        entry.highlight.OutlineColor = color
                        entry.highlight.FillTransparency = 0.92 + fade * 0.06
                        entry.highlight.OutlineTransparency = 0.28 + fade * 0.55

                        entry.stroke.Color = color
                        entry.stroke.Transparency = 0.28 + fade * 0.52
                        entry.accent.BackgroundColor3 = color
                        entry.accent.BackgroundTransparency = 1 - opacity
                        entry.card.BackgroundTransparency = 0.18 + fade * 0.58
                        entry.name.TextTransparency = 1 - opacity
                        entry.distance.TextTransparency = 1 - opacity
                        entry.healthBackground.BackgroundTransparency = 0.08 + fade * 0.66
                        entry.health.BackgroundTransparency = 1 - opacity

                        entry.name.Text = player.DisplayName
                        entry.name.Visible = library.flags["Universal ESP Names"] == true
                        entry.distance.Visible = library.flags["Universal ESP Distance"] == true
                        entry.healthBackground.Visible = library.flags["Universal ESP Health"] == true
                        entry.distance.Text = tostring(math.floor(distance + 0.5)) .. "m"

                        local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                        entry.displayedHealth += (ratio - entry.displayedHealth) * 0.28
                        entry.health.Size = UDim2.new(entry.displayedHealth, 0, 1, 0)
                        entry.health.BackgroundColor3 = Color3.fromHSV(entry.displayedHealth * 0.33, 0.78, 1)
                    end
                end
            end
        end
    end

    updateConnection = addConnection(RunService.RenderStepped, function(deltaTime)
        accumulator += deltaTime
        if accumulator >= 1 / 30 then
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
        local playersToRemove = {}
        for player in pairs(state.esp) do
            table.insert(playersToRemove, player)
        end
        for _, player in ipairs(playersToRemove) do
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

local aimPreview = visualsRight:AddSection("Target Preview")
aimPreview:AddToggle({text = "Enabled", flag = "Universal Aim Preview", state = false})
aimPreview:AddToggle({text = "Lock Preview Target", flag = "Universal Aim Lock Preview", state = false})
aimPreview:AddToggle({text = "Show FOV Circle", flag = "Universal Aim Show FOV", state = true})
aimPreview:AddToggle({text = "Show Target Line", flag = "Universal Aim Show Line", state = true})
aimPreview:AddToggle({text = "Team Check", flag = "Universal Aim Team Check", state = true})
aimPreview:AddList({
    text = "Target Part",
    flag = "Universal Aim Part",
    values = {"Head", "Torso"},
    value = "Head",
})
aimPreview:AddSlider({
    text = "FOV Radius",
    flag = "Universal Aim FOV",
    min = 40,
    max = 400,
    value = 140,
    float = 5,
    suffix = " px",
})
aimPreview:AddSlider({
    text = "Maximum Distance",
    flag = "Universal Aim Max Distance",
    min = 50,
    max = 1500,
    value = 500,
    float = 10,
    suffix = " studs",
})
aimPreview:AddColor({
    text = "Indicator Color",
    flag = "Universal Aim Color",
    color = Color3.fromRGB(0, 170, 255),
})
aimPreview:AddLabel("Visual target preview only; it never moves your camera or input")

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
    coordinates.Size = UDim2.fromOffset(330, 26)
    coordinates.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
    coordinates.BackgroundTransparency = 0.16
    coordinates.BorderSizePixel = 0
    coordinates.TextColor3 = Color3.fromRGB(235, 240, 250)
    coordinates.TextSize = 12
    coordinates.Font = Enum.Font.Code
    coordinates.Visible = false
    coordinates.ZIndex = 510
    coordinates.Parent = root
    createRounded(coordinates, 7)

    local coordinatesStroke = Instance.new("UIStroke")
    coordinatesStroke.Color = Color3.fromRGB(0, 170, 255)
    coordinatesStroke.Transparency = 0.38
    coordinatesStroke.Parent = coordinates

    local fovCircle = Instance.new("Frame")
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.BackgroundTransparency = 1
    fovCircle.BorderSizePixel = 0
    fovCircle.Visible = false
    fovCircle.ZIndex = 505
    fovCircle.Parent = root
    createRounded(fovCircle, 999)

    local fovStroke = Instance.new("UIStroke")
    fovStroke.Thickness = 1
    fovStroke.Transparency = 0.34
    fovStroke.Color = Color3.fromRGB(0, 170, 255)
    fovStroke.Parent = fovCircle

    local targetDot = Instance.new("Frame")
    targetDot.AnchorPoint = Vector2.new(0.5, 0.5)
    targetDot.Size = UDim2.fromOffset(10, 10)
    targetDot.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    targetDot.BorderSizePixel = 0
    targetDot.Visible = false
    targetDot.ZIndex = 515
    targetDot.Parent = root
    createRounded(targetDot, 999)

    local targetDotStroke = Instance.new("UIStroke")
    targetDotStroke.Color = Color3.fromRGB(6, 8, 12)
    targetDotStroke.Thickness = 2
    targetDotStroke.Transparency = 0.1
    targetDotStroke.Parent = targetDot

    local targetLabel = Instance.new("TextLabel")
    targetLabel.AnchorPoint = Vector2.new(0.5, 1)
    targetLabel.Size = UDim2.fromOffset(170, 22)
    targetLabel.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
    targetLabel.BackgroundTransparency = 0.18
    targetLabel.BorderSizePixel = 0
    targetLabel.Text = ""
    targetLabel.TextColor3 = Color3.fromRGB(245, 247, 255)
    targetLabel.TextSize = 11
    targetLabel.Font = Enum.Font.Code
    targetLabel.TextTruncate = Enum.TextTruncate.AtEnd
    targetLabel.Visible = false
    targetLabel.ZIndex = 515
    targetLabel.Parent = root
    createRounded(targetLabel, 6)

    local targetLabelStroke = Instance.new("UIStroke")
    targetLabelStroke.Thickness = 1
    targetLabelStroke.Transparency = 0.35
    targetLabelStroke.Color = Color3.fromRGB(0, 170, 255)
    targetLabelStroke.Parent = targetLabel

    local targetLine = Instance.new("Frame")
    targetLine.AnchorPoint = Vector2.new(0.5, 0.5)
    targetLine.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    targetLine.BackgroundTransparency = 0.35
    targetLine.BorderSizePixel = 0
    targetLine.Visible = false
    targetLine.ZIndex = 506
    targetLine.Parent = root

    local function setScreenLine(frame, from, to, thickness)
        local delta = to - from
        local length = delta.Magnitude
        local midpoint = from + delta / 2
        frame.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
        frame.Size = UDim2.fromOffset(length, thickness or 1)
        frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
    end

    local function getTargetPart(character)
        if not character then
            return nil
        end

        if library.flags["Universal Aim Part"] == "Torso" then
            return character:FindFirstChild("UpperTorso")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("HumanoidRootPart")
        end

        return character:FindFirstChild("Head")
            or character:FindFirstChild("HumanoidRootPart")
    end

    local function targetValid(player, camera, localRoot, center, radius, maxDistance)
        if not player or player == LocalPlayer then
            return nil
        end

        local character = player.Character
        local humanoid = getHumanoid(character)
        local targetPart = getTargetPart(character)
        local targetRoot = getRoot(character)

        if not character or not humanoid or humanoid.Health <= 0 or not targetPart or not targetRoot then
            return nil
        end

        if library.flags["Universal Aim Team Check"] == true
            and LocalPlayer.Team ~= nil
            and player.Team == LocalPlayer.Team then
            return nil
        end

        local worldDistance = localRoot and (localRoot.Position - targetRoot.Position).Magnitude or math.huge
        if worldDistance > maxDistance then
            return nil
        end

        local point, onScreen = camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen or point.Z <= 0 then
            return nil
        end

        local screenPoint = Vector2.new(point.X, point.Y)
        local screenDistance = (screenPoint - center).Magnitude
        if screenDistance > radius then
            return nil
        end

        return {
            player = player,
            part = targetPart,
            point = screenPoint,
            screenDistance = screenDistance,
            worldDistance = worldDistance,
        }
    end

    local function findNearestTarget(camera, localRoot, center, radius, maxDistance)
        local best
        for _, player in ipairs(Players:GetPlayers()) do
            local candidate = targetValid(player, camera, localRoot, center, radius, maxDistance)
            if candidate and (not best or candidate.screenDistance < best.screenDistance) then
                best = candidate
            end
        end
        return best
    end

    renderConnection = addConnection(RunService.RenderStepped, function()
        if state.unloading then
            return
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end

        camera.FieldOfView = tonumber(library.flags["Universal FOV"]) or 70

        local viewport = camera.ViewportSize
        local center = viewport / 2
        local showCrosshair = library.flags["Universal Crosshair"] == true
        local size = tonumber(library.flags["Universal Crosshair Size"]) or 9
        local gap = tonumber(library.flags["Universal Crosshair Gap"]) or 4
        local crosshairColor = typeof(library.flags["Universal Crosshair Color"]) == "Color3"
            and library.flags["Universal Crosshair Color"]
            or Color3.fromRGB(0, 170, 255)

        for _, line in ipairs(crosshair) do
            line.Visible = showCrosshair
            line.BackgroundColor3 = crosshairColor
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

        local previewEnabled = library.flags["Universal Aim Preview"] == true
        local radius = math.max(20, tonumber(library.flags["Universal Aim FOV"]) or 140)
        local maxDistance = math.max(50, tonumber(library.flags["Universal Aim Max Distance"]) or 500)
        local previewColor = typeof(library.flags["Universal Aim Color"]) == "Color3"
            and library.flags["Universal Aim Color"]
            or Color3.fromRGB(0, 170, 255)

        fovCircle.Position = UDim2.fromOffset(center.X, center.Y)
        fovCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
        fovCircle.Visible = previewEnabled and library.flags["Universal Aim Show FOV"] == true
        fovStroke.Color = previewColor
        targetDot.BackgroundColor3 = previewColor
        targetLine.BackgroundColor3 = previewColor
        targetLabelStroke.Color = previewColor

        if not previewEnabled then
            state.aimTarget = nil
            targetDot.Visible = false
            targetLabel.Visible = false
            targetLine.Visible = false
            return
        end

        local localRoot = getRoot()
        local locked = library.flags["Universal Aim Lock Preview"] == true
        local target

        if locked and state.aimTarget then
            target = targetValid(state.aimTarget, camera, localRoot, center, radius, maxDistance)
        end

        if not target then
            target = findNearestTarget(camera, localRoot, center, radius, maxDistance)
            state.aimTarget = target and target.player or nil
        elseif not locked then
            state.aimTarget = target.player
        end

        if target then
            targetDot.Position = UDim2.fromOffset(target.point.X, target.point.Y)
            targetDot.Visible = true
            targetLabel.Position = UDim2.fromOffset(target.point.X, target.point.Y - 10)
            targetLabel.Text = string.format(
                "%s  •  %dm",
                target.player.DisplayName,
                math.floor(target.worldDistance + 0.5)
            )
            targetLabel.Visible = true

            if library.flags["Universal Aim Show Line"] == true then
                setScreenLine(targetLine, center, target.point, 1)
                targetLine.Visible = true
            else
                targetLine.Visible = false
            end
        else
            targetDot.Visible = false
            targetLabel.Visible = false
            targetLine.Visible = false
        end
    end)

    state.overlays.coordinates = coordinates
    state.overlays.crosshair = crosshair
    state.overlays.fovCircle = fovCircle
    state.overlays.targetDot = targetDot
    state.overlays.targetLabel = targetLabel
    state.overlays.targetLine = targetLine

    library:AddCleanup(function()
        disconnect(renderConnection)
        state.aimTarget = nil
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
visualBinds:AddBind({
    text = "Toggle Target Preview",
    flag = "Universal Bind Aim Preview",
    key = "V",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Aim Preview", enabled == true)
    end,
})
visualBinds:AddBind({
    text = "Lock Preview Target",
    flag = "Universal Bind Aim Lock",
    key = "Q",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Aim Lock Preview", enabled == true)
        if not enabled then
            state.aimTarget = nil
        end
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

    for _, flag in ipairs({
        "Universal ESP",
        "Universal ESP Highlights",
        "Universal Crosshair",
        "Universal Coordinates",
        "Universal Aim Preview",
        "Universal Aim Lock Preview",
    }) do
        library.flags[flag] = false
    end
    state.aimTarget = nil

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
