--[[
    xanhub | Universal

    Orchestrates feature modules loaded from universal/modules/.
    Runs through loader.luau or standalone.
]]

local runtime = ...
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(runtime) ~= "table" then
	runtime = env.XANHUB_RUNTIME
end
runtime = type(runtime) == "table" and runtime or {}

local REPOSITORY_ROOT = runtime.repositoryRoot
	or "https://raw.githubusercontent.com/PPainez/idk/main"

local function bootstrapBodyValid(body)
	if type(body) ~= "string" or #body < 20 then
		return false
	end
	body = body:gsub("^\239\187\191", "")
	local prefix = string.lower(string.sub(body:match("^%s*(.*)") or body, 1, 180))
	return not (
		prefix == "404: not found"
		or string.match(prefix, "^404[:%s]")
		or string.match(prefix, "^<!doctype%s+html")
		or string.match(prefix, "^<html")
		or string.match(prefix, "^repository%s+not%s+found")
	)
end

local function bootstrapRequest(path)
	path = tostring(path):gsub("^/+", "")
	local urls = {
		REPOSITORY_ROOT:gsub("/+$", "") .. "/" .. path,
		"https://github.com/PPainez/idk/raw/refs/heads/main/" .. path,
		"https://cdn.jsdelivr.net/gh/PPainez/idk@main/" .. path,
	}
	local requestFunction = type(request) == "function" and request
		or type(http_request) == "function" and http_request
		or type(httprequest) == "function" and httprequest
		or type(syn) == "table" and type(syn.request) == "function" and syn.request
		or type(http) == "table" and type(http.request) == "function" and http.request
		or nil
	local errors = {}

	for _, url in ipairs(urls) do
		if requestFunction then
			local ok, response = pcall(requestFunction, {
				Url = url,
				Method = "GET",
				Headers = {
					["Cache-Control"] = "no-cache, no-store, max-age=0",
					["Pragma"] = "no-cache",
					["User-Agent"] = "xanhub-universal-bootstrap",
				},
			})
			if ok then
				local body = type(response) == "table"
					and (response.Body or response.body or response.ResponseBody)
					or response
				local status = type(response) == "table"
					and tonumber(response.StatusCode or response.Status or response.status_code)
					or nil
				if bootstrapBodyValid(body) and (not status or (status >= 200 and status < 300)) then
					return body
				end
				table.insert(errors, tostring(status or "request failed"))
			else
				table.insert(errors, tostring(response))
			end
		end

		local ok, body = pcall(function()
			return game:HttpGet(url, false)
		end)
		if ok and bootstrapBodyValid(body) then
			return body
		end
		table.insert(errors, tostring(body or "HttpGet failed"))
	end

	return nil, table.concat(errors, " | ")
end

local function bootstrapModule(path)
	local shared = runtime.shared
	if path == "shared/http.luau" and type(shared) == "table" and type(shared.Http) == "table" then
		return shared.Http
	end
	if path == "shared/constants.luau" and type(shared) == "table" and type(shared.Constants) == "table" then
		return shared.Constants
	end

	local source, loadError = bootstrapRequest(path)
	assert(source, "[xanhub universal] bootstrap failed for " .. path .. ": " .. tostring(loadError))

	local chunk, compileError = loadstring(source)
	assert(chunk, "[xanhub universal] compile failed for " .. path .. ": " .. tostring(compileError))
	return chunk()
end

local Http = bootstrapModule("shared/http.luau")
local Constants = bootstrapModule("shared/constants.luau")
local Connection = bootstrapModule("shared/connection.luau")
local ModuleLoader = bootstrapModule("shared/module_loader.luau")
local createContext = bootstrapModule("universal/lib/context.luau")

Http.setUserAgent(Constants.UNIVERSAL_USER_AGENT)
runtime.shared = {
	Http = Http,
	Constants = Constants,
}

