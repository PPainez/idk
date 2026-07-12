--[[
    xanhub | devmodules | instance inspector

    Read-only instance inspector with path resolving, attributes, children,
    common properties, and live property-watch logs.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub inspector] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub inspector] dev_shared missing")
    local section = dev.left:AddSection("Instance Inspector")

    section:AddButton({text = "Open Instance Inspector", callback = function()
        if dev.apis.instanceInspector then dev.apis.instanceInspector:Open() end
    end})
    section:AddButton({text = "Inspect Local Character", callback = function()
        if dev.apis.instanceInspector and ctx.LocalPlayer.Character then
            dev.apis.instanceInspector:Select(ctx.LocalPlayer.Character)
            dev.apis.instanceInspector:Open()
        end
    end})
    section:AddButton({text = "Inspect Current Camera", callback = function()
        if dev.apis.instanceInspector and ctx.Workspace.CurrentCamera then
            dev.apis.instanceInspector:Select(ctx.Workspace.CurrentCamera)
            dev.apis.instanceInspector:Open()
        end
    end})
    section:AddButton({text = "Inspect Mouse Target", callback = function()
        local target = ctx.UserInputService and ctx.UserInputService:GetMouseLocation()
        local camera = ctx.Workspace.CurrentCamera
        if dev.apis.instanceInspector and camera and target then
            local ray = camera:ViewportPointToRay(target.X, target.Y)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            if ctx.LocalPlayer.Character then
                params.FilterDescendantsInstances = { ctx.LocalPlayer.Character }
            end
            local hit = ctx.Workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
            if hit and hit.Instance then
                dev.apis.instanceInspector:Select(hit.Instance)
                dev.apis.instanceInspector:Open()
            else
                shared.notify("No instance under cursor", 2)
            end
        end
    end})
    section:AddButton({text = "Inspect ReplicatedStorage", callback = function()
        if dev.apis.instanceInspector then
            dev.apis.instanceInspector:Select(game:GetService("ReplicatedStorage"))
            dev.apis.instanceInspector:Open()
        end
    end})
    section:AddToggle({text = "Auto Refresh", flag = "Dev Inspector Auto Refresh", state = true})
    section:AddSlider({text = "Refresh Rate", flag = "Dev Inspector Refresh", min = 0.1, max = 2, value = 0.5, float = 0.1, suffix = "s"})
    section:AddLabel("Read-only by design; use Copy Path for scripts")

    local state = {
        selected = nil,
        window = nil,
        childRows = {},
        propertyRows = {},
        watchRows = {},
        watches = {},
        dirty = true,
        elapsed = 0,
    }
    local ui = {}

    local commonProperties = {
        "Name", "ClassName", "Parent", "Archivable",
        "Position", "CFrame", "Size", "Orientation", "Anchored", "CanCollide", "Transparency", "Color", "Material",
        "Value", "Enabled", "Visible", "Text", "Image", "SoundId", "AnimationId",
        "Health", "MaxHealth", "WalkSpeed", "JumpPower", "RigType",
    }

    local function resolvePath(path)
        path = tostring(path or "")
        path = string.gsub(path, "^%s+", "")
        path = string.gsub(path, "%s+$", "")
        if path == "" or path == "game" then return game end
        if path == "workspace" or path == "Workspace" or path == "game.Workspace" then return workspace end
        path = string.gsub(path, "^game[%.]?", "")
        path = string.gsub(path, "^workspace[%.]?", "Workspace.")

        local cursor = game
        local index = 1
        while index <= #path do
            local char = string.sub(path, index, index)
            local name
            if char == "." then
                index = index + 1
                local start = index
                while index <= #path and string.match(string.sub(path, index, index), "[%w_]") do index = index + 1 end
                name = string.sub(path, start, index - 1)
            elseif char == "[" then
                local quote = string.sub(path, index + 1, index + 1)
                if quote ~= '"' and quote ~= "'" then return nil end
                local close = string.find(path, quote .. "]", index + 2, true)
                if not close then return nil end
                name = string.sub(path, index + 2, close - 1)
                index = close + 2
            else
                local start = index
                while index <= #path and string.match(string.sub(path, index, index), "[%w_]") do index = index + 1 end
                name = string.sub(path, start, index - 1)
            end
            if name and name ~= "" then
                cursor = cursor:FindFirstChild(name)
                if not cursor then return nil end
            else
                index = index + 1
            end
        end
        return cursor
    end

    local function safeProperty(instance, property)
        local ok, value = pcall(function() return instance[property] end)
        return ok, value
    end

    local function clearRows(rows)
        for _, row in ipairs(rows) do shared.safeDestroy(row) end
        table.clear(rows)
    end

    local function selectInstance(instance)
        if typeof(instance) ~= "Instance" then return false end
        state.selected = instance
        state.dirty = true
        if ui.path then ui.path.Text = shared.instancePath(instance) end
        return true
    end

    local function addWatch(property)
        if not state.selected or state.watches[property] then return end
        local ok = pcall(function()
            local connection = state.selected:GetPropertyChangedSignal(property):Connect(function()
                local success, value = safeProperty(state.selected, property)
                table.insert(state.watchRows, 1, {
                    property = property,
                    value = success and shared.serialize(value, {maxDepth = 3, maxEntries = 30}) or "<unavailable>",
                    time = os.clock(),
                })
                while #state.watchRows > 100 do table.remove(state.watchRows) end
                state.dirty = true
            end)
            state.watches[property] = connection
        end)
        if not ok then shared.notify("Property cannot be watched", 2) end
    end

    local function clearWatches()
        for property, connection in pairs(state.watches) do
            pcall(function() connection:Disconnect() end)
            state.watches[property] = nil
        end
        state.watchRows = {}
    end

    local function buildProperties()
        if not ui.properties or not state.selected then return end
        clearRows(state.propertyRows)
        local instance = state.selected

        local header = shared.create("TextLabel", {
            Size = UDim2.new(1, -4, 0, 52),
            BackgroundColor3 = shared.theme.panel2,
            BorderSizePixel = 0,
            Text = instance.ClassName .. "  •  " .. instance.Name .. "\n" .. shared.instancePath(instance),
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = ui.properties,
        })
        shared.round(header, 5)
        local hp = Instance.new("UIPadding")
        hp.PaddingLeft = UDim.new(0, 7)
        hp.PaddingRight = UDim.new(0, 7)
        hp.Parent = header
        table.insert(state.propertyRows, header)

        local attributes = instance:GetAttributes()
        for name, value in pairs(attributes) do
            local row = shared.create("TextButton", {
                Size = UDim2.new(1, -4, 0, 30),
                BackgroundColor3 = shared.theme.background,
                BorderSizePixel = 0,
                Text = "@" .. name .. " = " .. shared.serialize(value, {maxDepth = 2}),
                TextColor3 = shared.theme.warning,
                TextSize = 10,
                Font = Enum.Font.Code,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = ui.properties,
            })
            shared.round(row, 4)
            local p = Instance.new("UIPadding")
            p.PaddingLeft = UDim.new(0, 6)
            p.Parent = row
            shared.connect(row.MouseButton1Click, function()
                shared.copy(shared.serialize(value, {maxDepth = 5}))
            end)
            table.insert(state.propertyRows, row)
        end

        for _, property in ipairs(commonProperties) do
            local ok, value = safeProperty(instance, property)
            if ok then
                local valueText = shared.serialize(value, {maxDepth = 3, maxEntries = 40, maxString = 700})
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 30),
                    BackgroundColor3 = shared.theme.background,
                    BorderSizePixel = 0,
                    Text = property .. " = " .. valueText,
                    TextColor3 = shared.theme.text,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = ui.properties,
                })
                shared.round(row, 4)
                local p = Instance.new("UIPadding")
                p.PaddingLeft = UDim.new(0, 6)
                p.Parent = row
                shared.connect(row.MouseButton1Click, function()
                    ui.selectedProperty = property
                    ui.propertyBox.Text = property
                    ui.valueBox.Text = valueText
                end)
                table.insert(state.propertyRows, row)
            end
        end
    end

    local function buildChildren()
        if not ui.children or not state.selected then return end
        clearRows(state.childRows)
        local children = state.selected:GetChildren()
        table.sort(children, function(a, b)
            if a.ClassName == b.ClassName then return a.Name < b.Name end
            return a.ClassName < b.ClassName
        end)
        for _, child in ipairs(children) do
            local row = shared.create("TextButton", {
                Size = UDim2.new(1, -4, 0, 28),
                BackgroundColor3 = shared.theme.panel2,
                BackgroundTransparency = 0.08,
                BorderSizePixel = 0,
                Text = child.ClassName .. "  •  " .. child.Name,
                TextColor3 = shared.theme.text,
                TextSize = 10,
                Font = Enum.Font.Code,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = ui.children,
            })
            shared.round(row, 4)
            local p = Instance.new("UIPadding")
            p.PaddingLeft = UDim.new(0, 6)
            p.Parent = row
            shared.connect(row.MouseButton1Click, function()
                clearWatches()
                selectInstance(child)
            end)
            table.insert(state.childRows, row)
        end
    end

    local function buildWatchLog()
        if not ui.watchList then return end
        for _, child in ipairs(ui.watchList:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        for _, entry in ipairs(state.watchRows) do
            local row = shared.create("TextLabel", {
                Size = UDim2.new(1, -4, 0, 24),
                BackgroundColor3 = shared.theme.panel2,
                BackgroundTransparency = 0.08,
                BorderSizePixel = 0,
                Text = string.format("%.2f  %s = %s", entry.time, entry.property, entry.value),
                TextColor3 = shared.theme.text,
                TextSize = 10,
                Font = Enum.Font.Code,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = ui.watchList,
            })
            shared.round(row, 4)
            local p = Instance.new("UIPadding")
            p.PaddingLeft = UDim.new(0, 6)
            p.Parent = row
        end
    end

    local function refresh()
        if not state.selected or not state.selected.Parent and state.selected ~= game then
            state.selected = game
        end
        buildProperties()
        buildChildren()
        buildWatchLog()
        state.dirty = false
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then return state.window end
        state.window = shared.makeWindow("Instance Inspector", 980, 580)
        local content = state.window.content

        ui.path = shared.makeTextBox(content, "game.Workspace.Model.Part", "game")
        ui.path.Position = UDim2.fromOffset(10, 10)
        ui.path.Size = UDim2.new(1, -150, 0, 30)
        local go = shared.makeButton(content, "Inspect Path", function()
            local instance = resolvePath(ui.path.Text)
            if instance then
                clearWatches()
                selectInstance(instance)
            else
                shared.notify("Path not found", 3)
            end
        end, 120)
        go.Position = UDim2.new(1, -130, 0, 10)

        ui.properties = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(10, 50),
            Size = UDim2.new(0.5, -15, 1, -60),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = content,
        })
        shared.round(ui.properties, 8)
        shared.stroke(ui.properties, shared.theme.border, 0.25, 1)
        local pp = Instance.new("UIPadding")
        pp.PaddingTop = UDim.new(0, 8)
        pp.PaddingLeft = UDim.new(0, 8)
        pp.PaddingRight = UDim.new(0, 8)
        pp.PaddingBottom = UDim.new(0, 8)
        pp.Parent = ui.properties
        local propLayout = Instance.new("UIListLayout")
        propLayout.Padding = UDim.new(0, 4)
        propLayout.Parent = ui.properties

        local right = shared.create("Frame", {
            Position = UDim2.new(0.5, 5, 0, 50),
            Size = UDim2.new(0.5, -15, 1, -60),
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

        local childTitle = shared.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            Text = "CHILDREN",
            TextColor3 = shared.theme.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = right,
        })
        ui.children = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 22),
            Size = UDim2.new(1, 0, 0.48, -26),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = right,
        })
        shared.round(ui.children, 6)
        local childLayout = Instance.new("UIListLayout")
        childLayout.Padding = UDim.new(0, 4)
        childLayout.Parent = ui.children

        ui.propertyBox = shared.makeTextBox(right, "Property to watch", "")
        ui.propertyBox.Position = UDim2.new(0, 0, 0.48, 2)
        ui.propertyBox.Size = UDim2.new(0.45, -3, 0, 30)
        ui.valueBox = shared.makeTextBox(right, "Selected value", "")
        ui.valueBox.Position = UDim2.new(0.45, 3, 0.48, 2)
        ui.valueBox.Size = UDim2.new(0.55, -3, 0, 30)

        local watchButton = shared.makeButton(right, "Watch Property", function()
            if ui.propertyBox.Text ~= "" then addWatch(ui.propertyBox.Text) end
        end, 108)
        watchButton.Position = UDim2.new(0, 0, 0.48, 38)
        local copyPath = shared.makeButton(right, "Copy Path", function()
            if state.selected then shared.copy(shared.instancePath(state.selected)) end
        end, 90)
        copyPath.Position = UDim2.new(0, 114, 0.48, 38)
        local parentButton = shared.makeButton(right, "Parent", function()
            if state.selected and state.selected.Parent then
                clearWatches()
                selectInstance(state.selected.Parent)
            end
        end, 70)
        parentButton.Position = UDim2.new(0, 210, 0.48, 38)
        local refreshButton = shared.makeButton(right, "Refresh", function() state.dirty = true end, 76)
        refreshButton.Position = UDim2.new(0, 286, 0.48, 38)

        ui.watchList = shared.create("ScrollingFrame", {
            Position = UDim2.new(0, 0, 0.48, 74),
            Size = UDim2.new(1, 0, 0.52, -74),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = right,
        })
        shared.round(ui.watchList, 6)
        local watchLayout = Instance.new("UIListLayout")
        watchLayout.Padding = UDim.new(0, 3)
        watchLayout.Parent = ui.watchList

        shared.connect(ctx.RunService.Heartbeat, function(delta)
            state.elapsed = state.elapsed + delta
            local interval = tonumber(ctx.library.flags["Dev Inspector Refresh"]) or 0.5
            if ctx.library.flags["Dev Inspector Auto Refresh"] ~= false and state.elapsed >= interval then
                state.elapsed = 0
                state.dirty = true
            end
            if state.window and state.window.root.Visible and state.dirty then refresh() end
        end)
        selectInstance(state.selected or game)
        return state.window
    end

    local api = {}
    function api:Open()
        buildWindow():Show()
        state.dirty = true
    end
    function api:Select(instance)
        clearWatches()
        return selectInstance(instance)
    end
    function api:GetSelected() return state.selected end
    function api:Watch(property) addWatch(property) end
    function api:Resolve(path) return resolvePath(path) end
    function api:GetState() return state end

    dev.apis.instanceInspector = api

    local function cleanup()
        clearWatches()
        if state.window then state.window:Destroy() end
    end

    local module = {name = "instance_inspector", setup = function() end, cleanup = cleanup, api = api}
    dev.modules.instance_inspector = module
    shared.addCleanup(cleanup)
    return module
end
