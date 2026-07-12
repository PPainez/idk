--[[
    xanhub | devmodules | animation logger

    Captures Animator.AnimationPlayed from players, NPCs, and self.
    Includes filtering, dedupe, blacklist, export, and viewer integration.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub animation logger] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub animation logger] dev_shared missing")
    local section = dev.left:AddSection("Animation Logger")

    section:AddToggle({text = "Enabled", flag = "Dev Animation Logger Enabled", state = false})
    section:AddToggle({text = "Limit Capture Range", flag = "Dev Animation Logger Range Limit", state = true})
    section:AddSlider({
        text = "Capture Range",
        flag = "Dev Animation Logger Range",
        min = 5,
        max = 1000,
        value = 150,
        float = 5,
        suffix = " studs",
    })
    section:AddList({
        text = "Source Filter",
        flag = "Dev Animation Logger Source",
        values = {"All", "Players", "NPCs", "Self"},
        value = "All",
    })
    section:AddSlider({
        text = "Dedupe Window",
        flag = "Dev Animation Logger Dedupe",
        min = 0,
        max = 10,
        value = 0.5,
        float = 0.1,
        suffix = "s",
    })
    section:AddSlider({
        text = "Maximum Entries",
        flag = "Dev Animation Logger Max Entries",
        min = 50,
        max = 1000,
        value = 300,
        float = 25,
    })
    section:AddButton({
        text = "Open Animation Logger",
        callback = function()
            shared.invokeApi("animationLogger", "Open")
        end,
    })
    section:AddButton({
        text = "Clear Animation Log",
        callback = function()
            shared.invokeApi("animationLogger", "Clear")
        end,
    })
    section:AddLabel("Captures Animator.AnimationPlayed without modifying tracks")

    local state = {
        entries = {},
        recent = {},
        blacklist = {},
        animatorConnections = setmetatable({}, {__mode = "k"}),
        trackConnections = setmetatable({}, {__mode = "k"}),
        selected = nil,
        window = nil,
        rows = {},
        dirty = true,
        entryEvent = Instance.new("BindableEvent"),
        scanConnection = nil,
        descendantConnection = nil,
        uiConnection = nil,
    }

    local ui = {}
    local persistenceFolder = "xanhub_dev"
    local persistencePath = persistenceFolder .. "/animation_logger.json"

    local function enabled()
        return ctx.library.flags["Dev Animation Logger Enabled"] == true
    end

    local function normalizeId(value)
        return tostring(value or ""):match("%d+")
    end

    local function sourceInfo(animator)
        local model = animator:FindFirstAncestorOfClass("Model")
        if not model then
            return nil, "Unknown", "Unknown"
        end
        local player = ctx.Players:GetPlayerFromCharacter(model)
        if player == ctx.LocalPlayer then
            return model, "Self", player.DisplayName or player.Name
        elseif player then
            return model, "Player", player.DisplayName or player.Name
        end
        return model, "NPC", model.Name
    end

    local function passesSource(sourceType)
        local filter = ctx.library.flags["Dev Animation Logger Source"] or "All"
        if filter == "All" then return true end
        if filter == "Players" then return sourceType == "Player" end
        if filter == "NPCs" then return sourceType == "NPC" end
        if filter == "Self" then return sourceType == "Self" end
        return true
    end

    local function passesRange(model)
        if ctx.library.flags["Dev Animation Logger Range Limit"] == false then
            return true
        end
        local localRoot = ctx.getRoot and ctx.getRoot() or nil
        local root = ctx.getRoot and ctx.getRoot(model) or (model and model:FindFirstChild("HumanoidRootPart"))
        if not localRoot or not root then
            return true
        end
        local range = tonumber(ctx.library.flags["Dev Animation Logger Range"]) or 150
        return (localRoot.Position - root.Position).Magnitude <= range
    end

    local function saveSettings()
        if type(writefile) ~= "function" then
            return
        end
        local ok, payload = pcall(function()
            local encoded = game:GetService("HttpService"):JSONEncode({blacklist = state.blacklist})
            return encoded
        end)
        if not ok then return end
        pcall(function()
            if type(isfolder) == "function" and not isfolder(persistenceFolder) and type(makefolder) == "function" then
                makefolder(persistenceFolder)
            end
            writefile(persistencePath, payload)
        end)
    end

    local function loadSettings()
        if type(readfile) ~= "function" or type(isfile) ~= "function" or not isfile(persistencePath) then
            return
        end
        local ok, decoded = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile(persistencePath))
        end)
        if ok and type(decoded) == "table" and type(decoded.blacklist) == "table" then
            for key, value in pairs(decoded.blacklist) do
                if value == true then
                    local id = normalizeId(key)
                    if id then state.blacklist[id] = true end
                end
            end
        end
    end

    loadSettings()

    local function markDirty()
        state.dirty = true
    end

    local function trimEntries()
        local maxEntries = math.clamp(tonumber(ctx.library.flags["Dev Animation Logger Max Entries"]) or 300, 50, 1000)
        while #state.entries > maxEntries do
            table.remove(state.entries)
        end
    end

    local function shouldDedupe(key)
        local now = os.clock()
        local window = math.max(0, tonumber(ctx.library.flags["Dev Animation Logger Dedupe"]) or 0.5)
        local last = state.recent[key]
        state.recent[key] = now
        return last ~= nil and now - last < window
    end

    local function trackMetadata(track, sourceModel, sourceType, sourceName)
        local animation = track.Animation
        local id = animation and normalizeId(animation.AnimationId)
        if not id then return nil end
        local animator = track.Parent
        local key = tostring(animator) .. ":" .. id
        if shouldDedupe(key) or state.blacklist[id] then
            return nil
        end
        return {
            id = id,
            animationId = "rbxassetid://" .. id,
            name = animation.Name ~= "" and animation.Name or track.Name,
            sourceName = sourceName,
            sourceType = sourceType,
            sourceModel = sourceModel,
            sourcePath = shared.instancePath(sourceModel),
            animatorPath = shared.instancePath(animator),
            speed = tonumber(track.Speed) or 1,
            weight = tonumber(track.WeightCurrent) or 0,
            looped = track.Looped == true,
            priority = tostring(track.Priority),
            length = tonumber(track.Length) or 0,
            startedAt = os.clock(),
            wallTime = os.time(),
            timePosition = tonumber(track.TimePosition) or 0,
            track = track,
            stopped = false,
        }
    end

    local function addEntry(entry)
        table.insert(state.entries, 1, entry)
        trimEntries()
        state.entryEvent:Fire(entry)
        markDirty()

        if entry.track and not state.trackConnections[entry.track] then
            local connection
            connection = entry.track.Stopped:Connect(function()
                entry.stopped = true
                entry.endedAt = os.clock()
                entry.durationPlayed = math.max(0, entry.endedAt - entry.startedAt)
                state.trackConnections[entry.track] = nil
                pcall(function() connection:Disconnect() end)
                markDirty()
            end)
            state.trackConnections[entry.track] = connection
        end
    end

    local function onAnimationPlayed(animator, track)
        if not enabled() then return end
        local model, sourceType, sourceName = sourceInfo(animator)
        if not model or not passesSource(sourceType) or not passesRange(model) then
            return
        end
        local ok, entry = pcall(trackMetadata, track, model, sourceType, sourceName)
        if ok and entry then
            addEntry(entry)
        end
    end

    local function attachAnimator(animator)
        if not animator:IsA("Animator") or state.animatorConnections[animator] then
            return
        end
        local connection = animator.AnimationPlayed:Connect(function(track)
            onAnimationPlayed(animator, track)
        end)
        state.animatorConnections[animator] = connection
        animator.AncestryChanged:Connect(function(_, parent)
            if not parent then
                local existing = state.animatorConnections[animator]
                if existing then pcall(function() existing:Disconnect() end) end
                state.animatorConnections[animator] = nil
            end
        end)
    end

    local function scanExisting()
        task.spawn(function()
            local count = 0
            for _, object in ipairs(ctx.Workspace:GetDescendants()) do
                if object:IsA("Animator") then
                    attachAnimator(object)
                end
                count = count + 1
                if count % 300 == 0 then task.wait() end
            end
        end)
    end

    local function exportEntries()
        local export = {}
        for _, entry in ipairs(state.entries) do
            table.insert(export, {
                id = entry.id,
                name = entry.name,
                sourceName = entry.sourceName,
                sourceType = entry.sourceType,
                sourcePath = entry.sourcePath,
                speed = entry.speed,
                looped = entry.looped,
                priority = entry.priority,
                length = entry.length,
                durationPlayed = entry.durationPlayed,
                wallTime = entry.wallTime,
            })
        end
        local ok, text = pcall(function()
            return game:GetService("HttpService"):JSONEncode(export)
        end)
        if ok then shared.copy(text) end
    end

    local function clearRows()
        for _, row in ipairs(state.rows) do
            shared.safeDestroy(row)
        end
        state.rows = {}
    end

    local function selectEntry(entry)
        state.selected = entry
        if not entry then
            ui.details.Text = "No entry selected"
            return
        end
        ui.details.Text = table.concat({
            "Animation: " .. tostring(entry.name),
            "ID: " .. tostring(entry.id),
            "Source: " .. tostring(entry.sourceName) .. " (" .. tostring(entry.sourceType) .. ")",
            "Path: " .. tostring(entry.sourcePath),
            string.format("Speed %.2f | Weight %.2f | Length %.3f", entry.speed, entry.weight, entry.length),
            "Priority: " .. tostring(entry.priority) .. " | Looped: " .. tostring(entry.looped),
            entry.stopped and string.format("Played for %.3fs", entry.durationPlayed or 0) or "Track currently active or stop not observed",
        }, "\n")
    end

    local function entryMatches(entry)
        local query = ui.search and string.lower(ui.search.Text) or ""
        if query == "" then return true end
        local haystack = string.lower(table.concat({entry.id, entry.name, entry.sourceName, entry.sourceType, entry.sourcePath}, " "))
        return string.find(haystack, query, 1, true) ~= nil
    end

    local function rebuildRows()
        if not ui.list then return end
        clearRows()
        local shown = 0
        for _, entry in ipairs(state.entries) do
            if entryMatches(entry) then
                shown = shown + 1
                if shown > 250 then break end
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 34),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.08,
                    BorderSizePixel = 0,
                    Text = "",
                    Parent = ui.list,
                })
                shared.round(row, 5)
                shared.stroke(row, shared.theme.border, 0.45, 1)
                local title = shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 2),
                    Size = UDim2.new(1, -16, 0, 16),
                    BackgroundTransparency = 1,
                    Text = tostring(entry.sourceName) .. "  •  " .. tostring(entry.name),
                    TextColor3 = shared.theme.text,
                    TextSize = 11,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 17),
                    Size = UDim2.new(1, -16, 0, 14),
                    BackgroundTransparency = 1,
                    Text = tostring(entry.id) .. "  |  " .. tostring(entry.sourceType) .. string.format("  |  %.2fx", entry.speed),
                    TextColor3 = shared.theme.muted,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                shared.connect(row.MouseButton1Click, function()
                    selectEntry(entry)
                end)
                table.insert(state.rows, row)
            end
        end
        if ui.count then ui.count.Text = string.format("%d captured • %d shown", #state.entries, shown) end
        state.dirty = false
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then return state.window end
        state.window = shared.makeWindow("Animation Logger", 840, 520)
        local content = state.window.content

        local left = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(0.58, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(left, 8)
        shared.stroke(left, shared.theme.border, 0.25, 1)
        local leftPad = Instance.new("UIPadding")
        leftPad.PaddingTop = UDim.new(0, 8)
        leftPad.PaddingLeft = UDim.new(0, 8)
        leftPad.PaddingRight = UDim.new(0, 8)
        leftPad.PaddingBottom = UDim.new(0, 8)
        leftPad.Parent = left

        ui.search = shared.makeTextBox(left, "Search ID, source, name, path", "")
        ui.search.Position = UDim2.fromOffset(0, 0)
        ui.count = shared.create("TextLabel", {
            Position = UDim2.fromOffset(0, 34),
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            Text = "0 captured",
            TextColor3 = shared.theme.muted,
            TextSize = 10,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = left,
        })
        ui.list = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 56),
            Size = UDim2.new(1, 0, 1, -56),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = left,
        })
        shared.round(ui.list, 6)
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 4)
        layout.Parent = ui.list
        shared.connect(ui.search:GetPropertyChangedSignal("Text"), markDirty)

        local right = shared.create("Frame", {
            Position = UDim2.new(0.58, 5, 0, 10),
            Size = UDim2.new(0.42, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(right, 8)
        shared.stroke(right, shared.theme.border, 0.25, 1)
        local rightPad = Instance.new("UIPadding")
        rightPad.PaddingTop = UDim.new(0, 10)
        rightPad.PaddingLeft = UDim.new(0, 10)
        rightPad.PaddingRight = UDim.new(0, 10)
        rightPad.PaddingBottom = UDim.new(0, 10)
        rightPad.Parent = right

        ui.details = shared.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 240),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = "No entry selected",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = right,
        })
        shared.round(ui.details, 6)
        local detailPad = Instance.new("UIPadding")
        detailPad.PaddingTop = UDim.new(0, 8)
        detailPad.PaddingLeft = UDim.new(0, 8)
        detailPad.PaddingRight = UDim.new(0, 8)
        detailPad.Parent = ui.details

        local buttons = shared.create("Frame", {
            Position = UDim2.fromOffset(0, 250),
            Size = UDim2.new(1, 0, 1, -250),
            BackgroundTransparency = 1,
            Parent = right,
        })
        local buttonLayout = Instance.new("UIGridLayout")
        buttonLayout.CellSize = UDim2.new(0.5, -4, 0, 30)
        buttonLayout.CellPadding = UDim2.fromOffset(6, 6)
        buttonLayout.Parent = buttons
        shared.makeButton(buttons, "Preview", function()
            if state.selected and dev.apis.animationViewer then
                dev.apis.animationViewer:Open(state.selected)
            else
                shared.notify("Select an animation first", 2)
            end
        end, 120)
        shared.makeButton(buttons, "Copy ID", function()
            if state.selected then shared.copy(state.selected.id) end
        end, 120)
        shared.makeButton(buttons, "Copy Source Path", function()
            if state.selected then shared.copy(state.selected.sourcePath) end
        end, 120)
        shared.makeButton(buttons, "Blacklist ID", function()
            if state.selected then
                state.blacklist[state.selected.id] = true
                saveSettings()
                shared.notify("Blacklisted " .. state.selected.id, 2)
            end
        end, 120)
        shared.makeButton(buttons, "Export JSON", exportEntries, 120)
        shared.makeButton(buttons, "Clear", function()
            state.entries = {}
            state.recent = {}
            state.selected = nil
            markDirty()
            selectEntry(nil)
        end, 120)

        shared.connect(ctx.RunService.Heartbeat, function()
            if state.window and state.window.root.Visible and state.dirty then
                rebuildRows()
            end
        end)
        markDirty()
        return state.window
    end

    local api = {}
    function api:Open()
        buildWindow():Show()
        markDirty()
    end
    function api:Clear()
        state.entries = {}
        state.recent = {}
        state.selected = nil
        markDirty()
        selectEntry(nil)
    end
    function api:GetEntries()
        return state.entries
    end
    function api:GetSelected()
        return state.selected
    end
    function api:Blacklist(id, value)
        id = normalizeId(id)
        if id then
            state.blacklist[id] = value ~= false
            saveSettings()
        end
    end
    function api:OnEntry(callback)
        return state.entryEvent.Event:Connect(callback)
    end
    function api:GetState()
        return state
    end

    dev.apis.animationLogger = api

    local function setup()
        scanExisting()
        state.descendantConnection = shared.connect(ctx.Workspace.DescendantAdded, function(object)
            if object:IsA("Animator") then attachAnimator(object) end
        end)
    end

    local function cleanup()
        for animator, connection in pairs(state.animatorConnections) do
            pcall(function() connection:Disconnect() end)
            state.animatorConnections[animator] = nil
        end
        for track, connection in pairs(state.trackConnections) do
            pcall(function() connection:Disconnect() end)
            state.trackConnections[track] = nil
        end
        shared.safeDestroy(state.entryEvent)
        if state.window then state.window:Destroy() end
        saveSettings()
    end

    local module = {name = "animation_logger", setup = setup, cleanup = cleanup, api = api}
    dev.modules.animation_logger = module
    shared.addCleanup(cleanup)
    return module
end