local function resolveBuildMetadata()
	if type(runtime.buildRevision) == "string" and runtime.buildRevision ~= "" then
		runtime.cacheBust = runtime.cacheBust or runtime.buildRevision
		return
	end

	local manifest, loadError = Http.fetchLuaTable(
		Constants.buildManifestUrls(true),
		{ "xanhub-build" },
		"@xanhub/build.luau"
	)
	if type(manifest) == "table" and type(manifest.revision) == "string" then
		runtime.buildRevision = manifest.revision
		runtime.cacheBust = manifest.revision
		runtime.buildVersion = manifest.version
		runtime.buildGeneratedAt = manifest.generatedAtUTC
	else
		runtime.cacheBust = runtime.cacheBust or Constants.MODULE_CACHE_BUST
		warn("[xanhub universal] Build metadata unavailable: " .. tostring(loadError))
	end
end

resolveBuildMetadata()

local moduleLoader = ModuleLoader.new(Http, function(path)
	return Constants.repositoryUrls(path, runtime.cacheBust or runtime.buildRevision)
end)

if runtime.forceFreshModules == true then
	moduleLoader.clear()
end

local UI_URL = runtime.uiUrl or Constants.uiUrl(runtime.cacheBust)

local function acquireLibrary()
	if runtime.reloadedFromUpdate == true then
		runtime.library = nil
	end

	if type(runtime.library) == "table" and not runtime.library.unloaded then
		return runtime.library
	end

	local source, fetchError = Http.fetchSource(Constants.repositoryUrls("ui.luau", runtime.cacheBust))
	assert(source, "[xanhub universal] UI request failed: " .. tostring(fetchError))

	local chunk, compileError = Http.compileSource(source, "@xanhub/ui.luau")
	assert(chunk, "[xanhub universal] UI compile failed: " .. tostring(compileError))

	local loaded = chunk()
	assert(type(loaded) == "table", "[xanhub universal] UI library returned an invalid value")

	runtime.library = loaded
	runtime.uiUrl = UI_URL
	runtime.repositoryRoot = REPOSITORY_ROOT
	runtime.placeId = game.PlaceId
	runtime.universeId = game.GameId
	env.XANHUB_RUNTIME = runtime
	return loaded
end

local library = acquireLibrary()
library:SetTitle("xanhub | Universal")
library:SetAccent(Color3.fromRGB(0, 170, 255))
library:SetTweening(true)

local services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	UserInputService = game:GetService("UserInputService"),
	Lighting = game:GetService("Lighting"),
	TweenService = game:GetService("TweenService"),
	TeleportService = game:GetService("TeleportService"),
	VirtualUser = game:GetService("VirtualUser"),
	StarterGui = game:GetService("StarterGui"),
	Workspace = game:GetService("Workspace"),
}

local state = {
	unloading = false,
	reloading = false,
	connections = {},
	original = {},
	esp = {},
	overlays = {},
	fly = {},
	noclipOriginal = setmetatable({}, { __mode = "k" }),
	movementOriginal = setmetatable({}, { __mode = "k" }),
	effectOriginal = setmetatable({}, { __mode = "k" }),
}

runtime.startedAt = tonumber(runtime.startedAt) or os.clock()
runtime.moduleStatus = {}
runtime.repositoryRoot = REPOSITORY_ROOT
runtime.uiUrl = UI_URL
runtime.placeId = game.PlaceId
runtime.universeId = game.GameId
env.XANHUB_RUNTIME = runtime

local connections = Connection.new(library, state.connections)
local ctx = createContext({
	library = library,
	runtime = runtime,
	state = state,
	env = env,
	connections = connections,
	services = services,
	columns = nil,
	tabs = nil,
	refs = {},
})

ctx.shared = {
	Http = Http,
	Constants = Constants,
}
ctx.fetchSource = Http.fetchSource
ctx.moduleLoader = moduleLoader

local startupFailures = {}

local function loadController(path, required)
	local factory, loadError = moduleLoader.tryLoad(path)
	if type(factory) ~= "function" then
		ctx.setModuleStatus(path, "load-error", loadError)
		table.insert(startupFailures, path .. ": " .. tostring(loadError))
		if required then
			error("[xanhub universal] required module failed: " .. path .. ": " .. tostring(loadError))
		end
		return nil
	end

	local startedAt = os.clock()
	local ok, result = xpcall(function()
		return factory(ctx)
	end, ctx.traceback)
	if not ok then
		ctx.setModuleStatus(path, "factory-error", result)
		table.insert(startupFailures, path .. ": " .. tostring(result))
		if required then
			error("[xanhub universal] required module failed: " .. path .. ": " .. tostring(result))
		end
		return nil
	end

	local record = ctx.setModuleStatus(path, "loaded")
	record.duration = os.clock() - startedAt
	return result
