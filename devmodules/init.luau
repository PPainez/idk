--[[
    xanhub | devmodules | initializer

    Loads the Developer tab and all bundled dev modules from /devmodules.
    Call BEFORE library:Init(), then call each returned module.setup AFTER Init().
]]

return function(ctx)
    assert(type(ctx) == "table", "[xanhub dev] missing ctx")

    local runtime = ctx.runtime or ((type(getgenv) == "function" and getgenv()) or _G).XANHUB_RUNTIME
    local root = type(runtime) == "table" and runtime.repositoryRoot
        or "https://raw.githubusercontent.com/PPainez/idk/main"
    local devRoot = tostring(root):gsub("/+$", "") .. "/devmodules"

    local moduleNames = {
        "dev_shared.luau",
        "notification_center.luau",
        "animation_viewer.luau",
        "animation_logger.luau",
        "remote_spy.luau",
        "console_logger.luau",
        "performance_profiler.luau",
        "instance_inspector.luau",
    }

    local function fetch(url)
        if type(ctx.fetchSource) == "function" then
            local body, err = ctx.fetchSource(url)
            if body then
                return body
            end
            error(err or "fetch failed")
        end

        local requestFunction = type(request) == "function" and request
            or type(http_request) == "function" and http_request
            or type(httprequest) == "function" and httprequest
            or type(syn) == "table" and type(syn.request) == "function" and syn.request
            or nil

        if requestFunction then
            local response = requestFunction({
                Url = url,
                Method = "GET",
                Headers = { ["Cache-Control"] = "no-cache" },
            })
            if type(response) == "table" then
                local status = tonumber(response.StatusCode or response.Status)
                local body = response.Body or response.body
                assert(not status or (status >= 200 and status < 300), "HTTP " .. tostring(status))
                assert(type(body) == "string", "empty response")
                return body
            elseif type(response) == "string" then
                return response
            end
        end
        return game:HttpGet(url, false)
    end

    local loaded = {}
    for _, name in ipairs(moduleNames) do
        local url = devRoot .. "/" .. name
        local source = fetch(url)
        local chunk, compileError = loadstring(source)
        assert(chunk, "[xanhub dev] " .. name .. " compile failed: " .. tostring(compileError))
        local factory = chunk()
        assert(type(factory) == "function", "[xanhub dev] " .. name .. " did not return a factory")
        local module = factory(ctx)
        if name ~= "dev_shared.luau" and type(module) == "table" then
            table.insert(loaded, module)
        end
    end

    return loaded
end
