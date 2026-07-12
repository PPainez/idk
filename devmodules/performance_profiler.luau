--[[
    xanhub | devmodules | performance profiler

    Live FPS/frame-time/memory/ping/instance telemetry with spike capture.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub profiler] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub profiler] dev_shared missing")
    local section = dev.right:AddSection("Performance Profiler")

    section:AddToggle({text = "Profiler Enabled", flag = "Dev Profiler Enabled", state = true})
    section:AddToggle({text = "Show Compact Overlay", flag = "Dev Profiler Overlay", state = false})
    section:AddSlider({text = "Spike Threshold", flag = "Dev Profiler Spike Ms", min = 10, max = 100, value = 33, float = 1, suffix = " ms"})
    section:AddSlider({text = "History Samples", flag = "Dev Profiler History", min = 30, max = 240, value = 120, float = 10})
    section:AddButton({text = "Open Performance Profiler", callback = function()
        if dev.apis.performanceProfiler then dev.apis.performanceProfiler:Open() end
    end})
    section:AddButton({text = "Copy Performance Snapshot", callback = function()
        if dev.apis.performanceProfiler then dev.apis.performanceProfiler:CopySnapshot() end
    end})

    local state = {
        frameTimes = {},
        spikes = {},
        snapshot = {},
        overlay = nil,
        window = nil,
        graphBars = {},
        lastSample = 0,
        frames = 0,
        accumulated = 0,
        dirty = true,
    }
    local ui = {}

    local function push(list, value, maxCount)
        table.insert(list, value)
        while #list > maxCount do table.remove(list, 1) end
    end

    local function average(list)
        if #list == 0 then return 0 end
        local total = 0
        for _, value in ipairs(list) do total = total + value end
        return total / #list
    end

    local function percentile(list, p)
        if #list == 0 then return 0 end
        local copy = table.clone(list)
        table.sort(copy)
        local index = math.clamp(math.ceil(#copy * p), 1, #copy)
        return copy[index]
    end

    local function getPing()
        local ok, value = pcall(function()
            local stats = game:GetService("Stats")
            local network = stats.Network.ServerStatsItem
            local item = network and (network["Data Ping"] or network["Ping"])
            if item then
                local text = item:GetValueString()
                return tonumber(tostring(text):match("[%d%.]+")) or tonumber(item:GetValue())
            end
        end)
        return ok and tonumber(value) or 0
    end

    local function getMemory()
        local ok, value = pcall(function()
            return game:GetService("Stats"):GetTotalMemoryUsageMb()
        end)
        if ok and tonumber(value) then return value end
        local okGc, kb = pcall(collectgarbage, "count")
        return okGc and tonumber(kb) and kb / 1024 or 0
    end

    local function getInstanceCount()
        local ok, count = pcall(function()
            return #game:GetDescendants()
        end)
        return ok and count or 0
    end

    local function makeSnapshot()
        local avgMs = average(state.frameTimes)
        local p95 = percentile(state.frameTimes, 0.95)
        local p99 = percentile(state.frameTimes, 0.99)
        local fps = avgMs > 0 and 1000 / avgMs or 0
        state.snapshot = {
            fps = fps,
            averageFrameMs = avgMs,
            p95FrameMs = p95,
            p99FrameMs = p99,
            worstFrameMs = #state.frameTimes > 0 and math.max(table.unpack(state.frameTimes)) or 0,
            memoryMb = getMemory(),
            pingMs = getPing(),
            instanceCount = getInstanceCount(),
            players = #ctx.Players:GetPlayers(),
            spikeCount = #state.spikes,
            sampleCount = #state.frameTimes,
            timestamp = os.time(),
        }
        state.dirty = true
        return state.snapshot
    end

    local function snapshotText(snapshot)
        snapshot = snapshot or state.snapshot
        return table.concat({
            string.format("FPS: %.1f", snapshot.fps or 0),
            string.format("Frame: %.2f ms avg | %.2f p95 | %.2f p99 | %.2f worst", snapshot.averageFrameMs or 0, snapshot.p95FrameMs or 0, snapshot.p99FrameMs or 0, snapshot.worstFrameMs or 0),
            string.format("Memory: %.1f MB", snapshot.memoryMb or 0),
            string.format("Ping: %.1f ms", snapshot.pingMs or 0),
            string.format("Instances: %d | Players: %d", snapshot.instanceCount or 0, snapshot.players or 0),
            string.format("Spikes: %d | Samples: %d", snapshot.spikeCount or 0, snapshot.sampleCount or 0),
        }, "\n")
    end

    local function ensureOverlay()
        if state.overlay and state.overlay.Parent then return state.overlay end
        local root = ctx.createOverlayRoot and ctx.createOverlayRoot() or ctx.library.base
        state.overlay = shared.create("TextLabel", {
            Name = "DevProfilerOverlay",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -14, 0, 14),
            Size = UDim2.fromOffset(250, 82),
            BackgroundColor3 = shared.theme.background,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Text = "Profiler initializing...",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 750,
            Visible = false,
            Parent = root,
        })
        shared.round(state.overlay, 7)
        shared.stroke(state.overlay, shared.accent(), 0.4, 1)
        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 7)
        padding.PaddingLeft = UDim.new(0, 8)
        padding.PaddingRight = UDim.new(0, 8)
        padding.Parent = state.overlay
        return state.overlay
    end

    local function rebuildSpikeRows()
        if not ui.spikeList then return end
        for _, child in ipairs(ui.spikeList:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        local start = math.max(1, #state.spikes - 100)
        for index = #state.spikes, start, -1 do
            local spike = state.spikes[index]
            local row = shared.create("TextLabel", {
                Size = UDim2.new(1, -4, 0, 22),
                BackgroundColor3 = shared.theme.panel2,
                BackgroundTransparency = 0.08,
                BorderSizePixel = 0,
                Text = string.format("%7.2f ms  |  %.1f FPS  |  t=%.2f", spike.ms, spike.fps, spike.time),
                TextColor3 = spike.ms >= 66 and shared.theme.danger or shared.theme.warning,
                TextSize = 10,
                Font = Enum.Font.Code,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = ui.spikeList,
            })
            shared.round(row, 4)
            local padding = Instance.new("UIPadding")
            padding.PaddingLeft = UDim.new(0, 6)
            padding.Parent = row
        end
    end

    local function updateGraph()
        if not ui.graph then return end
        local count = math.min(#state.frameTimes, #state.graphBars)
        local threshold = tonumber(ctx.library.flags["Dev Profiler Spike Ms"]) or 33
        for index, bar in ipairs(state.graphBars) do
            local sourceIndex = #state.frameTimes - count + index
            local value = sourceIndex >= 1 and state.frameTimes[sourceIndex] or 0
            local ratio = math.clamp(value / 80, 0, 1)
            bar.Size = UDim2.new(0, 4, ratio, 0)
            bar.Position = UDim2.new(0, (index - 1) * 5, 1, 0)
            bar.AnchorPoint = Vector2.new(0, 1)
            bar.BackgroundColor3 = value >= threshold and shared.theme.danger
                or value >= 20 and shared.theme.warning
                or shared.accent()
        end
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then return state.window end
        state.window = shared.makeWindow("Performance Profiler", 820, 500)
        local content = state.window.content

        local summary = shared.create("TextLabel", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(1, -20, 0, 100),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Text = "Profiler initializing...",
            TextColor3 = shared.theme.text,
            TextSize = 12,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = content,
        })
        shared.round(summary, 8)
        shared.stroke(summary, shared.theme.border, 0.25, 1)
        local sp = Instance.new("UIPadding")
        sp.PaddingTop = UDim.new(0, 8)
        sp.PaddingLeft = UDim.new(0, 10)
        sp.Parent = summary
        ui.summary = summary

        ui.graph = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 120),
            Size = UDim2.new(0.62, -15, 1, -130),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Parent = content,
        })
        shared.round(ui.graph, 8)
        shared.stroke(ui.graph, shared.theme.border, 0.25, 1)
        state.graphBars = {}
        for index = 1, 96 do
            local bar = shared.create("Frame", {
                Size = UDim2.fromOffset(4, 1),
                BackgroundColor3 = shared.accent(),
                BorderSizePixel = 0,
                Parent = ui.graph,
            })
            state.graphBars[index] = bar
        end

        ui.spikeList = shared.create("ScrollingFrame", {
            Position = UDim2.new(0.62, 5, 0, 120),
            Size = UDim2.new(0.38, -15, 1, -130),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = content,
        })
        shared.round(ui.spikeList, 8)
        shared.stroke(ui.spikeList, shared.theme.border, 0.25, 1)
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 3)
        layout.Parent = ui.spikeList

        shared.connect(ctx.RunService.Heartbeat, function()
            if state.window and state.window.root.Visible and state.dirty then
                ui.summary.Text = snapshotText()
                updateGraph()
                rebuildSpikeRows()
                state.dirty = false
            end
        end)
        return state.window
    end

    local api = {}
    function api:Open()
        buildWindow():Show()
        state.dirty = true
    end
    function api:GetSnapshot()
        return makeSnapshot()
    end
    function api:CopySnapshot()
        shared.copy(snapshotText(makeSnapshot()))
    end
    function api:GetHistory() return state.frameTimes end
    function api:GetSpikes() return state.spikes end
    function api:GetState() return state end

    dev.apis.performanceProfiler = api

    local function setup()
        ensureOverlay()
        shared.connect(ctx.RunService.RenderStepped, function(delta)
            if ctx.library.flags["Dev Profiler Enabled"] == false then return end
            local ms = delta * 1000
            local maxHistory = math.clamp(tonumber(ctx.library.flags["Dev Profiler History"]) or 120, 30, 240)
            push(state.frameTimes, ms, maxHistory)
            local threshold = tonumber(ctx.library.flags["Dev Profiler Spike Ms"]) or 33
            if ms >= threshold then
                push(state.spikes, {ms = ms, fps = delta > 0 and 1 / delta or 0, time = os.clock()}, 500)
                state.dirty = true
            end
            state.accumulated = state.accumulated + delta
            state.frames = state.frames + 1
            if state.accumulated >= 0.5 then
                makeSnapshot()
                local overlay = ensureOverlay()
                overlay.Visible = ctx.library.flags["Dev Profiler Overlay"] == true
                overlay.Text = string.format(
                    "FPS %5.1f   FRAME %5.2fms\nP95 %5.2f   PING %5.1fms\nMEM %6.1fMB   INST %d",
                    state.snapshot.fps or 0,
                    state.snapshot.averageFrameMs or 0,
                    state.snapshot.p95FrameMs or 0,
                    state.snapshot.pingMs or 0,
                    state.snapshot.memoryMb or 0,
                    state.snapshot.instanceCount or 0
                )
                state.accumulated = 0
                state.frames = 0
            end
        end)
    end

    local function cleanup()
        shared.safeDestroy(state.overlay)
        if state.window then state.window:Destroy() end
    end

    local module = {name = "performance_profiler", setup = setup, cleanup = cleanup, api = api}
    dev.modules.performance_profiler = module
    shared.addCleanup(cleanup)
    return module
end
