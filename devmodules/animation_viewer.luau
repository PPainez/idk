--[[
    xanhub | devmodules | animation viewer

    Advanced, isolated ViewportFrame animation player for developer timing work.
    It never plays the preview track on the live character.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub animation viewer] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub animation viewer] dev_shared missing")
    local section = dev.right:AddSection("Animation Viewer")

    section:AddLabel("Viewport-only playback with timeline, markers, frame stepping, and camera orbit")
    section:AddButton({
        text = "Open Animation Viewer",
        callback = function()
            shared.invokeApi("animationViewer", "Open")
        end,
    })

    section:AddList({
        text = "Default Rig",
        flag = "Dev Animation Viewer Rig",
        values = {"Source Model", "Local Character", "R15 Dummy", "R6 Dummy"},
        value = "Source Model",
    })
    section:AddToggle({text = "Loop Preview", flag = "Dev Animation Viewer Loop", state = true})
    section:AddSlider({
        text = "Default Speed",
        flag = "Dev Animation Viewer Speed",
        min = 0.1,
        max = 3,
        value = 1,
        float = 0.1,
        suffix = "x",
    })

    local state = {
        window = nil,
        viewport = nil,
        world = nil,
        camera = nil,
        model = nil,
        animation = nil,
        track = nil,
        id = nil,
        sourceModel = nil,
        sourceEntry = nil,
        paused = false,
        draggingTimeline = false,
        draggingCamera = false,
        dragStart = nil,
        yaw = math.rad(35),
        pitch = math.rad(-8),
        distance = 9,
        target = Vector3.new(0, 2.3, 0),
        markerRows = {},
        markers = {},
        connections = {},
        useTimeCallback = nil,
    }

    local function connect(signal, callback)
        local connection = shared.connect(signal, callback)
        table.insert(state.connections, connection)
        return connection
    end

    local function disconnectLocal()
        for _, connection in ipairs(state.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        state.connections = {}
    end

    local function normalizeId(value)
        local id = tostring(value or ""):match("%d+")
        return id
    end

    local function sanitizeClone(model)
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("Script") or object:IsA("LocalScript") or object:IsA("ModuleScript")
                or object:IsA("Tool") or object:IsA("ForceField") then
                shared.safeDestroy(object)
            elseif object:IsA("BasePart") then
                object.Anchored = false
                object.CanCollide = false
                object.CanTouch = false
                object.CanQuery = false
                object.CastShadow = false
            end
        end
    end

    local function makePart(parent, name, size, cframe, color)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.CFrame = cframe
        part.Color = color
        part.Material = Enum.Material.SmoothPlastic
        part.Anchored = false
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Parent = parent
        return part
    end

    local function motor(parent, name, part0, part1, c0, c1)
        local joint = Instance.new("Motor6D")
        joint.Name = name
        joint.Part0 = part0
        joint.Part1 = part1
        joint.C0 = c0 or CFrame.new()
        joint.C1 = c1 or CFrame.new()
        joint.Parent = parent
        return joint
    end

    local function createDummy(rigType)
        local model = Instance.new("Model")
        model.Name = rigType .. "PreviewRig"
        local skin = Color3.fromRGB(235, 188, 150)
        local shirt = Color3.fromRGB(24, 132, 210)
        local pants = Color3.fromRGB(62, 75, 105)

        if rigType == "R6" then
            local root = makePart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 2, 0), Color3.new(0, 0, 0))
            root.Transparency = 1
            local torso = makePart(model, "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 2, 0), shirt)
            local head = makePart(model, "Head", Vector3.new(2, 1, 1), CFrame.new(0, 3.5, 0), skin)
            local la = makePart(model, "Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 2, 0), skin)
            local ra = makePart(model, "Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 2, 0), skin)
            local ll = makePart(model, "Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 0, 0), pants)
            local rl = makePart(model, "Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 0, 0), pants)
            motor(root, "RootJoint", root, torso)
            motor(torso, "Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
            motor(torso, "Left Shoulder", torso, la, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
            motor(torso, "Right Shoulder", torso, ra, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
            motor(torso, "Left Hip", torso, ll, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))
            motor(torso, "Right Hip", torso, rl, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))
            model.PrimaryPart = root
        else
            local root = makePart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 2.6, 0), Color3.new(0, 0, 0))
            root.Transparency = 1
            local lower = makePart(model, "LowerTorso", Vector3.new(2, 1, 1), CFrame.new(0, 2.1, 0), shirt)
            local upper = makePart(model, "UpperTorso", Vector3.new(2, 1.6, 1), CFrame.new(0, 3.35, 0), shirt)
            local head = makePart(model, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.9, 0), skin)
            local lua = makePart(model, "LeftUpperArm", Vector3.new(0.75, 1.4, 0.75), CFrame.new(-1.4, 3.5, 0), skin)
            local lla = makePart(model, "LeftLowerArm", Vector3.new(0.65, 1.3, 0.65), CFrame.new(-1.4, 2.15, 0), skin)
            local lhand = makePart(model, "LeftHand", Vector3.new(0.6, 0.55, 0.65), CFrame.new(-1.4, 1.25, 0), skin)
            local rua = makePart(model, "RightUpperArm", Vector3.new(0.75, 1.4, 0.75), CFrame.new(1.4, 3.5, 0), skin)
            local rla = makePart(model, "RightLowerArm", Vector3.new(0.65, 1.3, 0.65), CFrame.new(1.4, 2.15, 0), skin)
            local rhand = makePart(model, "RightHand", Vector3.new(0.6, 0.55, 0.65), CFrame.new(1.4, 1.25, 0), skin)
            local lul = makePart(model, "LeftUpperLeg", Vector3.new(0.85, 1.5, 0.85), CFrame.new(-0.5, 0.9, 0), pants)
            local lll = makePart(model, "LeftLowerLeg", Vector3.new(0.75, 1.4, 0.75), CFrame.new(-0.5, -0.55, 0), pants)
            local lfoot = makePart(model, "LeftFoot", Vector3.new(0.8, 0.5, 1.1), CFrame.new(-0.5, -1.55, -0.12), pants)
            local rul = makePart(model, "RightUpperLeg", Vector3.new(0.85, 1.5, 0.85), CFrame.new(0.5, 0.9, 0), pants)
            local rll = makePart(model, "RightLowerLeg", Vector3.new(0.75, 1.4, 0.75), CFrame.new(0.5, -0.55, 0), pants)
            local rfoot = makePart(model, "RightFoot", Vector3.new(0.8, 0.5, 1.1), CFrame.new(0.5, -1.55, -0.12), pants)
            motor(root, "Root", root, lower)
            motor(lower, "Waist", lower, upper, CFrame.new(0, 0.5, 0), CFrame.new(0, -0.8, 0))
            motor(upper, "Neck", upper, head, CFrame.new(0, 0.8, 0), CFrame.new(0, -0.6, 0))
            motor(upper, "LeftShoulder", upper, lua, CFrame.new(-1, 0.45, 0), CFrame.new(0, 0.7, 0))
            motor(lua, "LeftElbow", lua, lla, CFrame.new(0, -0.7, 0), CFrame.new(0, 0.65, 0))
            motor(lla, "LeftWrist", lla, lhand, CFrame.new(0, -0.65, 0), CFrame.new(0, 0.3, 0))
            motor(upper, "RightShoulder", upper, rua, CFrame.new(1, 0.45, 0), CFrame.new(0, 0.7, 0))
            motor(rua, "RightElbow", rua, rla, CFrame.new(0, -0.7, 0), CFrame.new(0, 0.65, 0))
            motor(rla, "RightWrist", rla, rhand, CFrame.new(0, -0.65, 0), CFrame.new(0, 0.3, 0))
            motor(lower, "LeftHip", lower, lul, CFrame.new(-0.5, -0.5, 0), CFrame.new(0, 0.75, 0))
            motor(lul, "LeftKnee", lul, lll, CFrame.new(0, -0.75, 0), CFrame.new(0, 0.7, 0))
            motor(lll, "LeftAnkle", lll, lfoot, CFrame.new(0, -0.7, 0), CFrame.new(0, 0.25, 0.12))
            motor(lower, "RightHip", lower, rul, CFrame.new(0.5, -0.5, 0), CFrame.new(0, 0.75, 0))
            motor(rul, "RightKnee", rul, rll, CFrame.new(0, -0.75, 0), CFrame.new(0, 0.7, 0))
            motor(rll, "RightAnkle", rll, rfoot, CFrame.new(0, -0.7, 0), CFrame.new(0, 0.25, 0.12))
            model.PrimaryPart = root
        end

        local humanoid = Instance.new("Humanoid")
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        humanoid.Parent = model
        return model
    end

    local function destroyPreview()
        if state.track then
            pcall(function()
                state.track:Stop(0)
            end)
        end
        shared.safeDestroy(state.animation)
        shared.safeDestroy(state.model)
        state.track = nil
        state.animation = nil
        state.model = nil
        state.id = nil
    end

    local function chooseSourceModel(entry)
        local mode = ctx.library.flags["Dev Animation Viewer Rig"] or "Source Model"
        if mode == "Source Model" and entry and typeof(entry.sourceModel) == "Instance" and entry.sourceModel:IsA("Model") then
            return entry.sourceModel
        elseif mode == "Local Character" and ctx.LocalPlayer and ctx.LocalPlayer.Character then
            return ctx.LocalPlayer.Character
        elseif mode == "R6 Dummy" then
            return createDummy("R6")
        elseif mode == "R15 Dummy" then
            return createDummy("R15")
        end
        if ctx.LocalPlayer and ctx.LocalPlayer.Character then
            return ctx.LocalPlayer.Character
        end
        return createDummy("R15")
    end

    local function cloneSource(entry)
        local source = chooseSourceModel(entry)
        if not source then
            return nil
        end
        if source.Parent == nil and string.find(source.Name, "PreviewRig", 1, true) then
            return source
        end
        local oldArchivable = source.Archivable
        source.Archivable = true
        local ok, clone = pcall(function()
            return source:Clone()
        end)
        source.Archivable = oldArchivable
        if not ok then
            return nil
        end
        return clone
    end

    local function animatorFor(model)
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
            animator.Parent = humanoid
            return animator
        end
        local controller = model:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
        controller.Parent = model
        local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
        animator.Parent = controller
        return animator
    end

    local function fitCamera()
        if not state.model or not state.camera then
            return
        end
        local ok, cframe, size = pcall(function()
            return state.model:GetBoundingBox()
        end)
        if not ok then
            return
        end
        state.target = cframe.Position + Vector3.new(0, size.Y * 0.06, 0)
        state.distance = math.clamp(math.max(size.X, size.Y, size.Z) * 1.65, 5, 24)
    end

    local function updateCamera()
        if not state.camera then
            return
        end
        local cp = math.cos(state.pitch)
        local direction = Vector3.new(
            math.sin(state.yaw) * cp,
            math.sin(state.pitch),
            math.cos(state.yaw) * cp
        )
        state.camera.CFrame = CFrame.lookAt(state.target + direction * state.distance, state.target)
    end

    local ui = {}

    local function clearMarkers()
        state.markers = {}
        for _, row in ipairs(state.markerRows) do
            shared.safeDestroy(row)
        end
        state.markerRows = {}
    end

    local function populateMarkers(id)
        clearMarkers()
        if not ui.markerList then
            return
        end
        task.spawn(function()
            local provider = game:GetService("KeyframeSequenceProvider")
            local ok, sequence = pcall(function()
                return provider:GetKeyframeSequenceAsync("rbxassetid://" .. id)
            end)
            if not ok or not sequence then
                return
            end
            local markers = {}
            for _, keyframe in ipairs(sequence:GetKeyframes()) do
                table.insert(markers, {name = keyframe.Name, time = keyframe.Time})
                for _, marker in ipairs(keyframe:GetMarkers()) do
                    table.insert(markers, {name = marker.Name, time = keyframe.Time, value = marker.Value})
                end
            end
            table.sort(markers, function(a, b)
                return a.time < b.time
            end)
            state.markers = markers
            for _, marker in ipairs(markers) do
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 24),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.1,
                    BorderSizePixel = 0,
                    Text = string.format("%6.3f  %s", marker.time, marker.name),
                    TextColor3 = shared.theme.text,
                    TextSize = 11,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = ui.markerList,
                })
                shared.round(row, 4)
                local pad = Instance.new("UIPadding")
                pad.PaddingLeft = UDim.new(0, 6)
                pad.Parent = row
                connect(row.MouseButton1Click, function()
                    if state.track then
                        state.track.TimePosition = math.clamp(marker.time, 0, state.track.Length)
                    end
                end)
                table.insert(state.markerRows, row)
            end
            shared.safeDestroy(sequence)
        end)
    end

    local function updateStatus()
        if not ui.status then
            return
        end
        if not state.track then
            ui.status.Text = "No animation loaded"
            ui.time.Text = "0.000 / 0.000"
            return
        end
        local length = math.max(0, state.track.Length)
        local time = math.clamp(state.track.TimePosition, 0, math.max(length, 0))
        ui.status.Text = string.format("ID %s  |  %s  |  %.2fx", tostring(state.id), state.paused and "PAUSED" or "PLAYING", tonumber(ctx.library.flags["Dev Animation Viewer Speed"]) or 1)
        ui.time.Text = string.format("%.3f / %.3f", time, length)
        if ui.timelineFill and not state.draggingTimeline then
            local ratio = length > 0 and time / length or 0
            ui.timelineFill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
            ui.timelineKnob.Position = UDim2.new(math.clamp(ratio, 0, 1), 0, 0.5, 0)
        end
    end

    local function setPaused(paused)
        state.paused = paused == true
        if state.track then
            if state.paused then
                state.track:AdjustSpeed(0)
            else
                state.track:AdjustSpeed(tonumber(ctx.library.flags["Dev Animation Viewer Speed"]) or 1)
            end
        end
        if ui.play then
            ui.play.Text = state.paused and "Play" or "Pause"
        end
        updateStatus()
    end

    local function loadAnimation(value, entry)
        local id = normalizeId(value)
        if not id then
            shared.notify("Invalid animation ID", 3)
            return false
        end

        destroyPreview()
        clearMarkers()
        local model = cloneSource(entry)
        if not model then
            shared.notify("Could not clone a preview rig", 4)
            return false
        end
        sanitizeClone(model)
        model.Name = "xanhub_animation_preview"
        model:PivotTo(CFrame.new(0, 0, 0))
        model.Parent = state.world

        local animator = animatorFor(model)
        local animation = Instance.new("Animation")
        animation.AnimationId = "rbxassetid://" .. id
        local ok, track = pcall(function()
            return animator:LoadAnimation(animation)
        end)
        if not ok or not track then
            shared.safeDestroy(animation)
            shared.safeDestroy(model)
            shared.notify("Animation failed to load: " .. tostring(track), 4)
            return false
        end

        state.model = model
        state.animation = animation
        state.track = track
        state.id = id
        state.sourceEntry = entry
        state.paused = false
        track.Looped = ctx.library.flags["Dev Animation Viewer Loop"] ~= false
        track:Play(0)
        track:AdjustSpeed(tonumber(ctx.library.flags["Dev Animation Viewer Speed"]) or 1)
        fitCamera()
        updateCamera()
        populateMarkers(id)
        if ui.idBox then
            ui.idBox.Text = id
        end
        if ui.play then
            ui.play.Text = "Pause"
        end
        updateStatus()
        shared.notify("Animation " .. id .. " loaded", 2)
        return true
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then
            return state.window
        end
        state.window = shared.makeWindow("Animation Viewer", 860, 540)
        local content = state.window.content

        local left = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(0.65, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(left, 8)
        shared.stroke(left, shared.theme.border, 0.25, 1)

        state.viewport = shared.create("ViewportFrame", {
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.new(1, -16, 1, -86),
            BackgroundColor3 = Color3.fromRGB(10, 14, 22),
            BorderSizePixel = 0,
            Ambient = Color3.fromRGB(175, 185, 210),
            LightColor = Color3.fromRGB(255, 247, 235),
            LightDirection = Vector3.new(-1, -1, -1),
            Parent = left,
        })
        shared.round(state.viewport, 7)

        state.world = Instance.new("WorldModel")
        state.world.Parent = state.viewport
        state.camera = Instance.new("Camera")
        state.camera.FieldOfView = 42
        state.camera.Parent = state.viewport
        state.viewport.CurrentCamera = state.camera

        local timeline = shared.create("Frame", {
            Position = UDim2.new(0, 12, 1, -64),
            Size = UDim2.new(1, -24, 0, 12),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Active = true,
            Parent = left,
        })
        shared.round(timeline, 999)
        ui.timeline = timeline
        ui.timelineFill = shared.create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = shared.accent(),
            BorderSizePixel = 0,
            Parent = timeline,
        })
        shared.round(ui.timelineFill, 999)
        ui.timelineKnob = shared.create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundColor3 = shared.theme.text,
            BorderSizePixel = 0,
            Parent = timeline,
        })
        shared.round(ui.timelineKnob, 999)
        shared.stroke(ui.timelineKnob, shared.accent(), 0, 2)

        ui.time = shared.create("TextLabel", {
            Position = UDim2.new(0, 12, 1, -42),
            Size = UDim2.new(0.5, -12, 0, 22),
            BackgroundTransparency = 1,
            Text = "0.000 / 0.000",
            TextColor3 = shared.theme.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = left,
        })
        ui.status = shared.create("TextLabel", {
            Position = UDim2.new(0.5, 0, 1, -42),
            Size = UDim2.new(0.5, -12, 0, 22),
            BackgroundTransparency = 1,
            Text = "No animation loaded",
            TextColor3 = shared.theme.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = left,
        })

        local right = shared.create("Frame", {
            Position = UDim2.new(0.65, 5, 0, 10),
            Size = UDim2.new(0.35, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(right, 8)
        shared.stroke(right, shared.theme.border, 0.25, 1)

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.Parent = right
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 7)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = right

        ui.idBox = shared.makeTextBox(right, "Animation ID", "")
        ui.idBox.LayoutOrder = 1

        local loadRow = shared.create("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 2, Parent = right})
        local rowLayout = Instance.new("UIListLayout")
        rowLayout.FillDirection = Enum.FillDirection.Horizontal
        rowLayout.Padding = UDim.new(0, 6)
        rowLayout.Parent = loadRow
        shared.makeButton(loadRow, "Load", function()
            loadAnimation(ui.idBox.Text, state.sourceEntry)
        end, 80)
        shared.makeButton(loadRow, "Copy ID", function()
            if state.id then shared.copy(state.id) end
        end, 82)
        shared.makeButton(loadRow, "Reset Cam", function()
            state.yaw = math.rad(35)
            state.pitch = math.rad(-8)
            fitCamera()
            updateCamera()
        end, 92)

        local playback = shared.create("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 3, Parent = right})
        local playbackLayout = Instance.new("UIListLayout")
        playbackLayout.FillDirection = Enum.FillDirection.Horizontal
        playbackLayout.Padding = UDim.new(0, 5)
        playbackLayout.Parent = playback
        shared.makeButton(playback, "-0.10", function()
            if state.track then state.track.TimePosition = math.max(0, state.track.TimePosition - 0.1) end
        end, 58)
        shared.makeButton(playback, "-1f", function()
            if state.track then state.track.TimePosition = math.max(0, state.track.TimePosition - 1 / 60) end
        end, 48)
        ui.play = shared.makeButton(playback, "Pause", function()
            setPaused(not state.paused)
        end, 64)
        shared.makeButton(playback, "+1f", function()
            if state.track then state.track.TimePosition = math.min(state.track.Length, state.track.TimePosition + 1 / 60) end
        end, 48)
        shared.makeButton(playback, "+0.10", function()
            if state.track then state.track.TimePosition = math.min(state.track.Length, state.track.TimePosition + 0.1) end
        end, 58)

        local actionRow = shared.create("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 4, Parent = right})
        local actionLayout = Instance.new("UIListLayout")
        actionLayout.FillDirection = Enum.FillDirection.Horizontal
        actionLayout.Padding = UDim.new(0, 6)
        actionLayout.Parent = actionRow
        shared.makeButton(actionRow, "Use Time", function()
            if state.track and type(state.useTimeCallback) == "function" then
                state.useTimeCallback(state.track.TimePosition, state.sourceEntry)
                shared.notify(string.format("Used %.3fs", state.track.TimePosition), 2)
            elseif state.track then
                shared.copy(string.format("%.3f", state.track.TimePosition))
            end
        end, 88)
        shared.makeButton(actionRow, "Restart", function()
            if state.track then
                state.track.TimePosition = 0
                if state.paused then setPaused(false) end
            end
        end, 80)
        shared.makeButton(actionRow, "Stop", function()
            if state.track then
                state.track:Stop(0)
                state.track.TimePosition = 0
                state.paused = true
                updateStatus()
            end
        end, 68)

        local markerTitle = shared.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = "KEYFRAMES / MARKERS",
            TextColor3 = shared.theme.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 5,
            Parent = right,
        })
        ui.markerList = shared.create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, -186),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            LayoutOrder = 6,
            Parent = right,
        })
        shared.round(ui.markerList, 6)
        local markerLayout = Instance.new("UIListLayout")
        markerLayout.Padding = UDim.new(0, 3)
        markerLayout.Parent = ui.markerList

        local function seekFromInput(input)
            if not state.track or state.track.Length <= 0 then
                return
            end
            local x = math.clamp(input.Position.X - timeline.AbsolutePosition.X, 0, timeline.AbsoluteSize.X)
            local ratio = timeline.AbsoluteSize.X > 0 and x / timeline.AbsoluteSize.X or 0
            state.track.TimePosition = ratio * state.track.Length
            ui.timelineFill.Size = UDim2.new(ratio, 0, 1, 0)
            ui.timelineKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
        end
        connect(timeline.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                state.draggingTimeline = true
                seekFromInput(input)
            end
        end)
        connect(game:GetService("UserInputService").InputChanged, function(input)
            if state.draggingTimeline and input.UserInputType == Enum.UserInputType.MouseMovement then
                seekFromInput(input)
            end
        end)
        connect(game:GetService("UserInputService").InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                state.draggingTimeline = false
                state.draggingCamera = false
            end
        end)

        connect(state.viewport.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                state.draggingCamera = true
                state.dragStart = input.Position
            end
        end)
        connect(game:GetService("UserInputService").InputChanged, function(input)
            if state.draggingCamera and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - state.dragStart
                state.dragStart = input.Position
                state.yaw = state.yaw - delta.X * 0.008
                state.pitch = math.clamp(state.pitch - delta.Y * 0.006, math.rad(-70), math.rad(45))
                updateCamera()
            elseif state.viewport and input.UserInputType == Enum.UserInputType.MouseWheel then
                local mouse = game:GetService("UserInputService"):GetMouseLocation()
                local pos = state.viewport.AbsolutePosition
                local size = state.viewport.AbsoluteSize
                if mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y then
                    state.distance = math.clamp(state.distance - input.Position.Z * 0.8, 3, 30)
                    updateCamera()
                end
            end
        end)

        connect(ctx.RunService.RenderStepped, function()
            if state.track then
                state.track.Looped = ctx.library.flags["Dev Animation Viewer Loop"] ~= false
                if not state.paused then
                    state.track:AdjustSpeed(tonumber(ctx.library.flags["Dev Animation Viewer Speed"]) or 1)
                end
            end
            updateStatus()
            updateCamera()
        end)

        return state.window
    end

    local api = {}
    function api:Open(entryOrId)
        local window = buildWindow()
        window:Show()
        if type(entryOrId) == "table" then
            state.sourceEntry = entryOrId
            state.sourceModel = entryOrId.sourceModel
            loadAnimation(entryOrId.id or entryOrId.animationId, entryOrId)
        elseif entryOrId ~= nil then
            loadAnimation(entryOrId, nil)
        end
    end
    function api:Load(id, entry)
        buildWindow()
        return loadAnimation(id, entry)
    end
    function api:SetTime(value)
        if state.track then
            state.track.TimePosition = math.clamp(tonumber(value) or 0, 0, state.track.Length)
        end
    end
    function api:GetTime()
        return state.track and state.track.TimePosition or 0
    end
    function api:SetUseTimeCallback(callback)
        state.useTimeCallback = callback
    end
    function api:GetState()
        return state
    end
    function api:Destroy()
        disconnectLocal()
        destroyPreview()
        clearMarkers()
        if state.window then state.window:Destroy() end
        state.window = nil
    end

    dev.apis.animationViewer = api
    local module = {name = "animation_viewer", setup = function() end, api = api}
    dev.modules.animation_viewer = module
    shared.addCleanup(function()
        api:Destroy()
    end)
    return module
end
