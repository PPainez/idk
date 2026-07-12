
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

        local targetMarker = Instance.new("Frame")
        targetMarker.Position = UDim2.fromOffset(8, 8)
        targetMarker.Size = UDim2.fromOffset(6, 6)
        targetMarker.BackgroundColor3 = Color3.fromRGB(255, 82, 96)
        targetMarker.BackgroundTransparency = 1
        targetMarker.BorderSizePixel = 0
        targetMarker.Visible = false
        targetMarker.Parent = card
        createRounded(targetMarker, 999)

        local targetMarkerStroke = Instance.new("UIStroke")
        targetMarkerStroke.Color = Color3.fromRGB(255, 255, 255)
        targetMarkerStroke.Transparency = 0.35
        targetMarkerStroke.Thickness = 1
        targetMarkerStroke.Parent = targetMarker

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.fromOffset(18, 3)
        nameLabel.Size = UDim2.new(1, -62, 0, 15)
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
            targetMarker = targetMarker,
            targetMarkerStroke = targetMarkerStroke,
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

    local function setVisible(entry, visible, allowHighlight)
        if entry.highlight then
            entry.highlight.Enabled = visible
                and allowHighlight == true
                and library.flags["Universal ESP Highlights"] == true
        end
        if entry.billboard then
            entry.billboard.Enabled = visible
        end
        if not visible and entry.targetMarker then
            entry.targetMarker.Visible = false
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
                    local distance = localRoot and (localRoot.Position - root.Position).Magnitude or math.huge
                    local targetingEnabled = library.flags["Universal Aim Preview"] == true
                    local isTarget = targetingEnabled and state.aimTarget == player
                    local targetSync = library.flags["Universal Targeting Sync ESP"] ~= false

                    local espSameTeam = library.flags["Universal ESP Team Check"] == true
                        and LocalPlayer.Team ~= nil
                        and player.Team == LocalPlayer.Team
                    local targetingTeamCheck
                    if targetSync then
                        targetingTeamCheck = library.flags["Universal ESP Team Check"] == true
                    else
                        targetingTeamCheck = library.flags["Universal Aim Team Check"] == true
                    end
                    local targetSameTeam = targetingTeamCheck
                        and LocalPlayer.Team ~= nil
                        and player.Team == LocalPlayer.Team

                    local targetMaxDistance = targetSync
                        and maxDistance
                        or math.max(50, tonumber(library.flags["Universal Aim Max Distance"]) or 500)
                    local visibleForESP = enabled and not espSameTeam and distance <= maxDistance
                    local visibleForTarget = isTarget and not targetSameTeam and distance <= targetMaxDistance
                    local visible = visibleForESP or visibleForTarget
                    setVisible(entry, visible, visibleForESP)

                    if visible then
                        local displayMaxDistance = visibleForTarget and targetMaxDistance or maxDistance
                        local displayFadeStart = math.min(fadeStart, displayMaxDistance - 1)
                        local fade = math.clamp(
                            (distance - displayFadeStart) / math.max(1, displayMaxDistance - displayFadeStart),
                            0,
                            1
                        )
                        local opacity = 1 - (fade * (isTarget and 0.42 or 0.72))
                        local distanceScale = math.clamp(1 - (distance / displayMaxDistance) * 0.64, 0.34, 1)
                        local wantedScale = baseScale * distanceScale * (isTarget and 1.08 or 1)
                        entry.currentScale += (wantedScale - entry.currentScale) * 0.24
                        entry.scale.Scale = entry.currentScale
                        entry.billboard.MaxDistance = displayMaxDistance

                        local configuredTargetColor = typeof(library.flags["Universal Aim Color"]) == "Color3"
                            and library.flags["Universal Aim Color"]
                            or Color3.fromRGB(255, 82, 96)
                        local targetColor = targetSync and color or configuredTargetColor
                        local displayColor = isTarget and targetColor or color

                        entry.highlight.FillColor = displayColor
                        entry.highlight.OutlineColor = displayColor
                        entry.highlight.FillTransparency = 0.92 + fade * 0.06
                        entry.highlight.OutlineTransparency = 0.28 + fade * 0.55

                        entry.stroke.Color = displayColor
                        entry.stroke.Thickness = isTarget and 2 or 1
                        entry.stroke.Transparency = isTarget and 0.08 or (0.28 + fade * 0.52)
                        entry.accent.BackgroundColor3 = displayColor
                        entry.accent.Size = UDim2.new(0, isTarget and 4 or 2, 1, 0)
                        entry.accent.BackgroundTransparency = isTarget and 0 or (1 - opacity)
                        entry.card.BackgroundTransparency = isTarget and 0.06 or (0.18 + fade * 0.58)
                        entry.name.TextTransparency = isTarget and 0 or (1 - opacity)
                        entry.name.TextColor3 = isTarget and targetColor or Color3.fromRGB(245, 247, 255)
                        entry.distance.TextTransparency = 1 - opacity
                        entry.healthBackground.BackgroundTransparency = 0.08 + fade * 0.66
                        entry.health.BackgroundTransparency = 1 - opacity

                        entry.targetMarker.Visible = isTarget
                        entry.targetMarker.BackgroundColor3 = targetColor
                        entry.targetMarker.BackgroundTransparency = isTarget
                            and (0.08 + math.abs(math.sin(os.clock() * 5)) * 0.28)
                            or 1
                        entry.name.Text = player.DisplayName
                        entry.name.Visible = isTarget or library.flags["Universal ESP Names"] == true
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
                    setVisible(entry, false, false)
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

