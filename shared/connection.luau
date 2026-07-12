--[[
    xanhub | shared connection manager

    Prefer library:AddConnection(signal, callback) which owns Connect + cleanup.
    Falls back to raw Connect + local list when the library is unavailable.
]]

local Connection = {}

function Connection.new(library, fallbackList)
	local pool = {
		library = library,
		fallback = fallbackList,
	}

	function pool:connect(signal, callback)
		-- Already-connected RBXScriptConnection: track only, do not Connect again.
		if typeof(signal) == "RBXScriptConnection" then
			if type(self.fallback) == "table" then
				table.insert(self.fallback, signal)
			end
			return signal
		end

		if type(callback) ~= "function" then
			return nil
		end

		if self.library
			and type(self.library.AddConnection) == "function"
			and not self.library.unloaded then
			local connection = self.library:AddConnection(signal, callback)
			if connection then
				return connection
			end
		end

		local ok, connection = pcall(function()
			return signal:Connect(callback)
		end)
		if not ok or not connection then
			return nil
		end

		if type(self.fallback) == "table" then
			table.insert(self.fallback, connection)
		end

		return connection
	end

	function pool:disconnect(connection)
		if connection then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end

	function pool:disconnectAll()
		if type(self.fallback) ~= "table" then
			return
		end

		for index, connection in ipairs(self.fallback) do
			self:disconnect(connection)
			self.fallback[index] = nil
		end
	end

	return pool
end

return Connection
