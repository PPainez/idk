--[[
    xanhub | universal | modules | esp

    Player ESP UI and runtime.
]]

return function(ctx)
    local espSection = ctx.columns.visualsLeft:AddSection("Player ESP")
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
            local entry = ctx.state.esp[player]
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

            ctx.state.esp[player] = nil
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
            ctx.createRounded(card, 6)

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
            ctx.createRounded(targetMarker, 999)

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
            ctx.createRounded(barBackground, 2)

            local healthFill = Instance.new("Frame")
            healthFill.Size = UDim2.fromScale(1, 1)
            healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
            healthFill.BorderSizePixel = 0
            healthFill.Parent = barBackground
            ctx.createRounded(healthFill, 2)

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

            ctx.state.esp[player] = entry
            return entry
        end

        local function setVisible(entry, visible, allowHighlight)
            if entry.highlight then
                entry.highlight.Enabled = visible
                    and allowHighlight == true
                    and ctx.library.flags["Universal ESP Highlights"] == true
            end
            if entry.billboard then
                entry.billboard.Enabled = visible
            end
            if not visible and entry.targetMarker then
                entry.targetMarker.Visible = false
            end
        end

        local function update()
            if ctx.state.unloading then
                return
            end

            local enabled = ctx.library.flags["Universal ESP"] == true
            local localRoot = ctx.getRoot()
            local maxDistance = math.max(50, tonumber(ctx.library.flags["Universal ESP Max Distance"]) or 650)
            local fadeStart = math.clamp(
                tonumber(ctx.library.flags["Universal ESP Fade Start"]) or 250,
                0,
                maxDistance - 1
            )
            local baseScale = math.clamp(
                (tonumber(ctx.library.flags["Universal ESP Scale"]) or 78) / 100,
                0.5,
                1.1
            )
            local color = typeof(ctx.library.flags["Universal ESP Color"]) == "Color3"
                and ctx.library.flags["Universal ESP Color"]
                or Color3.fromRGB(0, 170, 255)

            for _, player in ipairs(ctx.Players:GetPlayers()) do
                if player ~= ctx.LocalPlayer then
                    local character = player.Character
                    local humanoid = ctx.getHumanoid(character)
                    local root = ctx.getRoot(character)
                    local entry = ctx.state.esp[player]

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
                        local targetingEnabled = ctx.library.flags["Universal Aim Preview"] == true
                        local isTarget = targetingEnabled and ctx.state.aimTarget == player
                        local targetSync = ctx.library.flags["Universal Targeting Sync ESP"] ~= false

                        local espSameTeam = ctx.library.flags["Universal ESP Team Check"] == true
                            and ctx.LocalPlayer.Team ~= nil
                            and player.Team == ctx.LocalPlayer.Team
                        local targetingTeamCheck
                        if targetSync then
                            targetingTeamCheck = ctx.library.flags["Universal ESP Team Check"] == true
                        else
                            targetingTeamCheck = ctx.library.flags["Universal Aim Team Check"] == true
                        end
                        local targetSameTeam = targetingTeamCheck
                            and ctx.LocalPlayer.Team ~= nil
                            and player.Team == ctx.LocalPlayer.Team

                        local targetMaxDistance = targetSync
                            and maxDistance
                            or math.max(50, tonumber(ctx.library.flags["Universal Aim Max Distance"]) or 500)
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

                            local configuredTargetColor = typeof(ctx.library.flags["Universal Aim Color"]) == "Color3"
                                and ctx.library.flags["Universal Aim Color"]
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
                            entry.name.Visible = isTarget or ctx.library.flags["Universal ESP Names"] == true
                            entry.distance.Visible = ctx.library.flags["Universal ESP Distance"] == true
                            entry.healthBackground.Visible = ctx.library.flags["Universal ESP Health"] == true
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

        updateConnection = ctx.addConnection(ctx.RunService.RenderStepped, function(deltaTime)
            accumulator += deltaTime
            if accumulator >= 1 / 30 then
                accumulator = 0
                update()
            end
        end)

        playerRemovingConnection = ctx.addConnection(ctx.Players.PlayerRemoving, destroyEntry)

        local control = ctx.option("Universal ESP")
        if control then
            control.callback = function(enabled)
                if not enabled then
                    for _, entry in pairs(ctx.state.esp) do
                        setVisible(entry, false, false)
                    end
                end
            end
        end

        ctx.library:AddCleanup(function()
            ctx.disconnect(updateConnection)
            ctx.disconnect(playerRemovingConnection)
            local playersToRemove = {}
            for player in pairs(ctx.state.esp) do
                table.insert(playersToRemove, player)
            end
            for _, player in ipairs(playersToRemove) do
                destroyEntry(player)
            end
        end)
    end

    return { setup = setupESPRuntime }
end
