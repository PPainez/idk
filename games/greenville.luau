--[[
    xanhub | Greenville

    Featured tuning garage edition.
]]

local GREENVILLE_PLACE_ID = 891852901
local GREENVILLE_UNIVERSE_ID = 371263894

local runtime = ...
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(runtime) ~= "table" then
	runtime = env.XANHUB_RUNTIME
end
runtime = type(runtime) == "table" and runtime or {}

local REPOSITORY_ROOT = (type(runtime) == "table" and runtime.repositoryRoot)
	or "https://raw.githubusercontent.com/PPainez/idk/main"

local function bootstrapModule(path)
	local shared = runtime.shared
	if path == "shared/http.luau" and type(shared) == "table" and type(shared.Http) == "table" then
		return shared.Http
	end
	if path == "shared/constants.luau" and type(shared) == "table" and type(shared.Constants) == "table" then
		return shared.Constants
	end

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
	local source
	local errors = {}

	for _, url in ipairs(urls) do
		if requestFunction then
			local ok, response = pcall(requestFunction, {
				Url = url,
				Method = "GET",
				Headers = {
					["Cache-Control"] = "no-cache, no-store, max-age=0",
					["Pragma"] = "no-cache",
					["User-Agent"] = "xanhub-greenville-bootstrap",
				},
			})
			if ok then
				local body = type(response) == "table" and (response.Body or response.body or response.ResponseBody) or response
				local status = type(response) == "table" and tonumber(response.StatusCode or response.Status or response.status_code) or nil
				if type(body) == "string" and #body > 20 and (not status or (status >= 200 and status < 300)) then
					source = body
					break
				end
				table.insert(errors, tostring(status or "request failed"))
			end
		end

		local ok, body = pcall(function()
			return game:HttpGet(url, false)
		end)
		if ok and type(body) == "string" and #body > 20 then
			source = body
			break
		end
		table.insert(errors, tostring(body or "HttpGet failed"))
	end

	assert(source, "[xanhub greenville] bootstrap failed for " .. path .. ": " .. table.concat(errors, " | "))

	local chunk, compileError = loadstring(source)
	assert(chunk, "[xanhub greenville] compile failed for " .. path .. ": " .. tostring(compileError))

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

if type(runtime.buildRevision) ~= "string" or runtime.buildRevision == "" then
	local manifest, manifestError = Http.fetchLuaTable(
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
		warn("[xanhub greenville] Build metadata unavailable: " .. tostring(manifestError))
	end
end

local moduleLoader = ModuleLoader.new(Http, function(path)
	return Constants.repositoryUrls(path, runtime.cacheBust or runtime.buildRevision)
end)

pcall(function()
	moduleLoader.clear()
end)
runtime.forceFreshModules = true

local UI_URL = runtime.uiUrl or Constants.uiUrl(runtime.cacheBust)

local function acquireLibrary()
	if type(runtime) == "table" and runtime.reloadedFromUpdate == true then
		runtime.library = nil
	end

	if type(runtime) == "table"
		and type(runtime.library) == "table"
		and not runtime.library.unloaded then
		return runtime.library
	end

	local source, fetchError = Http.fetchSource(Constants.repositoryUrls("ui.luau", runtime.cacheBust))
	assert(source, "[xanhub greenville] UI request failed: " .. tostring(fetchError))

	local chunk, compileError = Http.compileSource(source, "@xanhub/ui.luau")
	assert(chunk, "[xanhub greenville] UI compile failed: " .. tostring(compileError))

	local loaded = chunk()
	assert(type(loaded) == "table", "[xanhub greenville] UI library returned an invalid value")
	return loaded
end

local library = acquireLibrary()
runtime.library = library
runtime.uiUrl = UI_URL
runtime.repositoryRoot = REPOSITORY_ROOT
runtime.placeId = game.PlaceId
runtime.universeId = game.GameId
runtime.edition = "greenville"
env.XANHUB_RUNTIME = runtime

library:SetTitle("Tuning Garage")

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
	connections = {},
	overlays = {},
	tuning = {},
}

runtime.startedAt = tonumber(runtime.startedAt) or os.clock()
runtime.moduleStatus = type(runtime.moduleStatus) == "table" and runtime.moduleStatus or {}
runtime.repositoryRoot = REPOSITORY_ROOT
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
ctx.greenville = {
	placeId = GREENVILLE_PLACE_ID,
	universeId = GREENVILLE_UNIVERSE_ID,
	name = "Greenville",
}

local function safeLoadFeature(path)
	local factory, loadError = moduleLoader.tryLoad(path)
	if type(factory) ~= "function" then
		ctx.setModuleStatus(path, "load-error", loadError)
		warn("[xanhub greenville] failed to load " .. path .. ": " .. tostring(loadError))
		return nil
	end

	local startedAt = os.clock()
	local ok, result = xpcall(function()
		return factory(ctx)
	end, ctx.traceback)
	local record = ctx.setModuleStatus(path, ok and "loaded" or "factory-error", ok and nil or result)
	record.duration = os.clock() - startedAt
	if not ok then
		warn("[xanhub greenville] failed to initialize " .. path .. ": " .. tostring(result))
		return nil
	end
	return result
end

local uiResult = safeLoadFeature("games/greenville/modules/ui.luau")
assert(uiResult, "[xanhub greenville] UI module failed")
ctx.columns = uiResult.columns
ctx.tabs = uiResult.tabs

local tuningController = safeLoadFeature("games/greenville/modules/vehicle_tuning.luau")
assert(tuningController, "[xanhub greenville] vehicle tuning module failed")
ctx.tuningController = tuningController

assert(
	safeLoadFeature("games/greenville/modules/engine.luau"),
	"[xanhub greenville] engine controls failed"
)
assert(
	safeLoadFeature("games/greenville/modules/forced_induction.luau"),
	"[xanhub greenville] forced induction controls failed"
)
assert(
	safeLoadFeature("games/greenville/modules/modifications.luau"),
	"[xanhub greenville] modification controls failed"
)

library:AddCleanup(function()
	state.unloading = true
	runtime.unloading = true

	tuningController.cleanup()

	for flag, value in pairs(library.flags or {}) do
		if type(flag) == "string"
			and string.sub(flag, 1, 11) == "Greenville "
			and type(value) == "boolean" then
			library.flags[flag] = false
		end
	end

	connections:disconnectAll()
end)

local initialized, initError = library:Init()
assert(initialized, "[xanhub greenville] initialization failed: " .. tostring(initError))

library:SetOpen(true)
if ctx.tabs and ctx.tabs.tuning and library.selectTab then
	pcall(function()
		library:selectTab(ctx.tabs.tuning)
	end)
end

task.defer(function()
	if state.unloading then
		return
	end

	tuningController.setup()
	ctx.setModuleStatus("games/greenville/modules/vehicle_tuning.luau", "ready")
	print("[xanhub] Greenville tuning modules live for place", game.PlaceId)
end)

print("[xanhub] Greenville tuning menu ready for place", game.PlaceId, "build", runtime.buildRevision or "local")
return {
	library = library,
	runtime = runtime,
	state = state,
	context = ctx,
}
