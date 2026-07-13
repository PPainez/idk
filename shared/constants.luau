--[[
    xanhub | shared constants

    Single source of truth for repository URLs and version metadata.
]]

local Constants = {
	REPOSITORY_ROOT = "https://raw.githubusercontent.com/PPainez/idk/main",
	BRAND = "xanhub",
	-- Bump when you need executors / CDNs to drop stale module bodies.
	MODULE_CACHE_BUST = "20260712d",
	LOADER_USER_AGENT = "xanhub-loader",
	UNIVERSAL_USER_AGENT = "xanhub-universal",
	EXAMPLE_USER_AGENT = "xanhub-example",
}

function Constants.repositoryUrls(path)
	path = tostring(path):gsub("^/+", "")
	local root = Constants.REPOSITORY_ROOT
	local bust = tostring(Constants.MODULE_CACHE_BUST or "1")
	local q = "?xanhub=" .. bust
	return {
		root .. "/" .. path .. q,
		"https://github.com/PPainez/idk/raw/refs/heads/main/" .. path .. q,
		-- jsdelivr pins @main; query still helps some proxy layers
		"https://cdn.jsdelivr.net/gh/PPainez/idk@main/" .. path .. q,
	}
end

function Constants.uiUrl()
	return Constants.REPOSITORY_ROOT .. "/ui.luau?xanhub=" .. tostring(Constants.MODULE_CACHE_BUST or "1")
end

function Constants.universalUrl()
	return Constants.REPOSITORY_ROOT .. "/universal.luau?xanhub=" .. tostring(Constants.MODULE_CACHE_BUST or "1")
end

return Constants
