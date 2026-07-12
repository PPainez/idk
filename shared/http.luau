--[[
    xanhub | shared HTTP

    Executor-compatible source fetching used by loader, universal, and examples.
]]

local Http = {
	userAgent = "xanhub",
}

function Http.setUserAgent(agent)
	if type(agent) == "string" and agent ~= "" then
		Http.userAgent = agent
	end
end

function Http.getRequestFunction()
	if type(request) == "function" then
		return request, "request"
	end
	if type(http_request) == "function" then
		return http_request, "http_request"
	end
	if type(httprequest) == "function" then
		return httprequest, "httprequest"
	end
	if type(syn) == "table" and type(syn.request) == "function" then
		return syn.request, "syn.request"
	end
	if type(http) == "table" and type(http.request) == "function" then
		return http.request, "http.request"
	end
	return nil, "game:HttpGet"
end

function Http.validLuaBody(body)
	if type(body) ~= "string" or #body < 20 then
		return false
	end

	local cleaned = body:gsub("^\239\187\191", "")
	local prefix = string.lower(string.sub(cleaned:match("^%s*(.*)") or cleaned, 1, 256))

	if prefix == "404: not found"
		or string.match(prefix, "^404[:%s]")
		or string.match(prefix, "^<!doctype%s+html")
		or string.match(prefix, "^<html")
		or string.match(prefix, "^repository%s+not%s+found") then
		return false
	end

	return true
end

function Http.validSource(body, markers)
	if not Http.validLuaBody(body) then
		return false
	end

	if type(markers) ~= "table" or #markers == 0 then
		return true
	end

	for _, marker in ipairs(markers) do
		if type(marker) == "string" and string.find(body, marker, 1, true) then
			return true
		end
	end

	return false
end

function Http.summarizeBody(body)
	if type(body) ~= "string" then
		return tostring(body or "empty response")
	end

	local compact = body:gsub("%s+", " ")
	if #compact > 180 then
		compact = string.sub(compact, 1, 180) .. "..."
	end
	return compact
end

function Http.requestOne(url)
	local requestFunction, requestName = Http.getRequestFunction()
	local errors = {}

	if requestFunction then
		local ok, response = pcall(requestFunction, {
			Url = url,
			Method = "GET",
			Headers = {
				["Accept"] = "text/plain",
				["Cache-Control"] = "no-cache, no-store, max-age=0",
				["Pragma"] = "no-cache",
				["User-Agent"] = Http.userAgent,
			},
		})

		if ok and type(response) == "table" then
			local body = response.Body or response.body or response.ResponseBody
			local status = tonumber(response.StatusCode or response.Status or response.status_code)

			if Http.validLuaBody(body) and (not status or (status >= 200 and status < 300)) then
				return body
			end

			table.insert(errors, string.format(
				"%s status=%s body=%s",
				requestName,
				tostring(status or "unknown"),
				Http.summarizeBody(body or response.Message)
			))
		elseif ok and Http.validLuaBody(response) then
			return response
		else
			table.insert(errors, requestName .. " -> " .. tostring(response))
		end
	end

	local okNoCache, noCacheResult = pcall(function()
		return game:HttpGet(url, false)
	end)
	if okNoCache and Http.validLuaBody(noCacheResult) then
		return noCacheResult
	end
	table.insert(errors, "HttpGet(false) -> " .. tostring(noCacheResult))

	local okDefault, defaultResult = pcall(function()
		return game:HttpGet(url)
	end)
	if okDefault and Http.validLuaBody(defaultResult) then
		return defaultResult
	end
	table.insert(errors, "HttpGet(default) -> " .. tostring(defaultResult))

	return nil, table.concat(errors, " | ")
end

function Http.fetchSource(urlOrUrls, attempts)
	attempts = attempts or 2

	local urls = type(urlOrUrls) == "table" and urlOrUrls or { urlOrUrls }
	local errors = {}

	for _, url in ipairs(urls) do
		for attempt = 1, attempts do
			local body, requestError = Http.requestOne(url)
			if body then
				return body, nil, url
			end

			table.insert(errors, string.format(
				"%s -> %s",
				tostring(url),
				tostring(requestError or "request failed")
			))

			task.wait(0.25 * attempt)
		end
	end

	return nil, table.concat(errors, " | ")
end

function Http.rollingHash(value)
	local hash = 5381
	for index = 1, #value do
		hash = (hash * 33 + string.byte(value, index)) % 4294967296
	end
	return string.format("%08x-%d", hash, #value)
end

function Http.compileSource(source)
	local chunk, compileError = loadstring(source)
	if not chunk then
		return nil, tostring(compileError)
	end
	return chunk
end

function Http.loadModule(urlOrUrls, markers)
	local source, fetchError = Http.fetchSource(urlOrUrls)
	if not source then
		return nil, fetchError
	end

	if markers and not Http.validSource(source, markers) then
		return nil, "source validation failed"
	end

	local chunk, compileError = Http.compileSource(source)
	if not chunk then
		return nil, compileError
	end

	local ok, result = pcall(chunk)
	if not ok then
		return nil, tostring(result)
	end

	return result
end

return Http
