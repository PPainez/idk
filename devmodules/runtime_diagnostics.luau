--[[
    xanhub | devmodules | runtime diagnostics

    Lightweight health checks for module loading, UI roots, connections, frame
    pacing, memory, notifications, and build metadata.
]]

return function(ctx)
	local dev = assert(ctx.devtools, "[xanhub diagnostics] dev_shared missing")
	local shared = assert(dev.shared, "[xanhub diagnostics] dev_shared missing")
	local RunService = game:GetService("RunService")
	local Stats = game:GetService("Stats")

	local section = dev.left:AddSection("Runtime Diagnostics")
	section:AddToggle({ text = "Auto Refresh", flag = "Dev Diagnostics Auto Refresh", state = true })
	section:AddSlider({
		text = "Refresh Interval",
		flag = "Dev Diagnostics Interval",
		min = 0.5,
		max = 5,
		value = 1,
		float = 0.5,
		suffix = "s",
	})
	local healthLabel = section:AddLabel("Health: waiting for setup")
	local frameLabel = section:AddLabel("Frame: -- FPS")
	local moduleLabel = section:AddLabel("Modules: waiting")

	local api = {}
	local module
	local state = {
		destroyed = false,
		setupDone = false,
		window = nil,
		details = nil,
		frameConnection = nil,
		elapsed = 0,
		frames = 0,
		fps = 0,
		minimumFps = math.huge,
		maximumFrameMs = 0,
		lastSnapshot = nil,
	}

	local function flag(name, fallback)
		local value = ctx.library.flags[name]
		return value == nil and fallback or value
	end

	local function numberFlag(name, fallback)
		return tonumber(ctx.library.flags[name]) or fallback
	end

	local function countTable(value)
		local count = 0
		if type(value) == "table" then
			for _ in pairs(value) do
				count = count + 1
			end
		end
		return count
	end

	local function memoryMb()
		local ok, value = pcall(function()
			if type(gcinfo) == "function" then
				return gcinfo() / 1024
			end
			if type(collectgarbage) == "function" then
				return collectgarbage("count") / 1024
			end
			return nil
		end)
		return ok and tonumber(value) or nil
	end

	local function pingText()
		local ok, value = pcall(function()
			local network = Stats:FindFirstChild("Network")
			local serverStats = network and network:FindFirstChild("ServerStatsItem")
			local ping = serverStats and serverStats:FindFirstChild("Data Ping")
			if ping and type(ping.GetValueString) == "function" then
				return ping:GetValueString()
			end
			return nil
		end)
		return ok and value or nil
	end

	local function guiParents()
		local parents = {}
		local function add(value)
			if typeof(value) == "Instance" and not table.find(parents, value) then
				table.insert(parents, value)
			end
		end
		for _, getter in ipairs({ gethui, get_hidden_gui, gethiddengui }) do
			if type(getter) == "function" then
				local ok, value = pcall(getter)
				if ok then
					add(value)
				end
			end
		end
		pcall(function()
			add(game:GetService("CoreGui"))
		end)
		pcall(function()
			local player = ctx.LocalPlayer
			if player then
				add(player:FindFirstChildOfClass("PlayerGui"))
			end
		end)
		return parents
	end

	local function countUiRoots()
		local count = 0
		local names = {
			xanhub_ui = true,
			uwuware_ui = true,
			xanhub_dev_overlay = true,
		}
		for _, parent in ipairs(guiParents()) do
			pcall(function()
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") and names[child.Name] then
						count = count + 1
					end
				end
			end)
		end
		return count
	end

	local function moduleSummary()
		local ready = 0
		local errors = 0
		local pending = 0
		local status = type(ctx.runtime) == "table" and ctx.runtime.moduleStatus or {}
		for _, record in pairs(status or {}) do
			local value = tostring(record.status or "unknown")
			if string.find(value, "error", 1, true) then
				errors = errors + 1
			elseif value == "ready" or value == "loaded" or value == "cached" then
				ready = ready + 1
			else
				pending = pending + 1
			end
		end
		return ready, errors, pending
	end

	local function loaderSummary()
		local loaded = 0
		local errors = 0
		local bytes = 0
		local slowestPath
		local slowestDuration = 0
		if ctx.moduleLoader and type(ctx.moduleLoader.getStats) == "function" then
			for path, record in pairs(ctx.moduleLoader.getStats()) do
				if record.status == "error" then
					errors = errors + 1
			else
					loaded = loaded + 1
				end
				bytes = bytes + (tonumber(record.bytes) or 0)
				local duration = tonumber(record.duration) or 0
				if duration > slowestDuration then
					slowestDuration = duration
					slowestPath = path
				end
			end
		end
		return loaded, errors, bytes, slowestPath, slowestDuration
	end

	local function notificationSummary()
		local notifications = dev.apis and dev.apis.notifications
		if type(notifications) ~= "table" then
			return 0, 0
		end
		local active = type(notifications.GetActive) == "function" and notifications:GetActive() or {}
		local history = type(notifications.GetHistory) == "function" and notifications:GetHistory() or {}
		return #active, #history
	end

	local function buildSnapshot()
		local ready, moduleErrors, pending = moduleSummary()
		local loaded, loaderErrors, bytes, slowestPath, slowestDuration = loaderSummary()
		local activeNotices, historyNotices = notificationSummary()
		local runtime = ctx.runtime or {}
		local issues = {}
		local uiRoots = countUiRoots()

		if moduleErrors + loaderErrors > 0 then
			table.insert(issues, tostring(moduleErrors + loaderErrors) .. " module error(s)")
		end
		if uiRoots > 2 then
			table.insert(issues, tostring(uiRoots) .. " xanhub UI roots detected")
		end
		if not ctx.Workspace.CurrentCamera then
			table.insert(issues, "CurrentCamera unavailable")
		end
		if ctx.library.unloaded then
			table.insert(issues, "library is unloaded")
		end
		if state.fps > 0 and state.fps < 20 then
			table.insert(issues, "low frame rate")
		end

		return {
			capturedAt = os.time(),
			health = #issues == 0 and "healthy" or "attention",
			issues = issues,
			build = {
				version = runtime.buildVersion,
				revision = runtime.buildRevision,
				loaderVersion = runtime.loaderVersion,
				generatedAt = runtime.buildGeneratedAt,
			},
			session = {
				uptime = type(ctx.getUptime) == "function" and ctx.getUptime() or 0,
				placeId = game.PlaceId,
				universeId = game.GameId,
				jobId = game.JobId,
				executor = shared.getExecutorName(),
			},
			performance = {
				fps = state.fps,
				minimumFps = state.minimumFps == math.huge and 0 or state.minimumFps,
				maximumFrameMs = state.maximumFrameMs,
				memoryMb = memoryMb(),
				ping = pingText(),
			},
			modules = {
				ready = ready,
				errors = moduleErrors,
				pending = pending,
				loadedSources = loaded,
				loaderErrors = loaderErrors,
				bytes = bytes,
				slowestPath = slowestPath,
				slowestDuration = slowestDuration,
			},
			runtime = {
				connections = countTable(ctx.state.connections),
				espEntries = countTable(ctx.state.esp),
				uiRoots = uiRoots,
				activeNotifications = activeNotices,
				notificationHistory = historyNotices,
			},
		}
	end

	local function formatSnapshot(snapshot)
		local build = snapshot.build
		local session = snapshot.session
		local perf = snapshot.performance
		local modules = snapshot.modules
		local runtime = snapshot.runtime
		local revision = tostring(build.revision or "local")
		if #revision > 16 then
			revision = string.sub(revision, 1, 16)
		end
		local issueText = #snapshot.issues == 0 and "none" or table.concat(snapshot.issues, ", ")

		return table.concat({
			"xanhub runtime diagnostics",
			"health: " .. snapshot.health,
			"issues: " .. issueText,
			"",
			string.format("build: %s (%s)", tostring(build.version or "unknown"), revision),
			"loader: " .. tostring(build.loaderVersion or "unknown"),
			string.format("uptime: %.1fs", tonumber(session.uptime) or 0),
			"executor: " .. tostring(session.executor),
			"place: " .. tostring(session.placeId),
			"job: " .. tostring(session.jobId),
			"",
			string.format("fps: %.1f (minimum %.1f)", tonumber(perf.fps) or 0, tonumber(perf.minimumFps) or 0),
			string.format("largest frame: %.2fms", tonumber(perf.maximumFrameMs) or 0),
			"memory: " .. (perf.memoryMb and string.format("%.1f MB", perf.memoryMb) or "unavailable"),
			"ping: " .. tostring(perf.ping or "unavailable"),
			"",
			string.format("modules: %d ready, %d errors, %d pending", modules.ready, modules.errors + modules.loaderErrors, modules.pending),
			string.format("source cache: %d modules, %.1f KB", modules.loadedSources, modules.bytes / 1024),
			string.format("slowest source: %s (%.3fs)", tostring(modules.slowestPath or "none"), tonumber(modules.slowestDuration) or 0),
			string.format("connections: %d", runtime.connections),
			string.format("ESP entries: %d", runtime.espEntries),
			string.format("UI roots: %d", runtime.uiRoots),
			string.format("notifications: %d active, %d history", runtime.activeNotifications, runtime.notificationHistory),
		}, "\n")
	end

	local function refreshLabels(snapshot)
		healthLabel.Text = "Health: " .. snapshot.health .. (#snapshot.issues > 0 and (" · " .. table.concat(snapshot.issues, ", ")) or "")
		frameLabel.Text = string.format(
			"Frame: %.1f FPS · %.2fms max · %s",
			snapshot.performance.fps,
			snapshot.performance.maximumFrameMs,
			snapshot.performance.ping or "ping unavailable"
		)
		moduleLabel.Text = string.format(
			"Modules: %d ready · %d errors · %d cached sources",
			snapshot.modules.ready,
			snapshot.modules.errors + snapshot.modules.loaderErrors,
			snapshot.modules.loadedSources
		)
		if state.details and state.window and state.window.root.Visible then
			state.details.Text = formatSnapshot(snapshot)
		end
	end

	function api:Snapshot()
		state.lastSnapshot = buildSnapshot()
		refreshLabels(state.lastSnapshot)
		return state.lastSnapshot
	end

	function api:Format(snapshot)
		return formatSnapshot(snapshot or state.lastSnapshot or self:Snapshot())
	end

	function api:Copy()
		return shared.copy(self:Format(self:Snapshot()))
	end

	function api:Check(notifyResult)
		local snapshot = self:Snapshot()
		if notifyResult then
			if snapshot.health == "healthy" then
				shared.toast("success", "Runtime health check passed", {
					title = "Diagnostics",
					channel = "diagnostics",
					key = "diagnostics-health",
				})
			else
				shared.toast("warning", table.concat(snapshot.issues, ", "), {
					title = "Diagnostics found issues",
					channel = "diagnostics",
					key = "diagnostics-health",
					duration = 8,
				})
			end
		end
		return snapshot
	end

	local function buildWindow()
		if state.window then
			return state.window
		end
		state.window = shared.makeWindow("Runtime Diagnostics", 720, 500)
		local content = state.window.content
		state.details = shared.create("TextLabel", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 1, -58),
			BackgroundColor3 = shared.theme.panel,
			BorderSizePixel = 0,
			Text = "Waiting for diagnostics...",
			TextColor3 = shared.theme.text,
			TextSize = 12,
			Font = Enum.Font.Code,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = content,
		})
		shared.round(state.details, 8)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.Parent = state.details

		local row = shared.create("Frame", {
			Position = UDim2.new(0, 10, 1, -38),
			Size = UDim2.new(1, -20, 0, 28),
			BackgroundTransparency = 1,
			Parent = content,
		})
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 6)
		layout.Parent = row
		shared.makeButton(row, "Refresh", function()
			api:Check(false)
		end, 90)
		shared.makeButton(row, "Copy Report", function()
			api:Copy()
		end, 110)
		shared.makeButton(row, "Health Check", function()
			api:Check(true)
		end, 110)
		return state.window
	end

	function api:Open()
		buildWindow():Show()
		self:Snapshot()
	end

	function api:GetState()
		return state
	end

	section:AddButton({ text = "Run Health Check", callback = function() api:Check(true) end })
	section:AddButton({ text = "Open Diagnostics", callback = function() api:Open() end })
	section:AddButton({ text = "Copy Diagnostics", callback = function() api:Copy() end })

	local function setup()
		if state.setupDone or state.destroyed then
			return
		end
		state.setupDone = true
		state.frameConnection = shared.connect(RunService.RenderStepped, function(deltaTime)
			if state.destroyed then
				return
			end
			state.frames = state.frames + 1
			state.elapsed = state.elapsed + deltaTime
			state.maximumFrameMs = math.max(state.maximumFrameMs, deltaTime * 1000)
			if state.elapsed >= math.max(0.5, numberFlag("Dev Diagnostics Interval", 1)) then
				state.fps = state.frames / state.elapsed
				state.minimumFps = math.min(state.minimumFps, state.fps)
				state.frames = 0
				state.elapsed = 0
				if flag("Dev Diagnostics Auto Refresh", true) then
					api:Snapshot()
				end
			end
		end)

		dev.apis.diagnostics = api
		dev.modules.diagnostics = module
		api:Snapshot()
	end

	local function cleanup()
		if state.destroyed then
			return
		end
		state.destroyed = true
		if state.frameConnection then
			pcall(function()
				state.frameConnection:Disconnect()
			end)
			state.frameConnection = nil
		end
		if state.window then
			state.window:Destroy()
			state.window = nil
		end
		if dev.apis.diagnostics == api then
			dev.apis.diagnostics = nil
		end
	end

	module = {
		name = "diagnostics",
		setup = setup,
		cleanup = cleanup,
		api = api,
	}

	dev.apis.diagnostics = api
	dev.modules.diagnostics = module
	shared.addCleanup(cleanup)
	return module
end
