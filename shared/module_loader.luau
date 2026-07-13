--[[
    xanhub | shared module loader

    Fetches, validates, caches, and records diagnostics for repository modules.
]]

local ModuleLoader = {}

function ModuleLoader.new(http, repositoryUrls)
	local cache = {}
	local loading = {}
	local records = {}
	local generation = 1

	local function recordFor(path)
		local record = records[path]
		if not record then
			record = {
				path = path,
				loads = 0,
				cacheHits = 0,
				status = "idle",
				generation = generation,
			}
			records[path] = record
		end
		return record
	end

	local function tryLoad(path, markers)
		path = tostring(path)
		local record = recordFor(path)

		if cache[path] ~= nil then
			record.cacheHits = record.cacheHits + 1
			record.status = "cached"
			return cache[path]
		end

		if loading[path] then
			local message = "recursive module load detected: " .. path
			record.status = "error"
			record.error = message
			return nil, message
		end

		loading[path] = true
		record.loads = record.loads + 1
		record.status = "loading"
		record.startedAt = os.clock()
		record.error = nil
		record.generation = generation

		local module, loadError, metadata = http.loadModule(repositoryUrls(path), markers, "@xanhub/" .. path)
		loading[path] = nil

		record.duration = os.clock() - record.startedAt
		record.finishedAt = os.clock()
		if type(metadata) == "table" then
			for key, value in pairs(metadata) do
				record[key] = value
			end
		end

		if module == nil then
			record.status = "error"
			record.error = tostring(loadError or "module returned nil")
			return nil, record.error
		end

		cache[path] = module
		record.status = "loaded"
		return module
	end

	local function load(path, markers)
		local module, loadError = tryLoad(path, markers)
		assert(module ~= nil, "[xanhub] failed to load " .. tostring(path) .. ": " .. tostring(loadError))
		return module
	end

	local function invalidate(path)
		path = tostring(path)
		cache[path] = nil
		local record = recordFor(path)
		record.status = "invalidated"
		record.generation = generation
	end

	local function clear(clearRecords)
		table.clear(cache)
		table.clear(loading)
		generation = generation + 1
		if clearRecords == true then
			table.clear(records)
		else
			for _, record in pairs(records) do
				record.status = "invalidated"
				record.generation = generation
			end
		end
	end

	local function getStats()
		local output = {}
		for path, record in pairs(records) do
			local copy = {}
			for key, value in pairs(record) do
				copy[key] = value
			end
			output[path] = copy
		end
		return output
	end

	return {
		load = load,
		tryLoad = tryLoad,
		invalidate = invalidate,
		clear = clear,
		getStats = getStats,
		getGeneration = function()
			return generation
		end,
	}
end

return ModuleLoader
