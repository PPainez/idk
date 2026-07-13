--[[
    xanhub | universal | context

    Shared runtime state, services, and helpers for feature modules.
]]

local function createContext(deps)
	local library = deps.library
	local runtime = deps.runtime
	local state = deps.state
	local env = deps.env
	local connections = deps.connections

	local Players = deps.services.Players
	local RunService = deps.services.RunService
	local UserInputService = deps.services.UserInputService
	local Lighting = deps.services.Lighting
	local TweenService = deps.services.TweenService
	local TeleportService = deps.services.TeleportService
	local VirtualUser = deps.services.VirtualUser
	local StarterGui = deps.services.StarterGui
	local Workspace = deps.services.Workspace
	local LocalPlayer = Players.LocalPlayer

	local ctx = {
		library = library,
		runtime = runtime,
		state = state,
		env = env,
		columns = deps.columns,
		tabs = deps.tabs,
		refs = deps.refs or {},
		services = deps.services,
		Players = Players,
		RunService = RunService,
		UserInputService = UserInputService,
		Lighting = Lighting,
		TweenService = TweenService,
		TeleportService = TeleportService,
		VirtualUser = VirtualUser,
		StarterGui = StarterGui,
		Workspace = Workspace,
		LocalPlayer = LocalPlayer,
	}


	function ctx.traceback(err)
		local message = tostring(err)
		if type(debug) == "table" and type(debug.traceback) == "function" then
			local ok, result = pcall(debug.traceback, message, 2)
			if ok and type(result) == "string" then
				return result
			end
		end
		return message
	end

	function ctx.safeCall(label, callback, ...)
		if type(callback) ~= "function" then
			return false, "callback is not a function"
		end
		local arguments = table.pack(...)
		local ok, result = xpcall(function()
			return callback(table.unpack(arguments, 1, arguments.n))
		end, ctx.traceback)
		if not ok then
			warn("[xanhub " .. tostring(label or "callback") .. "] " .. tostring(result))
		end
		return ok, result
	end

	function ctx.setModuleStatus(path, status, detail)
		runtime = type(runtime) == "table" and runtime or {}
		runtime.moduleStatus = type(runtime.moduleStatus) == "table" and runtime.moduleStatus or {}
		local record = runtime.moduleStatus[tostring(path)] or {}
		record.status = tostring(status or "unknown")
		record.detail = detail and tostring(detail) or nil
		record.updatedAt = os.clock()
		runtime.moduleStatus[tostring(path)] = record
		return record
	end

	function ctx.getModuleStatus()
		return type(runtime) == "table" and runtime.moduleStatus or {}
	end

	function ctx.getUptime()
		local startedAt = type(runtime) == "table" and tonumber(runtime.startedAt) or nil
		return startedAt and math.max(0, os.clock() - startedAt) or 0
	end

	function ctx.notify(message, duration)
		-- Prefer stacked notification center when devtools loaded it.
		local notifications = ctx.devtools
			and ctx.devtools.apis
			and ctx.devtools.apis.notifications
		if type(notifications) == "table" and type(notifications.Info) == "function" then
			local ok = pcall(function()
				if type(message) == "table" then
					notifications:Notify(message)
				else
					notifications:Info(tostring(message), {
						duration = tonumber(duration) or 2,
						channel = "system",
					})
				end
			end)
			if ok then
				return
			end
		end

		if library
			and not library.unloaded
			and library.SendNotification
			and library.base then
			local ok = pcall(function()
				library:SendNotification(duration or 2, tostring(message))
			end)
			if ok then
				return
			end
		end

		print("[xanhub universal] " .. tostring(message))
	end

	function ctx.toast(typeName, message, options)
		options = type(options) == "table" and options or {}
		options.message = tostring(message or options.message or "")
		options.type = typeName or options.type or "info"
		local notifications = ctx.devtools
			and ctx.devtools.apis
			and ctx.devtools.apis.notifications
		if type(notifications) == "table" and type(notifications.Notify) == "function" then
			local ok = pcall(function()
				notifications:Notify(options)
			end)
			if ok then
				return true
			end
		end
		ctx.notify(options.message, options.duration or 2)
		return false
	end

	function ctx.addConnection(signal, callback)
		return connections:connect(signal, callback)
	end

	function ctx.disconnect(connection)
		connections:disconnect(connection)
	end

	function ctx.getCharacter()
		return LocalPlayer.Character
	end

	function ctx.getHumanoid(character)
		character = character or ctx.getCharacter()
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	function ctx.getRoot(character)
		character = character or ctx.getCharacter()
		return character and (
			character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChild("Torso") -- R6
			or character:FindFirstChild("UpperTorso") -- R15
			or character.PrimaryPart
		)
	end

	function ctx.getPlayerLabel(player)
		if not player then
			return "Unknown"
		end

		local displayName = player.DisplayName
		if type(displayName) ~= "string" or displayName == "" then
			return player.Name
		end

		local trimmed = string.match(displayName, "^%s*(.-)%s*$") or displayName
		if trimmed == "" or string.match(trimmed, "^%?+$") then
			return player.Name
		end

		return trimmed
	end

	function ctx.getTargetPart(character)
		if not character then
			return nil
		end

		if library.flags["Universal Aim Part"] == "Torso" then
			return character:FindFirstChild("UpperTorso")
				or character:FindFirstChild("Torso")
				or character:FindFirstChild("HumanoidRootPart")
		end

		return character:FindFirstChild("Head")
			or character:FindFirstChild("HumanoidRootPart")
	end

	function ctx.option(flag)
		return library.options and library.options[flag]
	end

	function ctx.setToggle(flag, enabled)
		local control = ctx.option(flag)
		if control and type(control.SetState) == "function" then
			control:SetState(enabled == true)
		else
			library.flags[flag] = enabled == true
		end
	end

	function ctx.toggle(flag)
		ctx.setToggle(flag, library.flags[flag] ~= true)
	end

	function ctx.safeClipboard(text)
		local setter = type(setclipboard) == "function" and setclipboard
			or type(toclipboard) == "function" and toclipboard
			or nil

		if not setter then
			ctx.notify("Clipboard is unavailable", 3)
			return false
		end

		local ok = pcall(setter, tostring(text))
		ctx.notify(ok and "Copied to clipboard" or "Clipboard failed", ok and 2 or 3)
		return ok
	end

	function ctx.createRounded(parent, radius)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radius or 6)
		corner.Parent = parent
		return corner
	end

	function ctx.createOverlayRoot()
		if state.overlays.root and state.overlays.root.Parent then
			return state.overlays.root
		end

		local root = Instance.new("Frame")
		root.Name = "UniversalOverlay"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.BorderSizePixel = 0
		root.Active = false
		root.ZIndex = 500
		root.Parent = library.base
		state.overlays.root = root
		return root
	end

	return ctx
end

return createContext
