--[[
    xanhub | devmodules | shared

    Shared tab, window, serialization, and cleanup helpers.
    Load this before the other devmodules.
]]

return function(ctx)
    assert(type(ctx) == "table", "[xanhub dev] missing ctx")
    assert(type(ctx.library) == "table", "[xanhub dev] missing ctx.library")

    ctx.devtools = type(ctx.devtools) == "table" and ctx.devtools or {}
    local dev = ctx.devtools

    if dev.shared then
        return dev.shared
    end

    if not dev.tab then
        dev.tab = ctx.library:AddTab("Dev Tools", 8)
        dev.tab.hidden = true
        dev.left = dev.tab:AddColumn()
        dev.right = dev.tab:AddColumn()
    end

    dev.modules = type(dev.modules) == "table" and dev.modules or {}
    dev.apis = type(dev.apis) == "table" and dev.apis or {}
    dev.windows = type(dev.windows) == "table" and dev.windows or {}
    dev.cleanup = type(dev.cleanup) == "table" and dev.cleanup or {}

    local shared = {}
    shared.theme = {
        background = Color3.fromRGB(8, 11, 17),
        panel = Color3.fromRGB(13, 17, 25),
        panel2 = Color3.fromRGB(18, 23, 33),
        border = Color3.fromRGB(43, 54, 73),
        text = Color3.fromRGB(239, 243, 252),
        muted = Color3.fromRGB(145, 157, 180),
        danger = Color3.fromRGB(255, 88, 105),
        success = Color3.fromRGB(92, 225, 145),
        warning = Color3.fromRGB(255, 194, 92),
    }

    local function accent()
        if type(ctx.library.GetAccent) == "function" then
            local ok, value = pcall(function()
                return ctx.library:GetAccent()
            end)
            if ok and typeof(value) == "Color3" then
                return value
            end
        end
        return Color3.fromRGB(0, 170, 255)
    end

    shared.accent = accent

    function shared.notify(message, duration)
        local notifications = dev.apis and dev.apis.notifications
        if type(notifications) == "table" and type(notifications.Info) == "function" then
            local ok = pcall(function()
                if type(message) == "table" then
                    notifications:Notify(message)
                else
                    notifications:Info(tostring(message), {
                        duration = tonumber(duration) or 3,
                        channel = "system",
                    })
                end
            end)
            if ok then
                return
            end
        end

        if type(ctx.notify) == "function" then
            ctx.notify(message, duration)
        elseif type(ctx.library.SendNotification) == "function" then
            ctx.library:SendNotification(duration or 3, tostring(message))
        else
            print("[xanhub dev] " .. tostring(message))
        end
    end

    -- Convenience for typed stacked toasts once notification_center is loaded.
    function shared.toast(typeName, message, options)
        options = type(options) == "table" and options or {}
        options.message = tostring(message or options.message or "")
        options.type = typeName or options.type or "info"
        local notifications = dev.apis and dev.apis.notifications
        if type(notifications) == "table" and type(notifications.Notify) == "function" then
            local ok = pcall(function()
                notifications:Notify(options)
            end)
            if ok then
                return true
            end
        end
        shared.notify(options.message, options.duration or 3)
        return false
    end

    function shared.safeDestroy(object)
        if object then
            pcall(function()
                object:Destroy()
            end)
        end
    end

    function shared.connect(signal, callback)
        if type(ctx.addConnection) == "function" then
            return ctx.addConnection(signal, callback)
        end
        local connection = signal:Connect(callback)
        table.insert(dev.cleanup, function()
            pcall(function()
                connection:Disconnect()
            end)
        end)
        return connection
    end

    function shared.addCleanup(callback)
        if type(ctx.library.AddCleanup) == "function" then
            ctx.library:AddCleanup(callback)
        else
            table.insert(dev.cleanup, callback)
        end
    end

    function shared.round(object, radius)
        if type(ctx.createRounded) == "function" then
            return ctx.createRounded(object, radius)
        end
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius or 6)
        corner.Parent = object
        return corner
    end

    function shared.stroke(object, color, transparency, thickness)
        local stroke = Instance.new("UIStroke")
        stroke.Color = color or shared.theme.border
        stroke.Transparency = transparency or 0
        stroke.Thickness = thickness or 1
        stroke.Parent = object
        return stroke
    end

    function shared.getGuiParent()
        local getters = { gethui, get_hidden_gui, gethiddengui }
        for _, getter in ipairs(getters) do
            if type(getter) == "function" then
                local ok, parent = pcall(getter)
                if ok and typeof(parent) == "Instance" then
                    return parent
                end
            end
        end
        if ctx.library and ctx.library.base and ctx.library.base.Parent then
            return ctx.library.base.Parent
        end
        return game:GetService("CoreGui")
    end

    function shared.ensureOverlayGui()
        if dev.overlayGui and dev.overlayGui.Parent then
            return dev.overlayGui
        end

        for _, window in pairs(dev.windows) do
            if type(window) == "table" and type(window.Destroy) == "function" then
                pcall(function()
                    window:Destroy()
                end)
            end
        end
        table.clear(dev.windows)

        local anchorParent
        if ctx.library and ctx.library.base then
            anchorParent = ctx.library.base.Parent or shared.getGuiParent()
        else
            anchorParent = shared.getGuiParent()
        end

        local overlay = Instance.new("ScreenGui")
        overlay.Name = "xanhub_dev_overlay"
        overlay.ResetOnSpawn = false
        overlay.IgnoreGuiInset = true
        overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        overlay.DisplayOrder = 1000001
        overlay.Enabled = true
        overlay.Parent = anchorParent

        dev.overlayGui = overlay
        shared.addCleanup(function()
            shared.safeDestroy(overlay)
            dev.overlayGui = nil
            table.clear(dev.windows)
        end)
        return overlay
    end

    function shared.invokeApi(key, method, ...)
        local api = dev.apis[key]
        if not api then
            shared.notify("Dev tool not loaded: " .. tostring(key), 4)
            return false
        end
        local fn = api[method]
        if type(fn) ~= "function" then
            shared.notify("Dev tool missing method: " .. tostring(method), 4)
            return false
        end
        local ok, err = pcall(fn, api, ...)
        if not ok then
            warn("[xanhub dev] " .. tostring(key) .. ":" .. tostring(method) .. " failed: " .. tostring(err))
            shared.notify("Dev tool error: " .. tostring(err), 4)
        end
        return ok, err
    end

    function shared.getExecutorName()
        if type(identifyexecutor) == "function" then
            local ok, name = pcall(identifyexecutor)
            if ok and type(name) == "string" and name ~= "" then
                return name
            end
        end
        if type(getexecutorname) == "function" then
            local ok, name = pcall(getexecutorname)
            if ok and type(name) == "string" and name ~= "" then
                return name
            end
        end
        return "Unknown"
    end

    function shared.getCapabilities()
        return {
            clipboard = type(setclipboard) == "function" or type(toclipboard) == "function",
            filesystem = type(isfolder) == "function" and type(writefile) == "function",
            gethui = type(gethui) == "function",
            hookmetamethod = type(hookmetamethod) == "function",
            getgc = type(getgc) == "function",
            getinstances = type(getinstances) == "function",
            gethiddenproperty = type(gethiddenproperty) == "function",
            debug = type(debug) == "table",
        }
    end

    function shared.luaQuote(value)
        return shared.serialize(value, { maxDepth = 4, maxEntries = 40, maxString = 800 })
    end

    function shared.copy(text)
        local fn = type(setclipboard) == "function" and setclipboard
            or type(toclipboard) == "function" and toclipboard
            or nil
        if not fn then
            shared.notify("Clipboard unavailable", 3)
            return false
        end
        local ok = pcall(fn, tostring(text))
        shared.notify(ok and "Copied" or "Copy failed", ok and 2 or 3)
        return ok
    end

    function shared.instancePath(instance)
        if typeof(instance) ~= "Instance" then
            return tostring(instance)
        end
        local segments = {}
        local cursor = instance
        while cursor and cursor ~= game do
            local name = cursor.Name
            if string.match(name, "^[%a_][%w_]*$") then
                table.insert(segments, 1, "." .. name)
            else
                table.insert(segments, 1, "[" .. string.format("%q", name) .. "]")
            end
            cursor = cursor.Parent
        end
        return "game" .. table.concat(segments)
    end

    local function serializeValue(value, state, depth)
        local valueType = typeof(value)
        depth = depth or 0
        if depth > state.maxDepth then
            return "<max-depth>"
        end
        if valueType == "nil" or valueType == "boolean" or valueType == "number" then
            return tostring(value)
        elseif valueType == "string" then
            local text = value
            if #text > state.maxString then
                text = string.sub(text, 1, state.maxString) .. "…"
            end
            return string.format("%q", text)
        elseif valueType == "Instance" then
            return shared.instancePath(value) .. " <" .. value.ClassName .. ">"
        elseif valueType == "Vector2" then
            return string.format("Vector2.new(%.4f, %.4f)", value.X, value.Y)
        elseif valueType == "Vector3" then
            return string.format("Vector3.new(%.4f, %.4f, %.4f)", value.X, value.Y, value.Z)
        elseif valueType == "Color3" then
            return string.format("Color3.fromRGB(%d, %d, %d)", math.floor(value.R * 255 + 0.5), math.floor(value.G * 255 + 0.5), math.floor(value.B * 255 + 0.5))
        elseif valueType == "CFrame" then
            local components = {value:GetComponents()}
            local strings = {}
            for index, component in ipairs(components) do
                strings[index] = string.format("%.5f", component)
            end
            return "CFrame.new(" .. table.concat(strings, ", ") .. ")"
        elseif valueType == "UDim2" then
            return string.format("UDim2.new(%.4f, %d, %.4f, %d)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
        elseif valueType == "EnumItem" then
            return tostring(value)
        elseif valueType == "table" then
            if state.seen[value] then
                return "<cycle>"
            end
            state.seen[value] = true
            local items = {}
            local count = 0
            for key, child in pairs(value) do
                count = count + 1
                if count > state.maxEntries then
                    table.insert(items, "…")
                    break
                end
                local keyText = serializeValue(key, state, depth + 1)
                local valueText = serializeValue(child, state, depth + 1)
                table.insert(items, "[" .. keyText .. "] = " .. valueText)
            end
            state.seen[value] = nil
            return "{" .. table.concat(items, ", ") .. "}"
        end
        return "<" .. valueType .. ": " .. tostring(value) .. ">"
    end

    function shared.serialize(value, options)
        options = type(options) == "table" and options or {}
        return serializeValue(value, {
            seen = {},
            maxDepth = math.clamp(tonumber(options.maxDepth) or 5, 1, 12),
            maxEntries = math.clamp(tonumber(options.maxEntries) or 80, 5, 500),
            maxString = math.clamp(tonumber(options.maxString) or 1200, 32, 12000),
        }, 0)
    end

    function shared.create(className, properties)
        local object = Instance.new(className)
        local parent = properties and properties.Parent
        if properties then
            for key, value in pairs(properties) do
                if key ~= "Parent" then
                    pcall(function()
                        object[key] = value
                    end)
                end
            end
        end
        if parent ~= nil then
            local ok = pcall(function()
                object.Parent = parent
            end)
            if not ok then
                -- leave unparented; callers that require a host should reparent / rebuild
            end
        end
        return object
    end

    function shared.makeButton(parent, text, callback, width)
        local button = shared.create("TextButton", {
            Size = UDim2.new(0, width or 104, 0, 28),
            BackgroundColor3 = shared.theme.panel2,
            BorderSizePixel = 0,
            Text = tostring(text),
            TextColor3 = shared.theme.text,
            TextSize = 12,
            Font = Enum.Font.Code,
            AutoButtonColor = false,
            Parent = parent,
        })
        shared.round(button, 6)
        local border = shared.stroke(button, shared.theme.border, 0.25, 1)
        shared.connect(button.MouseEnter, function()
            border.Color = accent()
        end)
        shared.connect(button.MouseLeave, function()
            border.Color = shared.theme.border
        end)
        shared.connect(button.MouseButton1Click, function()
            local ok, err = pcall(callback)
            if not ok then
                warn("[xanhub dev button] " .. tostring(err))
                shared.notify("Action failed: " .. tostring(err), 4)
            end
        end)
        return button
    end

    function shared.makeTextBox(parent, placeholder, text)
        local box = shared.create("TextBox", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = tostring(text or ""),
            PlaceholderText = tostring(placeholder or ""),
            PlaceholderColor3 = shared.theme.muted,
            TextColor3 = shared.theme.text,
            TextSize = 12,
            Font = Enum.Font.Code,
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = parent,
        })
        shared.round(box, 6)
        shared.stroke(box, shared.theme.border, 0.3, 1)
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 8)
        padding.PaddingRight = UDim.new(0, 8)
        padding.Parent = box
        return box
    end

    function shared.makeWindow(title, width, height)
        local existing = dev.windows[title]
        if existing and existing.root and existing.root.Parent then
            return existing
        end

        local parent = shared.ensureOverlayGui()
        local root = shared.create("Frame", {
            Name = "xanhub_dev_" .. string.gsub(string.lower(title), "%W+", "_"),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(width or 720, height or 480),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Visible = false,
            Active = true,
            ClipsDescendants = false,
            ZIndex = 1,
            Parent = parent,
        })
        shared.round(root, 10)
        shared.stroke(root, shared.theme.border, 0.12, 1)

        local scale = Instance.new("UIScale")
        scale.Parent = root

        local top = shared.create("Frame", {
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 2,
            Parent = root,
        })
        local topCorner = shared.round(top, 10)
        topCorner.CornerRadius = UDim.new(0, 10)

        shared.create("Frame", {
            Position = UDim2.new(0, 0, 1, -2),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = accent(),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = top,
        })

        local titleLabel = shared.create("TextLabel", {
            Position = UDim2.fromOffset(12, 0),
            Size = UDim2.new(1, -92, 1, 0),
            BackgroundTransparency = 1,
            Text = tostring(title),
            TextColor3 = shared.theme.text,
            TextSize = 14,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 4,
            Parent = top,
        })

        local minimize = shared.create("TextButton", {
            Position = UDim2.new(1, -72, 0, 0),
            Size = UDim2.fromOffset(34, 38),
            BackgroundTransparency = 1,
            Text = "_",
            TextColor3 = shared.theme.muted,
            TextSize = 15,
            Font = Enum.Font.Code,
            ZIndex = 4,
            Parent = top,
        })

        local close = shared.create("TextButton", {
            Position = UDim2.new(1, -38, 0, 0),
            Size = UDim2.fromOffset(38, 38),
            BackgroundTransparency = 1,
            Text = "x",
            TextColor3 = shared.theme.danger,
            TextSize = 14,
            Font = Enum.Font.Code,
            ZIndex = 4,
            Parent = top,
        })

        local content = shared.create("Frame", {
            Position = UDim2.fromOffset(0, 38),
            Size = UDim2.new(1, 0, 1, -38),
            BackgroundTransparency = 1,
            ClipsDescendants = false,
            ZIndex = 2,
            Parent = root,
        })

        local dragging = false
        local dragStart
        local startPosition
        shared.connect(top.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPosition = root.Position
            end
        end)
        shared.connect(game:GetService("UserInputService").InputChanged, function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                root.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
            end
        end)
        shared.connect(game:GetService("UserInputService").InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)

        local minimized = false
        shared.connect(minimize.MouseButton1Click, function()
            minimized = not minimized
            content.Visible = not minimized
            root.Size = minimized and UDim2.fromOffset(width or 720, 38) or UDim2.fromOffset(width or 720, height or 480)
            minimize.Text = minimized and "+" or "_"
        end)
        shared.connect(close.MouseButton1Click, function()
            root.Visible = false
        end)

        local function updateScale()
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
            scale.Scale = math.clamp(math.min((viewport.X - 24) / (width or 720), (viewport.Y - 24) / (height or 480), 1), 0.55, 1)
        end
        updateScale()
        if workspace.CurrentCamera then
            shared.connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateScale)
        end

        local window = {
            root = root,
            top = top,
            content = content,
            title = titleLabel,
            scale = scale,
        }
        function window:Show()
            shared.ensureOverlayGui().Enabled = true
            root.Visible = true
        end
        function window:Hide()
            root.Visible = false
        end
        function window:Toggle()
            root.Visible = not root.Visible
        end
        function window:Destroy()
            shared.safeDestroy(root)
            dev.windows[title] = nil
        end

        dev.windows[title] = window
        shared.addCleanup(function()
            if dev.windows[title] == window then
                window:Destroy()
            end
        end)
        return window
    end

    dev.shared = shared
    return shared
end