local targetingSection = combatLeft:AddSection("Targeting")
targetingSection:AddToggle({text = "Enabled", flag = "Universal Aim Preview", state = false})
targetingSection:AddToggle({
    text = "Sync With ESP",
    flag = "Universal Targeting Sync ESP",
    state = true,
})
targetingSection:AddToggle({text = "Show FOV Circle", flag = "Universal Aim Show FOV", state = true})
targetingSection:AddToggle({text = "Team Check", flag = "Universal Aim Team Check", state = true})
targetingSection:AddList({
    text = "Target Part",
    flag = "Universal Aim Part",
    values = {"Head", "Torso"},
    value = "Head",
})
targetingSection:AddSlider({
    text = "Targeting Radius",
    flag = "Universal Aim FOV",
    min = 35,
    max = 400,
    value = 140,
    float = 5,
    suffix = " px",
})
targetingSection:AddSlider({
    text = "Maximum Distance",
    flag = "Universal Aim Max Distance",
    min = 50,
    max = 1500,
    value = 500,
    float = 10,
    suffix = " studs",
})
targetingSection:AddLabel("Sync With ESP uses its team, range, and color settings")

local targetingLockSection = combatRight:AddSection("Lock Settings")
targetingLockSection:AddToggle({
    text = "Lock Current Target",
    flag = "Universal Aim Lock Preview",
    state = false,
})
targetingLockSection:AddToggle({
    text = "Auto Switch When Lost",
    flag = "Universal Aim Auto Switch",
    state = true,
})
targetingLockSection:AddToggle({text = "Show Target Line", flag = "Universal Aim Show Line", state = true})
targetingLockSection:AddColor({
    text = "Target Color",
    flag = "Universal Aim Color",
    color = Color3.fromRGB(255, 82, 96),
})
local targetingStatus = targetingLockSection:AddLabel("Target: none")
targetingLockSection:AddLabel("Targeting only selects and marks an ESP target")

-- NEW: Combat Aim Settings
local combatAimSection = combatRight:AddSection("Combat Aim")
combatAimSection:AddToggle({
    text = "Aim Lock (Camera Track)",
    flag = "Universal Combat Aim Lock",
    state = false,
})
combatAimSection:AddToggle({
    text = "Silent Aim",
    flag = "Universal Combat Silent Aim",
    state = false,
})
combatAimSection:AddSlider({
    text = "Smoothness",
    flag = "Universal Combat Smoothness",
    min = 1,
    max = 25,
    value = 6,
    float = 0.5,
})
combatAimSection:AddSlider({
    text = "Prediction",
    flag = "Universal Combat Prediction",
    min = 0,
    max = 2.5,
    value = 1.1,
    float = 0.05,
})
combatAimSection:AddToggle({
    text = "Lock Only (No Auto Switch)",
    flag = "Universal Combat Lock Only",
    state = false,
})

local function setupCombatRuntime()
    local aimConnection

    local function getTargetPart(character)
        if not character then return nil end
        if library.flags["Universal Aim Part"] == "Torso" then
            return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
        end
        return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    end

    aimConnection = addConnection(RunService.RenderStepped, function()
        if state.unloading then return end

        local lockEnabled = library.flags["Universal Combat Aim Lock"] == true
        local silentEnabled = library.flags["Universal Combat Silent Aim"] == true

        if not lockEnabled and not silentEnabled then return end

        local targetPlayer = state.aimTarget
        if not targetPlayer then return end

        local character = targetPlayer.Character
        local targetPart = getTargetPart(character)
        local root = getRoot(character)

        if not targetPart or not root then return end

        local prediction = tonumber(library.flags["Universal Combat Prediction"]) or 1.1
        local vel = root.AssemblyLinearVelocity or Vector3.zero
        local predictedPos = targetPart.Position + vel * prediction * (1/60)

        local smoothness = tonumber(library.flags["Universal Combat Smoothness"]) or 6

        if lockEnabled then
            local cam = Workspace.CurrentCamera
            local currentCF = cam.CFrame
            local targetCF = CFrame.lookAt(currentCF.Position, predictedPos)
            cam.CFrame = currentCF:Lerp(targetCF, 1 / smoothness)
        end
    end)

    library:AddCleanup(function()
        disconnect(aimConnection)
    end)
