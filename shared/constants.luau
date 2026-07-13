--[[
    xanhub | shared constants

    Single source of truth for repository URLs, cache busting, and build metadata.
]]

local Constants = {
	REPOSITORY_ROOT = "https://raw.githubusercontent.com/PPainez/idk/main",
	BRAND = "xanhub",
	BUILD_CHANNEL = "main",
	BUILD_MANIFEST_PATH = "build.luau",

	-- Fallback used before build.luau has been read. Normal module requests use
	-- runtime.buildRevision once the loader has resolved the current build.
	MODULE_CACHE_BUST = "20260713a",

	LOADER_VERSION = "1.3.0",
	LOADER_USER_AGENT = "xanhub-loader/1.3",
	UNIVERSAL_USER_AGENT = "xanhub-universal/1.3",
	EXAMPLE_USER_AGENT = "xanhub-example/1.3",
}

local function runtimeTable()
	local env = (type(getgenv) == "function" and getgenv()) or _G
	return type(env.XANHUB_RUNTIME) == "table" and env.XANHUB_RUNTIME or nil
end

local function sanitizeQueryValue(value)
	value = tostring(value or "")
	value = value:gsub("[^%w%-%._]", "-")
	if value == "" then
		value = "1"
	end
	return value
end

function Constants.cacheBust(explicit)
	if explicit ~= nil then
		return sanitizeQueryValue(explicit)
	end

	local runtime = runtimeTable()
	if runtime then
		local value = runtime.cacheBust or runtime.buildRevision
		if value ~= nil and tostring(value) ~= "" then
			return sanitizeQueryValue(value)
		end
	end

	return sanitizeQueryValue(Constants.MODULE_CACHE_BUST)
end

function Constants.repositoryUrls(path, cacheBust)
	path = tostring(path):gsub("^/+", "")
	local root = Constants.REPOSITORY_ROOT:gsub("/+$", "")
	local query = "?xanhub=" .. Constants.cacheBust(cacheBust)

	return {
		root .. "/" .. path .. query,
		"https://github.com/PPainez/idk/raw/refs/heads/main/" .. path .. query,
		"https://cdn.jsdelivr.net/gh/PPainez/idk@main/" .. path .. query,
	}
end

function Constants.freshRepositoryUrls(path)
	-- A short time bucket avoids permanently cached update metadata while still
	-- allowing repeated checks in the same minute to share a response.
	local bucket = math.floor((os.time and os.time() or 0) / 60)
	return Constants.repositoryUrls(path, "check-" .. tostring(bucket))
end

function Constants.uiUrl(cacheBust)
	return Constants.repositoryUrls("ui.luau", cacheBust)[1]
end

function Constants.universalUrl(cacheBust)
	return Constants.repositoryUrls("universal.luau", cacheBust)[1]
end

function Constants.buildManifestUrls(fresh)
	if fresh then
		return Constants.freshRepositoryUrls(Constants.BUILD_MANIFEST_PATH)
	end
	return Constants.repositoryUrls(Constants.BUILD_MANIFEST_PATH)
end

return Constants
