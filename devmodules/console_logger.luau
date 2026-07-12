--[[
    xanhub | devmodules | console logger

    Captures LogService output and ScriptContext errors into a searchable window.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub console] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub console] dev_shared missing")
    local section = dev.right:AddSection("Console Logger")

    section:AddToggle({text = "Capture Console", flag = "Dev Console Enabled", state = true})
    section:AddToggle({text = "Include Output", flag = "Dev Console Output", state = true})
    section:AddToggle({text = "Include Warnings", flag = "Dev Console Warnings", state = true})
    section:AddToggle({text = "Include Errors", flag = "Dev Console Errors", state = true})
    section:AddSlider({text = "Maximum Entries", flag = "Dev Console Max Entries", min = 100, max = 3000, value = 800, float = 100})
    section:AddButton({text = "Open Console Logger", callback = function()
        shared.invokeApi("consoleLogger", "Open")
    end})
    section:AddButton({text = "Clear Console Log", callback = function()
        shared.invokeApi("consoleLogger", "Clear")
    end})

    local state = {
        entries = {},
        rows = {},
        selected = nil,
        dirty = true,
        window = nil,
        entryEvent = Instance.new("BindableEvent"),
    }
    local ui = {}

    local function categoryFor(messageType)
        if messageType == Enum.MessageType.MessageWarning then return "Warning" end
        if messageType == Enum.MessageType.MessageError then return "Error" end
        if messageType == Enum.MessageType.MessageInfo then return "Info" end
        return "Output"
    end

    local function allowed(category)
        if ctx.library.flags["Dev Console Enabled"] == false then return false end
        if category == "Warning" then return ctx.library.flags["Dev Console Warnings"] ~= false end
        if category == "Error" then return ctx.library.flags["Dev Console Errors"] ~= false end
        return ctx.library.flags["Dev Console Output"] ~= false
    end

    local function addEntry(category, message, stack, source)
        if not allowed(category) then return end
        message = tostring(message or "")
        if string.find(message, "[xanhub console internal]", 1, true) then return end
        local entry = {
            category = category,
            message = message,
            stack = tostring(stack or ""),
            source = tostring(source or ""),
            timestamp = os.clock(),
            wallTime = os.time(),
        }
        table.insert(state.entries, 1, entry)
        local maxEntries = math.clamp(tonumber(ctx.library.flags["Dev Console Max Entries"]) or 800, 100, 3000)
        while #state.entries > maxEntries do table.remove(state.entries) end
        state.entryEvent:Fire(entry)
        state.dirty = true
    end

    local function selectEntry(entry)
        state.selected = entry
        if not entry then
            ui.details.Text = "No entry selected"
            return
        end
        local lines = {
            entry.category .. "  |  " .. tostring(entry.wallTime),
            entry.source ~= "" and ("Source: " .. entry.source) or "",
            "",
            entry.message,
        }
        if entry.stack ~= "" then
            table.insert(lines, "")
            table.insert(lines, entry.stack)
        end
        ui.details.Text = table.concat(lines, "\n")
    end

    local function matches(entry)
        local query = ui.search and string.lower(ui.search.Text) or ""
        local filter = ui.filter or "All"
        if filter ~= "All" and entry.category ~= filter then return false end
        if query == "" then return true end
        local haystack = string.lower(entry.category .. " " .. entry.message .. " " .. entry.stack .. " " .. entry.source)
        return string.find(haystack, query, 1, true) ~= nil
    end

    local function clearRows()
        for _, row in ipairs(state.rows) do shared.safeDestroy(row) end
        state.rows = {}
    end

    local function colorFor(category)
        if category == "Error" then return shared.theme.danger end
        if category == "Warning" then return shared.theme.warning end
        if category == "Info" then return shared.accent() end
        return shared.theme.muted
    end

    local function rebuildRows()
        if not ui.list then return end
        clearRows()
        local shown = 0
        for _, entry in ipairs(state.entries) do
            if matches(entry) then
                shown = shown + 1
                if shown > 400 then break end
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 34),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.08,
                    BorderSizePixel = 0,
                    Text = "",
                    Parent = ui.list,
                })
                shared.round(row, 5)
                shared.create("Frame", {
                    Size = UDim2.fromOffset(3, 34),
                    BackgroundColor3 = colorFor(entry.category),
                    BorderSizePixel = 0,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(9, 2),
                    Size = UDim2.new(1, -16, 0, 15),
                    BackgroundTransparency = 1,
                    Text = entry.category,
                    TextColor3 = colorFor(entry.category),
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(9, 16),
                    Size = UDim2.new(1, -16, 0, 15),
                    BackgroundTransparency = 1,
                    Text = string.gsub(entry.message, "\n", " "),
                    TextColor3 = shared.theme.text,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.connect(row.MouseButton1Click, function() selectEntry(entry) end)
                table.insert(state.rows, row)
            end
        end
        if ui.count then ui.count.Text = string.format("%d entries • %d shown", #state.entries, shown) end
        state.dirty = false
    end

    local function exportAll()
        local lines = {}
        for index = #state.entries, 1, -1 do
            local entry = state.entries[index]
            table.insert(lines, string.format("[%s] %s", entry.category, entry.message))
            if entry.stack ~= "" then table.insert(lines, entry.stack) end
        end
        shared.copy(table.concat(lines, "\n"))
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then return state.window end
        state.window = shared.makeWindow("Console Logger", 900, 540)
        local content = state.window.content

        local left = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(0.5, -15, 1, -20),
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

        ui.search = shared.makeTextBox(left, "Search output, warnings, errors, stack", "")
        ui.filter = "All"
        local filterRow = shared.create("Frame", {Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = left})
        local filterButton
        filterButton = shared.makeButton(filterRow, "Filter: All", function()
            local values = {"All", "Output", "Info", "Warning", "Error"}
            local index = table.find(values, ui.filter) or 1
            ui.filter = values[index % #values + 1]
            filterButton.Text = "Filter: " .. ui.filter
            state.dirty = true
        end, 112)
        ui.count = shared.create("TextLabel", {
            Position = UDim2.fromOffset(120, 0),
            Size = UDim2.new(1, -120, 1, 0),
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
            Position = UDim2.new(0.5, 5, 0, 10),
            Size = UDim2.new(0.5, -15, 1, -20),
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
            Size = UDim2.new(1, 0, 1, -42),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = "No entry selected",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
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

        local buttons = shared.create("Frame", {Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = right})
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.Padding = UDim.new(0, 6)
        layout.Parent = buttons
        shared.makeButton(buttons, "Copy Selected", function()
            if state.selected then shared.copy(ui.details.Text) end
        end, 112)
        shared.makeButton(buttons, "Export All", exportAll, 92)
        shared.makeButton(buttons, "Clear", function()
            state.entries = {}
            state.selected = nil
            selectEntry(nil)
            state.dirty = true
        end, 70)

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
    function api:GetEntries() return state.entries end
    function api:OnEntry(callback) return state.entryEvent.Event:Connect(callback) end
    function api:GetState() return state end

    dev.apis.consoleLogger = api

    local function setup()
        local logService = game:GetService("LogService")
        local scriptContext = game:GetService("ScriptContext")
        shared.connect(logService.MessageOut, function(message, messageType)
            addEntry(categoryFor(messageType), message, "", "LogService")
        end)
        shared.connect(scriptContext.Error, function(message, stackTrace, scriptInstance)
            addEntry("Error", message, stackTrace, scriptInstance and shared.instancePath(scriptInstance) or "ScriptContext")
        end)
    end

    local function cleanup()
        shared.safeDestroy(state.entryEvent)
        if state.window then state.window:Destroy() end
    end

    local module = {name = "console_logger", setup = setup, cleanup = cleanup, api = api}
    dev.modules.console_logger = module
    shared.addCleanup(cleanup)
    return module
end
