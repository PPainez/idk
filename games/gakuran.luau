--[[
    xanhub | Gakuran

    Featured edition for (学乱) Gakuran.
    Combat · Visuals ESP · Self · Rhythm · QOL (basketball + util + VC) · Parry Builder · DevTools
]]

local GAKURAN_PLACE_ID = 128736949265057

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
					["User-Agent"] = "xanhub-gakuran-bootstrap",
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

	assert(source, "[xanhub gakuran] bootstrap failed for " .. path .. ": " .. table.concat(errors, " | "))
	local chunk, compileError = loadstring(source)
	assert(chunk, "[xanhub gakuran] compile failed for " .. path .. ": " .. tostring(compileError))
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
		warn("[xanhub gakuran] Build metadata unavailable: " .. tostring(manifestError))
	end
end

local moduleLoader = ModuleLoader.new(Http, function(path)
	return Constants.repositoryUrls(path, runtime.cacheBust or runtime.buildRevision)
end)

-- Always clear in-process module cache so re-exec after push loads new combat/etc.
pcall(function()
	moduleLoader.clear()
end)
if type(runtime) == "table" then
	runtime.forceFreshModules = true
end

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
	assert(source, "[xanhub gakuran] UI request failed: " .. tostring(fetchError))

	local chunk, compileError = Http.compileSource(source, "@xanhub/ui.luau")
	assert(chunk, "[xanhub gakuran] UI compile failed: " .. tostring(compileError))

	local loaded = chunk()
	assert(type(loaded) == "table", "[xanhub gakuran] UI library returned an invalid value")

	runtime = type(runtime) == "table" and runtime or {}
	runtime.library = loaded
	runtime.uiUrl = UI_URL
	runtime.repositoryRoot = REPOSITORY_ROOT
	runtime.placeId = game.PlaceId
	runtime.universeId = game.GameId
	runtime.edition = "gakuran"
	env.XANHUB_RUNTIME = runtime
	return loaded
end

local library = acquireLibrary()
library:SetTitle("xanhub | Gakuran")
library:SetAccent(Color3.fromRGB(255, 168, 64))
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
	parry = {
		profiles = {},
		selected = nil,
	},
	rhythm = {},
	basketball = {},
	combat = {},
	vc = {}, -- for vc bypass state
}

runtime.startedAt = tonumber(runtime.startedAt) or os.clock()
runtime.moduleStatus = {}
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
ctx.gakuran = {
	placeId = GAKURAN_PLACE_ID,
	name = "Gakuran",
}

local function safeLoadFeature(path)
	local factory, loadError = moduleLoader.tryLoad(path)
	if type(factory) ~= "function" then
		ctx.setModuleStatus(path, "load-error", loadError)
		warn("[xanhub gakuran] failed to load " .. path .. ": " .. tostring(loadError))
		return nil
	end
	local startedAt = os.clock()
	local ok, result = xpcall(function()
		return factory(ctx)
	end, ctx.traceback)
	local record = ctx.setModuleStatus(path, ok and "loaded" or "factory-error", ok and nil or result)
	record.duration = os.clock() - startedAt
	if not ok then
		warn("[xanhub gakuran] failed to initialize " .. path .. ": " .. tostring(result))
		return nil
	end
	return result
end

local function safeSetup(name, controller)
	if not controller or type(controller.setup) ~= "function" then
		return true
	end
	local startedAt = os.clock()
	local ok, err = xpcall(controller.setup, ctx.traceback)
	local record = ctx.setModuleStatus(name, ok and "ready" or "setup-error", ok and nil or err)
	record.setupDuration = os.clock() - startedAt
	if not ok then
		warn("[xanhub gakuran] " .. tostring(name) .. " setup failed: " .. tostring(err))
	end
	return ok
end

local uiResult = safeLoadFeature("games/gakuran/modules/ui.luau")
assert(uiResult, "[xanhub gakuran] UI module failed")
ctx.columns = uiResult.columns
ctx.tabs = uiResult.tabs

-- Load VC Bypass — store on ctx so qol.luau buttons reach it at click time
local vcController = safeLoadFeature("games/gakuran/modules/vc_bypass.luau")
ctx.vcController = vcController

