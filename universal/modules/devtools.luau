--[[
    xanhub | universal | devtools

    Loads the devmodule manifest, owns module lifecycle, adds the Settings toggle,
    and shows the Dev Tools tab on demand.
]]

local FALLBACK_MODULES = {
	"dev_shared.luau",
	"notification_center.luau",
	"runtime_diagnostics.luau",
	"animation_viewer.luau",
	"animation_logger.luau",
	"remote_spy.luau",
	"console_logger.luau",
	"performance_profiler.luau",
	"instance_inspector.luau",
}

return function(ctx)
	local library = ctx.library
	local moduleLoader = ctx.moduleLoader
	local loadedModules = {}
	local setupState = setmetatable({}, { __mode = "k" })
	local controllerSetup = false

	ctx.devtools = type(ctx.devtools) == "table" and ctx.devtools or {}
	ctx.devtools.loadErrors = type(ctx.devtools.loadErrors) == "table" and ctx.devtools.loadErrors or {}

	local function modulePath(name)
		name = tostring(name):gsub("^/+", "")
		return string.find(name, "/", 1, true) and name or ("devmodules/" .. name)
	end

	local function loadManifest()
		local manifest, loadError = moduleLoader.tryLoad("devmodules/manifest.luau")
		if type(manifest) == "table" and type(manifest.modules) == "table" then
			ctx.setModuleStatus("devmodules/manifest.luau", "loaded")
			return manifest
		end
		ctx.setModuleStatus("devmodules/manifest.luau", "load-error", loadError)
		warn("[xanhub dev] manifest unavailable; using fallback list: " .. tostring(loadError))
		return {
			name = "fallback",
			version = "fallback",
			modules = FALLBACK_MODULES,
		}
	end

	local manifest = loadManifest()
	ctx.devtools.manifest = manifest

	local function loadFactory(path)
		local factory, loadError = moduleLoader.tryLoad(path)
		if type(factory) ~= "function" then
			ctx.devtools.loadErrors[path] = tostring(loadError or "module did not return a factory")
			ctx.setModuleStatus(path, "load-error", loadError)
			warn("[xanhub dev] failed to load " .. path .. ": " .. tostring(loadError))
			return nil
		end
		return factory
	end

	local function initializeFactory(path, factory)
		local startedAt = os.clock()
		local ok, result = xpcall(function()
			return factory(ctx)
		end, ctx.traceback)
		local record = ctx.setModuleStatus(path, ok and "loaded" or "factory-error", ok and nil or result)
		record.duration = os.clock() - startedAt
		if not ok then
			ctx.devtools.loadErrors[path] = tostring(result)
			warn("[xanhub dev] failed to initialize " .. path .. ": " .. tostring(result))
			return nil
		end
		return result
	end

	-- dev_shared must run first because every other module builds UI through it.
	local sharedPath = "devmodules/dev_shared.luau"
	local sharedFactory = loadFactory(sharedPath)
	if sharedFactory then
		initializeFactory(sharedPath, sharedFactory)
	end

	if not ctx.devtools.shared then
		return {
			setup = function()
				warn("[xanhub dev] dev_shared failed; Dev Tools unavailable")
			end,
			setEnabled = function() end,
			modules = loadedModules,
		}
	end

	for _, name in ipairs(manifest.modules) do
		local path = modulePath(name)
		if path ~= sharedPath and path ~= "devmodules/manifest.luau" then
			local factory = loadFactory(path)
			if factory then
				local module = initializeFactory(path, factory)
				if type(module) == "table" then
					module.__path = path
					table.insert(loadedModules, module)
				end
			end
		end
	end

	local function setupModule(module)
		if type(module) ~= "table" or type(module.setup) ~= "function" then
			return true
		end
		if setupState[module] == "ready" then
			return true
		end
		if setupState[module] == "running" then
			return false
		end

		setupState[module] = "running"
		local startedAt = os.clock()
		local ok, result = xpcall(module.setup, ctx.traceback)
		setupState[module] = ok and "ready" or "error"
		local path = module.__path or ("devmodules/" .. tostring(module.name or "unknown"))
		local record = ctx.setModuleStatus(path, ok and "ready" or "setup-error", ok and nil or result)
		record.setupDuration = os.clock() - startedAt

		if not ok then
			ctx.devtools.loadErrors[path] = tostring(result)
			warn("[xanhub dev] " .. tostring(module.name or path) .. " setup failed: " .. tostring(result))
		end
		return ok
	end

	local function setupNamed(name)
		for _, module in ipairs(loadedModules) do
			if module.name == name then
				return setupModule(module)
			end
		end
		return false
	end

	local function runSetups()
		for _, module in ipairs(loadedModules) do
			setupModule(module)
		end
	end

	local function setEnabled(enabled)
		local dev = ctx.devtools
		if not dev or not dev.tab or type(library.SetTabVisible) ~= "function" then
			return
		end

		library:SetTabVisible(dev.tab, enabled == true)
		if enabled then
			runSetups()
			if library.selectTab then
				library:selectTab(dev.tab)
			end
		end
	end

	local function addExecutorSection()
		local dev = ctx.devtools
		local shared = dev and dev.shared
		if not dev or not shared or not dev.left then
			return
		end

		local caps = shared.getCapabilities()
		local section = dev.left:AddSection("Executor Utils")
		section:AddLabel("Executor: " .. shared.getExecutorName())
		section:AddLabel(string.format(
			"Clipboard %s · Files %s · Hidden UI %s",
			caps.clipboard and "yes" or "no",
			caps.filesystem and "yes" or "no",
			caps.gethui and "yes" or "no"
		))
		section:AddButton({
			text = "Copy Executor Name",
			callback = function()
				shared.copy(shared.getExecutorName())
			end,
		})
		section:AddButton({
			text = "Copy Place + Job ID",
			callback = function()
				shared.copy(string.format("PlaceId=%s  JobId=%s", tostring(game.PlaceId), tostring(game.JobId)))
			end,
		})
		section:AddButton({
			text = "Count All Instances",
			callback = function()
				local count = 0
				if caps.getinstances then
					local ok, list = pcall(getinstances)
					if ok and type(list) == "table" then
						count = #list
					end
				else
					local ok, list = pcall(function()
						return game:GetDescendants()
					end)
					if ok and type(list) == "table" then
						count = #list
					end
				end
				ctx.notify("Instances: " .. tostring(count), 3)
			end,
		})
		section:AddLabel("Outbound Remote Spy logging uses its wrapper API")
	end

	addExecutorSection()

	local devToolsFlag = ctx.gakuran and "Gakuran Dev Tools" or "Universal Dev Tools"
	if library.SettingsMain then
		local devToggle = library.SettingsMain:AddToggle({
			text = "Enable Dev Tools Tab",
			flag = devToolsFlag,
			state = false,
			callback = function(enabled)
				setEnabled(enabled == true)
			end,
		})
		local devLabel = library.SettingsMain:AddLabel(
			"Notifications, diagnostics, animation tools, Remote Spy, and more"
		)

		do
			local options = library.options or {}
			local checkOption = options["Universal Check for Updates"]
			local unloadOption = options["Unload xanhub"]
			local basePosition = (unloadOption and tonumber(unloadOption.position) or 0) + 1
			if checkOption and tonumber(checkOption.position) then
				basePosition = tonumber(checkOption.position) + 2
			end
			devToggle.position = basePosition
			devLabel.position = basePosition + 1
		end
	end

	if library.AddCleanup then
		library:AddCleanup(function()
			local dev = ctx.devtools
			if not dev then
				return
			end
			for _, fn in ipairs(dev.cleanup or {}) do
				pcall(fn)
			end
			if dev.tab and type(library.SetTabVisible) == "function" then
				pcall(function()
					library:SetTabVisible(dev.tab, false)
				end)
			end
		end)
	end

	local function setup()
		if controllerSetup then
			return
		end
		controllerSetup = true

		local dev = ctx.devtools
		if dev and dev.shared and library.base then
			pcall(dev.shared.ensureOverlayGui)
		end

		-- Notifications and diagnostics are infrastructure, so arm them even while
		-- the Dev Tools tab remains hidden. setupModule makes this idempotent.
		setupNamed("notifications")
		setupNamed("diagnostics")

		local enabled = library.flags[devToolsFlag] == true
		setEnabled(enabled)
	end

	return {
		setup = setup,
		setEnabled = setEnabled,
		modules = loadedModules,
		manifest = manifest,
		getSetupState = function()
			return setupState
		end,
	}
end
