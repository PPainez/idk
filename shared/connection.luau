--[[
    xanhub | shared connection manager

    Routes signal connections through library:AddConnection when available.
]]

local Connection = {}

function Connection.new(library, fallbackList)
	local pool = {
		library = library,
		fallback = fallbackList,
	}

	function pool:connect(signal, callback)
		local connection = signal:Connect(callback)

		if self.library
			and type(self.library.AddConnection) == "function"
			and not self.library.unloaded then
			self.library:AddConnection(connection)
		elseif type(self.fallback) == "table" then
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
