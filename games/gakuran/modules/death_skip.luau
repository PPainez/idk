--[[
    xanhub | gakuran | skip death screen

    Death controller (SpawnServiceClient-style object bound to DeathUI.HeartButton):
      - 7 heart clicks → self:_doRespawn()
      - _doRespawn fires Remotes.SpawnRequest + transition cleanup

    Instant skip: locate that controller and call _doRespawn() directly
    (verified live — no heart presses needed).
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
	st.controller = nil

	local section = columns.homeRight:AddSection("Death")
	section:AddToggle({
		text = "Skip Death Screen",
		flag = "Gakuran Skip Death",
		state = false,
		tip = "When death UI shows, skip instantly via game _doRespawn (no heart spam)",
	})
	section:AddToggle({
		text = "Instant Respawn",
		flag = "Gakuran Skip Death Instant",
		state = true,
		tip = "Call death controller :_doRespawn() + SpawnRequest immediately",
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
		-- Controller flag
		if type(st.controller) == "table" and st.controller._dead == true then
			return true, "controller"
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

	local function looksLikeDeathController(t)
		return type(t) == "table"
			and type(t._doRespawn) == "function"
			and (t._spawnRemote ~= nil or t._heartBtn ~= nil or t._gui ~= nil)
	end

	local function resolveFromUpvalue(fn)
		if type(fn) ~= "function" then
			return nil
		end
		if type(getupvalues) == "function" then
			local ok, ups = pcall(getupvalues, fn)
			if ok and type(ups) == "table" then
				for _, v in pairs(ups) do
					if looksLikeDeathController(v) then
						return v
					end
					-- sometimes wrapped as { [1] = controller }
					if type(v) == "table" then
						for _, inner in pairs(v) do
							if looksLikeDeathController(inner) then
								return inner
							end
						end
					end
				end
			end
		end
		if type(getupvalue) == "function" then
			for i = 1, 12 do
				local ok, a, b = pcall(getupvalue, fn, i)
				if not ok then
					break
				end
				local val = if b ~= nil then b else a
				if looksLikeDeathController(val) then
					return val
				end
			end
		end
		if type(debug) == "table" and type(debug.getupvalue) == "function" then
			for i = 1, 12 do
				local ok, name, val = pcall(debug.getupvalue, fn, i)
				if not ok or name == nil then
					break
				end
				if looksLikeDeathController(val) then
					return val
				end
			end
		end
		return nil
	end

	local function findDeathController()
		if looksLikeDeathController(st.controller) then
			return st.controller
		end

		-- Primary: HeartButton connection upvalue (live-verified path)
		local ui = getDeathUi()
		local btn = ui and ui:FindFirstChild("Frame") and ui.Frame:FindFirstChild("HeartButton")
		if btn and type(getconnections) == "function" then
			for _, signalName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down" }) do
				local ok, list = pcall(function()
					return getconnections(btn[signalName])
				end)
				if ok and type(list) == "table" then
					for _, conn in ipairs(list) do
						local ctrl = resolveFromUpvalue(conn.Function)
						if ctrl then
							st.controller = ctrl
							return ctrl
						end
					end
				end
			end
		end

		-- Fallback: scan getgc for the controller table
		if type(getgc) == "function" then
			local ok, objects = pcall(getgc, true)
			if ok and type(objects) == "table" then
				for _, obj in ipairs(objects) do
					if looksLikeDeathController(obj) then
						-- Prefer the one bound to local player / current DeathUI
						local guiOk = true
						if obj._gui and obj._gui.Parent == nil then
							guiOk = false
						end
						if guiOk then
							st.controller = obj
							return obj
						end
					end
				end
			end
		end

		return nil
	end

	local function instantDoRespawn()
		local ctrl = findDeathController()
		if not ctrl then
			return false, "no death controller"
		end

		-- Clear minigame state so _doRespawn isn't blocked by in-flight flags
		pcall(function()
			ctrl._clicks = 7
			ctrl._busy = false
			ctrl._respawnInFlight = false
		end)

		local ok, err = pcall(function()
			ctrl:_doRespawn()
		end)
		if ok then
			return true, "doRespawn"
		end
		return false, tostring(err)
	end

	local function fireSpawnRequest()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local spawnRequest = remotes and remotes:FindFirstChild("SpawnRequest")
		if not spawnRequest then
			return false
		end
		return pcall(function()
			spawnRequest:FireServer()
		end)
	end

	local function fireFallbackRemotes()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotes then
			return
		end
		for _, name in ipairs({ "SpawnRequest", "LoadCharacter", "Revive" }) do
			local inst = remotes:FindFirstChild(name)
			if inst then
				pcall(function()
					if inst:IsA("RemoteEvent") then
						inst:FireServer()
					elseif inst:IsA("RemoteFunction") then
						inst:InvokeServer()
					end
				end)
			end
		end
		local legacy = ReplicatedStorage:FindFirstChild("RespawnRE")
		if legacy then
			pcall(function()
				legacy:FireServer()
			end)
		end
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
		if not force and (now - (st.lastSkipAt or 0)) < 0.8 then
			return
		end

		st.busy = true
		st.lastSkipAt = now
		setStatus("instant…")

		task.spawn(function()
			local method = "none"
			local ok, err = pcall(function()
				if flag("Gakuran Skip Death Instant", true) then
					local did, how = instantDoRespawn()
					if did then
						method = how or "doRespawn"
					else
						-- Direct remote (same as controller uses)
						if fireSpawnRequest() then
							method = "SpawnRequest"
						else
							fireFallbackRemotes()
							method = "fallback-remotes"
						end
					end
				else
					-- Non-instant: still prefer controller, else heart path
					local did = instantDoRespawn()
					if did then
						method = "doRespawn"
					else
						method = "heart-fallback"
						-- Last resort: 7 spaced clicks
						local ui = getDeathUi()
						local btn = ui and ui:FindFirstChild("Frame") and ui.Frame:FindFirstChild("HeartButton")
						if btn and type(getconnections) == "function" then
							for _ = 1, 8 do
								for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
									pcall(function()
										if conn.Function then
											conn.Function()
										end
									end)
								end
								if not isDeathScreenActive() then
									break
								end
								task.wait(0.72)
							end
						end
						fireSpawnRequest()
					end
				end

				clearDeathEffects()

				local t0 = os.clock()
				while os.clock() - t0 < 1.5 do
					if not isDeathScreenActive() then
						break
					end
					task.wait(0.05)
				end
			end)

			if ok then
				if isDeathScreenActive() then
					setStatus("tried · " .. method)
					if ctx.notify then
						ctx.notify("Death skip (" .. method .. ") — still on screen", 3)
					end
				else
					setStatus("skipped · " .. method)
					if ctx.notify then
						ctx.notify("Death skipped instantly", 2)
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
		local function watchCharacter(character)
			if not character then
				return
			end
			ctx.addConnection(character:GetAttributeChangedSignal("Dead"), function()
				if character:GetAttribute("Dead") == true then
					task.defer(function()
						-- DeathUI may take a frame to build/bind
						task.wait(0.05)
						findDeathController()
						skipDeath(false)
					end)
				end
			end)
			if character:GetAttribute("Dead") == true and flag("Gakuran Skip Death", false) then
				task.defer(function()
					findDeathController()
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
				task.wait(0.25)
				watchCharacter(getCharacter())
			end)
		end)

		-- Cache controller once DeathUI exists
		task.defer(function()
			for _ = 1, 30 do
				if findDeathController() then
					break
				end
				task.wait(0.2)
			end
		end)

		local accum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran Skip Death", false) then
				return
			end
			accum = accum + (tonumber(dt) or 0)
			if accum < 0.15 then
				return
			end
			accum = 0
			if isDeathScreenActive() then
				findDeathController()
				skipDeath(false)
			end
		end)

		setStatus("ready")
	end

	return { setup = setup }
end
