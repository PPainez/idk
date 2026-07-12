--[[
    xanhub | shared constants

    Single source of truth for repository URLs and version metadata.
]]

local Constants = {
	REPOSITORY_ROOT = "https://raw.githubusercontent.com/PPainez/idk/main",
	BRAND = "xanhub",
	LOADER_USER_AGENT = "xanhub-loader",
	UNIVERSAL_USER_AGENT = "xanhub-universal",
	EXAMPLE_USER_AGENT = "xanhub-example",
}

function Constants.repositoryUrls(path)
	path = tostring(path):gsub("^/+", "")
	local root = Constants.REPOSITORY_ROOT
	return {
		root .. "/" .. path,
		"https://github.com/PPainez/idk/raw/refs/heads/main/" .. path,
		"https://cdn.jsdelivr.net/gh/PPainez/idk@main/" .. path,
	}
end

function Constants.uiUrl()
	return Constants.REPOSITORY_ROOT .. "/ui.luau"
end

function Constants.universalUrl()
	return Constants.REPOSITORY_ROOT .. "/universal.luau"
end

return Constants
