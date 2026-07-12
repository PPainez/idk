--[[
    xanhub | universal | modules | esp

    Signature UI-native ESP renderer.
    Built for smooth scaling, strong readability, target integration,
    off-screen indicators, visibility dimming, and complete cleanup.
]]

local R15_BONES = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
}

local R6_BONES = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}

local DEFAULT_ACCENT = Color3.fromRGB(0, 170, 255)
local DEFAULT_TARGET = Color3.fromRGB(255, 82, 96)
local DEFAULT_FRIENDLY = Color3.fromRGB(92, 220, 155)
local DEFAULT_OCCLUDED = Color3.fromRGB(105, 115, 135)
local WHITE = Color3.fromRGB(245, 247, 255)
local DARK = Color3.fromRGB(7, 10, 16)
local DARK_SOFT = Color3.fromRGB(13, 17, 25)
local MUTED = Color3.fromRGB(155, 165, 185)

local function clamp(value, minimum, maximum)
    if minimum > maximum then
        minimum, maximum = maximum, minimum
    end
    return math.clamp(value, minimum, maximum)
end

local function damp(current, target, speed, deltaTime)
    local alpha = 1 - math.exp(-math.max(speed, 0.01) * math.max(deltaTime, 0))
    return current + (target - current) * alpha
end

local function dampVector2(current, target, speed, deltaTime)
    if not current then
        return target
    end
    local alpha = 1 - math.exp(-math.max(speed, 0.01) * math.max(deltaTime, 0))
    return current:Lerp(target, alpha)
end

local function getPlayerLabel(player)
    local displayName = player.DisplayName
    if type(displayName) ~= "string" or displayName == "" then
        return player.Name
    end

    local trimmed = string.match(displayName, "^%s*(.-)%s*$") or displayName
    if trimmed == "" or string.match(trimmed, "^%?+$") then
        return player.Name
    end

    return trimmed
end

local function getToolName(character)
    if not character then
        return nil
    end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool or tool.Name == "" then
        return nil
    end

    return tool.Name
end

local function getBonePairs(character)
    if character and character:FindFirstChild("UpperTorso") then
        return R15_BONES
    end
    return R6_BONES
end

local function setLine(frame, pointA, pointB, thickness)
    if not frame then
        return
    end

    local delta = pointB - pointA
    local length = delta.Magnitude
    if length < 0.5 then
        frame.Visible = false
        return
    end

    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromOffset((pointA.X + pointB.X) * 0.5, (pointA.Y + pointB.Y) * 0.5)
    frame.Size = UDim2.fromOffset(length, math.max(1, thickness or 1))
    frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
end

local function safeDestroy(object)
    if object then
        pcall(function()
            object:Destroy()
        end)
    end
end

