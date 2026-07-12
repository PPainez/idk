--[[
    xanhub | shared module loader

    Fetches and caches Luau modules from the repository.
]]

local ModuleLoader = {}

function ModuleLoader.new(http, repositoryUrls)
	local cache = {}

	local function load(path, markers)
		if cache[path] then
			return cache[path]
		end

		local module, loadError = http.loadModule(repositoryUrls(path), markers)
		assert(module, "[xanhub] failed to load " .. tostring(path) .. ": " .. tostring(loadError))

		cache[path] = module
		return module
	end

	return {
		load = load,
		clear = function()
			table.clear(cache)
		end,
	}
end

return ModuleLoader
