--[[
    xanhub | universal | updates

    Fast build-manifest update checks with a full-source fallback and complete
    menu replacement reload.
]]

local UNIVERSAL_MARKERS = {
	"xanhub | Universal",
	"local runtime = ...",
}

-- Used only when build.luau is unavailable. This fallback is intentionally
-- all-or-nothing so transient missing files cannot create a false revision.
local FALLBACK_MANIFEST = {
	"shared/constants.luau",
	"shared/http.luau",
	"shared/connection.luau",
	"shared/module_loader.luau",
	"ui.luau",
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
	"devmodules/manifest.luau",
	"devmodules/dev_shared.luau",
	"devmodules/notification_center.luau",
	"devmodules/runtime_diagnostics.luau",
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
	local UPDATE_REVISION_FILE = UPDATE_FOLDER .. "/universal_build_revision.txt"

	local controllerState = {
		checking = false,
		prompting = false,
		reloading = false,
		disposed = false,
		sessionRevision = type(runtime) == "table" and runtime.buildRevision or nil,
		previousRevision = nil,
		promptedRevision = nil,
		declinedRevision = nil,
		lastCheckedAt = nil,
		latestManifest = nil,
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

	local function safeTraceback(err)
		if type(ctx.traceback) == "function" then
			return ctx.traceback(err)
		end
		return tostring(err)
	end

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

	local function revisionLabel(revision)
		revision = tostring(revision or "unknown")
		return #revision > 10 and string.sub(revision, 1, 10) or revision
	end

	local function fetchBuildManifest()
		local manifest, loadError = Http.fetchLuaTable(
			Constants.buildManifestUrls(true),
			{ "xanhub-build" },
			"@xanhub/build.luau"
		)
		if type(manifest) ~= "table" then
			return nil, loadError
		end
		if type(manifest.revision) ~= "string" or manifest.revision == "" then
			return nil, "build manifest has no revision"
		end
		return manifest
	end

	local function fetchUniversalSource(revision)
		local source, fetchError = Http.fetchSource(
			Constants.repositoryUrls("universal.luau", revision),
			2
		)
		if not source then
			return nil, fetchError
		end
		if not Http.validSource(source, UNIVERSAL_MARKERS) then
			return nil, "universal.luau failed marker validation"
		end
		return source
	end

	local function fetchFallbackBuild()
		local fingerprints = {}
		local mainSource
		local errors = {}

		for _, path in ipairs(FALLBACK_MANIFEST) do
			local source, fetchError = Http.fetchSource(Constants.freshRepositoryUrls(path), 1)
			if not source then
				table.insert(errors, path .. ": " .. tostring(fetchError))
			else
				table.insert(fingerprints, path .. ":" .. Http.rollingHash(source))
				if path == "universal.luau" then
					mainSource = source
				end
			end
		end

		if #errors > 0 then
			return nil, nil, nil, "fallback incomplete: " .. table.concat(errors, " | ")
		end
		if not mainSource or not Http.validSource(mainSource, UNIVERSAL_MARKERS) then
			return nil, nil, nil, "fallback universal source invalid"
		end

		table.sort(fingerprints)
		local revision = Http.rollingHash(table.concat(fingerprints, "|"))
		return mainSource, revision, {
			name = "xanhub-build-fallback",
			version = "fallback",
			revision = revision,
			fileCount = #fingerprints,
		}, "fallback hash"
	end

	local function fetchRemoteBuild()
		local manifest, manifestError = fetchBuildManifest()
		if manifest then
			local source, sourceError = fetchUniversalSource(manifest.revision)
			if not source then
				return nil, nil, manifest, sourceError
			end
			return source, manifest.revision, manifest, "build manifest"
		end

		warn("[xanhub updater] build.luau unavailable; using fallback: " .. tostring(manifestError))
		return fetchFallbackBuild()
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
			["xanhub_dev_overlay"] = true,
		}
		local parents = {}

		local function addParent(parent)
			if typeof(parent) == "Instance" and not table.find(parents, parent) then
				table.insert(parents, parent)
			end
		end

		for _, getter in ipairs({ gethui, get_hidden_gui, gethiddengui }) do
			if type(getter) == "function" then
				local ok, parent = pcall(getter)
				if ok then
					addParent(parent)
				end
			end
		end

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

	local function buildReloadRuntime(revision, manifest, entrySource)
		local nextRuntime = {}
		if type(runtime) == "table" then
			for key, value in pairs(runtime) do
				if key ~= "library" and key ~= "unloading" and key ~= "moduleStatus" and key ~= "shared" then
					nextRuntime[key] = value
				end
			end
		end

		nextRuntime.library = nil
		nextRuntime.shared = nil
		nextRuntime.unloading = false
		nextRuntime.reloadedFromUpdate = true
		nextRuntime.forceFreshModules = true
		nextRuntime.buildRevision = revision
		nextRuntime.cacheBust = revision
		nextRuntime.buildVersion = manifest and manifest.version or nextRuntime.buildVersion
		nextRuntime.buildGeneratedAt = manifest and manifest.generatedAtUTC or nextRuntime.buildGeneratedAt
		nextRuntime.entrySource = entrySource
		nextRuntime.placeId = game.PlaceId
		nextRuntime.universeId = game.GameId
		nextRuntime.repositoryRoot = runtime and runtime.repositoryRoot or Constants.REPOSITORY_ROOT
		nextRuntime.uiUrl = Constants.uiUrl(revision)
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

	local function reloadRemoteBuild(source, revision, manifest)
		if controllerState.reloading or state.reloading then
			return
		end

		local compiledChunk, compileError = Http.compileSource(source, "@xanhub/universal-update")
		if not compiledChunk then
			setStatus("update compile failed")
			ctx.toast("error", "Update compile failed: " .. tostring(compileError), {
				title = "Update rejected",
				channel = "updates",
				duration = 7,
			})
			return
		end

		controllerState.reloading = true
		state.reloading = true
		setStatus("update accepted — unloading features")
		ctx.toast("info", "The current menu will unload and reopen on build " .. revisionLabel(revision), {
			title = "Applying update",
			channel = "updates",
			duration = 3,
		})

		task.spawn(function()
			disableActiveFeatures()
			controllerState.disposed = true
			state.unloading = true

			local nextRuntime = buildReloadRuntime(revision, manifest, source)
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
			task.wait(0.08)
			env.XANHUB_RUNTIME = nextRuntime

			local started, startResult = xpcall(function()
				return compiledChunk(nextRuntime)
			end, safeTraceback)

			if started then
				writeSavedRevision(revision)
			else
				warn("[xanhub updater] updated script failed to start:\n" .. tostring(startResult))
			end
		end)
	end

	local function askToReload(source, revision, manifest, manual)
		if controllerState.prompting or controllerState.reloading or controllerState.disposed then
			return
		end
		if controllerState.promptedRevision == revision and not manual then
			return
		end

		controllerState.prompting = true
		controllerState.promptedRevision = revision
		setStatus("build " .. revisionLabel(revision) .. " available — waiting for choice")

		local versionText = manifest and manifest.version and (" v" .. tostring(manifest.version)) or ""
		confirmWarning.text = "A newer Universal build" .. versionText .. " is available."
			.. "\n\nReload features now?"
			.. "\n\nThe current functions and menu will unload, then the updated build will reopen."
			.. "\nThis may briefly flicker if the executor is slow."

		local accepted = confirmWarning:Show() == true
		controllerState.prompting = false

		if accepted then
			reloadRemoteBuild(source, revision, manifest)
		else
			controllerState.declinedRevision = revision
			setStatus("build " .. revisionLabel(revision) .. " available — reload declined")
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
		setStatus("checking current build...")

		task.spawn(function()
			local source, latestRevision, manifest, providerOrError = fetchRemoteBuild()
			controllerState.checking = false
			controllerState.lastCheckedAt = os.time()

			if controllerState.disposed or state.unloading or controllerState.reloading then
				return
			end

			if not source or not latestRevision then
				setStatus("check failed")
				if manual then
					ctx.toast("error", "Update check failed: " .. tostring(providerOrError), {
						title = "Update check",
						channel = "updates",
						duration = 7,
					})
				end
				return
			end

			controllerState.latestManifest = manifest
			controllerState.previousRevision = controllerState.previousRevision or readSavedRevision()

			-- runtime.buildRevision represents the build actually running. Only a
			-- difference from that value means a reload is necessary.
			if controllerState.sessionRevision == nil then
				controllerState.sessionRevision = latestRevision
			end

			if latestRevision ~= controllerState.sessionRevision then
				task.defer(function()
					askToReload(source, latestRevision, manifest, manual)
				end)
				return
			end

			writeSavedRevision(latestRevision)
			controllerState.previousRevision = latestRevision
			local versionText = manifest and manifest.version and ("v" .. tostring(manifest.version) .. " · ") or ""
			setStatus(versionText .. "up to date · " .. revisionLabel(latestRevision))
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
		getState = function()
			return controllerState
		end,
	}
end
