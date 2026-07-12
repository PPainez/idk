--[[
    xanhub | universal | devtools

    Loads devmodules, adds Settings toggle, and shows Dev Tools tab on demand.
]]

local DEV_MODULE_PATHS = {
	"devmodules/dev_shared.luau",
	"devmodules/notification_center.luau",
	"devmodules/animation_viewer.luau",
	"devmodules/animation_logger.luau",
	"devmodules/remote_spy.luau",
	"devmodules/console_logger.luau",
	"devmodules/performance_profiler.luau",
	"devmodules/instance_inspector.luau",
}

return function(ctx)
	local library = ctx.library
	local moduleLoader = ctx.moduleLoader
	local loadedModules = {}
	local setupsRan = false

	ctx.devtools = type(ctx.devtools) == "table" and ctx.devtools or {}

	local function runSetups()
		if setupsRan then
			return
		end
		for _, module in ipairs(loadedModules) do
			if type(module.setup) == "function" then
				local ok, err = pcall(module.setup)
				if not ok then
					warn("[xanhub dev] " .. tostring(module.name) .. " setup failed: " .. tostring(err))
				end
			end
		end
		setupsRan = true
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
			"Caps: clipboard=%s  fs=%s  gethui=%s  hook=%s",
			tostring(caps.clipboard),
			tostring(caps.filesystem),
			tostring(caps.gethui),
			tostring(caps.hookmetamethod)
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
		section:AddLabel("getgc disabled (crashes many executors)")
		section:AddLabel("Use Remote Spy wrapper API for logged outbound calls")
	end

	for _, path in ipairs(DEV_MODULE_PATHS) do
		local factory = moduleLoader.load(path)
		local module = factory(ctx)
		if type(module) == "table" then
			table.insert(loadedModules, module)
		end
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
		local devLabel = library.SettingsMain:AddLabel("Notifications, Animation Logger, Viewer, Remote Spy, and more")

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
		local dev = ctx.devtools
		if dev and dev.shared and library.base then
			pcall(dev.shared.ensureOverlayGui)
		end

		-- Always arm the stacked notification service (combat/AP toasts, etc.)
		-- even when the Dev Tools tab is hidden.
		for _, module in ipairs(loadedModules) do
			if type(module) == "table" and module.name == "notifications" and type(module.setup) == "function" then
				local ok, err = pcall(module.setup)
				if not ok then
					warn("[xanhub dev] notifications setup failed: " .. tostring(err))
				end
				break
			end
		end

		local enabled = library.flags[devToolsFlag] == true
		setEnabled(enabled)
	end

	return {
		setup = setup,
		setEnabled = setEnabled,
		modules = loadedModules,
	}
end