return function(ctx)
    -- Controls -----------------------------------------------------------------

    local espSection = ctx.columns.visualsLeft:AddSection("Player ESP")
    espSection:AddToggle({text = "Enabled", flag = "Universal ESP", state = false})
    espSection:AddList({
        text = "Signature Style",
        flag = "Universal ESP Box Style",
        values = {"Signature", "Corners", "Full", "Double", "Minimal"},
        value = "Signature",
    })
    espSection:AddToggle({text = "Box", flag = "Universal ESP Box", state = true})
    espSection:AddToggle({text = "Box Fill", flag = "Universal ESP Box Fill", state = false})
    espSection:AddToggle({text = "Animated Scanline", flag = "Universal ESP Scanline", state = false})
    espSection:AddToggle({text = "Pulse Glow", flag = "Universal ESP Pulse", state = true})
    espSection:AddToggle({text = "Target Chevrons", flag = "Universal ESP Target Chevron", state = true})
    espSection:AddToggle({text = "Nametag", flag = "Universal ESP Nametag", state = true})
    espSection:AddToggle({text = "Show Username", flag = "Universal ESP Show Username", state = false})
    espSection:AddToggle({text = "Distance", flag = "Universal ESP Distance", state = true})
    espSection:AddToggle({text = "Held Tool", flag = "Universal ESP Tool", state = false})
    espSection:AddToggle({text = "Health Bar", flag = "Universal ESP Health", state = true})
    espSection:AddToggle({text = "Health Number", flag = "Universal ESP Health Number", state = true})
    espSection:AddList({
        text = "Health Bar Side",
        flag = "Universal ESP Health Side",
        values = {"Left", "Right"},
        value = "Left",
    })
    espSection:AddToggle({text = "Skeleton", flag = "Universal ESP Skeleton", state = false})
    espSection:AddToggle({text = "Head Dot", flag = "Universal ESP Head Dot", state = false})
    espSection:AddToggle({text = "Tracer", flag = "Universal ESP Tracer", state = false})
    espSection:AddList({
        text = "Tracer From",
        flag = "Universal ESP Tracer From",
        values = {"Bottom", "Center", "Top"},
        value = "Bottom",
    })
    espSection:AddToggle({text = "Off-screen Arrows", flag = "Universal ESP Offscreen", state = true})
    espSection:AddToggle({text = "Highlights", flag = "Universal ESP Highlights", state = false})
    espSection:AddToggle({text = "Team Check", flag = "Universal ESP Team Check", state = false})

    local visibilitySection = ctx.columns.visualsLeft:AddSection("Visibility")
    visibilitySection:AddToggle({text = "Visibility Check", flag = "Universal ESP Visibility Check", state = true})
    visibilitySection:AddToggle({text = "Hide Occluded", flag = "Universal ESP Hide Occluded", state = false})
    visibilitySection:AddSlider({
        text = "Occluded Opacity",
        flag = "Universal ESP Occluded Opacity",
        min = 10,
        max = 90,
        value = 42,
        float = 1,
        suffix = "%",
    })
    visibilitySection:AddToggle({text = "Use Team Colors", flag = "Universal ESP Use Team Color", state = false})
    visibilitySection:AddToggle({text = "Clutter Control", flag = "Universal ESP Clutter Control", state = true})
    visibilitySection:AddSlider({
        text = "Compact After",
        flag = "Universal ESP Compact Distance",
        min = 75,
        max = 1000,
        value = 220,
        float = 5,
        suffix = " studs",
    })
    visibilitySection:AddSlider({
        text = "Maximum Nametags",
        flag = "Universal ESP Max Nametags",
        min = 4,
        max = 30,
        value = 12,
        float = 1,
    })

    local styleSection = ctx.columns.visualsRight:AddSection("Signature Styling")
    styleSection:AddLabel("UI-native neon brackets with smooth target emphasis")
    styleSection:AddToggle({text = "Chroma Shift", flag = "Universal ESP Chroma", state = false})
    styleSection:AddSlider({
        text = "Fill Opacity",
        flag = "Universal ESP Fill Opacity",
        min = 0,
        max = 55,
        value = 12,
        float = 1,
        suffix = "%",
    })
    styleSection:AddSlider({
        text = "Glow Strength",
        flag = "Universal ESP Glow Strength",
        min = 0,
        max = 100,
        value = 52,
        float = 1,
        suffix = "%",
    })
    styleSection:AddSlider({
        text = "Corner Length",
        flag = "Universal ESP Corner Length",
        min = 10,
        max = 48,
        value = 25,
        float = 1,
        suffix = "%",
    })
    styleSection:AddSlider({
        text = "Box Thickness",
        flag = "Universal ESP Box Thickness",
        min = 1,
        max = 4,
        value = 2,
        float = 0.5,
    })
    styleSection:AddSlider({
        text = "Line Thickness",
        flag = "Universal ESP Line Thickness",
        min = 1,
        max = 3,
        value = 1.5,
        float = 0.5,
    })
    styleSection:AddSlider({
        text = "Text Size",
        flag = "Universal ESP Nametag Size",
        min = 10,
        max = 18,
        value = 13,
        float = 1,
    })
    styleSection:AddSlider({
        text = "Fade Start",
        flag = "Universal ESP Fade Start",
        min = 50,
        max = 1200,
        value = 300,
        float = 10,
        suffix = " studs",
    })
    styleSection:AddSlider({
        text = "Maximum Distance",
        flag = "Universal ESP Max Distance",
        min = 50,
        max = 2500,
        value = 800,
        float = 10,
        suffix = " studs",
    })

    local performanceSection = ctx.columns.visualsRight:AddSection("ESP Performance")
    performanceSection:AddToggle({text = "Adaptive Refresh", flag = "Universal ESP Adaptive", state = true})
    performanceSection:AddSlider({
        text = "Refresh Rate",
        flag = "Universal ESP Refresh Rate",
        min = 20,
        max = 120,
        value = 60,
        float = 5,
        suffix = " Hz",
    })
    performanceSection:AddSlider({
        text = "Maximum Players",
        flag = "Universal ESP Max Players",
        min = 4,
        max = 50,
        value = 24,
        float = 1,
    })
    local rendererStatus = performanceSection:AddLabel("Renderer: UI-native / waiting")

    local colorsSection = ctx.columns.visualsRight:AddSection("ESP Colors")
    colorsSection:AddColor({text = "Enemy Color", flag = "Universal ESP Color", color = DEFAULT_ACCENT})
    colorsSection:AddColor({text = "Friendly Color", flag = "Universal ESP Friendly Color", color = DEFAULT_FRIENDLY})
    colorsSection:AddColor({text = "Skeleton Color", flag = "Universal ESP Skeleton Color", color = Color3.fromRGB(0, 210, 255)})
    colorsSection:AddColor({text = "Occluded Color", flag = "Universal ESP Occluded Color", color = DEFAULT_OCCLUDED})

    local previewSection = ctx.columns.visualsRight:AddSection("Signature Preview")
    previewSection:AddLabel("Preview updates live with your ESP settings")
    ctx.refs.espPreviewSection = previewSection

    -- Runtime ------------------------------------------------------------------

    local function setupESPRuntime()
        local overlayRoot = ctx.createOverlayRoot()
        local renderConnection
        local playerRemovingConnection
        local previewConnection
        local renderAccumulator = 0
        local statusAccumulator = 0
        local previewHost

        local function flag(name, default)
            local value = ctx.library.flags[name]
            if type(value) == "boolean" then
                return value
            end
            return default
        end

        local function numberFlag(name, default)
            return tonumber(ctx.library.flags[name]) or default
        end

        local function colorFlag(name, fallback)
            local value = ctx.library.flags[name]
            if typeof(value) == "Color3" then
                return value
            end
            return fallback
        end

        local function newFrame(parent, name, zIndex)
            local frame = Instance.new("Frame")
            frame.Name = name
            frame.BackgroundColor3 = WHITE
            frame.BackgroundTransparency = 1
            frame.BorderSizePixel = 0
            frame.Visible = false
            frame.ZIndex = zIndex or 520
            frame.Parent = parent
            return frame
        end

        local function addStroke(parent, color, thickness, transparency)
            local stroke = Instance.new("UIStroke")
            stroke.Color = color or DEFAULT_ACCENT
            stroke.Thickness = thickness or 1
            stroke.Transparency = transparency or 0
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Parent = parent
            return stroke
        end

        local function addCorner(parent, radius)
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, radius or 4)
            corner.Parent = parent
            return corner
        end

        local function newText(parent, name, zIndex)
            local label = Instance.new("TextLabel")
            label.Name = name
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.TextColor3 = WHITE
            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            label.TextStrokeTransparency = 0.42
            label.Font = Enum.Font.GothamMedium
            label.TextSize = 13
            label.Text = ""
            label.Visible = false
            label.ZIndex = zIndex or 525
            label.Parent = parent
            return label
        end

        local function createLayer(name, zIndex)
            local layer = newFrame(overlayRoot, name, zIndex)
            layer.Size = UDim2.fromScale(1, 1)
            layer.Position = UDim2.fromScale(0, 0)
            layer.BackgroundTransparency = 1
            layer.Visible = true
            layer.Active = false
            layer.ClipsDescendants = false
            return layer
        end

        -- Separate sibling layers prevent distant boxes from drawing over labels.
        local geometryLayer = createLayer("ESP_Geometry", 520)
        local labelLayer = createLayer("ESP_Labels", 700)
        local offscreenLayer = createLayer("ESP_Offscreen", 820)

        local function createCornerLine(parent, index)
            local line = newFrame(parent, "Corner" .. index, 528)
            line.BackgroundColor3 = DEFAULT_ACCENT
            line.BackgroundTransparency = 0
            local stroke = addStroke(line, Color3.fromRGB(0, 0, 0), 1, 0.18)
            return {frame = line, stroke = stroke}
        end

        local function createSkeletonLine(parent, index)
            local line = newFrame(parent, "Bone" .. index, 524)
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BackgroundColor3 = DEFAULT_ACCENT
            line.BackgroundTransparency = 0
            local stroke = addStroke(line, Color3.fromRGB(0, 0, 0), 1, 0.35)
            return {frame = line, stroke = stroke}
        end

        local function hideEntry(entry)
            if not entry then
                return
            end

            if entry.root then
                entry.root.Visible = false
            end
            if entry.namePill then
                entry.namePill.Visible = false
            end
            if entry.healthBackground then
                entry.healthBackground.Visible = false
            end
            if entry.healthText then
                entry.healthText.Visible = false
            end
            if entry.offscreen then
                entry.offscreen.Visible = false
            end
            if entry.highlight then
                entry.highlight.Enabled = false
            end
        end

        local function destroyEntry(player)
            local entry = ctx.state.esp[player]
            if not entry then
                return
            end

            safeDestroy(entry.highlight)
            safeDestroy(entry.root)
            safeDestroy(entry.namePill)
            safeDestroy(entry.healthBackground)
            safeDestroy(entry.healthText)
            safeDestroy(entry.offscreen)
            ctx.state.esp[player] = nil
        end

        local function createEntry(player, character)
            destroyEntry(player)

            local rootPart = ctx.getRoot(character)
            if not rootPart then
                return nil
            end

            local root = newFrame(geometryLayer, "ESP_" .. player.Name, 520)
            root.Size = UDim2.fromScale(1, 1)
            root.Position = UDim2.fromScale(0, 0)
            root.BackgroundTransparency = 1
            root.Visible = false

            local glow = newFrame(root, "Glow", 521)
            glow.BackgroundTransparency = 1
            local glowStroke = addStroke(glow, DEFAULT_ACCENT, 5, 0.8)
            addCorner(glow, 3)

            local box = newFrame(root, "Box", 523)
            box.BackgroundColor3 = DEFAULT_ACCENT
            box.BackgroundTransparency = 1
            local boxStroke = addStroke(box, DEFAULT_ACCENT, 2, 0.05)
            addCorner(box, 2)

            local corners = {}
            for index = 1, 8 do
                corners[index] = createCornerLine(root, index)
            end

            local scanline = newFrame(root, "Scanline", 527)
            scanline.BackgroundColor3 = DEFAULT_ACCENT
            scanline.BackgroundTransparency = 0.28
            scanline.Size = UDim2.fromOffset(20, 1)
            local scanGradient = Instance.new("UIGradient")
            scanGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(0.5, DEFAULT_ACCENT),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
            })
            scanGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 1),
            })
            scanGradient.Parent = scanline

            local chevronLeft = newText(root, "TargetChevronLeft", 531)
            chevronLeft.Text = "›"
            chevronLeft.TextXAlignment = Enum.TextXAlignment.Center
            chevronLeft.TextYAlignment = Enum.TextYAlignment.Center
            chevronLeft.TextSize = 26

            local chevronRight = newText(root, "TargetChevronRight", 531)
            chevronRight.Text = "‹"
            chevronRight.TextXAlignment = Enum.TextXAlignment.Center
            chevronRight.TextYAlignment = Enum.TextYAlignment.Center
            chevronRight.TextSize = 26

            local namePill = newFrame(labelLayer, "NamePill_" .. player.Name, 729)
            namePill.BackgroundColor3 = DARK
            namePill.BackgroundTransparency = 0.12
            local nameStroke = addStroke(namePill, DEFAULT_ACCENT, 1, 0.28)
            addCorner(namePill, 6)

            local statusDot = newFrame(namePill, "StatusDot", 531)
            statusDot.AnchorPoint = Vector2.new(0.5, 0.5)
            statusDot.Size = UDim2.fromOffset(6, 6)
            statusDot.BackgroundColor3 = Color3.fromRGB(90, 235, 155)
            statusDot.BackgroundTransparency = 0
            statusDot.Visible = true
            addCorner(statusDot, 999)

            local nameLabel = newText(namePill, "Name", 531)
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextYAlignment = Enum.TextYAlignment.Center
            nameLabel.TextStrokeTransparency = 1
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Visible = true

            local detailLabel = newText(namePill, "Details", 531)
            detailLabel.TextXAlignment = Enum.TextXAlignment.Left
            detailLabel.TextYAlignment = Enum.TextYAlignment.Center
            detailLabel.TextColor3 = MUTED
            detailLabel.TextStrokeTransparency = 1
            detailLabel.Visible = true

            local targetBadge = newText(namePill, "TargetBadge", 532)
            targetBadge.AnchorPoint = Vector2.new(1, 0.5)
            targetBadge.Text = "LOCK"
            targetBadge.TextSize = 9
            targetBadge.TextXAlignment = Enum.TextXAlignment.Right
            targetBadge.TextStrokeTransparency = 1

            local healthBackground = newFrame(labelLayer, "HealthBackground_" .. player.Name, 724)
            healthBackground.BackgroundColor3 = Color3.fromRGB(20, 25, 34)
            healthBackground.BackgroundTransparency = 0.05
            addCorner(healthBackground, 3)
            local healthStroke = addStroke(healthBackground, Color3.fromRGB(0, 0, 0), 1, 0.15)

            local healthFill = newFrame(healthBackground, "HealthFill", 530)
            healthFill.AnchorPoint = Vector2.new(0, 1)
            healthFill.Position = UDim2.fromScale(0, 1)
            healthFill.Size = UDim2.fromScale(1, 1)
            healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
            healthFill.BackgroundTransparency = 0
            healthFill.Visible = true
            addCorner(healthFill, 3)

            local healthTicks = {}
            for index = 1, 3 do
                local tick = newFrame(healthBackground, "Tick" .. index, 531)
                tick.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
                tick.BackgroundTransparency = 0.25
                tick.Visible = true
                healthTicks[index] = tick
            end

            local healthText = newText(labelLayer, "HealthText_" .. player.Name, 728)
            healthText.TextSize = 10
            healthText.TextXAlignment = Enum.TextXAlignment.Center
            healthText.TextYAlignment = Enum.TextYAlignment.Center

            local tracer = newFrame(root, "Tracer", 519)
            tracer.AnchorPoint = Vector2.new(0.5, 0.5)
            tracer.BackgroundColor3 = DEFAULT_ACCENT
            tracer.BackgroundTransparency = 0.25

            local headDot = newFrame(root, "HeadDot", 530)
            headDot.AnchorPoint = Vector2.new(0.5, 0.5)
            headDot.BackgroundColor3 = DEFAULT_ACCENT
            headDot.BackgroundTransparency = 0
            addCorner(headDot, 999)
            local headStroke = addStroke(headDot, Color3.fromRGB(0, 0, 0), 1, 0.18)

            local skeleton = {}
            for index = 1, #R15_BONES do
                skeleton[index] = createSkeletonLine(root, index)
            end

            local offscreen = newFrame(offscreenLayer, "Offscreen_" .. player.Name, 835)
            offscreen.Size = UDim2.fromOffset(120, 42)
            offscreen.AnchorPoint = Vector2.new(0.5, 0.5)
            offscreen.BackgroundColor3 = DARK
            offscreen.BackgroundTransparency = 0.14
            local offscreenStroke = addStroke(offscreen, DEFAULT_ACCENT, 1, 0.2)
            addCorner(offscreen, 7)

            local arrow = newText(offscreen, "Arrow", 537)
            arrow.AnchorPoint = Vector2.new(0.5, 0.5)
            arrow.Position = UDim2.fromOffset(18, 21)
            arrow.Size = UDim2.fromOffset(26, 26)
            arrow.Text = "▲"
            arrow.TextSize = 18
            arrow.TextXAlignment = Enum.TextXAlignment.Center
            arrow.TextYAlignment = Enum.TextYAlignment.Center
            arrow.Visible = true

            local offscreenName = newText(offscreen, "Name", 537)
            offscreenName.Position = UDim2.fromOffset(36, 5)
            offscreenName.Size = UDim2.new(1, -42, 0, 17)
            offscreenName.TextSize = 11
            offscreenName.TextXAlignment = Enum.TextXAlignment.Left
            offscreenName.TextStrokeTransparency = 1
            offscreenName.Visible = true

            local offscreenDistance = newText(offscreen, "Distance", 537)
            offscreenDistance.Position = UDim2.fromOffset(36, 21)
            offscreenDistance.Size = UDim2.new(1, -42, 0, 15)
            offscreenDistance.TextSize = 10
            offscreenDistance.TextColor3 = MUTED
            offscreenDistance.TextXAlignment = Enum.TextXAlignment.Left
            offscreenDistance.TextStrokeTransparency = 1
            offscreenDistance.Visible = true

            local highlight = Instance.new("Highlight")
            highlight.Name = "xanhub_signature_highlight"
            highlight.Adornee = character
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillTransparency = 0.93
            highlight.OutlineTransparency = 0.18
            highlight.Enabled = false
            highlight.Parent = character

            local entry = {
                player = player,
                character = character,
                rootPart = rootPart,
                root = root,
                glow = glow,
                glowStroke = glowStroke,
                box = box,
                boxStroke = boxStroke,
                corners = corners,
                scanline = scanline,
                chevronLeft = chevronLeft,
                chevronRight = chevronRight,
                namePill = namePill,
                nameStroke = nameStroke,
                statusDot = statusDot,
                nameLabel = nameLabel,
                detailLabel = detailLabel,
                targetBadge = targetBadge,
                healthBackground = healthBackground,
                healthStroke = healthStroke,
                healthFill = healthFill,
                healthTicks = healthTicks,
                healthText = healthText,
                tracer = tracer,
                headDot = headDot,
                headStroke = headStroke,
                skeleton = skeleton,
                offscreen = offscreen,
                offscreenStroke = offscreenStroke,
                arrow = arrow,
                offscreenName = offscreenName,
                offscreenDistance = offscreenDistance,
                highlight = highlight,
                displayTopLeft = nil,
                displayBottomRight = nil,
                displayedHealth = 1,
                lineOfSight = true,
                lastVisibilityCheck = 0,
                lastTextUpdate = 0,
                scanPhase = (player.UserId % 100) / 100,
            }

            ctx.state.esp[player] = entry
            return entry
        end

        local function getBounds(camera, character)
            local ok, boundingCFrame, boundingSize = pcall(function()
                local cframe, size = character:GetBoundingBox()
                return cframe, size
            end)

            if not ok or typeof(boundingCFrame) ~= "CFrame" or typeof(boundingSize) ~= "Vector3" then
                return nil
            end

            -- Protect against intentionally huge accessories or map-attached character parts.
            boundingSize = Vector3.new(
                clamp(boundingSize.X, 1.5, 12),
                clamp(boundingSize.Y, 3, 16),
                clamp(boundingSize.Z, 1.5, 12)
            )

            local minX, minY = math.huge, math.huge
            local maxX, maxY = -math.huge, -math.huge
            local pointsInFront = 0

            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do
                        local offset = Vector3.new(
                            boundingSize.X * 0.5 * x,
                            boundingSize.Y * 0.5 * y,
                            boundingSize.Z * 0.5 * z
                        )
                        local point = camera:WorldToViewportPoint(boundingCFrame:PointToWorldSpace(offset))
                        if point.Z > 0.05 then
                            pointsInFront += 1
                            minX = math.min(minX, point.X)
                            minY = math.min(minY, point.Y)
                            maxX = math.max(maxX, point.X)
                            maxY = math.max(maxY, point.Y)
                        end
                    end
                end
            end

            if pointsInFront < 2 then
                return nil
            end

            local viewport = camera.ViewportSize
            local capX = viewport.X * 2
            local capY = viewport.Y * 2
            minX = clamp(minX - 3, -capX, capX)
            maxX = clamp(maxX + 3, -capX, capX)
            minY = clamp(minY - 3, -capY, capY)
            maxY = clamp(maxY + 3, -capY, capY)

            local width = maxX - minX
            local height = maxY - minY
            if width < 3 or height < 6 or width > viewport.X * 2.5 or height > viewport.Y * 2.5 then
                return nil
            end

            return {
                topLeft = Vector2.new(minX, minY),
                bottomRight = Vector2.new(maxX, maxY),
                onScreen = maxX >= 0 and minX <= viewport.X and maxY >= 0 and minY <= viewport.Y,
            }
        end

        local function getTargetSettings(maxDistance)
            local syncESP = ctx.library.flags["Universal Targeting Sync ESP"] ~= false
            local teamCheck = syncESP
                and flag("Universal ESP Team Check", false)
                or flag("Universal Aim Team Check", true)
            local targetMaximum = syncESP
                and maxDistance
                or math.max(50, numberFlag("Universal Aim Max Distance", 500))
            local targetColor = syncESP
                and colorFlag("Universal ESP Color", DEFAULT_ACCENT)
                or colorFlag("Universal Aim Color", DEFAULT_TARGET)
            return teamCheck, targetMaximum, targetColor
        end

        local function resolveColor(player, baseColor, friendlyColor, isTarget, targetColor, lineOfSight)
            local color = baseColor

            if isTarget then
                color = targetColor
            elseif flag("Universal ESP Use Team Color", false) and player.TeamColor then
                color = player.TeamColor.Color
            elseif ctx.LocalPlayer.Team ~= nil and player.Team == ctx.LocalPlayer.Team then
                color = friendlyColor
            elseif flag("Universal ESP Chroma", false) then
                local hue = (os.clock() * 0.12 + (player.UserId % 911) * 0.0017) % 1
                color = Color3.fromHSV(hue, 0.82, 1)
            end

            if not lineOfSight then
                local occluded = colorFlag("Universal ESP Occluded Color", DEFAULT_OCCLUDED)
                color = color:Lerp(occluded, 0.62)
            end

            return color
        end

        local function checkLineOfSight(entry, camera, targetPosition)
            if not flag("Universal ESP Visibility Check", true) then
                entry.lineOfSight = true
                return true
            end

            local now = os.clock()
            local interval = 0.11 + ((entry.player.UserId % 7) * 0.009)
            if now - entry.lastVisibilityCheck < interval then
                return entry.lineOfSight
            end

            entry.lastVisibilityCheck = now
            local direction = targetPosition - camera.CFrame.Position
            if direction.Magnitude < 1 then
                entry.lineOfSight = true
                return true
            end

            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            local exclusions = {entry.character}
            if ctx.LocalPlayer.Character then
                table.insert(exclusions, ctx.LocalPlayer.Character)
            end
            params.FilterDescendantsInstances = exclusions

            local ok, result = pcall(function()
                return ctx.Workspace:Raycast(camera.CFrame.Position, direction, params)
            end)

            entry.lineOfSight = not ok or result == nil
            return entry.lineOfSight
        end

        local function layoutCorners(entry, topLeft, bottomRight, color, opacity, thickness, cornerPercent, visible)
            local width = bottomRight.X - topLeft.X
            local height = bottomRight.Y - topLeft.Y
            local length = clamp(math.min(width, height) * (cornerPercent / 100), 5, math.min(width, height) * 0.48)
            local x1, y1 = topLeft.X, topLeft.Y
            local x2, y2 = bottomRight.X, bottomRight.Y

            local segments = {
                {Vector2.new(x1, y1), Vector2.new(x1 + length, y1)},
                {Vector2.new(x1, y1), Vector2.new(x1, y1 + length)},
                {Vector2.new(x2, y1), Vector2.new(x2 - length, y1)},
                {Vector2.new(x2, y1), Vector2.new(x2, y1 + length)},
                {Vector2.new(x1, y2), Vector2.new(x1 + length, y2)},
                {Vector2.new(x1, y2), Vector2.new(x1, y2 - length)},
                {Vector2.new(x2, y2), Vector2.new(x2 - length, y2)},
                {Vector2.new(x2, y2), Vector2.new(x2, y2 - length)},
            }

            for index, corner in ipairs(entry.corners) do
                local segment = segments[index]
                local frame = corner.frame
                frame.Visible = visible
                if visible then
                    frame.BackgroundColor3 = color
                    frame.BackgroundTransparency = 1 - opacity
                    corner.stroke.Thickness = math.max(1, thickness * 0.65)
                    setLine(frame, segment[1], segment[2], thickness)
                end
            end
        end

        local function updateSkeleton(entry, camera, color, opacity, thickness, visible)
            local pairsList = getBonePairs(entry.character)

            for index, bone in ipairs(entry.skeleton) do
                local pair = pairsList[index]
                local frame = bone.frame
                frame.Visible = false

                if visible and pair then
                    local partA = entry.character:FindFirstChild(pair[1])
                    local partB = entry.character:FindFirstChild(pair[2])
                    if partA and partB and partA:IsA("BasePart") and partB:IsA("BasePart") then
                        local pointA, onA = camera:WorldToViewportPoint(partA.Position)
                        local pointB, onB = camera:WorldToViewportPoint(partB.Position)
                        if onA and onB and pointA.Z > 0 and pointB.Z > 0 then
                            frame.Visible = true
                            frame.BackgroundColor3 = color
                            frame.BackgroundTransparency = 1 - opacity
                            bone.stroke.Thickness = math.max(1, thickness * 0.55)
                            setLine(frame, Vector2.new(pointA.X, pointA.Y), Vector2.new(pointB.X, pointB.Y), thickness)
                        end
                    end
                end
            end
        end

        local function setEntryDepth(entry, renderIndex, isTarget)
            local priority = clamp(64 - (renderIndex or 1), 1, 64)
            local geometryBase = isTarget and 640 or (540 + priority)
            local labelBase = isTarget and 810 or (720 + priority)
            local offscreenBase = isTarget and 900 or (840 + priority)

            entry.root.ZIndex = geometryBase
            entry.tracer.ZIndex = geometryBase
            entry.glow.ZIndex = geometryBase + 1
            entry.box.ZIndex = geometryBase + 3
            entry.scanline.ZIndex = geometryBase + 5
            entry.headDot.ZIndex = geometryBase + 6
            entry.chevronLeft.ZIndex = geometryBase + 7
            entry.chevronRight.ZIndex = geometryBase + 7
            for _, corner in ipairs(entry.corners) do
                corner.frame.ZIndex = geometryBase + 4
            end
            for _, bone in ipairs(entry.skeleton) do
                bone.frame.ZIndex = geometryBase + 2
            end

            entry.namePill.ZIndex = labelBase
            entry.statusDot.ZIndex = labelBase + 1
            entry.nameLabel.ZIndex = labelBase + 2
            entry.detailLabel.ZIndex = labelBase + 2
            entry.targetBadge.ZIndex = labelBase + 3
            entry.healthBackground.ZIndex = labelBase - 2
            entry.healthFill.ZIndex = labelBase - 1
            entry.healthText.ZIndex = labelBase + 1
            for _, tick in ipairs(entry.healthTicks) do
                tick.ZIndex = labelBase
            end

            entry.offscreen.ZIndex = offscreenBase
            entry.arrow.ZIndex = offscreenBase + 2
            entry.offscreenName.ZIndex = offscreenBase + 2
            entry.offscreenDistance.ZIndex = offscreenBase + 2
        end

        local function rectanglesOverlap(a, b, padding)
            padding = padding or 3
            return not (
                a.right + padding <= b.left
                or a.left >= b.right + padding
                or a.bottom + padding <= b.top
                or a.top >= b.bottom + padding
            )
        end

        local function claimNametag(layout, x, y, width, height, isTarget, compact)
            if not layout or not layout.enabled then
                return x, y, true
            end

            if layout.count >= layout.maximum and not isTarget then
                layout.hidden += 1
                return x, y, false
            end

            local attempts = isTarget and 6 or (compact and 2 or 4)
            local step = height + 3
            for attempt = 0, attempts do
                local candidateY = math.max(4, y - attempt * step)
                local rectangle = {
                    left = x,
                    top = candidateY,
                    right = x + width,
                    bottom = candidateY + height,
                }
                local blocked = false
                for _, occupied in ipairs(layout.occupied) do
                    if rectanglesOverlap(rectangle, occupied, 3) then
                        blocked = true
                        break
                    end
                end
                if not blocked then
                    table.insert(layout.occupied, rectangle)
                    layout.count += 1
                    return x, candidateY, true
                end
            end

            if isTarget then
                local rectangle = {left = x, top = y, right = x + width, bottom = y + height}
                table.insert(layout.occupied, rectangle)
                layout.count += 1
                return x, y, true
            end

            layout.hidden += 1
            return x, y, false
        end

        local function updateOffscreen(entry, camera, displayColor, distance, isTarget, visible)
            local offscreen = entry.offscreen
            if not visible or not flag("Universal ESP Offscreen", true) then
                offscreen.Visible = false
                return
            end

            local rootPart = entry.rootPart
            if not rootPart or not rootPart.Parent then
                offscreen.Visible = false
                return
            end

            local projected = camera:WorldToViewportPoint(rootPart.Position)
            local viewport = camera.ViewportSize
            local center = viewport * 0.5
            local direction = Vector2.new(projected.X - center.X, projected.Y - center.Y)
            if projected.Z < 0 then
                direction = -direction
            end

            if direction.Magnitude < 0.01 then
                direction = Vector2.new(0, -1)
            else
                direction = direction.Unit
            end

            local marginX = 78
            local marginY = 54
            local availableX = math.max(1, center.X - marginX)
            local availableY = math.max(1, center.Y - marginY)
            local scaleX = math.abs(direction.X) > 0.001 and availableX / math.abs(direction.X) or math.huge
            local scaleY = math.abs(direction.Y) > 0.001 and availableY / math.abs(direction.Y) or math.huge
            local edge = center + direction * math.min(scaleX, scaleY)
            local angle = math.deg(math.atan2(direction.Y, direction.X)) + 90

            offscreen.Visible = true
            offscreen.Position = UDim2.fromOffset(edge.X, edge.Y)
            offscreen.Size = UDim2.fromOffset(isTarget and 112 or 92, isTarget and 36 or 30)
            offscreen.BackgroundTransparency = isTarget and 0.04 or 0.14
            entry.offscreenStroke.Color = displayColor
            entry.offscreenStroke.Thickness = isTarget and 2 or 1
            entry.arrow.TextColor3 = displayColor
            entry.arrow.Rotation = angle
            entry.offscreenName.Text = getPlayerLabel(entry.player)
            entry.offscreenName.TextColor3 = isTarget and displayColor or WHITE
            entry.offscreenDistance.Text = tostring(math.floor(distance + 0.5)) .. "m"
        end

        local function updateText(entry, distance, humanoid, isTarget, lineOfSight, compact)
            local now = os.clock()
            if now - entry.lastTextUpdate < 0.08 then
                return
            end
            entry.lastTextUpdate = now

            local displayName = getPlayerLabel(entry.player)
            if compact and flag("Universal ESP Distance", true) then
                entry.nameLabel.Text = displayName .. "  •  " .. tostring(math.floor(distance + 0.5)) .. "m"
            else
                entry.nameLabel.Text = displayName
            end

            local details = {}
            if flag("Universal ESP Show Username", false) and entry.player.Name ~= displayName then
                table.insert(details, "@" .. entry.player.Name)
            end
            if flag("Universal ESP Distance", true) then
                table.insert(details, tostring(math.floor(distance + 0.5)) .. "m")
            end
            if flag("Universal ESP Tool", true) then
                local toolName = getToolName(entry.character)
                if toolName then
                    table.insert(details, toolName)
                end
            end
            entry.detailLabel.Text = compact
                and ""
                or (#details > 0 and table.concat(details, "  •  ") or (lineOfSight and "visible" or "occluded"))

            local health = math.max(0, math.floor(humanoid.Health + 0.5))
            entry.healthText.Text = tostring(health)
            entry.targetBadge.Visible = isTarget
        end

        local function updateEntry(entry, candidate, camera, deltaTime, baseColor, friendlyColor, skeletonColor, maxDistance, fadeStart, labelLayout, renderIndex)
            local player = candidate.player
            local character = candidate.character
            local humanoid = candidate.humanoid
            local rootPart = candidate.rootPart
            local distance = candidate.distance
            local isTarget = candidate.isTarget
            local targetColor = candidate.targetColor

            entry.character = character
            entry.rootPart = rootPart
            entry.highlight.Adornee = character
            setEntryDepth(entry, renderIndex, isTarget)

            local bounds = getBounds(camera, character)
            local lineOfSight = checkLineOfSight(entry, camera, rootPart.Position)
            local hiddenByOcclusion = flag("Universal ESP Hide Occluded", false) and not lineOfSight and not isTarget

            if hiddenByOcclusion then
                hideEntry(entry)
                return
            end

            if not bounds or not bounds.onScreen then
                hideEntry(entry)
                updateOffscreen(entry, camera, resolveColor(player, baseColor, friendlyColor, isTarget, targetColor, lineOfSight), distance, isTarget, true)
                return
            end

            entry.offscreen.Visible = false
            entry.root.Visible = true

            local rawTopLeft = bounds.topLeft
            local rawBottomRight = bounds.bottomRight
            local smoothSpeed = isTarget and 24 or 18
            entry.displayTopLeft = dampVector2(entry.displayTopLeft, rawTopLeft, smoothSpeed, deltaTime)
            entry.displayBottomRight = dampVector2(entry.displayBottomRight, rawBottomRight, smoothSpeed, deltaTime)

            local topLeft = entry.displayTopLeft
            local bottomRight = entry.displayBottomRight
            local width = math.max(3, bottomRight.X - topLeft.X)
            local height = math.max(6, bottomRight.Y - topLeft.Y)
            local centerX = (topLeft.X + bottomRight.X) * 0.5
            local centerY = (topLeft.Y + bottomRight.Y) * 0.5

            local fade = clamp((distance - fadeStart) / math.max(1, maxDistance - fadeStart), 0, 1)
            local opacity = 1 - fade * (isTarget and 0.46 or 0.78)
            if not lineOfSight then
                opacity *= clamp(numberFlag("Universal ESP Occluded Opacity", 42) / 100, 0.1, 0.9)
            end
            opacity = clamp(opacity, 0.08, 1)

            local clutterControl = flag("Universal ESP Clutter Control", true)
            local compactDistance = math.max(75, numberFlag("Universal ESP Compact Distance", 220))
            local compact = clutterControl and not isTarget and distance >= compactDistance

            local displayColor = resolveColor(player, baseColor, friendlyColor, isTarget, targetColor, lineOfSight)
            local style = ctx.library.flags["Universal ESP Box Style"] or "Signature"
            if style ~= "Signature" and style ~= "Corners" and style ~= "Full" and style ~= "Double" and style ~= "Minimal" then
                style = style == "Corner" and "Corners" or "Signature"
            end

            local boxEnabled = flag("Universal ESP Box", true) and style ~= "Minimal"
            local showFull = boxEnabled and not compact and (style == "Signature" or style == "Full" or style == "Double")
            local showCorners = boxEnabled and (style == "Signature" or style == "Corners" or style == "Double")
            local boxThickness = clamp(numberFlag("Universal ESP Box Thickness", 2), 1, 4)
            local lineThickness = clamp(numberFlag("Universal ESP Line Thickness", 1.5), 1, 3)
            local cornerPercent = clamp(numberFlag("Universal ESP Corner Length", 25), 10, 48)
            local pulse = flag("Universal ESP Pulse", true)
                and (0.76 + math.abs(math.sin(os.clock() * (isTarget and 5.2 or 2.8) + entry.scanPhase * 6.28)) * 0.24)
                or 1
            local glowStrength = clamp(numberFlag("Universal ESP Glow Strength", 52) / 100, 0, 1)
            local fillOpacity = clamp(numberFlag("Universal ESP Fill Opacity", 12) / 100, 0, 0.55)

            local showFill = boxEnabled and not compact and flag("Universal ESP Box Fill", false)
            entry.box.Visible = showFull or showFill
            entry.box.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
            entry.box.Size = UDim2.fromOffset(width, height)
            entry.box.BackgroundColor3 = displayColor
            entry.box.BackgroundTransparency = showFill
                and clamp(1 - fillOpacity * opacity, 0.45, 1)
                or 1
            entry.boxStroke.Color = displayColor
            entry.boxStroke.Thickness = isTarget and boxThickness + 0.75 or boxThickness
            entry.boxStroke.Transparency = showFull and clamp(1 - opacity * pulse, 0.02, 0.94) or 1

            entry.glow.Visible = boxEnabled and not compact and glowStrength > 0 and style ~= "Minimal"
            entry.glow.Position = UDim2.fromOffset(topLeft.X - 2, topLeft.Y - 2)
            entry.glow.Size = UDim2.fromOffset(width + 4, height + 4)
            entry.glowStroke.Color = displayColor
            entry.glowStroke.Thickness = 3 + glowStrength * (isTarget and 5 or 3)
            entry.glowStroke.Transparency = clamp(0.96 - opacity * glowStrength * pulse * 0.48, 0.43, 0.97)

            layoutCorners(
                entry,
                topLeft,
                bottomRight,
                displayColor,
                opacity * pulse,
                isTarget and boxThickness + 1 or boxThickness,
                cornerPercent,
                showCorners
            )

            local scanlineVisible = boxEnabled
                and style == "Signature"
                and not compact
                and flag("Universal ESP Scanline", false)
                and width > 12
                and height > 18
            entry.scanline.Visible = scanlineVisible
            if scanlineVisible then
                local progress = (os.clock() * (isTarget and 0.92 or 0.58) + entry.scanPhase) % 1
                entry.scanline.Position = UDim2.fromOffset(topLeft.X + 3, topLeft.Y + 3 + (height - 6) * progress)
                entry.scanline.Size = UDim2.fromOffset(math.max(4, width - 6), isTarget and 2 or 1)
                entry.scanline.BackgroundColor3 = displayColor
                entry.scanline.BackgroundTransparency = clamp(0.2 + fade * 0.55, 0.2, 0.86)
            end

            local showChevrons = isTarget and flag("Universal ESP Target Chevron", true)
            local chevronPulse = 1 + math.sin(os.clock() * 5) * 0.08
            entry.chevronLeft.Visible = showChevrons
            entry.chevronRight.Visible = showChevrons
            entry.chevronLeft.TextColor3 = displayColor
            entry.chevronRight.TextColor3 = displayColor
            entry.chevronLeft.TextTransparency = 1 - opacity
            entry.chevronRight.TextTransparency = 1 - opacity
            entry.chevronLeft.Position = UDim2.fromOffset(topLeft.X - 22 * chevronPulse, centerY - 15)
            entry.chevronRight.Position = UDim2.fromOffset(bottomRight.X + 2 * chevronPulse, centerY - 15)
            entry.chevronLeft.Size = UDim2.fromOffset(20, 30)
            entry.chevronRight.Size = UDim2.fromOffset(20, 30)

            local showName = flag("Universal ESP Nametag", true)
            local textSize = clamp(numberFlag("Universal ESP Nametag Size", 13), 10, 18)
            local detailsRequested = flag("Universal ESP Distance", true)
                or flag("Universal ESP Tool", false)
                or flag("Universal ESP Show Username", false)
            local detailsVisible = detailsRequested and not compact
            local pillHeight = detailsVisible and 30 or 20
            local pillWidth
            if compact then
                pillWidth = clamp(math.max(width + 8, 92), 88, 152)
            else
                pillWidth = clamp(math.max(width + 14, isTarget and 148 or 112), 100, 214)
            end

            local pillX = centerX - pillWidth * 0.5
            local pillY = topLeft.Y - pillHeight - (compact and 3 or 6)
            local labelX, labelY, labelClaimed = pillX, pillY, false
            if showName then
                labelX, labelY, labelClaimed = claimNametag(
                    labelLayout,
                    pillX,
                    pillY,
                    pillWidth,
                    pillHeight,
                    isTarget,
                    compact
                )
            end
            local nameVisible = showName and labelClaimed
            entry.namePill.Visible = nameVisible
            entry.namePill.Position = UDim2.fromOffset(labelX, labelY)
            entry.namePill.Size = UDim2.fromOffset(pillWidth, pillHeight)
            entry.namePill.BackgroundTransparency = compact
                and clamp(0.34 + fade * 0.48, 0.3, 0.92)
                or clamp(0.14 + fade * 0.58 + (lineOfSight and 0 or 0.08), 0.12, 0.9)
            entry.nameStroke.Color = displayColor
            entry.nameStroke.Thickness = isTarget and 1.5 or 1
            entry.nameStroke.Transparency = compact
                and clamp(0.45 + fade * 0.42, 0.42, 0.94)
                or clamp(0.22 + fade * 0.54, 0.16, 0.88)
            entry.statusDot.Visible = nameVisible and not compact
            entry.statusDot.Position = UDim2.fromOffset(10, detailsVisible and 10 or pillHeight * 0.5)
            entry.statusDot.BackgroundColor3 = lineOfSight and Color3.fromRGB(90, 235, 155) or Color3.fromRGB(255, 177, 72)
            entry.nameLabel.Position = UDim2.fromOffset(compact and 7 or 19, 1)
            entry.nameLabel.Size = UDim2.new(1, isTarget and -66 or (compact and -12 or -24), 0, detailsVisible and 16 or pillHeight - 2)
            entry.nameLabel.TextSize = compact and math.max(10, textSize - 2) or textSize
            entry.nameLabel.TextColor3 = isTarget and displayColor or WHITE
            entry.nameLabel.TextTransparency = 1 - opacity
            entry.detailLabel.Visible = nameVisible and detailsVisible
            entry.detailLabel.Position = UDim2.fromOffset(19, 15)
            entry.detailLabel.Size = UDim2.new(1, -24, 0, 13)
            entry.detailLabel.TextSize = math.max(9, textSize - 4)
            entry.detailLabel.TextTransparency = clamp(1 - opacity + 0.12, 0, 1)
            entry.targetBadge.Position = UDim2.new(1, -7, 0, detailsVisible and 10 or pillHeight * 0.5)
            entry.targetBadge.Size = UDim2.fromOffset(40, 14)
            entry.targetBadge.TextColor3 = displayColor
            entry.targetBadge.TextTransparency = 1 - opacity

            local maximumHealth = math.max(1, humanoid.MaxHealth)
            local healthRatio = clamp(humanoid.Health / maximumHealth, 0, 1)
            entry.displayedHealth = damp(entry.displayedHealth, healthRatio, 13, deltaTime)
            local showHealth = flag("Universal ESP Health", true)
            local healthHeight = clamp(height * (compact and 0.72 or 0.84), 18, 320)
            local healthSide = ctx.library.flags["Universal ESP Health Side"] == "Right" and "Right" or "Left"
            local barX = healthSide == "Right" and bottomRight.X + 6 or topLeft.X - 9
            local barY = centerY - healthHeight * 0.5
            local meaningfulHealth = healthRatio <= 0.58
            local healthVisible = showHealth and (not compact or isTarget or meaningfulHealth)
            entry.healthBackground.Visible = healthVisible
            entry.healthBackground.Position = UDim2.fromOffset(barX, barY)
            entry.healthBackground.Size = UDim2.fromOffset(compact and 2 or 3, healthHeight)
            entry.healthBackground.BackgroundTransparency = clamp(0.04 + fade * 0.68, 0.04, 0.92)
            entry.healthStroke.Transparency = clamp(0.15 + fade * 0.58, 0.15, 0.9)
            entry.healthFill.Size = UDim2.new(1, 0, entry.displayedHealth, 0)
            entry.healthFill.BackgroundColor3 = Color3.fromHSV(clamp(entry.displayedHealth, 0, 1) * 0.34, 0.78, 1)
            entry.healthFill.BackgroundTransparency = 1 - opacity
            for index, tick in ipairs(entry.healthTicks) do
                tick.Visible = healthVisible and not compact and healthHeight >= 64
                tick.Position = UDim2.new(0, 0, index / 4, 0)
                tick.Size = UDim2.new(1, 0, 0, 1)
                tick.BackgroundTransparency = clamp(0.22 + fade * 0.6, 0.22, 0.9)
            end

            local showHealthNumber = healthVisible
                and flag("Universal ESP Health Number", true)
                and (not compact or isTarget)
                and height >= 42
            entry.healthText.Visible = showHealthNumber
            entry.healthText.TextColor3 = entry.healthFill.BackgroundColor3
            entry.healthText.TextTransparency = 1 - opacity
            entry.healthText.Position = UDim2.fromOffset(
                healthSide == "Right" and barX - 31 or barX + 7,
                barY + healthHeight * (1 - entry.displayedHealth) - 7
            )
            entry.healthText.Size = UDim2.fromOffset(28, 14)

            local showTracer = flag("Universal ESP Tracer", false)
            entry.tracer.Visible = showTracer
            if showTracer then
                local viewport = camera.ViewportSize
                local tracerFrom = ctx.library.flags["Universal ESP Tracer From"] or "Bottom"
                local origin
                if tracerFrom == "Center" then
                    origin = viewport * 0.5
                elseif tracerFrom == "Top" then
                    origin = Vector2.new(viewport.X * 0.5, 0)
                else
                    origin = Vector2.new(viewport.X * 0.5, viewport.Y)
                end
                entry.tracer.BackgroundColor3 = displayColor
                entry.tracer.BackgroundTransparency = clamp(1 - opacity * 0.72, 0.15, 0.92)
                setLine(entry.tracer, origin, Vector2.new(centerX, bottomRight.Y), lineThickness)
            end

            local showHeadDot = flag("Universal ESP Head Dot", false)
            local head = character:FindFirstChild("Head")
            entry.headDot.Visible = false
            if showHeadDot and head and head:IsA("BasePart") then
                local headPoint, headOnScreen = camera:WorldToViewportPoint(head.Position)
                if headOnScreen and headPoint.Z > 0 then
                    local radius = clamp(height * 0.032, 3, 8)
                    entry.headDot.Visible = true
                    entry.headDot.Position = UDim2.fromOffset(headPoint.X, headPoint.Y)
                    entry.headDot.Size = UDim2.fromOffset(radius * 2, radius * 2)
                    entry.headDot.BackgroundColor3 = displayColor
                    entry.headDot.BackgroundTransparency = 1 - opacity
                    entry.headStroke.Transparency = clamp(0.12 + fade * 0.6, 0.12, 0.9)
                end
            end

            updateSkeleton(
                entry,
                camera,
                isTarget and displayColor or skeletonColor,
                opacity * 0.92,
                lineThickness,
                flag("Universal ESP Skeleton", false)
            )

            entry.highlight.Enabled = flag("Universal ESP Highlights", false)
            entry.highlight.FillColor = displayColor
            entry.highlight.OutlineColor = displayColor
            entry.highlight.FillTransparency = clamp(0.92 + fade * 0.06, 0.9, 0.99)
            entry.highlight.OutlineTransparency = clamp(0.18 + fade * 0.68 + (lineOfSight and 0 or 0.08), 0.12, 0.96)

            updateText(entry, distance, humanoid, isTarget, lineOfSight, compact)
        end

        local function buildCandidateList(camera)
            local localRoot = ctx.getRoot()
            local maxDistance = math.max(50, numberFlag("Universal ESP Max Distance", 800))
            local enabled = flag("Universal ESP", false)
            local targetTeamCheck, targetMaxDistance, targetColor = getTargetSettings(maxDistance)
            local candidates = {}

            for _, player in ipairs(ctx.Players:GetPlayers()) do
                if player ~= ctx.LocalPlayer then
                    local character = player.Character
                    local humanoid = ctx.getHumanoid(character)
                    local rootPart = ctx.getRoot(character)
                    local entry = ctx.state.esp[player]

                    if character and humanoid and rootPart and humanoid.Health > 0 then
                        if not entry or entry.character ~= character or entry.rootPart ~= rootPart then
                            entry = createEntry(player, character)
                        end

                        if entry then
                            local distance = localRoot and (localRoot.Position - rootPart.Position).Magnitude or math.huge
                            local isTarget = ctx.state.aimTarget == player
                            local espSameTeam = flag("Universal ESP Team Check", false)
                                and ctx.LocalPlayer.Team ~= nil
                                and player.Team == ctx.LocalPlayer.Team
                            local targetSameTeam = targetTeamCheck
                                and ctx.LocalPlayer.Team ~= nil
                                and player.Team == ctx.LocalPlayer.Team
                            local visibleForESP = enabled and not espSameTeam and distance <= maxDistance
                            local visibleForTarget = isTarget and not targetSameTeam and distance <= targetMaxDistance

                            if visibleForESP or visibleForTarget then
                                table.insert(candidates, {
                                    player = player,
                                    character = character,
                                    humanoid = humanoid,
                                    rootPart = rootPart,
                                    entry = entry,
                                    distance = distance,
                                    isTarget = isTarget,
                                    targetColor = targetColor,
                                })
                            else
                                hideEntry(entry)
                            end
                        end
                    elseif entry then
                        destroyEntry(player)
                    end
                end
            end

            table.sort(candidates, function(a, b)
                if a.isTarget ~= b.isTarget then
                    return a.isTarget
                end
                return a.distance < b.distance
            end)

            local maximumPlayers = clamp(math.floor(numberFlag("Universal ESP Max Players", 24)), 4, 50)
            for index = maximumPlayers + 1, #candidates do
                hideEntry(candidates[index].entry)
            end

            return candidates, math.min(#candidates, maximumPlayers), maxDistance
        end

        local function render(deltaTime)
            if ctx.state.unloading then
                return
            end

            local camera = ctx.Workspace.CurrentCamera
            if not camera then
                return
            end

            local candidates, visibleCount, maxDistance = buildCandidateList(camera)
            local fadeStart = clamp(numberFlag("Universal ESP Fade Start", 300), 0, math.max(0, maxDistance - 1))
            local baseColor = colorFlag("Universal ESP Color", DEFAULT_ACCENT)
            local friendlyColor = colorFlag("Universal ESP Friendly Color", DEFAULT_FRIENDLY)
            local skeletonColor = colorFlag("Universal ESP Skeleton Color", Color3.fromRGB(0, 210, 255))
            local maximumPlayers = clamp(math.floor(numberFlag("Universal ESP Max Players", 24)), 4, 50)
            local labelLayout = {
                enabled = flag("Universal ESP Clutter Control", true),
                occupied = {},
                count = 0,
                hidden = 0,
                maximum = clamp(math.floor(numberFlag("Universal ESP Max Nametags", 12)), 4, 30),
            }

            for index = 1, math.min(visibleCount, maximumPlayers) do
                local candidate = candidates[index]
                local ok = pcall(function()
                    updateEntry(
                        candidate.entry,
                        candidate,
                        camera,
                        deltaTime,
                        baseColor,
                        friendlyColor,
                        skeletonColor,
                        maxDistance,
                        fadeStart,
                        labelLayout,
                        index
                    )
                end)
                if not ok then
                    hideEntry(candidate.entry)
                end
            end

            statusAccumulator += deltaTime
            if statusAccumulator >= 0.35 then
                statusAccumulator = 0
                rendererStatus.Text = string.format(
                    "Renderer: layered | %d visible | %d labels%s",
                    visibleCount,
                    labelLayout.count,
                    labelLayout.hidden > 0 and (" | " .. tostring(labelLayout.hidden) .. " decluttered") or ""
                )
            end
        end

        -- Compact live preview --------------------------------------------------

        local preview = {}

        local function buildPreview()
            local section = ctx.refs.espPreviewSection
            if previewHost or not section or not section.content then
                return
            end

            previewHost = Instance.new("Frame")
            previewHost.Name = "SignatureESPPreview"
            previewHost.Size = UDim2.new(1, -8, 0, 224)
            previewHost.BackgroundColor3 = DARK
            previewHost.BorderSizePixel = 0
            previewHost.Parent = section.content
            addCorner(previewHost, 9)
            preview.panelStroke = addStroke(previewHost, DEFAULT_ACCENT, 1, 0.45)

            local grid = Instance.new("UIGradient")
            grid.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 14, 22)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 21, 31)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 11, 18)),
            })
            grid.Rotation = 90
            grid.Parent = previewHost

            preview.header = newText(previewHost, "Header", 3)
            preview.header.Position = UDim2.fromOffset(12, 8)
            preview.header.Size = UDim2.new(1, -24, 0, 18)
            preview.header.Text = "XANHUB SIGNATURE ESP"
            preview.header.TextSize = 10
            preview.header.TextColor3 = MUTED
            preview.header.TextXAlignment = Enum.TextXAlignment.Left
            preview.header.TextStrokeTransparency = 1
            preview.header.Visible = true

            preview.box = newFrame(previewHost, "PreviewBox", 3)
            preview.box.Position = UDim2.fromOffset(76, 44)
            preview.box.Size = UDim2.fromOffset(108, 150)
            preview.box.BackgroundColor3 = DEFAULT_ACCENT
            preview.box.BackgroundTransparency = 0.88
            preview.boxStroke = addStroke(preview.box, DEFAULT_ACCENT, 2, 0.1)
            addCorner(preview.box, 3)

            preview.glow = newFrame(previewHost, "PreviewGlow", 2)
            preview.glow.Position = UDim2.fromOffset(73, 41)
            preview.glow.Size = UDim2.fromOffset(114, 156)
            preview.glow.BackgroundTransparency = 1
            preview.glowStroke = addStroke(preview.glow, DEFAULT_ACCENT, 5, 0.78)
            addCorner(preview.glow, 4)

            preview.corners = {}
            for index = 1, 8 do
                preview.corners[index] = createCornerLine(previewHost, index)
            end

            preview.scanline = newFrame(previewHost, "PreviewScanline", 5)
            preview.scanline.Size = UDim2.fromOffset(100, 1)
            preview.scanline.BackgroundColor3 = DEFAULT_ACCENT
            preview.scanline.BackgroundTransparency = 0.25

            preview.namePill = newFrame(previewHost, "PreviewName", 6)
            preview.namePill.Position = UDim2.fromOffset(59, 14)
            preview.namePill.Size = UDim2.fromOffset(142, 30)
            preview.namePill.BackgroundColor3 = DARK_SOFT
            preview.namePill.BackgroundTransparency = 0.04
            preview.nameStroke = addStroke(preview.namePill, DEFAULT_ACCENT, 1, 0.24)
            addCorner(preview.namePill, 6)

            preview.name = newText(preview.namePill, "Name", 7)
            preview.name.Position = UDim2.fromOffset(10, 2)
            preview.name.Size = UDim2.new(1, -16, 0, 14)
            preview.name.Text = "xanparty"
            preview.name.TextSize = 12
            preview.name.TextXAlignment = Enum.TextXAlignment.Left
            preview.name.TextStrokeTransparency = 1
            preview.name.Visible = true

            preview.details = newText(preview.namePill, "Details", 7)
            preview.details.Position = UDim2.fromOffset(10, 15)
            preview.details.Size = UDim2.new(1, -16, 0, 12)
            preview.details.Text = "64m  •  Tool"
            preview.details.TextSize = 9
            preview.details.TextColor3 = MUTED
            preview.details.TextXAlignment = Enum.TextXAlignment.Left
            preview.details.TextStrokeTransparency = 1
            preview.details.Visible = true

            preview.healthBg = newFrame(previewHost, "PreviewHealth", 6)
            preview.healthBg.Position = UDim2.fromOffset(67, 58)
            preview.healthBg.Size = UDim2.fromOffset(4, 120)
            preview.healthBg.BackgroundColor3 = Color3.fromRGB(22, 27, 36)
            preview.healthBg.BackgroundTransparency = 0.02
            preview.healthBg.Visible = true
            addCorner(preview.healthBg, 3)

            preview.healthFill = newFrame(preview.healthBg, "Fill", 7)
            preview.healthFill.AnchorPoint = Vector2.new(0, 1)
            preview.healthFill.Position = UDim2.fromScale(0, 1)
            preview.healthFill.Size = UDim2.new(1, 0, 0.72, 0)
            preview.healthFill.BackgroundColor3 = Color3.fromRGB(118, 235, 105)
            preview.healthFill.BackgroundTransparency = 0
            preview.healthFill.Visible = true
            addCorner(preview.healthFill, 3)

            preview.chevronLeft = newText(previewHost, "LeftChevron", 8)
            preview.chevronLeft.Position = UDim2.fromOffset(44, 100)
            preview.chevronLeft.Size = UDim2.fromOffset(24, 32)
            preview.chevronLeft.Text = "›"
            preview.chevronLeft.TextSize = 26
            preview.chevronLeft.Visible = true

            preview.chevronRight = newText(previewHost, "RightChevron", 8)
            preview.chevronRight.Position = UDim2.fromOffset(191, 100)
            preview.chevronRight.Size = UDim2.fromOffset(24, 32)
            preview.chevronRight.Text = "‹"
            preview.chevronRight.TextSize = 26
            preview.chevronRight.Visible = true
        end

        local function updatePreview()
            if not previewHost then
                return
            end

            local color = colorFlag("Universal ESP Color", DEFAULT_ACCENT)
            if flag("Universal ESP Chroma", false) then
                color = Color3.fromHSV((os.clock() * 0.12) % 1, 0.82, 1)
            end

            local style = ctx.library.flags["Universal ESP Box Style"] or "Signature"
            local showBox = flag("Universal ESP Box", true) and style ~= "Minimal"
            local showFull = showBox and (style == "Signature" or style == "Full" or style == "Double")
            local showCorners = showBox and (style == "Signature" or style == "Corners" or style == "Double")
            local pulse = flag("Universal ESP Pulse", true) and (0.76 + math.abs(math.sin(os.clock() * 3)) * 0.24) or 1
            local thickness = clamp(numberFlag("Universal ESP Box Thickness", 2), 1, 4)
            local fillOpacity = clamp(numberFlag("Universal ESP Fill Opacity", 12) / 100, 0, 0.55)
            local glowStrength = clamp(numberFlag("Universal ESP Glow Strength", 52) / 100, 0, 1)

            preview.panelStroke.Color = color
            local showFill = showBox and flag("Universal ESP Box Fill", true)
            preview.box.Visible = showFull or showFill
            preview.box.BackgroundColor3 = color
            preview.box.BackgroundTransparency = showFill and 1 - fillOpacity or 1
            preview.boxStroke.Color = color
            preview.boxStroke.Thickness = thickness
            preview.boxStroke.Transparency = showFull and 1 - pulse or 1
            preview.glow.Visible = showBox and glowStrength > 0
            preview.glowStroke.Color = color
            preview.glowStroke.Thickness = 3 + glowStrength * 4
            preview.glowStroke.Transparency = clamp(0.96 - glowStrength * pulse * 0.5, 0.44, 0.96)
            preview.nameStroke.Color = color
            preview.name.TextColor3 = color
            preview.chevronLeft.TextColor3 = color
            preview.chevronRight.TextColor3 = color
            preview.chevronLeft.Visible = flag("Universal ESP Target Chevron", true)
            preview.chevronRight.Visible = flag("Universal ESP Target Chevron", true)
            preview.healthBg.Visible = flag("Universal ESP Health", true)
            preview.healthFill.Visible = preview.healthBg.Visible
            preview.namePill.Visible = flag("Universal ESP Nametag", true)
            local previewDetails = {}
            if flag("Universal ESP Distance", true) then
                table.insert(previewDetails, "64m")
            end
            if flag("Universal ESP Tool", true) then
                table.insert(previewDetails, "Tool")
            end
            preview.details.Text = table.concat(previewDetails, "  •  ")
            preview.name.TextSize = clamp(numberFlag("Universal ESP Nametag Size", 13), 10, 18)

            local topLeft = Vector2.new(76, 44)
            local bottomRight = Vector2.new(184, 194)
            layoutCorners(preview, topLeft, bottomRight, color, pulse, thickness, numberFlag("Universal ESP Corner Length", 25), showCorners)

            preview.scanline.Visible = showBox and style == "Signature" and flag("Universal ESP Scanline", true)
            if preview.scanline.Visible then
                local progress = (os.clock() * 0.62) % 1
                preview.scanline.Position = UDim2.fromOffset(80, 48 + 142 * progress)
                preview.scanline.Size = UDim2.fromOffset(100, 1)
                preview.scanline.BackgroundColor3 = color
            end
        end

        renderConnection = ctx.addConnection(ctx.RunService.RenderStepped, function(deltaTime)
            renderAccumulator += deltaTime

            local refreshRate = clamp(numberFlag("Universal ESP Refresh Rate", 60), 20, 120)
            if flag("Universal ESP Adaptive", true) then
                local playerCount = math.max(0, #ctx.Players:GetPlayers() - 1)
                if playerCount >= 28 then
                    refreshRate = math.min(refreshRate, 30)
                elseif playerCount >= 16 then
                    refreshRate = math.min(refreshRate, 45)
                end
            end

            local interval = 1 / refreshRate
            if renderAccumulator >= interval then
                local elapsed = renderAccumulator
                renderAccumulator = 0
                render(elapsed)
            end
        end)

        playerRemovingConnection = ctx.addConnection(ctx.Players.PlayerRemoving, destroyEntry)

        previewConnection = ctx.addConnection(ctx.RunService.Heartbeat, function()
            if not previewHost then
                buildPreview()
            end
            updatePreview()
        end)

        local control = ctx.option("Universal ESP")
        if control then
            local previousCallback = control.callback
            control.callback = function(enabled)
                if type(previousCallback) == "function" then
                    pcall(previousCallback, enabled)
                end
                if not enabled then
                    for _, entry in pairs(ctx.state.esp) do
                        hideEntry(entry)
                    end
                end
            end
        end

        ctx.library:AddCleanup(function()
            ctx.disconnect(renderConnection)
            ctx.disconnect(playerRemovingConnection)
            ctx.disconnect(previewConnection)

            safeDestroy(previewHost)

            local players = {}
            for player in pairs(ctx.state.esp) do
                table.insert(players, player)
            end
            for _, player in ipairs(players) do
                destroyEntry(player)
            end

            safeDestroy(geometryLayer)
            safeDestroy(labelLayer)
            safeDestroy(offscreenLayer)
        end)
    end

    return {setup = setupESPRuntime}
end
