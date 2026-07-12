--[[
    xanhub | devmodules | remote spy

    Developer-safe remote monitor:
      • discovers RemoteEvent / UnreliableRemoteEvent / RemoteFunction instances
      • logs inbound client events
      • logs outbound calls made through this module's wrapper API
      • serializes arguments safely with limits and cycle protection

    It intentionally does not hook __namecall, replace game callbacks, replay calls,
    or intercept unrelated scripts' outbound traffic.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub remote spy] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub remote spy] dev_shared missing")
    local section = dev.left:AddSection("Remote Spy")

    section:AddToggle({text = "Enabled", flag = "Dev Remote Spy Enabled", state = false})
    section:AddToggle({text = "Capture Inbound Events", flag = "Dev Remote Spy Inbound", state = true})
    section:AddToggle({text = "Capture Wrapped Outbound", flag = "Dev Remote Spy Outbound", state = true})
    section:AddToggle({text = "Include Bindables", flag = "Dev Remote Spy Bindables", state = false})
    section:AddSlider({
        text = "Maximum Entries",
        flag = "Dev Remote Spy Max Entries",
        min = 100,
        max = 2000,
        value = 500,
        float = 50,
    })
    section:AddSlider({
        text = "Serialize Depth",
        flag = "Dev Remote Spy Depth",
        min = 1,
        max = 10,
        value = 5,
        float = 1,
    })
    section:AddButton({
        text = "Open Remote Spy",
        callback = function()
            local api = dev.apis.remoteSpy
            if api then api:Open() end
        end,
    })
    section:AddButton({
        text = "Clear Remote Log",
        callback = function()
            local api = dev.apis.remoteSpy
            if api then api:Clear() end
        end,
    })
    section:AddLabel("Inbound events + outbound calls made through dev.apis.remoteSpy")

    local state = {
        entries = {},
        remoteConnections = setmetatable({}, {__mode = "k"}),
        discovered = setmetatable({}, {__mode = "k"}),
        rows = {},
        selected = nil,
        window = nil,
        dirty = true,
        entryEvent = Instance.new("BindableEvent"),
    }
    local ui = {}

    local function isRemote(object)
        return object:IsA("RemoteEvent")
            or object:IsA("RemoteFunction")
            or object:IsA("UnreliableRemoteEvent")
    end

    local function isBindable(object)
        return object:IsA("BindableEvent") or object:IsA("BindableFunction")
    end

    local function enabled()
        return ctx.library.flags["Dev Remote Spy Enabled"] == true
    end

    local function trim()
        local maxEntries = math.clamp(tonumber(ctx.library.flags["Dev Remote Spy Max Entries"]) or 500, 100, 2000)
        while #state.entries > maxEntries do
            table.remove(state.entries)
        end
    end

    local function serializeArguments(args)
        local depth = tonumber(ctx.library.flags["Dev Remote Spy Depth"]) or 5
        local rendered = {}
        for index = 1, args.n or #args do
            rendered[index] = shared.serialize(args[index], {
                maxDepth = depth,
                maxEntries = 100,
                maxString = 4000,
            })
        end
        return rendered
    end

    local function callerInfo(level)
        if type(debug) ~= "table" then return nil end
        local info = {}
        pcall(function()
            if type(debug.info) == "function" then
                info.source = debug.info(level or 4, "s")
                info.line = debug.info(level or 4, "l")
                info.name = debug.info(level or 4, "n")
            end
        end)
        return next(info) and info or nil
    end

    local function addEntry(remote, direction, args, result, metadata)
        if not enabled() then return nil end
        local entry = {
            remote = remote,
            className = typeof(remote) == "Instance" and remote.ClassName or tostring(metadata and metadata.className or "Unknown"),
            name = typeof(remote) == "Instance" and remote.Name or tostring(metadata and metadata.name or remote),
            path = typeof(remote) == "Instance" and shared.instancePath(remote) or tostring(metadata and metadata.path or remote),
            direction = direction,
            args = args,
            serialized = serializeArguments(args),
            result = result,
            resultSerialized = result ~= nil and shared.serialize(result, {maxDepth = 5, maxEntries = 100, maxString = 4000}) or nil,
            timestamp = os.clock(),
            wallTime = os.time(),
            callsite = metadata and metadata.callsite or nil,
            elapsed = metadata and metadata.elapsed or nil,
            error = metadata and metadata.error or nil,
        }
        table.insert(state.entries, 1, entry)
        trim()
        state.entryEvent:Fire(entry)
        state.dirty = true
        return entry
    end

    local function attachRemote(remote)
        if state.discovered[remote] then return end
        state.discovered[remote] = true
        if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
            local connection = remote.OnClientEvent:Connect(function(...)
                if enabled() and ctx.library.flags["Dev Remote Spy Inbound"] ~= false then
                    addEntry(remote, "INBOUND", table.pack(...), nil, nil)
                end
            end)
            state.remoteConnections[remote] = connection
        elseif remote:IsA("BindableEvent") then
            local connection = remote.Event:Connect(function(...)
                if enabled() and ctx.library.flags["Dev Remote Spy Bindables"] == true then
                    addEntry(remote, "BINDABLE", table.pack(...), nil, nil)
                end
            end)
            state.remoteConnections[remote] = connection
        end
        remote.AncestryChanged:Connect(function(_, parent)
            if not parent then
                local connection = state.remoteConnections[remote]
                if connection then pcall(function() connection:Disconnect() end) end
                state.remoteConnections[remote] = nil
                state.discovered[remote] = nil
            end
        end)
    end

    local function scanExisting()
        task.spawn(function()
            local count = 0
            for _, object in ipairs(game:GetDescendants()) do
                if isRemote(object) or (ctx.library.flags["Dev Remote Spy Bindables"] == true and isBindable(object)) then
                    attachRemote(object)
                end
                count = count + 1
                if count % 500 == 0 then task.wait() end
            end
        end)
    end

    local function exportSnippet(entry)
        if not entry or typeof(entry.remote) ~= "Instance" then
            return ""
        end
        local remotePath = entry.path
        local args = {}
        for index = 1, entry.args.n or #entry.args do
            table.insert(args, shared.luaQuote(entry.args[index]))
        end
        local argText = table.concat(args, ", ")
        if entry.remote:IsA("RemoteFunction") then
            return string.format("local result = %s:InvokeServer(%s)", remotePath, argText)
        end
        return string.format("%s:FireServer(%s)", remotePath, argText)
    end

    local function exportEntry(entry)
        if not entry then return "" end
        local lines = {
            "-- " .. entry.direction .. " " .. entry.path,
            "-- class: " .. entry.className,
            "-- time: " .. tostring(entry.wallTime),
        }
        if entry.callsite then
            table.insert(lines, "-- caller: " .. tostring(entry.callsite.source) .. ":" .. tostring(entry.callsite.line) .. " " .. tostring(entry.callsite.name or ""))
        end
        table.insert(lines, "{")
        for index, value in ipairs(entry.serialized) do
            table.insert(lines, string.format("    [%d] = %s,", index, value))
        end
        table.insert(lines, "}")
        if entry.resultSerialized then
            table.insert(lines, "-- result: " .. entry.resultSerialized)
        end
        if entry.error then
            table.insert(lines, "-- error: " .. tostring(entry.error))
        end
        return table.concat(lines, "\n")
    end

    local function selectEntry(entry)
        state.selected = entry
        if not entry then
            ui.details.Text = "No entry selected"
            return
        end
        local lines = {
            entry.direction .. "  " .. entry.className,
            entry.path,
            string.format("Arguments: %d", entry.args.n or #entry.args),
        }
        if entry.elapsed then table.insert(lines, string.format("Elapsed: %.4fs", entry.elapsed)) end
        if entry.callsite then
            table.insert(lines, "Caller: " .. tostring(entry.callsite.source) .. ":" .. tostring(entry.callsite.line))
        end
        if entry.error then table.insert(lines, "Error: " .. tostring(entry.error)) end
        table.insert(lines, "")
        for index, value in ipairs(entry.serialized) do
            table.insert(lines, string.format("[%d] %s", index, value))
        end
        if entry.resultSerialized then
            table.insert(lines, "")
            table.insert(lines, "Result: " .. entry.resultSerialized)
        end
        ui.details.Text = table.concat(lines, "\n")
    end

    local function matches(entry)
        local query = ui.search and string.lower(ui.search.Text) or ""
        local direction = ui.direction or "All"
        if direction ~= "All" and entry.direction ~= direction then return false end
        if query == "" then return true end
        local haystack = string.lower(table.concat({entry.name, entry.path, entry.className, entry.direction, table.concat(entry.serialized, " ")}, " "))
        return string.find(haystack, query, 1, true) ~= nil
    end

    local function clearRows()
        for _, row in ipairs(state.rows) do shared.safeDestroy(row) end
        state.rows = {}
    end

    local function rebuildRows()
        if not ui.list then return end
        clearRows()
        local shown = 0
        for _, entry in ipairs(state.entries) do
            if matches(entry) then
                shown = shown + 1
                if shown > 300 then break end
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 36),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.08,
                    BorderSizePixel = 0,
                    Text = "",
                    Parent = ui.list,
                })
                shared.round(row, 5)
                local color = entry.direction == "INBOUND" and shared.theme.success
                    or entry.direction == "OUTBOUND" and shared.accent()
                    or entry.direction == "RETURN" and shared.theme.warning
                    or shared.theme.muted
                shared.create("Frame", {
                    Size = UDim2.fromOffset(3, 36),
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(9, 2),
                    Size = UDim2.new(1, -16, 0, 16),
                    BackgroundTransparency = 1,
                    Text = entry.direction .. "  •  " .. entry.name,
                    TextColor3 = shared.theme.text,
                    TextSize = 11,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(9, 18),
                    Size = UDim2.new(1, -16, 0, 15),
                    BackgroundTransparency = 1,
                    Text = entry.className .. "  |  " .. tostring(entry.args.n or #entry.args) .. " args",
                    TextColor3 = shared.theme.muted,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                shared.connect(row.MouseButton1Click, function() selectEntry(entry) end)
                table.insert(state.rows, row)
            end
        end
        if ui.count then
            local discovered = 0
            for _ in pairs(state.discovered) do discovered = discovered + 1 end
            ui.count.Text = string.format("%d entries • %d shown • %d remotes", #state.entries, shown, discovered)
        end
        state.dirty = false
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then return state.window end
        state.window = shared.makeWindow("Remote Spy", 900, 560)
        local content = state.window.content

        local left = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(0.54, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(left, 8)
        shared.stroke(left, shared.theme.border, 0.25, 1)
        local lp = Instance.new("UIPadding")
        lp.PaddingTop = UDim.new(0, 8)
        lp.PaddingLeft = UDim.new(0, 8)
        lp.PaddingRight = UDim.new(0, 8)
        lp.PaddingBottom = UDim.new(0, 8)
        lp.Parent = left

        ui.search = shared.makeTextBox(left, "Search path, name, class, arguments", "")
        ui.search.Position = UDim2.fromOffset(0, 0)
        local filterRow = shared.create("Frame", {
            Position = UDim2.fromOffset(0, 34),
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            Parent = left,
        })
        ui.direction = "All"
        local filterButton
        filterButton = shared.makeButton(filterRow, "Direction: All", function()
            local values = {"All", "INBOUND", "OUTBOUND", "RETURN", "BINDABLE"}
            local index = table.find(values, ui.direction) or 1
            ui.direction = values[index % #values + 1]
            filterButton.Text = "Direction: " .. ui.direction
            state.dirty = true
        end, 132)
        ui.count = shared.create("TextLabel", {
            Position = UDim2.fromOffset(140, 0),
            Size = UDim2.new(1, -140, 1, 0),
            BackgroundTransparency = 1,
            Text = "0 entries",
            TextColor3 = shared.theme.muted,
            TextSize = 10,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = filterRow,
        })
        ui.list = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 66),
            Size = UDim2.new(1, 0, 1, -66),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = left,
        })
        shared.round(ui.list, 6)
        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 4)
        listLayout.Parent = ui.list
        shared.connect(ui.search:GetPropertyChangedSignal("Text"), function() state.dirty = true end)

        local right = shared.create("Frame", {
            Position = UDim2.new(0.54, 5, 0, 10),
            Size = UDim2.new(0.46, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(right, 8)
        shared.stroke(right, shared.theme.border, 0.25, 1)
        local rp = Instance.new("UIPadding")
        rp.PaddingTop = UDim.new(0, 8)
        rp.PaddingLeft = UDim.new(0, 8)
        rp.PaddingRight = UDim.new(0, 8)
        rp.PaddingBottom = UDim.new(0, 8)
        rp.Parent = right

        ui.details = shared.create("TextBox", {
            Size = UDim2.new(1, 0, 1, -76),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = "No entry selected",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextWrapped = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ClearTextOnFocus = false,
            MultiLine = true,
            Parent = right,
        })
        shared.round(ui.details, 6)
        local dp = Instance.new("UIPadding")
        dp.PaddingTop = UDim.new(0, 8)
        dp.PaddingLeft = UDim.new(0, 8)
        dp.PaddingRight = UDim.new(0, 8)
        dp.Parent = ui.details

        local buttons = shared.create("Frame", {
            Position = UDim2.new(0, 0, 1, -66),
            Size = UDim2.new(1, 0, 0, 66),
            BackgroundTransparency = 1,
            Parent = right,
        })
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = UDim2.new(0.5, -4, 0, 28)
        grid.CellPadding = UDim2.fromOffset(6, 6)
        grid.Parent = buttons
        shared.makeButton(buttons, "Copy Entry", function()
            if state.selected then shared.copy(exportEntry(state.selected)) end
        end, 120)
        shared.makeButton(buttons, "Copy Path", function()
            if state.selected then shared.copy(state.selected.path) end
        end, 120)
        shared.makeButton(buttons, "Copy Snippet", function()
            if state.selected then shared.copy(exportSnippet(state.selected)) end
        end, 120)
        shared.makeButton(buttons, "Inspect Remote", function()
            if state.selected and typeof(state.selected.remote) == "Instance" and dev.apis.instanceInspector then
                dev.apis.instanceInspector:Select(state.selected.remote)
                dev.apis.instanceInspector:Open()
            end
        end, 120)
        shared.makeButton(buttons, "Clear", function()
            state.entries = {}
            state.selected = nil
            selectEntry(nil)
            state.dirty = true
        end, 120)

        shared.connect(ctx.RunService.Heartbeat, function()
            if state.window and state.window.root.Visible and state.dirty then rebuildRows() end
        end)
        return state.window
    end

    local api = {}
    function api:Open()
        buildWindow():Show()
        state.dirty = true
    end
    function api:Clear()
        state.entries = {}
        state.selected = nil
        state.dirty = true
        selectEntry(nil)
    end
    function api:GetEntries()
        return state.entries
    end
    function api:OnEntry(callback)
        return state.entryEvent.Event:Connect(callback)
    end
    function api:Log(remote, direction, ...)
        return addEntry(remote, direction or "CUSTOM", table.pack(...), nil, {callsite = callerInfo(4)})
    end
    function api:FireServer(remote, ...)
        assert(typeof(remote) == "Instance" and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")), "expected RemoteEvent")
        local args = table.pack(...)
        if ctx.library.flags["Dev Remote Spy Outbound"] ~= false then
            addEntry(remote, "OUTBOUND", args, nil, {callsite = callerInfo(4)})
        end
        return remote:FireServer(table.unpack(args, 1, args.n))
    end
    function api:InvokeServer(remote, ...)
        assert(typeof(remote) == "Instance" and remote:IsA("RemoteFunction"), "expected RemoteFunction")
        local args = table.pack(...)
        local callsite = callerInfo(4)
        if ctx.library.flags["Dev Remote Spy Outbound"] ~= false then
            addEntry(remote, "OUTBOUND", args, nil, {callsite = callsite})
        end
        local started = os.clock()
        local packed = table.pack(pcall(function()
            return remote:InvokeServer(table.unpack(args, 1, args.n))
        end))
        local elapsed = os.clock() - started
        local ok = packed[1]
        if ok then
            local results = table.pack(table.unpack(packed, 2, packed.n))
            addEntry(remote, "RETURN", results, results[1], {callsite = callsite, elapsed = elapsed})
            return table.unpack(results, 1, results.n)
        end
        addEntry(remote, "RETURN", table.pack(), nil, {callsite = callsite, elapsed = elapsed, error = packed[2]})
        error(packed[2], 2)
    end
    function api:GetState()
        return state
    end

    dev.apis.remoteSpy = api

    local function setup()
        scanExisting()
        shared.connect(game.DescendantAdded, function(object)
            if isRemote(object) or (ctx.library.flags["Dev Remote Spy Bindables"] == true and isBindable(object)) then
                attachRemote(object)
            end
        end)
    end

    local function cleanup()
        for remote, connection in pairs(state.remoteConnections) do
            pcall(function() connection:Disconnect() end)
            state.remoteConnections[remote] = nil
        end
        shared.safeDestroy(state.entryEvent)
        if state.window then state.window:Destroy() end
    end

    local module = {name = "remote_spy", setup = setup, cleanup = cleanup, api = api}
    dev.modules.remote_spy = module
    shared.addCleanup(cleanup)
    return module
end
