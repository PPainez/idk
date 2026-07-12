--[[
    xanhub | Gakuran

    Featured edition for (学乱) Gakuran.
    Combat · Visuals ESP · Rhythm · Basketball · Parry Builder · DevTools
]]

local GAKURAN_PLACE_ID = 128736949265057

local runtime = ...
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(runtime) ~= "table" then
	runtime = env.XANHUB_RUNTIME
end

local REPOSITORY_ROOT = (type(runtime) == "table" and runtime.repositoryRoot)
	or "https://raw.githubusercontent.com/PPainez/idk/main"

local function bootstrapModule(path)
	local source, loadError

	local ok, result = pcall(function()
		return game:HttpGet(REPOSITORY_ROOT .. "/" .. path, true)
	end)

	if ok and type(result) == "string" and #result > 20 then
		source = result
	else
		loadError = tostring(result or "request failed")
	end

	assert(source, "[xanhub gakuran] bootstrap failed for " .. path .. ": " .. tostring(loadError))

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

local moduleLoader = ModuleLoader.new(Http, function(path)
	return Constants.repositoryUrls(path)
end)

if type(runtime) == "table" and runtime.forceFreshModules == true then
	moduleLoader.clear()
end

local UI_URL = (type(runtime) == "table" and runtime.uiUrl) or Constants.uiUrl()

local function acquireLibrary()
	if type(runtime) == "table" and runtime.reloadedFromUpdate == true then
		runtime.library = nil
	end

	if type(runtime) == "table"
		and type(runtime.library) == "table"
		and not runtime.library.unloaded then
		return runtime.library
	end

	local source, fetchError = Http.fetchSource(UI_URL)
	assert(source, "[xanhub gakuran] UI request failed: " .. tostring(fetchError))

	local chunk, compileError = Http.compileSource(source)
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
library:SetTweening(false)

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
}

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
ctx.moduleLoader = moduleLoader
ctx.gakuran = {
	placeId = GAKURAN_PLACE_ID,
	name = "Gakuran",
}

local function safeLoadFeature(path)
	local ok, result = pcall(function()
		return moduleLoader.load(path)(ctx)
	end)
	if not ok then
		warn("[xanhub gakuran] failed to load " .. path .. ": " .. tostring(result))
		return nil
	end
	return result
end

local function safeSetup(name, controller)
	if not controller or type(controller.setup) ~= "function" then
		return
	end
	local ok, err = pcall(controller.setup)
	if not ok then
		warn("[xanhub gakuran] " .. tostring(name) .. " setup failed: " .. tostring(err))
	end
end

local uiResult = safeLoadFeature("games/gakuran/modules/ui.luau")
assert(uiResult, "[xanhub gakuran] UI module failed")
ctx.columns = uiResult.columns
ctx.tabs = uiResult.tabs

local devtoolsController = safeLoadFeature("universal/modules/devtools.luau")
local parryBuilder = safeLoadFeature("games/gakuran/modules/parry_builder.luau")

local featureSetups = {}
local featureNames = {}
for _, modulePath in ipairs({
	"games/gakuran/modules/combat.luau",
	"games/gakuran/modules/visuals.luau",
	"games/gakuran/modules/rhythm.luau",
	"games/gakuran/modules/basketball.luau",
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
		local ok, err = pcall(setup)
		if not ok then
			warn("[xanhub gakuran] feature setup failed (" .. tostring(featureNames[index]) .. "): " .. tostring(err))
		end
	end

	safeSetup("devtools", devtoolsController)
	safeSetup("parry_builder", parryBuilder)

	if state.unloading then
		return
	end

	if ctx.refs.runtimeStatus then
		ctx.refs.runtimeStatus.Text = detected
			and ("Status: ready · " .. #featureNames .. " features live")
			or "Status: wrong place — some features may misbehave"
	end

	pcall(function()
		ctx.notify(detected and "xanhub Gakuran ready" or "xanhub Gakuran loaded (place mismatch)", 3)
	end)
	print("[xanhub] Gakuran features live for place", game.PlaceId, table.concat(featureNames, ", "))
end)

print("[xanhub] Gakuran menu ready for place", game.PlaceId)
return {
	library = library,
	runtime = runtime,
	state = state,
}
