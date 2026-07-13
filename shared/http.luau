--[[
    xanhub | shared HTTP

    Executor-compatible source fetching used by loader, universal, game editions,
    update checks, and examples.
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
	if type(fluxus) == "table" and type(fluxus.request) == "function" then
		return fluxus.request, "fluxus.request"
	end
	return nil, "game:HttpGet"
end

function Http.cleanBody(body)
	if type(body) ~= "string" then
		return body
	end
	return body:gsub("^\239\187\191", "")
end

function Http.validLuaBody(body)
	body = Http.cleanBody(body)
	if type(body) ~= "string" or #body < 20 then
		return false
	end

	local prefix = string.lower(string.sub(body:match("^%s*(.*)") or body, 1, 256))
	if prefix == "404: not found"
		or string.match(prefix, "^404[:%s]")
		or string.match(prefix, "^<!doctype%s+html")
		or string.match(prefix, "^<html")
		or string.match(prefix, "^repository%s+not%s+found")
		or string.match(prefix, "^bad%s+gateway")
		or string.match(prefix, "^service%s+unavailable") then
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

function Http.summarizeBody(body, maximum)
	maximum = math.clamp(tonumber(maximum) or 180, 40, 1000)
	if type(body) ~= "string" then
		return tostring(body or "empty response")
	end

	local compact = body:gsub("%s+", " ")
	if #compact > maximum then
		compact = string.sub(compact, 1, maximum) .. "..."
	end
	return compact
end

local function responseBody(response)
	if type(response) ~= "table" then
		return response
	end
	return response.Body or response.body or response.ResponseBody or response.responseBody
end

local function responseStatus(response)
	if type(response) ~= "table" then
		return nil
	end
	return tonumber(response.StatusCode or response.Status or response.status_code or response.statusCode)
end

function Http.requestOne(url)
	local requestFunction, requestName = Http.getRequestFunction()
	local errors = {}

	if requestFunction then
		local ok, response = pcall(requestFunction, {
			Url = url,
			Method = "GET",
			Headers = {
				["Accept"] = "text/plain, application/octet-stream;q=0.9, */*;q=0.1",
				["Cache-Control"] = "no-cache, no-store, max-age=0",
				["Pragma"] = "no-cache",
				["User-Agent"] = Http.userAgent,
			},
		})

		if ok then
			local body = Http.cleanBody(responseBody(response))
			local status = responseStatus(response)
			local successField = type(response) == "table" and response.Success
			local statusOkay = not status or (status >= 200 and status < 300)
			local successOkay = successField == nil or successField == true

			if statusOkay and successOkay and Http.validLuaBody(body) then
				return body, nil, {
					provider = requestName,
					status = status,
					url = url,
				}
			end

			table.insert(errors, string.format(
				"%s status=%s body=%s",
				requestName,
				tostring(status or "unknown"),
				Http.summarizeBody(body or (type(response) == "table" and (response.Message or response.StatusMessage)))
			))
		else
			table.insert(errors, requestName .. " -> " .. Http.summarizeBody(response))
		end
	end

	local okNoCache, noCacheResult = pcall(function()
		return game:HttpGet(url, false)
	end)
	noCacheResult = Http.cleanBody(noCacheResult)
	if okNoCache and Http.validLuaBody(noCacheResult) then
		return noCacheResult, nil, {
			provider = "game:HttpGet(false)",
			url = url,
		}
	end
	table.insert(errors, "HttpGet(false) -> " .. Http.summarizeBody(noCacheResult))

	local okDefault, defaultResult = pcall(function()
		return game:HttpGet(url)
	end)
	defaultResult = Http.cleanBody(defaultResult)
	if okDefault and Http.validLuaBody(defaultResult) then
		return defaultResult, nil, {
			provider = "game:HttpGet",
			url = url,
		}
	end
	table.insert(errors, "HttpGet(default) -> " .. Http.summarizeBody(defaultResult))

	return nil, table.concat(errors, " | ")
end

function Http.fetchSource(urlOrUrls, attempts)
	attempts = math.clamp(tonumber(attempts) or 2, 1, 5)

	local urls = type(urlOrUrls) == "table" and urlOrUrls or { urlOrUrls }
	local errors = {}

	for _, url in ipairs(urls) do
		for attempt = 1, attempts do
			local body, requestError, metadata = Http.requestOne(url)
			if body then
				return body, nil, url, metadata
			end

			table.insert(errors, string.format(
				"%s -> %s",
				tostring(url),
				tostring(requestError or "request failed")
			))

			if attempt < attempts then
				task.wait(0.2 * attempt)
			end
		end
	end

	return nil, table.concat(errors, " | ")
end

function Http.rollingHash(value)
	value = tostring(value or "")
	local hash = 5381
	for index = 1, #value do
		hash = (hash * 33 + string.byte(value, index)) % 4294967296
	end
	return string.format("%08x-%d", hash, #value)
end

function Http.compileSource(source, chunkName)
	local ok, chunk, compileError = pcall(loadstring, source, chunkName)
	if not ok then
		chunk, compileError = loadstring(source)
	end
	if not chunk then
		return nil, tostring(compileError)
	end
	return chunk
end

function Http.executeSource(source, chunkName, ...)
	local chunk, compileError = Http.compileSource(source, chunkName)
	if not chunk then
		return nil, compileError
	end

	local arguments = table.pack(...)
	local ok, result = pcall(function()
		return chunk(table.unpack(arguments, 1, arguments.n))
	end)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

function Http.loadModule(urlOrUrls, markers, chunkName)
	local startedAt = os.clock()
	local source, fetchError, providerUrl, requestMetadata = Http.fetchSource(urlOrUrls)
	if not source then
		return nil, fetchError
	end

	if markers and not Http.validSource(source, markers) then
		return nil, "source validation failed"
	end

	local chunk, compileError = Http.compileSource(source, chunkName)
	if not chunk then
		return nil, compileError
	end

	local ok, result = pcall(chunk)
	if not ok then
		return nil, tostring(result)
	end

	return result, nil, {
		url = providerUrl,
		provider = requestMetadata and requestMetadata.provider,
		status = requestMetadata and requestMetadata.status,
		bytes = #source,
		hash = Http.rollingHash(source),
		duration = os.clock() - startedAt,
	}
end

function Http.fetchLuaTable(urlOrUrls, markers, chunkName)
	local result, loadError, metadata = Http.loadModule(urlOrUrls, markers, chunkName)
	if type(result) ~= "table" then
		return nil, loadError or "source did not return a table", metadata
	end
	return result, nil, metadata
end

return Http
