--[[
    xanhub | devmodules | initializer

    Standalone initializer for hosts that do not use universal/modules/devtools.
    Call before library:Init(), then call module.setup() after initialization.
]]

return function(ctx)
	assert(type(ctx) == "table", "[xanhub dev] missing ctx")

	local runtime = ctx.runtime or ((type(getgenv) == "function" and getgenv()) or _G).XANHUB_RUNTIME or {}
	local root = runtime.repositoryRoot or "https://raw.githubusercontent.com/PPainez/idk/main"
	local devRoot = tostring(root):gsub("/+$", "") .. "/devmodules"
	local Http = ctx.shared and ctx.shared.Http
	local Constants = ctx.shared and ctx.shared.Constants

	local function fetch(urlOrUrls)
		if Http and type(Http.fetchSource) == "function" then
			local body, fetchError = Http.fetchSource(urlOrUrls)
			if body then
				return body
			end
			error(fetchError or "fetch failed")
		end
		if type(ctx.fetchSource) == "function" then
			local body, fetchError = ctx.fetchSource(urlOrUrls)
			if body then
				return body
			end
			error(fetchError or "fetch failed")
		end

		local urls = type(urlOrUrls) == "table" and urlOrUrls or { urlOrUrls }
		local requestFunction = type(request) == "function" and request
			or type(http_request) == "function" and http_request
			or type(httprequest) == "function" and httprequest
			or type(syn) == "table" and type(syn.request) == "function" and syn.request
			or nil
		local errors = {}

		for _, url in ipairs(urls) do
			if requestFunction then
				local ok, response = pcall(requestFunction, {
					Url = url,
					Method = "GET",
					Headers = { ["Cache-Control"] = "no-cache, no-store, max-age=0" },
				})
				if ok then
					local status = type(response) == "table" and tonumber(response.StatusCode or response.Status) or nil
					local body = type(response) == "table" and (response.Body or response.body) or response
					if type(body) == "string" and #body > 20 and (not status or (status >= 200 and status < 300)) then
						return body
					end
					table.insert(errors, tostring(status or body))
				end
			end
			local ok, body = pcall(function()
				return game:HttpGet(url, false)
			end)
			if ok and type(body) == "string" and #body > 20 then
				return body
			end
			table.insert(errors, tostring(body))
		end
		error(table.concat(errors, " | "))
	end

	local function urlsFor(name)
		local path = "devmodules/" .. tostring(name)
		if Constants and type(Constants.repositoryUrls) == "function" then
			return Constants.repositoryUrls(path, runtime.cacheBust or runtime.buildRevision)
		end
		return { devRoot .. "/" .. tostring(name) }
	end

	local function execute(name)
		if ctx.moduleLoader and type(ctx.moduleLoader.tryLoad) == "function" then
			local result, loadError = ctx.moduleLoader.tryLoad("devmodules/" .. name)
			assert(result ~= nil, "[xanhub dev] " .. name .. " failed: " .. tostring(loadError))
			return result
		end
		local source = fetch(urlsFor(name))
		local chunk, compileError = loadstring(source)
		assert(chunk, "[xanhub dev] " .. name .. " compile failed: " .. tostring(compileError))
		return chunk()
	end

	local manifest = execute("manifest.luau")
	local names = type(manifest) == "table" and type(manifest.modules) == "table"
		and manifest.modules
		or {
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

	local loaded = {}
	local setupState = setmetatable({}, { __mode = "k" })
	for _, name in ipairs(names) do
		local factory = execute(name)
		assert(type(factory) == "function", "[xanhub dev] " .. name .. " did not return a factory")
		local module = factory(ctx)
		if name ~= "dev_shared.luau" and type(module) == "table" then
			local originalSetup = module.setup
			if type(originalSetup) == "function" then
				module.setup = function()
					if setupState[module] then
						return
					end
					setupState[module] = true
					return originalSetup()
				end
			end
			table.insert(loaded, module)
		end
	end

	return loaded, manifest
end
