--[[
    xanhub | gakuran | skip death screen

    Death UI is PlayerScripts.respawnstuff:
      - Character attribute Dead → DeathUI ("RESTART YOUR HEART")
      - HeartButton must be clicked 7 times → RespawnRE:FireServer()
    We auto-complete the heart minigame and fire every known respawn remote.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local LocalPlayer = Players.LocalPlayer
	local RunService = ctx.RunService
	local StarterGui = ctx.StarterGui or game:GetService("StarterGui")
	local UserInputService = ctx.UserInputService or game:GetService("UserInputService")
	local Workspace = ctx.Workspace or game:GetService("Workspace")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	if type(ctx.state.deathSkip) ~= "table" then
		ctx.state.deathSkip = {}
	end
	local st = ctx.state.deathSkip
	st.busy = false
	st.lastSkipAt = 0

	local section = columns.homeRight:AddSection("Death")
	section:AddToggle({
		text = "Skip Death Screen",
		flag = "Gakuran Skip Death",
		state = false,
		tip = "Auto-complete the heart minigame and respawn when Dead / DeathUI shows",
	})
	section:AddToggle({
		text = "Instant (no heart spam)",
		flag = "Gakuran Skip Death Instant",
		state = true,
		tip = "Fire respawn remotes immediately instead of simulating 7 heart clicks",
	})
	section:AddButton({
		text = "Skip Death Now",
		callback = function()
			if type(st.skipNow) == "function" then
				st.skipNow(true)
			end
		end,
	})
	ctx.refs.deathSkipStatus = section:AddLabel("Death: idle")

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function setStatus(text)
		pcall(function()
			if ctx.refs.deathSkipStatus then
				ctx.refs.deathSkipStatus.Text = "Death: " .. tostring(text)
			end
		end)
	end

	local function getCharacter()
		local character = LocalPlayer.Character
		local folder = Workspace:FindFirstChild("Players")
		if folder then
			local named = folder:FindFirstChild(LocalPlayer.Name)
			if named and named:FindFirstChildOfClass("Humanoid") then
				return named
			end
		end
		return character
	end

	local function getDeathUi()
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		return pg and pg:FindFirstChild("DeathUI")
	end

	local function isDeathScreenActive()
		local ui = getDeathUi()
		if ui then
			local frame = ui:FindFirstChild("Frame")
			if ui.Enabled and frame and frame.Visible then
				return true, "ui"
			end
			if ui.Enabled then
				return true, "ui-enabled"
			end
		end
		local character = getCharacter()
		if character and character:GetAttribute("Dead") == true then
			return true, "attr"
		end
		return false, nil
	end

	local function clearDeathEffects()
		local cam = Workspace.CurrentCamera
		if cam then
			for _, name in ipairs({ "DeathColorCorrection", "DeathBlurEffect" }) do
				local fx = cam:FindFirstChild(name)
				if fx then
					pcall(function()
						fx:Destroy()
					end)
				end
			end
		end
		local ui = getDeathUi()
		if ui then
			pcall(function()
				ui.Enabled = false
				local frame = ui:FindFirstChild("Frame")
				if frame then
					frame.Visible = false
				end
				local sound = ui:FindFirstChild("HeartbeatSound")
				if sound and sound:IsA("Sound") then
					sound:Stop()
				end
			end)
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
		pcall(function()
			UserInputService.MouseIconEnabled = true
		end)
	end

	local function fireRespawnRemotes()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local tried = {}

		local function tryFire(inst, label)
			if not inst then
				return false
			end
			local ok = false
			if inst:IsA("RemoteEvent") then
				ok = pcall(function()
					inst:FireServer()
				end)
			elseif inst:IsA("RemoteFunction") then
				ok = pcall(function()
					inst:InvokeServer()
				end)
			elseif inst:IsA("UnreliableRemoteEvent") then
				ok = pcall(function()
					inst:FireServer()
				end)
			end
			table.insert(tried, label .. (ok and " ok" or " fail"))
			return ok
		end

		-- Exact remote from PlayerScripts.respawnstuff dorespawn()
		tryFire(ReplicatedStorage:FindFirstChild("RespawnRE"), "RespawnRE")
		tryFire(ReplicatedStorage:FindFirstChild("RespawnRE", true), "RespawnRE*")

		if remotes then
			tryFire(remotes:FindFirstChild("LoadCharacter"), "LoadCharacter")
			tryFire(remotes:FindFirstChild("SpawnRequest"), "SpawnRequest")
			tryFire(remotes:FindFirstChild("Revive"), "Revive")
		end

		return tried
	end

	local function clickHeartOnce()
		local ui = getDeathUi()
		if not ui then
			return false
		end
		local frame = ui:FindFirstChild("Frame")
		local btn = frame and frame:FindFirstChild("HeartButton")
		if not btn then
			return false
		end

		if type(getconnections) == "function" then
			local fired = false
			for _, signalName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down" }) do
				local ok, list = pcall(function()
					return getconnections(btn[signalName])
				end)
				if ok and type(list) == "table" then
					for _, conn in ipairs(list) do
						pcall(function()
							if conn.Function then
								conn.Function()
								fired = true
							elseif type(conn.Fire) == "function" then
								conn:Fire()
								fired = true
							end
						end)
					end
				end
			end
			if fired then
				return true
			end
		end

		-- Fallback: synthetic activation if the control supports it
		return pcall(function()
			if typeof(btn.Activate) == "function" then
				btn:Activate()
			end
		end)
	end

	local function completeHeartMinigame()
		-- respawnstuff onclick requires 7 clicks; each click locks ~0.7s via v11.
		for i = 1, 10 do
			clickHeartOnce()
			local ui = getDeathUi()
			local msg = ui and ui:FindFirstChild("Frame") and ui.Frame:FindFirstChild("MessageText")
			if msg and type(msg.Text) == "string" and msg.Text:upper():find("RESTORED", 1, true) then
				return true
			end
			if not isDeathScreenActive() then
				return true
			end
			task.wait(0.75)
		end
		return not isDeathScreenActive()
	end

	local function skipDeath(force)
		if st.busy then
			return
		end
		local active = isDeathScreenActive()
		if not active and not force then
			return
		end
		if not force and not flag("Gakuran Skip Death", false) then
			return
		end

		local now = os.clock()
		if not force and (now - (st.lastSkipAt or 0)) < 1.2 then
			return
		end

		st.busy = true
		st.lastSkipAt = now
		setStatus("skipping…")

		task.spawn(function()
			local ok, err = pcall(function()
				-- Always complete the 7-click heart path: dorespawn() only runs after v10 >= 7.
				-- Instant also blasts remotes first in case RespawnRE/LoadCharacter is enough.
				if flag("Gakuran Skip Death Instant", true) then
					fireRespawnRemotes()
				end
				completeHeartMinigame()
				fireRespawnRemotes()

				-- Local cleanup so the overlay never sticks if remotes lag
				clearDeathEffects()

				-- Wait briefly for character refresh
				local t0 = os.clock()
				while os.clock() - t0 < 2 do
					if not isDeathScreenActive() then
						break
					end
					task.wait(0.1)
				end
			end)

			if ok then
				if isDeathScreenActive() then
					setStatus("tried · still on death UI")
					if ctx.notify then
						ctx.notify("Death skip fired — still on screen (server may block)", 3)
					end
				else
					setStatus("skipped")
					if ctx.notify then
						ctx.notify("Death screen skipped", 2)
					end
				end
			else
				setStatus("error")
				warn("[xanhub death skip] " .. tostring(err))
			end
			st.busy = false
		end)
	end

	st.skipNow = skipDeath

	local function setup()
		-- Watch Dead attribute on current + future characters
		local function watchCharacter(character)
			if not character then
				return
			end
			ctx.addConnection(character:GetAttributeChangedSignal("Dead"), function()
				if character:GetAttribute("Dead") == true then
					task.defer(function()
						skipDeath(false)
					end)
				end
			end)
			if character:GetAttribute("Dead") == true and flag("Gakuran Skip Death", false) then
				task.defer(function()
					skipDeath(false)
				end)
			end
		end

		local char = getCharacter() or LocalPlayer.Character
		if char then
			watchCharacter(char)
		end
		ctx.addConnection(LocalPlayer.CharacterAdded, function(character)
			task.defer(function()
				watchCharacter(character)
				-- Workspace.Players clone can lag behind
				task.wait(0.25)
				watchCharacter(getCharacter())
			end)
		end)

		-- Poll DeathUI in case attribute is missed
		local accum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran Skip Death", false) then
				return
			end
			accum = accum + (tonumber(dt) or 0)
			if accum < 0.2 then
				return
			end
			accum = 0
			if isDeathScreenActive() then
				skipDeath(false)
			end
		end)

		setStatus("ready")
	end

	return { setup = setup }
end
