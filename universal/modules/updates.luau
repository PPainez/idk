--[[
    xanhub | universal | updates

    Remote update checker with full menu replacement reload.
]]

local UNIVERSAL_MARKERS = {
	"xanhub | Universal",
	"local runtime = ...",
}

local UPDATE_MANIFEST = {
	"universal.luau",
	"universal/lib/context.luau",
	"universal/modules/ui.luau",
	"universal/modules/updates.luau",
	"universal/modules/movement.luau",
	"universal/modules/esp.luau",
	"universal/modules/overlay.luau",
	"universal/modules/world.luau",
	"universal/modules/utility.luau",
	"universal/modules/keybinds.luau",
	"universal/modules/devtools.luau",
	"devmodules/dev_shared.luau",
	"devmodules/remote_spy.luau",
	"devmodules/console_logger.luau",
	"devmodules/performance_profiler.luau",
	"devmodules/instance_inspector.luau",
	"devmodules/animation_viewer.luau",
	"devmodules/animation_logger.luau",
}

return function(ctx)
	local library = ctx.library
	local runtime = ctx.runtime
	local state = ctx.state
	local env = ctx.env
	local Http = ctx.shared.Http
	local Constants = ctx.shared.Constants

	local UPDATE_FOLDER = "xanhub_updates"
	local UPDATE_REVISION_FILE = UPDATE_FOLDER .. "/universal_manifest_revision.txt"

	local controllerState = {
		checking = false,
		prompting = false,
		reloading = false,
		disposed = false,
		sessionRevision = nil,
		previousRevision = nil,
		promptedRevision = nil,
		declinedRevision = nil,
	}

	local updateFilesystem = type(isfolder) == "function"
		and type(makefolder) == "function"
		and type(isfile) == "function"
		and type(readfile) == "function"
		and type(writefile) == "function"

	local statusLabel
	local confirmWarning = library:AddWarning({
		type = "confirm",
		text = "",
	})

	local function setStatus(message)
		if controllerState.disposed then
			return
		end

		if statusLabel and statusLabel.Text ~= nil then
			pcall(function()
				statusLabel.Text = "Updates: " .. tostring(message)
			end)
		end
	end

	local function fetchManifestSource(path)
		for _, url in ipairs(Constants.repositoryUrls(path)) do
			local source, requestError = Http.requestOne(url)
			if source and Http.validLuaBody(source) then
				return source, url
			end
		end
		return nil, "failed to fetch " .. path
	end

	local function fetchRemoteBuild()
		local errors = {}
		local fingerprints = {}
		local mainSource

		for _, path in ipairs(UPDATE_MANIFEST) do
			local source, providerOrError = fetchManifestSource(path)
			if not source then
				table.insert(errors, tostring(providerOrError))
			else
				table.insert(fingerprints, path .. ":" .. Http.rollingHash(source))
				if path == "universal.luau" then
					mainSource = source
				end
			end
		end

		if not mainSource then
			return nil, nil, table.concat(errors, " | ")
		end

		if not Http.validSource(mainSource, UNIVERSAL_MARKERS) then
			return nil, nil, "universal.luau failed marker validation"
		end

		table.sort(fingerprints)
		local revision = Http.rollingHash(table.concat(fingerprints, "|"))
		return mainSource, revision, "manifest(" .. tostring(#fingerprints) .. " files)"
	end

	local function readSavedRevision()
		if not updateFilesystem then
			return nil
		end

		local ok, result = pcall(function()
			if not isfile(UPDATE_REVISION_FILE) then
				return nil
			end
			return tostring(readfile(UPDATE_REVISION_FILE)):match("%S+")
		end)
		return ok and result or nil
	end

	local function writeSavedRevision(revision)
		if not updateFilesystem or type(revision) ~= "string" then
			return false
		end

		return pcall(function()
			if not isfolder(UPDATE_FOLDER) then
				makefolder(UPDATE_FOLDER)
			end
			writefile(UPDATE_REVISION_FILE, revision)
		end)
	end

	local function destroyExistingUiRoots()
		local names = {
			["xanhub_ui"] = true,
			["uwuware_ui"] = true,
		}
		local parents = {}

		local function addParent(parent)
			if typeof(parent) == "Instance" and not table.find(parents, parent) then
				table.insert(parents, parent)
			end
		end

		local function addGetter(getter)
			if type(getter) == "function" then
				local ok, parent = pcall(getter)
				if ok then
					addParent(parent)
				end
			end
		end

		addGetter(gethui)
		addGetter(get_hidden_gui)
		addGetter(gethiddengui)

		pcall(function()
			addParent(game:GetService("CoreGui"))
		end)

		pcall(function()
			local player = ctx.Players.LocalPlayer
			if player then
				addParent(player:FindFirstChildOfClass("PlayerGui"))
			end
		end)

		for _, parent in ipairs(parents) do
			pcall(function()
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") and names[child.Name] then
						child:Destroy()
					end
				end
			end)
		end
	end

	local function buildReloadRuntime(revision)
		local nextRuntime = {}
		if type(runtime) == "table" then
			for key, value in pairs(runtime) do
				if key ~= "library" and key ~= "unloading" then
					nextRuntime[key] = value
				end
			end
		end

		nextRuntime.library = nil
		nextRuntime.unloading = false
		nextRuntime.reloadedFromUpdate = true
		nextRuntime.forceFreshModules = true
		nextRuntime.updateRevision = revision
		nextRuntime.placeId = game.PlaceId
		nextRuntime.universeId = game.GameId
		nextRuntime.repositoryRoot = runtime and runtime.repositoryRoot or Constants.REPOSITORY_ROOT
		nextRuntime.uiUrl = runtime and runtime.uiUrl or Constants.uiUrl()
		return nextRuntime
	end

	local function disableActiveFeatures()
		for flag, value in pairs(library.flags or {}) do
			if type(flag) == "string"
				and string.sub(flag, 1, 10) == "Universal "
				and type(value) == "boolean" then
				library.flags[flag] = false
			end
		end
		state.aimTarget = nil
	end

	local function reloadRemoteBuild(revision)
		if controllerState.reloading or state.reloading then
			return
		end

		controllerState.reloading = true
		state.reloading = true
		state.unloading = true
		setStatus("downloading latest build...")
		ctx.notify("Downloading latest Universal build...", 2)

		task.spawn(function()
			local source, latestRevision, providerOrError = fetchRemoteBuild()
			local targetRevision = latestRevision or revision

			if not source then
				controllerState.reloading = false
				state.reloading = false
				state.unloading = false
				setStatus("reload failed")
				ctx.notify("Update reload failed: " .. tostring(providerOrError), 5)
				return
			end

			local compiledChunk, compileError = Http.compileSource(source)
			if not compiledChunk then
				controllerState.reloading = false
				state.reloading = false
				state.unloading = false
				setStatus("reload compile failed")
				ctx.notify("Update compile failed: " .. tostring(compileError), 5)
				return
			end

			setStatus("replacing menu...")
			ctx.notify("Replacing menu with updated build...", 2)

			disableActiveFeatures()
			controllerState.disposed = true

			local nextRuntime = buildReloadRuntime(targetRevision)
			if type(runtime) == "table" then
				runtime.unloading = true
				runtime.library = nil
			end

			env.xanhub = nil
			env.library = nil

			local unloadOk, unloadError = pcall(function()
				library:Unload()
			end)
			if not unloadOk then
				warn("[xanhub updater] unload warning: " .. tostring(unloadError))
			end

			destroyExistingUiRoots()
			task.wait(0.05)

			env.XANHUB_RUNTIME = nextRuntime

			local started, startResult = xpcall(function()
				return compiledChunk(nextRuntime)
			end, debug.traceback)

			if started then
				writeSavedRevision(targetRevision)
				setStatus("reload complete")
				ctx.notify("Universal updated successfully", 3)
			else
				state.reloading = false
				state.unloading = false
				setStatus("reload failed")
				warn("[xanhub updater] updated script failed to start:\n" .. tostring(startResult))
				ctx.notify("Updated build failed to start", 5)
			end
		end)
	end

	local function askToReload(_source, revision, reason, manual)
		if controllerState.prompting or controllerState.reloading or controllerState.disposed then
			return
		end

		if controllerState.promptedRevision == revision and not manual then
			return
		end

		controllerState.prompting = true
		controllerState.promptedRevision = revision
		setStatus("update available — waiting for choice")

		local reasonText = reason == "session"
			and "A newer Universal build was published after this menu loaded."
			or "Universal features changed since your previous load."

		confirmWarning.text = reasonText
			.. "\n\nReload now to replace every tab with the latest build?"
			.. "\n\nYour current menu will fully unload, then reopen instantly."

		local accepted = confirmWarning:Show() == true
		controllerState.prompting = false

		if accepted then
			setStatus("update accepted — preparing reload")
			reloadRemoteBuild(revision)
		else
			controllerState.declinedRevision = revision
			setStatus("update available — reload declined")
			ctx.notify("Update reload cancelled", 2)
		end
	end

	local function checkForUpdates(manual)
		if controllerState.disposed or state.unloading or controllerState.reloading then
			return
		end

		if controllerState.checking then
			if manual then
				ctx.notify("An update check is already running", 2)
			end
			return
		end

		controllerState.checking = true
		setStatus("checking...")

		task.spawn(function()
			local source, latestRevision, providerOrError = fetchRemoteBuild()
			controllerState.checking = false

			if controllerState.disposed or state.unloading or controllerState.reloading then
				return
			end

			if not source or not latestRevision then
				setStatus("check failed")
				if manual then
					ctx.notify("Update check failed: " .. tostring(providerOrError), 4)
				end
				return
			end

			if controllerState.previousRevision == nil then
				controllerState.previousRevision = readSavedRevision()
			end

			local changedSinceSession = controllerState.sessionRevision ~= nil
				and latestRevision ~= controllerState.sessionRevision
			local changedSinceLastLoad = controllerState.previousRevision ~= nil
				and latestRevision ~= controllerState.previousRevision

			if controllerState.sessionRevision == nil then
				controllerState.sessionRevision = latestRevision
			end

			if changedSinceSession or changedSinceLastLoad then
				askToReload(source, latestRevision, changedSinceSession and "session" or "last_load", manual)
				return
			end

			if controllerState.previousRevision == nil then
				writeSavedRevision(latestRevision)
				controllerState.previousRevision = latestRevision
				setStatus("baseline saved")
			elseif controllerState.declinedRevision == latestRevision then
				setStatus("update available — reload declined")
			else
				setStatus("up to date")
			end

			if manual then
				ctx.notify("Universal is up to date", 2)
			end
		end)
	end

	local updateButton = library.SettingsMain:AddButton({
		text = "Check for Updates",
		flag = "Universal Check for Updates",
		callback = function()
			checkForUpdates(true)
		end,
	})

	statusLabel = library.SettingsMain:AddLabel("Updates: waiting for check")

	do
		local options = library.options or {}
		local unloadOption = options["Unload xanhub"]
			or options["Unload Cheat"]
			or options["Unload"]
		local panicOption = options["Panic Key"]
		local unloadPosition = unloadOption and tonumber(unloadOption.position) or 0

		updateButton.position = unloadPosition + 1
		statusLabel.position = unloadPosition + 2
		if panicOption and tonumber(panicOption.position) <= statusLabel.position then
			panicOption.position = statusLabel.position + 1
		end
	end

	return {
		check = checkForUpdates,
		cancel = function()
			controllerState.disposed = true
			controllerState.checking = false
			controllerState.prompting = false
			pcall(function()
				confirmWarning:Close()
			end)
		end,
	}
end