local devtoolsController = safeLoadFeature("universal/modules/devtools.luau")
local parryBuilder = safeLoadFeature("games/gakuran/modules/parry_builder.luau")

local featureSetups = {}
local featureNames = {}
for _, modulePath in ipairs({
	"games/gakuran/modules/combat.luau",
	"games/gakuran/modules/visuals.luau",
	"games/gakuran/modules/self_exploits.luau",
	"games/gakuran/modules/rhythm.luau",
	"games/gakuran/modules/qol.luau",
	"games/gakuran/modules/basketball.luau",
	"games/gakuran/modules/death_skip.luau",
}) do
	local feature = safeLoadFeature(modulePath)
	if feature and type(feature.setup) == "function" then
		table.insert(featureSetups, feature.setup)
		table.insert(featureNames, modulePath:match("([^/]+)%.luau$") or modulePath)
	end
end

local initialized, initError = library:Init()
assert(initialized, "[xanhub gakuran] initialization failed: " .. tostring(initError))

-- Show menu immediately so the multi-game loader can close without waiting on feature wiring.
pcall(function()
	ctx.createOverlayRoot()
end)
library:SetOpen(true)
if ctx.tabs and ctx.tabs.home and library.selectTab then
	pcall(function()
		library:selectTab(ctx.tabs.home)
	end)
end

local detected = game.PlaceId == GAKURAN_PLACE_ID
if ctx.refs.runtimeStatus then
	ctx.refs.runtimeStatus.Text = detected
		and ("Status: ready · wiring " .. #featureNames .. " features…")
		or "Status: wrong place — some features may misbehave"
end
if ctx.refs.featureStatus then
	ctx.refs.featureStatus.Text = "Loaded: " .. table.concat(featureNames, ", ")
end

library:AddCleanup(function()
	state.unloading = true

	if type(runtime) == "table" then
		runtime.unloading = true
	end

	for flag, value in pairs(library.flags or {}) do
		if type(flag) == "string"
			and string.sub(flag, 1, 8) == "Gakuran "
			and type(value) == "boolean" then
			library.flags[flag] = false
		end
	end

	connections:disconnectAll()

	if state.overlays.root then
		pcall(function()
			state.overlays.root:Destroy()
		end)
		state.overlays.root = nil
	end
end)

-- Wire features after return so loader.luau is not stuck on "Starting Gakuran…".
task.defer(function()
	if state.unloading then
		return
	end

	for index, setup in ipairs(featureSetups) do
		if state.unloading then
			return
		end
		local featureName = tostring(featureNames[index])
		local startedAt = os.clock()
		local ok, err = xpcall(setup, ctx.traceback)
		local record = ctx.setModuleStatus("games/gakuran/modules/" .. featureName .. ".luau", ok and "ready" or "setup-error", ok and nil or err)
		record.setupDuration = os.clock() - startedAt
		if not ok then
			warn("[xanhub gakuran] feature setup failed (" .. featureName .. "): " .. tostring(err))
		end
	end

	safeSetup("devtools", devtoolsController)
	safeSetup("parry_builder", parryBuilder)
	-- vc_bypass has no setup() — it's fully wired at load time via ctx.addConnection

	if state.unloading then
		return
	end

	if ctx.refs.runtimeStatus then
		ctx.refs.runtimeStatus.Text = detected
			and ("Status: ready · " .. #featureNames .. " features live")
			or "Status: wrong place — some features may misbehave"
	end

	-- Re-apply place autoload after feature setups (toggles exist + runtimes wired)
	pcall(function()
		if library.TryAutoloadConfig then
			library:TryAutoloadConfig()
		end
	end)

	pcall(function()
		ctx.notify(detected and "xanhub Gakuran ready" or "xanhub Gakuran loaded (place mismatch)", 3)
	end)
	print("[xanhub] Gakuran features live for place", game.PlaceId, table.concat(featureNames, ", "))
end)

print("[xanhub] Gakuran menu ready for place", game.PlaceId, "build", runtime.buildRevision or "local")
return {
	library = library,
	runtime = runtime,
	state = state,
	context = ctx,
}