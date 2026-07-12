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

	function ctx.notify(message, duration)
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
