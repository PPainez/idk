--[[
    xanhub | devmodules | advanced notifications

    Stacked, queued, typed notifications for debug tools, moderation notices,
    progress tasks, developer diagnostics, and general script feedback.

    Public API:
      api:Notify(options|string)
      api:Debug(message, options?)
      api:Info(message, options?)
      api:Success(message, options?)
      api:Warn(message, options?)
      api:Error(message, options?)
      api:Mod(message, options?)
      api:Progress(options) -> handle
      api:Dismiss(idOrHandle, reason?)
      api:Clear(channel?)
      api:Open()
      api:GetHistory()
      api:OnNotification(callback)
      api:OnDismiss(callback)
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub notifications] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub notifications] dev_shared missing")

    local TweenService = game:GetService("TweenService")
    local TextService = game:GetService("TextService")
    local HttpService = game:GetService("HttpService")
    local RunService = game:GetService("RunService")

    local settingsSection = dev.left:AddSection("Advanced Notifications")
    settingsSection:AddToggle({text = "Enabled", flag = "Dev Notifications Enabled", state = true})
    settingsSection:AddToggle({text = "Show Debug Notices", flag = "Dev Notifications Debug", state = true})
    settingsSection:AddToggle({text = "Pause Timer on Hover", flag = "Dev Notifications Pause Hover", state = true})
    settingsSection:AddToggle({text = "Show Timestamp", flag = "Dev Notifications Timestamp", state = true})
    settingsSection:AddToggle({text = "Reduced Motion", flag = "Dev Notifications Reduced Motion", state = false})
    settingsSection:AddList({
        text = "Stack Placement",
        flag = "Dev Notifications Placement",
        values = {"Top Right", "Bottom Right", "Top Left", "Bottom Left"},
        value = "Top Right",
    })
    settingsSection:AddSlider({
        text = "Maximum Visible",
        flag = "Dev Notifications Max Visible",
        min = 1,
        max = 8,
        value = 5,
        float = 1,
    })
    settingsSection:AddSlider({
        text = "Default Duration",
        flag = "Dev Notifications Duration",
        min = 1,
        max = 15,
        value = 5,
        float = 0.5,
        suffix = "s",
    })
    settingsSection:AddSlider({
        text = "Toast Width",
        flag = "Dev Notifications Width",
        min = 280,
        max = 460,
        value = 360,
        float = 10,
        suffix = " px",
    })
    settingsSection:AddSlider({
        text = "History Limit",
        flag = "Dev Notifications History Limit",
        min = 50,
        max = 1000,
        value = 250,
        float = 50,
    })
    settingsSection:AddButton({text = "Open Notification Center", callback = function()
        if dev.apis.notifications then
            dev.apis.notifications:Open()
        end
    end})
    settingsSection:AddButton({text = "Test Notification Stack", callback = function()
        if dev.apis.notifications then
            dev.apis.notifications:Demo()
        end
    end})
    settingsSection:AddButton({text = "Clear Active Notifications", callback = function()
        if dev.apis.notifications then
            dev.apis.notifications:Clear()
        end
    end})

    local historySection = dev.right:AddSection("Notification History")
    historySection:AddToggle({text = "Record History", flag = "Dev Notifications Record History", state = true})
    historySection:AddToggle({text = "Group Duplicate Keys", flag = "Dev Notifications Group Duplicates", state = true})
    historySection:AddButton({text = "Copy Notification History", callback = function()
        if dev.apis.notifications then
            dev.apis.notifications:CopyHistory()
        end
    end})
    historySection:AddButton({text = "Clear Notification History", callback = function()
        if dev.apis.notifications then
            dev.apis.notifications:ClearHistory()
        end
    end})
    local runtimeLabel = historySection:AddLabel("Status: waiting for setup")
    historySection:AddLabel("API: ctx.devtools.apis.notifications")

    local TYPES = {
        debug = {
            title = "Debug",
            icon = "D",
            color = Color3.fromRGB(129, 151, 184),
            priority = -10,
        },
        info = {
            title = "Information",
            icon = "i",
            color = Color3.fromRGB(0, 170, 255),
            priority = 0,
        },
        success = {
            title = "Success",
            icon = "+",
            color = Color3.fromRGB(80, 221, 140),
            priority = 10,
        },
        warning = {
            title = "Warning",
            icon = "!",
            color = Color3.fromRGB(255, 188, 79),
            priority = 20,
        },
        error = {
            title = "Error",
            icon = "x",
            color = Color3.fromRGB(255, 82, 102),
            priority = 30,
        },
        mod = {
            title = "Moderator Notice",
            icon = "M",
            color = Color3.fromRGB(189, 117, 255),
            priority = 40,
        },
    }

    local state = {
        destroyed = false,
        root = nil,
        stack = nil,
        layout = nil,
        active = {},
        activeOrder = {},
        pending = {},
        byKey = {},
        history = {},
        rows = {},
        nextId = 0,
        window = nil,
        dirty = true,
        filter = "All",
        placement = nil,
        width = nil,
        notifyEvent = Instance.new("BindableEvent"),
        dismissEvent = Instance.new("BindableEvent"),
    }

    local ui = {}
    local api = {}
    local module

    local function flag(name, fallback)
        local value = ctx.library.flags[name]
        if value == nil then
            return fallback
        end
        return value
    end

    local function numberFlag(name, fallback)
        return tonumber(ctx.library.flags[name]) or fallback
    end

    local function normalizeType(value)
        value = string.lower(tostring(value or "info"))
        if value == "warn" then
            value = "warning"
        elseif value == "moderation" or value == "moderator" or value == "admin" then
            value = "mod"
        elseif value == "fatal" then
            value = "error"
        end
        if not TYPES[value] then
            value = "info"
        end
        return value
    end

    local function copyTable(source)
        local result = {}
        if type(source) == "table" then
            for key, value in pairs(source) do
                result[key] = value
            end
        end
        return result
    end

    local function safeCall(callback, ...)
        if type(callback) ~= "function" then
            return true
        end
        local ok, result = pcall(callback, ...)
        if not ok then
            warn("[xanhub notifications] callback failed: " .. tostring(result))
        end
        return ok, result
    end

    local function tween(object, duration, properties, style, direction)
        if not object or not object.Parent then
            return nil
        end
        if flag("Dev Notifications Reduced Motion", false) then
            for property, value in pairs(properties) do
                pcall(function()
                    object[property] = value
                end)
            end
            return nil
        end
        local ok, animation = pcall(function()
            return TweenService:Create(
                object,
                TweenInfo.new(
                    duration or 0.18,
                    style or Enum.EasingStyle.Quint,
                    direction or Enum.EasingDirection.Out
                ),
                properties
            )
        end)
        if ok and animation then
            animation:Play()
            return animation
        end
        return nil
    end

    local function typeData(typeName)
        return TYPES[normalizeType(typeName)]
    end

    local function normalizeOptions(input, extra)
        local options
        if type(input) == "table" then
            options = copyTable(input)
        else
            options = copyTable(extra)
            options.message = tostring(input or options.message or "")
        end

        options.type = normalizeType(options.type or options.level or options.kind)
        local style = typeData(options.type)
        options.title = tostring(options.title or style.title)
        options.message = tostring(options.message or options.text or "")
        options.channel = tostring(options.channel or "default")
        options.priority = tonumber(options.priority) or style.priority
        options.duration = tonumber(options.duration)
        if options.duration == nil then
            options.duration = numberFlag("Dev Notifications Duration", 5)
        end
        options.sticky = options.sticky == true or options.duration <= 0
        options.icon = tostring(options.icon or style.icon)
        options.color = typeof(options.color) == "Color3" and options.color or style.color
        options.key = options.key and tostring(options.key) or nil
        options.group = options.group ~= false
        options.replace = options.replace ~= false
        options.progress = tonumber(options.progress)
        if options.progress then
            options.progress = math.clamp(options.progress, 0, 1)
        end
        options.actions = type(options.actions) == "table" and options.actions or {}
        options.metadata = type(options.metadata) == "table" and options.metadata or {}
        options.createdAt = os.time()
        options.createdClock = os.clock()
        return options
    end

    local function getStackWidth()
        return math.clamp(numberFlag("Dev Notifications Width", 360), 280, 460)
    end

    local function ensureRoot()
        if state.root and state.root.Parent then
            return state.root
        end

        local parent = ctx.library.base
        if not parent then
            local ok, result = pcall(function()
                if type(gethui) == "function" then
                    return gethui()
                end
                return game:GetService("CoreGui")
            end)
            parent = ok and result or nil
        end
        assert(parent, "[xanhub notifications] no UI parent")

        state.root = shared.create("Frame", {
            Name = "xanhub_notification_overlay",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Active = false,
            ZIndex = 7900,
            Parent = parent,
        })

        state.stack = shared.create("Frame", {
            Name = "NotificationStack",
            Size = UDim2.new(0, getStackWidth(), 1, -36),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 7901,
            Parent = state.root,
        })

        state.layout = Instance.new("UIListLayout")
        state.layout.FillDirection = Enum.FillDirection.Vertical
        state.layout.SortOrder = Enum.SortOrder.LayoutOrder
        state.layout.Padding = UDim.new(0, 8)
        state.layout.Parent = state.stack
        return state.root
    end

    local function applyPlacement(force)
        if not state.stack or not state.stack.Parent then
            return
        end
        local placement = tostring(flag("Dev Notifications Placement", "Top Right"))
        local width = getStackWidth()
        if not force and state.placement == placement and state.width == width then
            return
        end
        state.placement = placement
        state.width = width
        state.stack.Size = UDim2.new(0, width, 1, -36)

        local right = string.find(placement, "Right", 1, true) ~= nil
        local bottom = string.find(placement, "Bottom", 1, true) ~= nil
        state.stack.AnchorPoint = Vector2.new(right and 1 or 0, bottom and 1 or 0)
        state.stack.Position = UDim2.new(right and 1 or 0, right and -18 or 18, bottom and 1 or 0, bottom and -18 or 18)
        state.layout.HorizontalAlignment = right and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
        state.layout.VerticalAlignment = bottom and Enum.VerticalAlignment.Bottom or Enum.VerticalAlignment.Top
    end

    local function formatClock(timestamp)
        local ok, result = pcall(function()
            return os.date("%H:%M:%S", timestamp)
        end)
        return ok and result or tostring(timestamp)
    end

    local function measureHeight(record)
        local width = getStackWidth()
        local messageWidth = math.max(120, width - 74)
        local textSize = 12
        local bounds = TextService:GetTextSize(
            record.message ~= "" and record.message or " ",
            textSize,
            Enum.Font.Code,
            Vector2.new(messageWidth, 1000)
        )
        local messageHeight = math.clamp(bounds.Y, 16, 74)
        local actionHeight = #record.actions > 0 and 34 or 0
        local progressHeight = record.progress ~= nil and 8 or 0
        return math.clamp(54 + messageHeight + actionHeight + progressHeight, 74, 170)
    end

    local function categoryText(record)
        local parts = {string.upper(record.type), record.channel}
        if flag("Dev Notifications Timestamp", true) then
            table.insert(parts, formatClock(record.createdAt))
        end
        return table.concat(parts, "  •  ")
    end

    local function setTextFade(root, transparency)
        if not root then
            return
        end
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                descendant.TextTransparency = transparency
            elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
                descendant.ImageTransparency = transparency
            end
        end
    end

    local function refreshRecord(record, resetTimer)
        if not record.ui or not record.ui.wrapper or not record.ui.wrapper.Parent then
            return
        end
        local uiRecord = record.ui
        local height = measureHeight(record)
        record.height = height
        uiRecord.wrapper.Size = UDim2.new(1, 0, 0, height)
        uiRecord.card.Size = UDim2.new(1, 0, 1, 0)
        uiRecord.accent.BackgroundColor3 = record.color
        uiRecord.icon.BackgroundColor3 = record.color
        uiRecord.iconLabel.Text = record.icon
        uiRecord.title.Text = record.title
        uiRecord.message.Text = record.message
        uiRecord.meta.Text = categoryText(record)
        uiRecord.count.Visible = record.count > 1
        uiRecord.count.Text = "×" .. tostring(record.count)
        uiRecord.progressTrack.Visible = record.progress ~= nil
        uiRecord.progressFill.BackgroundColor3 = record.color
        uiRecord.progressFill.Size = UDim2.new(record.progress or 0, 0, 1, 0)
        uiRecord.timerFill.BackgroundColor3 = record.color

        local actionHeight = #record.actions > 0 and 34 or 0
        local progressHeight = record.progress ~= nil and 8 or 0
        uiRecord.message.Position = UDim2.fromOffset(54, 37)
        uiRecord.message.Size = UDim2.new(1, -66, 1, -(50 + actionHeight + progressHeight))
        uiRecord.actionRow.Visible = #record.actions > 0
        uiRecord.actionRow.Position = UDim2.new(0, 54, 1, -(38 + progressHeight))
        uiRecord.progressTrack.Position = UDim2.new(0, 12, 1, -10)
        uiRecord.timerTrack.Position = UDim2.new(0, 0, 1, -2)

        for _, child in ipairs(uiRecord.actionRow:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        for index, action in ipairs(record.actions) do
            if index > 3 then
                break
            end
            local button = shared.create("TextButton", {
                Size = UDim2.new(0, 92, 0, 24),
                BackgroundColor3 = shared.theme.panel2,
                BorderSizePixel = 0,
                Text = tostring(action.text or action.label or ("Action " .. index)),
                TextColor3 = shared.theme.text,
                TextSize = 10,
                Font = Enum.Font.Code,
                AutoButtonColor = false,
                ZIndex = 7912,
                Parent = uiRecord.actionRow,
            })
            shared.round(button, 5)
            local buttonStroke = shared.stroke(button, shared.theme.border, 0.3, 1)
            shared.connect(button.MouseEnter, function()
                buttonStroke.Color = record.color
            end)
            shared.connect(button.MouseLeave, function()
                buttonStroke.Color = shared.theme.border
            end)
            shared.connect(button.MouseButton1Click, function()
                local ok, result = safeCall(action.callback, record.handle, record)
                if ok and result ~= false and action.close ~= false then
                    api:Dismiss(record.id, "action")
                end
            end)
        end

        if resetTimer then
            record.timerToken = record.timerToken + 1
            record.remaining = record.sticky and math.huge or math.max(0.05, record.duration)
        end
    end

    local function makeHandle(record)
        local handle = {}
        handle.id = record.id

        function handle:Update(changes)
            if type(changes) ~= "table" or record.closed then
                return self
            end
            if changes.title ~= nil then record.title = tostring(changes.title) end
            if changes.message ~= nil or changes.text ~= nil then record.message = tostring(changes.message or changes.text or "") end
            if changes.type ~= nil or changes.level ~= nil then
                record.type = normalizeType(changes.type or changes.level)
                local style = typeData(record.type)
                if changes.color == nil then record.color = style.color end
                if changes.icon == nil then record.icon = style.icon end
            end
            if typeof(changes.color) == "Color3" then record.color = changes.color end
            if changes.icon ~= nil then record.icon = tostring(changes.icon) end
            if changes.channel ~= nil then record.channel = tostring(changes.channel) end
            if changes.duration ~= nil then
                record.duration = tonumber(changes.duration) or record.duration
                record.sticky = changes.sticky == true or record.duration <= 0
            elseif changes.sticky ~= nil then
                record.sticky = changes.sticky == true
            end
            if changes.progress ~= nil then
                record.progress = math.clamp(tonumber(changes.progress) or 0, 0, 1)
            end
            if type(changes.actions) == "table" then record.actions = changes.actions end
            refreshRecord(record, changes.resetTimer ~= false)
            state.dirty = true
            return self
        end

        function handle:SetProgress(value, message)
            record.progress = math.clamp(tonumber(value) or 0, 0, 1)
            if message ~= nil then
                record.message = tostring(message)
            end
            refreshRecord(record, false)
            return self
        end

        function handle:Complete(message, duration)
            return self:Update({
                type = "success",
                title = "Complete",
                message = message or record.message,
                progress = 1,
                duration = duration or 3,
                sticky = false,
                resetTimer = true,
            })
        end

        function handle:Fail(message, duration)
            return self:Update({
                type = "error",
                title = "Failed",
                message = message or record.message,
                duration = duration or 6,
                sticky = false,
                resetTimer = true,
            })
        end

        function handle:Dismiss(reason)
            api:Dismiss(record.id, reason or "api")
        end

        function handle:IsActive()
            return record.closed ~= true and state.active[record.id] == record
        end

        function handle:GetRecord()
            return record
        end

        record.handle = handle
        return handle
    end

    local function removeActiveOrder(id)
        for index, value in ipairs(state.activeOrder) do
            if value == id then
                table.remove(state.activeOrder, index)
                return
            end
        end
    end

    local function appendHistory(record)
        if flag("Dev Notifications Record History", true) == false then
            return
        end
        table.insert(state.history, 1, record.history)
        local limit = math.clamp(numberFlag("Dev Notifications History Limit", 250), 50, 1000)
        while #state.history > limit do
            table.remove(state.history)
        end
        state.dirty = true
    end

    local function makeRecord(options)
        state.nextId = state.nextId + 1
        local record = {
            id = state.nextId,
            type = options.type,
            title = options.title,
            message = options.message,
            channel = options.channel,
            priority = options.priority,
            duration = options.duration,
            sticky = options.sticky,
            icon = options.icon,
            color = options.color,
            key = options.key,
            group = options.group,
            replace = options.replace,
            progress = options.progress,
            actions = options.actions,
            metadata = options.metadata,
            createdAt = options.createdAt,
            createdClock = options.createdClock,
            count = 1,
            hovered = false,
            closed = false,
            closing = false,
            timerToken = 0,
            remaining = options.sticky and math.huge or math.max(0.05, options.duration),
            ui = nil,
        }
        record.history = {
            id = record.id,
            type = record.type,
            title = record.title,
            message = record.message,
            channel = record.channel,
            key = record.key,
            priority = record.priority,
            createdAt = record.createdAt,
            count = record.count,
            status = "queued",
            metadata = record.metadata,
        }
        makeHandle(record)
        appendHistory(record)
        return record
    end

    local function createToast(record)
        ensureRoot()
        applyPlacement(true)

        local wrapper = shared.create("Frame", {
            Name = "Toast_" .. tostring(record.id),
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            LayoutOrder = -(record.priority * 100000) + record.id,
            ZIndex = 7902,
            Parent = state.stack,
        })

        local right = string.find(state.placement or "Top Right", "Right", 1, true) ~= nil
        local slideOffset = right and 34 or -34
        local card = shared.create("Frame", {
            Name = "Card",
            Position = UDim2.fromOffset(slideOffset, 0),
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = shared.theme.panel,
            BackgroundTransparency = 0.03,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Active = true,
            ZIndex = 7903,
            Parent = wrapper,
        })
        shared.round(card, 9)
        local border = shared.stroke(card, shared.theme.border, 0.12, 1)

        local accent = shared.create("Frame", {
            Size = UDim2.new(0, 4, 1, 0),
            BackgroundColor3 = record.color,
            BorderSizePixel = 0,
            ZIndex = 7905,
            Parent = card,
        })

        local icon = shared.create("Frame", {
            Position = UDim2.fromOffset(12, 12),
            Size = UDim2.fromOffset(30, 30),
            BackgroundColor3 = record.color,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            ZIndex = 7906,
            Parent = card,
        })
        shared.round(icon, 7)

        local iconLabel = shared.create("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = record.icon,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 14,
            Font = Enum.Font.Code,
            ZIndex = 7907,
            Parent = icon,
        })

        local title = shared.create("TextLabel", {
            Position = UDim2.fromOffset(54, 9),
            Size = UDim2.new(1, -92, 0, 20),
            BackgroundTransparency = 1,
            Text = record.title,
            TextColor3 = shared.theme.text,
            TextSize = 13,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 7907,
            Parent = card,
        })

        local meta = shared.create("TextLabel", {
            Position = UDim2.fromOffset(54, 26),
            Size = UDim2.new(1, -92, 0, 12),
            BackgroundTransparency = 1,
            Text = categoryText(record),
            TextColor3 = shared.theme.muted,
            TextSize = 9,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 7907,
            Parent = card,
        })

        local message = shared.create("TextLabel", {
            Position = UDim2.fromOffset(54, 38),
            Size = UDim2.new(1, -66, 1, -50),
            BackgroundTransparency = 1,
            Text = record.message,
            TextColor3 = shared.theme.text,
            TextTransparency = 0.06,
            TextSize = 12,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 7907,
            Parent = card,
        })

        local close = shared.create("TextButton", {
            Position = UDim2.new(1, -32, 0, 5),
            Size = UDim2.fromOffset(27, 27),
            BackgroundTransparency = 1,
            Text = "×",
            TextColor3 = shared.theme.muted,
            TextSize = 16,
            Font = Enum.Font.Code,
            AutoButtonColor = false,
            ZIndex = 7910,
            Parent = card,
        })

        local count = shared.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -10, 1, -8),
            Size = UDim2.fromOffset(34, 18),
            BackgroundColor3 = record.color,
            BackgroundTransparency = 0.14,
            BorderSizePixel = 0,
            Text = "×1",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 9,
            Font = Enum.Font.Code,
            Visible = false,
            ZIndex = 7911,
            Parent = card,
        })
        shared.round(count, 999)

        local actionRow = shared.create("Frame", {
            Size = UDim2.new(1, -66, 0, 26),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 7911,
            Parent = card,
        })
        local actionLayout = Instance.new("UIListLayout")
        actionLayout.FillDirection = Enum.FillDirection.Horizontal
        actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        actionLayout.Padding = UDim.new(0, 6)
        actionLayout.Parent = actionRow

        local progressTrack = shared.create("Frame", {
            Size = UDim2.new(1, -24, 0, 4),
            BackgroundColor3 = shared.theme.background,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 7908,
            Parent = card,
        })
        shared.round(progressTrack, 999)

        local progressFill = shared.create("Frame", {
            Size = UDim2.new(record.progress or 0, 0, 1, 0),
            BackgroundColor3 = record.color,
            BorderSizePixel = 0,
            ZIndex = 7909,
            Parent = progressTrack,
        })
        shared.round(progressFill, 999)

        local timerTrack = shared.create("Frame", {
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = shared.theme.background,
            BackgroundTransparency = 0.45,
            BorderSizePixel = 0,
            ZIndex = 7908,
            Parent = card,
        })

        local timerFill = shared.create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = record.color,
            BorderSizePixel = 0,
            ZIndex = 7909,
            Parent = timerTrack,
        })

        record.ui = {
            wrapper = wrapper,
            card = card,
            border = border,
            accent = accent,
            icon = icon,
            iconLabel = iconLabel,
            title = title,
            meta = meta,
            message = message,
            close = close,
            count = count,
            actionRow = actionRow,
            progressTrack = progressTrack,
            progressFill = progressFill,
            timerTrack = timerTrack,
            timerFill = timerFill,
        }

        shared.connect(card.MouseEnter, function()
            record.hovered = true
            border.Color = record.color
            close.TextColor3 = record.color
        end)
        shared.connect(card.MouseLeave, function()
            record.hovered = false
            border.Color = shared.theme.border
            close.TextColor3 = shared.theme.muted
        end)
        shared.connect(close.MouseButton1Click, function()
            api:Dismiss(record.id, "user")
        end)

        refreshRecord(record, true)
        local targetHeight = record.height
        wrapper.Size = UDim2.new(1, 0, 0, 0)
        setTextFade(card, 1)
        tween(wrapper, 0.22, {Size = UDim2.new(1, 0, 0, targetHeight)}, Enum.EasingStyle.Quint)
        task.defer(function()
            if card.Parent then
                tween(card, 0.24, {Position = UDim2.fromOffset(0, 0)}, Enum.EasingStyle.Quint)
                setTextFade(card, 0)
            end
        end)

        record.history.status = "visible"
        state.dirty = true
    end

    local function startTimer(record)
        if record.sticky then
            if record.ui and record.ui.timerTrack then
                record.ui.timerTrack.Visible = false
            end
            return
        end

        if record.ui and record.ui.timerTrack then
            record.ui.timerTrack.Visible = true
        end
        local token = record.timerToken
        task.spawn(function()
            local last = os.clock()
            while not state.destroyed and not record.closed and record.timerToken == token do
                RunService.Heartbeat:Wait()
                local now = os.clock()
                local delta = math.max(0, now - last)
                last = now
                local paused = record.hovered and flag("Dev Notifications Pause Hover", true)
                if not paused then
                    record.remaining = record.remaining - delta
                end
                if record.ui and record.ui.timerFill and record.ui.timerFill.Parent then
                    local ratio = math.clamp(record.remaining / math.max(0.05, record.duration), 0, 1)
                    record.ui.timerFill.Size = UDim2.new(ratio, 0, 1, 0)
                end
                if record.remaining <= 0 then
                    api:Dismiss(record.id, "timeout")
                    break
                end
            end
        end)
    end

    local function sortPending()
        table.sort(state.pending, function(a, b)
            if a.priority == b.priority then
                return a.id < b.id
            end
            return a.priority > b.priority
        end)
    end

    local function activeCount()
        local count = 0
        for _ in pairs(state.active) do
            count = count + 1
        end
        return count
    end

    local function promotePending()
        if state.destroyed then
            return
        end
        local maximum = math.clamp(numberFlag("Dev Notifications Max Visible", 5), 1, 8)
        sortPending()
        while activeCount() < maximum and #state.pending > 0 do
            local record = table.remove(state.pending, 1)
            if not record.closed then
                state.active[record.id] = record
                table.insert(state.activeOrder, record.id)
                createToast(record)
                startTimer(record)
            end
        end
        runtimeLabel.Text = string.format("Status: %d visible • %d queued • %d history", activeCount(), #state.pending, #state.history)
    end

    function api:Dismiss(idOrHandle, reason)
        local id = type(idOrHandle) == "table" and tonumber(idOrHandle.id) or tonumber(idOrHandle)
        if not id then
            return false
        end
        local record = state.active[id]
        if not record then
            for index, queued in ipairs(state.pending) do
                if queued.id == id then
                    record = queued
                    table.remove(state.pending, index)
                    break
                end
            end
        end
        if not record or record.closed or record.closing then
            return false
        end

        record.closing = true
        record.timerToken = record.timerToken + 1
        if record.key and state.byKey[record.key] == record then
            state.byKey[record.key] = nil
        end
        state.active[id] = nil
        removeActiveOrder(id)
        record.history.status = "dismissed"
        record.history.reason = tostring(reason or "dismissed")
        record.history.dismissedAt = os.time()
        state.dirty = true

        local function finish()
            record.closed = true
            record.closing = false
            if record.ui and record.ui.wrapper then
                shared.safeDestroy(record.ui.wrapper)
            end
            record.ui = nil
            state.dismissEvent:Fire(record, reason)
            promotePending()
        end

        if record.ui and record.ui.card and record.ui.wrapper then
            local right = string.find(state.placement or "Top Right", "Right", 1, true) ~= nil
            tween(record.ui.card, 0.18, {Position = UDim2.fromOffset(right and 38 or -38, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            setTextFade(record.ui.card, 1)
            tween(record.ui.wrapper, 0.2, {Size = UDim2.new(1, 0, 0, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.delay(flag("Dev Notifications Reduced Motion", false) and 0 or 0.21, finish)
        else
            finish()
        end
        return true
    end

    function api:Notify(input, extra)
        if state.destroyed or flag("Dev Notifications Enabled", true) == false then
            return nil
        end
        local options = normalizeOptions(input, extra)
        if options.type == "debug" and flag("Dev Notifications Debug", true) == false then
            return nil
        end

        if options.key and flag("Dev Notifications Group Duplicates", true) and options.group then
            local existing = state.byKey[options.key]
            if existing and not existing.closed then
                existing.count = existing.count + 1
                existing.history.count = existing.count
                if options.replace then
                    existing.title = options.title
                    existing.message = options.message
                    existing.type = options.type
                    existing.channel = options.channel
                    existing.priority = options.priority
                    existing.duration = options.duration
                    existing.sticky = options.sticky
                    existing.icon = options.icon
                    existing.color = options.color
                    existing.progress = options.progress
                    existing.actions = options.actions
                end
                refreshRecord(existing, true)
                if state.active[existing.id] then
                    startTimer(existing)
                end
                state.notifyEvent:Fire(existing, true)
                state.dirty = true
                return existing.handle
            end
        end

        local record = makeRecord(options)
        if record.key then
            state.byKey[record.key] = record
        end
        table.insert(state.pending, record)
        state.notifyEvent:Fire(record, false)
        promotePending()
        return record.handle
    end

    local function typedNotify(typeName, message, options)
        options = copyTable(options)
        options.type = typeName
        options.message = tostring(message or options.message or "")
        return api:Notify(options)
    end

    function api:Debug(message, options) return typedNotify("debug", message, options) end
    function api:Info(message, options) return typedNotify("info", message, options) end
    function api:Success(message, options) return typedNotify("success", message, options) end
    function api:Warn(message, options) return typedNotify("warning", message, options) end
    function api:Warning(message, options) return typedNotify("warning", message, options) end
    function api:Error(message, options) return typedNotify("error", message, options) end
    function api:Mod(message, options)
        options = copyTable(options)
        if options.duration == nil and options.sticky == nil then
            options.duration = 8
        end
        options.channel = options.channel or "moderation"
        return typedNotify("mod", message, options)
    end

    function api:Progress(options)
        options = copyTable(options)
        options.type = options.type or "info"
        options.title = options.title or "Working"
        options.message = options.message or "Task in progress"
        options.progress = tonumber(options.progress) or 0
        options.sticky = options.sticky ~= false
        options.duration = options.sticky and 0 or (options.duration or 8)
        return self:Notify(options)
    end

    function api:Clear(channel)
        channel = channel and tostring(channel) or nil
        local ids = {}
        for id, record in pairs(state.active) do
            if not channel or record.channel == channel then
                table.insert(ids, id)
            end
        end
        for _, record in ipairs(state.pending) do
            if not channel or record.channel == channel then
                table.insert(ids, record.id)
            end
        end
        for _, id in ipairs(ids) do
            self:Dismiss(id, "clear")
        end
    end

    function api:ClearHistory()
        table.clear(state.history)
        state.dirty = true
        if ui.details then
            ui.details.Text = "No notification selected"
        end
    end

    function api:GetHistory()
        local result = {}
        for index, entry in ipairs(state.history) do
            result[index] = copyTable(entry)
        end
        return result
    end

    function api:GetActive()
        local result = {}
        for _, id in ipairs(state.activeOrder) do
            local record = state.active[id]
            if record then
                table.insert(result, record.handle)
            end
        end
        return result
    end

    function api:OnNotification(callback)
        return state.notifyEvent.Event:Connect(callback)
    end

    function api:OnDismiss(callback)
        return state.dismissEvent.Event:Connect(callback)
    end

    function api:CopyHistory()
        local encoded
        local ok = pcall(function()
            encoded = HttpService:JSONEncode(self:GetHistory())
        end)
        if not ok or not encoded then
            encoded = shared.serialize(self:GetHistory(), {maxDepth = 8, maxEntries = 1000})
        end
        shared.copy(encoded)
    end

    local function historyColor(typeName)
        return typeData(typeName).color
    end

    local function historyMatches(entry)
        if state.filter ~= "All" and string.lower(state.filter) ~= entry.type then
            return false
        end
        local query = ui.search and string.lower(ui.search.Text) or ""
        if query == "" then
            return true
        end
        local haystack = string.lower(table.concat({
            entry.type or "",
            entry.title or "",
            entry.message or "",
            entry.channel or "",
            entry.key or "",
            entry.status or "",
        }, " "))
        return string.find(haystack, query, 1, true) ~= nil
    end

    local function clearRows()
        for _, row in ipairs(state.rows) do
            shared.safeDestroy(row)
        end
        state.rows = {}
    end

    local function showHistoryDetails(entry)
        if not ui.details then
            return
        end
        if not entry then
            ui.details.Text = "No notification selected"
            return
        end
        ui.details.Text = table.concat({
            string.format("[%s] %s", string.upper(entry.type or "info"), entry.title or ""),
            "Channel: " .. tostring(entry.channel or "default"),
            "Status: " .. tostring(entry.status or "unknown"),
            "Created: " .. formatClock(entry.createdAt or os.time()),
            entry.key and ("Key: " .. tostring(entry.key)) or "",
            entry.count and entry.count > 1 and ("Grouped count: " .. tostring(entry.count)) or "",
            "",
            tostring(entry.message or ""),
            "",
            "Metadata:",
            shared.serialize(entry.metadata or {}, {maxDepth = 6, maxEntries = 100}),
        }, "\n")
        ui.selected = entry
    end

    local function rebuildHistory()
        if not ui.list then
            return
        end
        clearRows()
        local shown = 0
        for _, entry in ipairs(state.history) do
            if historyMatches(entry) then
                shown = shown + 1
                if shown > 350 then
                    break
                end
                local color = historyColor(entry.type)
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 42),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.06,
                    BorderSizePixel = 0,
                    Text = "",
                    AutoButtonColor = false,
                    Parent = ui.list,
                })
                shared.round(row, 6)
                shared.create("Frame", {
                    Size = UDim2.fromOffset(3, 42),
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(10, 3),
                    Size = UDim2.new(1, -18, 0, 16),
                    BackgroundTransparency = 1,
                    Text = tostring(entry.title or typeData(entry.type).title),
                    TextColor3 = color,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(10, 19),
                    Size = UDim2.new(1, -18, 0, 18),
                    BackgroundTransparency = 1,
                    Text = string.gsub(tostring(entry.message or ""), "\n", " "),
                    TextColor3 = shared.theme.text,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.connect(row.MouseButton1Click, function()
                    showHistoryDetails(entry)
                end)
                table.insert(state.rows, row)
            end
        end
        if ui.count then
            ui.count.Text = string.format("%d recorded • %d shown", #state.history, shown)
        end
        state.dirty = false
    end

    local function buildWindow()
        if state.window and state.window.root and state.window.root.Parent then
            return state.window
        end
        state.window = shared.makeWindow("Notification Center", 900, 540)
        local content = state.window.content

        local left = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(0.52, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(left, 8)
        shared.stroke(left, shared.theme.border, 0.25, 1)
        local leftPadding = Instance.new("UIPadding")
        leftPadding.PaddingTop = UDim.new(0, 8)
        leftPadding.PaddingLeft = UDim.new(0, 8)
        leftPadding.PaddingRight = UDim.new(0, 8)
        leftPadding.PaddingBottom = UDim.new(0, 8)
        leftPadding.Parent = left

        ui.search = shared.makeTextBox(left, "Search title, message, channel, key", "")
        local filterRow = shared.create("Frame", {
            Position = UDim2.fromOffset(0, 34),
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            Parent = left,
        })
        local filterValues = {"All", "Debug", "Info", "Success", "Warning", "Error", "Mod"}
        local filterButton
        filterButton = shared.makeButton(filterRow, "Filter: All", function()
            local index = table.find(filterValues, state.filter) or 1
            state.filter = filterValues[index % #filterValues + 1]
            filterButton.Text = "Filter: " .. state.filter
            state.dirty = true
        end, 118)
        ui.count = shared.create("TextLabel", {
            Position = UDim2.fromOffset(126, 0),
            Size = UDim2.new(1, -126, 1, 0),
            BackgroundTransparency = 1,
            Text = "0 recorded",
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
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
            Parent = left,
        })
        shared.round(ui.list, 6)
        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 5)
        listLayout.Parent = ui.list
        local listPadding = Instance.new("UIPadding")
        listPadding.PaddingTop = UDim.new(0, 5)
        listPadding.PaddingLeft = UDim.new(0, 5)
        listPadding.PaddingRight = UDim.new(0, 5)
        listPadding.PaddingBottom = UDim.new(0, 5)
        listPadding.Parent = ui.list

        local right = shared.create("Frame", {
            Position = UDim2.new(0.52, 5, 0, 10),
            Size = UDim2.new(0.48, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(right, 8)
        shared.stroke(right, shared.theme.border, 0.25, 1)

        ui.details = shared.create("TextLabel", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(1, -20, 1, -56),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = "No notification selected",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = right,
        })
        shared.round(ui.details, 6)
        local detailsPadding = Instance.new("UIPadding")
        detailsPadding.PaddingTop = UDim.new(0, 8)
        detailsPadding.PaddingLeft = UDim.new(0, 8)
        detailsPadding.PaddingRight = UDim.new(0, 8)
        detailsPadding.PaddingBottom = UDim.new(0, 8)
        detailsPadding.Parent = ui.details

        local buttonRow = shared.create("Frame", {
            Position = UDim2.new(0, 10, 1, -38),
            Size = UDim2.new(1, -20, 0, 28),
            BackgroundTransparency = 1,
            Parent = right,
        })
        local buttonLayout = Instance.new("UIListLayout")
        buttonLayout.FillDirection = Enum.FillDirection.Horizontal
        buttonLayout.Padding = UDim.new(0, 6)
        buttonLayout.Parent = buttonRow
        shared.makeButton(buttonRow, "Copy Selected", function()
            if ui.selected then
                shared.copy(shared.serialize(ui.selected, {maxDepth = 8, maxEntries = 200}))
            end
        end, 116)
        shared.makeButton(buttonRow, "Copy All", function()
            api:CopyHistory()
        end, 92)
        shared.makeButton(buttonRow, "Clear", function()
            api:ClearHistory()
        end, 72)

        shared.connect(ui.search:GetPropertyChangedSignal("Text"), function()
            state.dirty = true
        end)
        state.dirty = true
        return state.window
    end

    function api:Open()
        buildWindow():Show()
        state.dirty = true
    end

    function api:Close()
        if state.window then
            state.window:Hide()
        end
    end

    function api:Demo()
        self:Debug("Frame sampler connected and waiting for spikes.", {title = "Debug Trace", channel = "debug"})
        self:Info("Universal module initialization completed.", {title = "Runtime", channel = "system"})
        self:Success("Configuration saved successfully.", {title = "Saved", channel = "config"})
        self:Warn("A deprecated API was detected; compatibility mode is active.", {title = "Compatibility", channel = "debug"})
        self:Error("Example exception captured with stack metadata.", {title = "Script Error", channel = "debug", duration = 8})
        self:Mod("Moderator tools are enabled for this session.", {
            title = "Staff Notice",
            key = "demo-mod-notice",
            actions = {
                {text = "Acknowledge", callback = function() return true end},
                {text = "Open Center", callback = function() api:Open() return false end, close = false},
            },
        })
        local progress = self:Progress({
            title = "Building Cache",
            message = "Preparing developer indexes...",
            channel = "system",
            key = "demo-progress",
        })
        task.spawn(function()
            for index = 1, 10 do
                if not progress or not progress:IsActive() then
                    return
                end
                task.wait(0.16)
                progress:SetProgress(index / 10, string.format("Preparing developer indexes... %d%%", index * 10))
            end
            progress:Complete("Developer indexes are ready.")
        end)
    end

    local function setup()
        ensureRoot()
        applyPlacement(true)

        shared.connect(RunService.Heartbeat, function()
            if state.destroyed then
                return
            end
            applyPlacement(false)
            promotePending()
            if state.dirty and state.window and state.window.root.Visible then
                rebuildHistory()
            end
        end)

        dev.apis.notifications = api
        dev.modules.notifications = module
        ctx.notifications = api

        local env = (type(getgenv) == "function" and getgenv()) or _G
        env.XANHUB_NOTIFICATIONS = api
        runtimeLabel.Text = "Status: ready • stacked notifications enabled"

        task.defer(function()
            api:Info("Advanced stacked notifications are ready.", {
                title = "Notification Service",
                channel = "system",
                key = "notification-service-ready",
                duration = 3,
            })
        end)
    end

    local function cleanup()
        if state.destroyed then
            return
        end
        state.destroyed = true
        for id in pairs(state.active) do
            local record = state.active[id]
            if record then
                record.closed = true
                record.timerToken = record.timerToken + 1
            end
        end
        table.clear(state.active)
        table.clear(state.activeOrder)
        table.clear(state.pending)
        table.clear(state.byKey)
        if state.window then
            state.window:Destroy()
            state.window = nil
        end
        shared.safeDestroy(state.root)
        shared.safeDestroy(state.notifyEvent)
        shared.safeDestroy(state.dismissEvent)
        local env = (type(getgenv) == "function" and getgenv()) or _G
        if env.XANHUB_NOTIFICATIONS == api then
            env.XANHUB_NOTIFICATIONS = nil
        end
        if ctx.notifications == api then
            ctx.notifications = nil
        end
    end

    module = {
        name = "notifications",
        setup = setup,
        cleanup = cleanup,
        api = api,
    }

    dev.apis.notifications = api
    dev.modules.notifications = module
    shared.addCleanup(cleanup)
    return module
end