end

local function runSetup(path, controller)
	if not controller or type(controller.setup) ~= "function" then
		return true
	end

	local startedAt = os.clock()
	local ok, result = xpcall(controller.setup, ctx.traceback)
	local record = ctx.setModuleStatus(path, ok and "ready" or "setup-error", ok and nil or result)
	record.setupDuration = os.clock() - startedAt
	if not ok then
		table.insert(startupFailures, path .. ": " .. tostring(result))
		warn("[xanhub universal] setup failed (" .. path .. "): " .. tostring(result))
	end
	return ok
end

local uiResult = loadController("universal/modules/ui.luau", true)
ctx.columns = uiResult.columns
ctx.tabs = uiResult.tabs

local updateController = loadController("universal/modules/updates.luau", false) or {
	check = function() end,
	cancel = function() end,
}
local devtoolsController = loadController("universal/modules/devtools.luau", false)

local featureControllers = {}
for _, modulePath in ipairs({
	"universal/modules/movement.luau",
	"universal/modules/overlay.luau",
	"universal/modules/esp.luau",
	"universal/modules/world.luau",
	"universal/modules/utility.luau",
}) do
	table.insert(featureControllers, {
		path = modulePath,
		controller = loadController(modulePath, false),
	})
end

loadController("universal/modules/keybinds.luau", false)

local initialized, initError = library:Init()
assert(initialized, "[xanhub universal] initialization failed: " .. tostring(initError))

state.original.cameraFov = services.Workspace.CurrentCamera
	and services.Workspace.CurrentCamera.FieldOfView
	or 70

pcall(ctx.createOverlayRoot)
for _, entry in ipairs(featureControllers) do
	runSetup(entry.path, entry.controller)
end
runSetup("universal/modules/devtools.luau", devtoolsController)

task.defer(function()
	if not state.unloading and type(updateController.check) == "function" then
		updateController.check(false)
	end
end)

library:AddCleanup(function()
	state.unloading = true
	if type(updateController.cancel) == "function" then
		updateController.cancel()
	end

	runtime.unloading = true

	for flag, value in pairs(library.flags or {}) do
		if type(flag) == "string"
			and string.sub(flag, 1, 10) == "Universal "
			and type(value) == "boolean" then
			library.flags[flag] = false
		end
	end
	state.aimTarget = nil

	local camera = services.Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = state.original.cameraFov or 70
	end

	connections:disconnectAll()

	if state.overlays.root then
		pcall(function()
			state.overlays.root:Destroy()
		end)
		state.overlays.root = nil
	end
end)

library:SetOpen(true)
library:selectTab(ctx.tabs.home)

local readyCount = 0
for _, record in pairs(runtime.moduleStatus) do
	if record.status == "ready" or record.status == "loaded" then
		readyCount = readyCount + 1
	end
end

if ctx.refs.runtimeStatus then
	local buildText = type(runtime.buildRevision) == "string" and string.sub(runtime.buildRevision, 1, 8) or "local"
	ctx.refs.runtimeStatus.Text = string.format(
		"Status: ready · %d modules · build %s",
		readyCount,
		buildText
	)
end

if #startupFailures > 0 then
	ctx.toast("warning", tostring(#startupFailures) .. " module issue(s) were isolated; open Dev Tools diagnostics", {
		title = "Partial startup",
		channel = "runtime",
		duration = 7,
		key = "universal-startup-failures",
	})
else
	ctx.notify(runtime.reloadedFromUpdate and "xanhub Universal updated" or "xanhub Universal ready", 3)
end

print("[xanhub] Universal loaded for place", game.PlaceId, "build", runtime.buildRevision or "local")

return {
	library = library,
	runtime = runtime,
	state = state,
	context = ctx,
}