end

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
    fovCircle.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    fovCircle.BackgroundTransparency = 0.985
    fovCircle.BorderSizePixel = 0
    fovCircle.Visible = false
    fovCircle.ZIndex = 505
    fovCircle.Parent = root
    createRounded(fovCircle, 999)

    local fovStroke = Instance.new("UIStroke")
    fovStroke.Thickness = 1
    fovStroke.Transparency = 0.56
    fovStroke.Color = Color3.fromRGB(0, 170, 255)
    fovStroke.Parent = fovCircle

    local targetLine = Instance.new("Frame")
    targetLine.AnchorPoint = Vector2.new(0.5, 0.5)
    targetLine.BackgroundColor3 = Color3.fromRGB(255, 82, 96)
    targetLine.BackgroundTransparency = 0.56
    targetLine.BorderSizePixel = 0
    targetLine.Visible = false
    targetLine.ZIndex = 506
    targetLine.Parent = root

    local function setScreenLine(frame, from, to, thickness)
        local delta = to - from
        local length = delta.Magnitude
        if length <= 0.001 then
            frame.Visible = false
            return
        end
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

    local function targetingSettings()
        local syncESP = library.flags["Universal Targeting Sync ESP"] ~= false
        local teamCheck
        if syncESP then
            teamCheck = library.flags["Universal ESP Team Check"] == true
        else
            teamCheck = library.flags["Universal Aim Team Check"] == true
        end

        local targetMaximum = math.max(
            50,
            tonumber(library.flags["Universal Aim Max Distance"]) or 500
        )
        if syncESP then
            targetMaximum = math.min(
                targetMaximum,
                math.max(50, tonumber(library.flags["Universal ESP Max Distance"]) or 650)
            )
        end

        local espColor = typeof(library.flags["Universal ESP Color"]) == "Color3"
            and library.flags["Universal ESP Color"]
            or Color3.fromRGB(0, 170, 255)
        local configuredColor = typeof(library.flags["Universal Aim Color"]) == "Color3"
            and library.flags["Universal Aim Color"]
            or Color3.fromRGB(255, 82, 96)

        return syncESP, teamCheck, targetMaximum, syncESP and espColor or configuredColor
    end

    local function targetValid(player, camera, localRoot, center, radius, maxDistance, teamCheck)
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

        if teamCheck and LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then
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

    local function findNearestTarget(camera, localRoot, center, radius, maxDistance, teamCheck)
        local best
        for _, player in ipairs(Players:GetPlayers()) do
            local candidate = targetValid(
                player,
                camera,
                localRoot,
                center,
                radius,
                maxDistance,
                teamCheck
            )
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

        local targetingEnabled = library.flags["Universal Aim Preview"] == true
        local requestedRadius = math.max(20, tonumber(library.flags["Universal Aim FOV"]) or 140)
        local radius = math.min(requestedRadius, math.min(viewport.X, viewport.Y) * 0.47)
        local _, teamCheck, maxDistance, targetColor = targetingSettings()

        fovCircle.Position = UDim2.fromOffset(center.X, center.Y)
        fovCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
        fovCircle.Visible = targetingEnabled and library.flags["Universal Aim Show FOV"] == true
        fovCircle.BackgroundColor3 = targetColor
        fovStroke.Color = targetColor
        targetLine.BackgroundColor3 = targetColor

        if not targetingEnabled then
            state.aimTarget = nil
            targetLine.Visible = false
            targetingStatus.Text = "Target: none"
            return
        end

        local localRoot = getRoot()
        local locked = library.flags["Universal Aim Lock Preview"] == true
        local autoSwitch = library.flags["Universal Aim Auto Switch"] ~= false
        local target

        if locked and state.aimTarget then
            target = targetValid(
                state.aimTarget,
                camera,
                localRoot,
                center,
                radius,
                maxDistance,
                teamCheck
            )
        end

        if not target and (not locked or autoSwitch) then
            target = findNearestTarget(
                camera,
                localRoot,
                center,
                radius,
                maxDistance,
                teamCheck
            )
            state.aimTarget = target and target.player or nil
        elseif target and not locked then
            state.aimTarget = target.player
        elseif not target and locked and not autoSwitch then
            state.aimTarget = nil
        end

        if target then
            targetingStatus.Text = string.format(
                "Target: %s | %dm",
                target.player.DisplayName,
                math.floor(target.worldDistance + 0.5)
            )

            if library.flags["Universal Aim Show Line"] == true then
                setScreenLine(targetLine, center, target.point, 1)
                targetLine.Visible = true
            else
                targetLine.Visible = false
            end
        else
            targetingStatus.Text = locked and "Target: lost" or "Target: none in radius"
            targetLine.Visible = false
        end
    end)

    state.overlays.coordinates = coordinates
    state.overlays.crosshair = crosshair
    state.overlays.fovCircle = fovCircle
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
    text = "Toggle Targeting",
    flag = "Universal Bind Aim Preview",
    key = "V",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Aim Preview", enabled == true)
    end,
})
visualBinds:AddBind({
    text = "Lock Target",
    flag = "Universal Bind Aim Lock",
    key = "Q",
    mode = "toggle",
    nomouse = true,
    callback = function(enabled)
        setToggle("Universal Aim Lock Preview", enabled == true)
        setToggle("Universal Combat Aim Lock", enabled == true)
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
setupCombatRuntime()  -- NEW

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
notify("Universal menu loaded with combat locks", 3)
print("[xanhub] Universal loaded for place", game.PlaceId)

return {
    library = library,
    runtime = runtime,
    state = state,
}
