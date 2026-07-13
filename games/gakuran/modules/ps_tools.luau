--[[
    xanhub | gakuran | ps_tools

    Server Ops / Admin-style player tools.

    Paths (no require() of game modules — avoids Plugin capability taint):
      A) OwnerCommands RemoteFunction when authorized (VIP / panel)
      B) Public client puppet loop (CFrame / velocity / anchor / humanoid)

    Citra Hub note applies here too: full FE control of other players only
    works when the server grants ownership or on vulnerable ("TROLL") builds.
    On stock public FE, Goto (self TP) is solid; Bring/Fling/etc. are
    best-effort continuous client writes (same approach other hubs use).
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players or game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = ctx.Workspace or game:GetService("Workspace")
	local RunService = ctx.RunService or game:GetService("RunService")
	local LocalPlayer = ctx.LocalPlayer or Players.LocalPlayer

	if not columns or not columns.psLeft or not columns.psRight then
		warn("[xanhub gakuran] ps_tools: Server Ops columns missing")
		return { setup = function() end }
	end

	if type(ctx.state.psTools) ~= "table" then
		ctx.state.psTools = {}
	end
	local st = ctx.state.psTools
	st.nameToUserId = {}
	st.puppets = st.puppets or {} -- userId -> { mode = "bring"|"fling"|..., until = t }
	st.puppetConn = nil

	-- UI ------------------------------------------------------------------

	local statusSec = columns.psLeft:AddSection("Access")
	ctx.refs.psAccess = statusSec:AddLabel("Access: checking...")
	statusSec:AddLabel("Owner remote if allowed, else client puppet")
	statusSec:AddLabel("Note: other hubs only fully work on TROLL/vulnerable builds")

	local listSec = columns.psLeft:AddSection("Target")
	local playerList = listSec:AddList({
		text = "Puppet",
		flag = "Gakuran PS Target",
		values = { "(none)", "all" },
		value = "(none)",
		max = 10,
		tip = "Select player or 'all'",
	})
	listSec:AddButton({
		text = "Refresh Players",
		callback = function()
			if st.refresh then
				st.refresh()
			end
		end,
	})
	listSec:AddToggle({
		text = "Spectate Target",
		flag = "Gakuran PS Spectate",
		state = false,
		callback = function(on)
			if st.spectate then
				st.spectate(on)
			end
		end,
	})

	local modeSec = columns.psLeft:AddSection("Mode")
	modeSec:AddToggle({
		text = "Prefer Owner Remote",
		flag = "Gakuran PS Prefer Owner",
		state = true,
	})
	modeSec:AddToggle({
		text = "Client Puppet Fallback",
		flag = "Gakuran PS Public Fallback",
		state = true,
		tip = "Loop CFrame/velocity/anchor on targets when not authorized",
	})
	modeSec:AddSlider({
		text = "Puppet Hold Ms",
		flag = "Gakuran PS Puppet Ms",
		min = 200,
		max = 8000,
		value = 2500,
		float = 100,
		suffix = " ms",
		tip = "How long continuous puppet runs (Bring/Fling/Spin/Freeze)",
	})

	local actSec = columns.psRight:AddSection("Commands")
	local bulkSec = columns.psRight:AddSection("Bulk / Stop")

	-- Helpers -------------------------------------------------------------

	local function flag(name, default)
		local v = library.flags[name]
		if v == nil then
			return default
		end
		return v
	end

	local function numFlag(name, default)
		return tonumber(flag(name, default)) or default
	end

	local function notify(msg, t)
		pcall(function()
			ctx.notify(tostring(msg), t or 2)
		end)
	end

	local function setAccess(text)
		pcall(function()
			if ctx.refs.psAccess then
				ctx.refs.psAccess.Text = "Access: " .. tostring(text)
			end
		end)
	end

	local function getRemote(name)
		local ok, inst = pcall(function()
			local r = ReplicatedStorage:FindFirstChild("Remotes")
			return r and r:FindFirstChild(name)
		end)
		return ok and inst or nil
	end

	local function ownerInvoke(action, payload)
		local rf = getRemote("OwnerCommands")
		if not rf or not rf:IsA("RemoteFunction") then
			return { ok = false, error = "no OwnerCommands" }
		end
		local ok, res = pcall(function()
			return rf:InvokeServer(action, payload or {})
		end)
		if not ok then
			return { ok = false, error = tostring(res) }
		end
		if type(res) == "table" then
			return res
		end
		return { ok = res ~= false, data = res }
	end

	local function charOf(plr)
		if not plr then
			return nil
		end
		local c
		pcall(function()
			local folder = Workspace:FindFirstChild("Players")
			if folder then
				local named = folder:FindFirstChild(plr.Name)
				if named and named:FindFirstChildOfClass("Humanoid") then
					c = named
					return
				end
			end
			c = plr.Character
		end)
		return c
	end

	local function hrpOf(ch)
		if not ch then
			return nil
		end
		local h
		pcall(function()
			h = ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart
		end)
		return h
	end

	local function humOf(ch)
		if not ch then
			return nil
		end
		local h
		pcall(function()
			h = ch:FindFirstChildOfClass("Humanoid")
		end)
		return h
	end

	local function playerLabel(plr)
		if not plr then
			return nil
		end
		local name, display
		pcall(function()
			name = plr.Name
			display = plr.DisplayName
		end)
		if type(name) ~= "string" then
			return nil
		end
		if type(display) == "string" and display ~= "" and display ~= name then
			return display .. " (@" .. name .. ")"
		end
		return name
	end

	local function resolveTargets()
		local value = library.flags["Gakuran PS Target"]
		local list = {}
		if value == "all" then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= LocalPlayer then
					list[#list + 1] = p
				end
			end
			return list
		end
		if type(value) ~= "string" or value == "" or value == "(none)" then
			return list
		end
		local uid = st.nameToUserId[value]
		for _, p in ipairs(Players:GetPlayers()) do
			if (uid and p.UserId == uid) or playerLabel(p) == value or p.Name == value then
				list[1] = p
				break
			end
		end
		return list
	end

	-- Spectate ------------------------------------------------------------

	local oldCamSubject
	function st.spectate(on)
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		if on then
			local targets = resolveTargets()
			local plr = targets[1]
			if not plr then
				notify("Pick a target to spectate", 2)
				library.flags["Gakuran PS Spectate"] = false
				return
			end
			local hum = humOf(charOf(plr))
			if hum then
				pcall(function()
					if not oldCamSubject then
						oldCamSubject = cam.CameraSubject
					end
					cam.CameraSubject = hum
				end)
				notify("Spectating " .. plr.Name, 2)
			end
		else
			pcall(function()
				local me = humOf(charOf(LocalPlayer))
				cam.CameraSubject = oldCamSubject or me
				oldCamSubject = nil
			end)
		end
	end

	-- Puppet engine -------------------------------------------------------

	local function clearPuppet(uid)
		st.puppets[uid] = nil
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			local hrp = hrpOf(charOf(plr))
			local hum = humOf(charOf(plr))
			pcall(function()
				if hrp then
					hrp.Anchored = false
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end
				if hum then
					hum.PlatformStand = false
					hum.Sit = false
				end
			end)
		end
	end

	local function clearAllPuppets()
		local ids = {}
		for uid in pairs(st.puppets) do
			ids[#ids + 1] = uid
		end
		for i = 1, #ids do
			clearPuppet(ids[i])
		end
	end

	local function startPuppet(plr, mode, durationSec)
		if not plr then
			return
		end
		local ms = durationSec or (numFlag("Gakuran PS Puppet Ms", 2500) / 1000)
		st.puppets[plr.UserId] = {
			mode = mode,
			untilT = os.clock() + ms,
			name = plr.Name,
		}
	end

	local function ensurePuppetLoop()
		if st.puppetConn then
			return
		end
		st.puppetConn = RunService.Heartbeat:Connect(function()
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran PS Public Fallback", true) then
				return
			end
			local now = os.clock()
			local meHrp = hrpOf(charOf(LocalPlayer))
			local remove = {}
			for uid, job in pairs(st.puppets) do
				if now > (job.untilT or 0) then
					remove[#remove + 1] = uid
				else
					local plr = Players:GetPlayerByUserId(uid)
					if not plr then
						remove[#remove + 1] = uid
					else
						local ch = charOf(plr)
						local hrp = hrpOf(ch)
						local hum = humOf(ch)
						if hrp then
							local mode = job.mode
							if mode == "bring" and meHrp then
								pcall(function()
									hrp.Anchored = false
									hrp.CFrame = meHrp.CFrame * CFrame.new(2, 0, 0)
									hrp.AssemblyLinearVelocity = Vector3.zero
									hrp.AssemblyAngularVelocity = Vector3.zero
								end)
							elseif mode == "fling" then
								pcall(function()
									hrp.Anchored = false
									if hum then
										hum.PlatformStand = true
									end
									hrp.AssemblyLinearVelocity = Vector3.new(
										(math.random() - 0.5) * 120,
										90 + math.random() * 80,
										(math.random() - 0.5) * 120
									)
									hrp.AssemblyAngularVelocity = Vector3.new(40, 40, 40)
								end)
							elseif mode == "spin" then
								pcall(function()
									hrp.Anchored = false
									hrp.AssemblyAngularVelocity = Vector3.new(0, 80, 0)
								end)
							elseif mode == "freeze" then
								pcall(function()
									hrp.Anchored = true
									hrp.AssemblyLinearVelocity = Vector3.zero
									hrp.AssemblyAngularVelocity = Vector3.zero
									if hum then
										hum.PlatformStand = true
									end
								end)
							elseif mode == "sit" then
								pcall(function()
									if hum then
										hum.Sit = true
									end
								end)
							end
						end
					end
				end
			end
			for i = 1, #remove do
				clearPuppet(remove[i])
			end
		end)
		if type(ctx.addConnection) == "function" then
			-- track for unload via library cleanup instead
		end
	end

	-- Owner + public actions ----------------------------------------------

	local OWNER_MAP = {
		Bring = "Bring",
		Goto = "TeleportTo",
		Heal = "Heal",
		Respawn = "Respawn",
		Kill = nil, -- no stock kill
		Fling = nil,
		Spin = nil,
		Freeze = nil,
		Unfreeze = nil,
		Sit = nil,
		Jump = nil,
	}

	local function tryOwnerOn(plr, action)
		if not flag("Gakuran PS Prefer Owner", true) then
			return false
		end
		local mapped = OWNER_MAP[action]
		if not mapped then
			return false
		end
		local res = ownerInvoke(mapped, { TargetUserId = plr.UserId })
		return type(res) == "table" and res.ok == true, res
	end

	local function publicGoto(plr)
		local me = hrpOf(charOf(LocalPlayer))
		local them = hrpOf(charOf(plr))
		if not me or not them then
			return false
		end
		return pcall(function()
			me.CFrame = them.CFrame * CFrame.new(0, 0, 3)
		end)
	end

	local function publicHeal(plr)
		local hum = humOf(charOf(plr))
		if not hum then
			return false
		end
		return pcall(function()
			hum.Health = hum.MaxHealth
		end)
	end

	local function publicKill(plr)
		local hum = humOf(charOf(plr))
		if not hum then
			return false
		end
		return pcall(function()
			hum.Health = 0
		end)
	end

	local function publicRespawn(plr)
		if plr == LocalPlayer then
			local ok = false
			local sr = getRemote("SpawnRequest")
			if sr and sr:IsA("RemoteEvent") then
				ok = pcall(function()
					sr:FireServer()
				end) or ok
			end
			local lc = getRemote("LoadCharacter")
			if lc and lc:IsA("RemoteFunction") then
				ok = pcall(function()
					lc:InvokeServer()
				end) or ok
			end
			local rv = getRemote("Revive")
			if rv and rv:IsA("RemoteEvent") then
				ok = pcall(function()
					rv:FireServer()
				end) or ok
			end
			return ok
		end
		return publicKill(plr)
	end

	local function publicJump(plr)
		local hum = humOf(charOf(plr))
		if not hum then
			return false
		end
		return pcall(function()
			hum.Jump = true
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end

	local function runOnTargets(action, label)
		local targets = resolveTargets()
		if #targets == 0 then
			notify("Pick a target (or all)", 2)
			return
		end

		ensurePuppetLoop()
		local ownerHits, clientHits = 0, 0

		for _, plr in ipairs(targets) do
			local owned = false
			if action == "Goto" and plr ~= LocalPlayer then
				-- Goto is always self → them
				if tryOwnerOn(plr, "Goto") then
					owned = true
					ownerHits = ownerHits + 1
				elseif flag("Gakuran PS Public Fallback", true) and publicGoto(plr) then
					clientHits = clientHits + 1
				end
			elseif action == "Bring" then
				if tryOwnerOn(plr, "Bring") then
					owned = true
					ownerHits = ownerHits + 1
				elseif flag("Gakuran PS Public Fallback", true) then
					startPuppet(plr, "bring")
					clientHits = clientHits + 1
				end
			elseif action == "Heal" then
				if tryOwnerOn(plr, "Heal") then
					ownerHits = ownerHits + 1
				elseif flag("Gakuran PS Public Fallback", true) and publicHeal(plr) then
					clientHits = clientHits + 1
				end
			elseif action == "Respawn" then
				if tryOwnerOn(plr, "Respawn") then
					ownerHits = ownerHits + 1
				elseif flag("Gakuran PS Public Fallback", true) and publicRespawn(plr) then
					clientHits = clientHits + 1
				end
			elseif action == "Fling" then
				if flag("Gakuran PS Public Fallback", true) then
					startPuppet(plr, "fling")
					clientHits = clientHits + 1
				end
			elseif action == "Spin" then
				if flag("Gakuran PS Public Fallback", true) then
					startPuppet(plr, "spin")
					clientHits = clientHits + 1
				end
			elseif action == "Freeze" then
				if flag("Gakuran PS Public Fallback", true) then
					startPuppet(plr, "freeze")
					clientHits = clientHits + 1
				end
			elseif action == "Unfreeze" then
				clearPuppet(plr.UserId)
				clientHits = clientHits + 1
			elseif action == "Sit" then
				if flag("Gakuran PS Public Fallback", true) then
					startPuppet(plr, "sit")
					clientHits = clientHits + 1
				end
			elseif action == "Jump" then
				if flag("Gakuran PS Public Fallback", true) and publicJump(plr) then
					clientHits = clientHits + 1
				end
			elseif action == "Kill" then
				if flag("Gakuran PS Public Fallback", true) and publicKill(plr) then
					clientHits = clientHits + 1
				end
			end
			owned = owned -- silence
		end

		local msg = (label or action)
			.. " · owner "
			.. tostring(ownerHits)
			.. " · client "
			.. tostring(clientHits)
		notify(msg, 2)
	end

	-- Buttons (Citra-like set + our extras) -------------------------------

	local function btn(section, text, action)
		section:AddButton({
			text = text,
			callback = function()
				runOnTargets(action, text)
			end,
		})
	end

	btn(actSec, "Bring", "Bring")
	btn(actSec, "Goto", "Goto")
	btn(actSec, "Fling", "Fling")
	btn(actSec, "Spin", "Spin")
	btn(actSec, "Freeze", "Freeze")
	btn(actSec, "Unfreeze", "Unfreeze")
	btn(actSec, "Sit", "Sit")
	btn(actSec, "Jump", "Jump")
	btn(actSec, "Kill", "Kill")
	btn(actSec, "Heal", "Heal")
	btn(actSec, "Respawn", "Respawn")

	bulkSec:AddButton({
		text = "Stop All Puppets",
		callback = function()
			clearAllPuppets()
			notify("Puppets stopped", 2)
		end,
	})
	bulkSec:AddButton({
		text = "Heal All",
		callback = function()
			library.flags["Gakuran PS Target"] = "all"
			if playerList and playerList.SetValue then
				pcall(function()
					playerList:SetValue("all", true)
				end)
			end
			-- try owner bulk then client
			if flag("Gakuran PS Prefer Owner", true) then
				local res = ownerInvoke("HealAll", {})
				if type(res) == "table" and res.ok == true then
					notify("Heal All ok (owner)", 2)
					return
				end
			end
			runOnTargets("Heal", "Heal All")
		end,
	})
	bulkSec:AddButton({
		text = "Bring All",
		callback = function()
			if playerList and playerList.SetValue then
				pcall(function()
					playerList:SetValue("all", true)
				end)
			end
			library.flags["Gakuran PS Target"] = "all"
			if flag("Gakuran PS Prefer Owner", true) then
				local res = ownerInvoke("BringAll", {})
				if type(res) == "table" and res.ok == true then
					notify("Bring All ok (owner)", 2)
					return
				end
			end
			runOnTargets("Bring", "Bring All")
		end,
	})

	-- Refresh list --------------------------------------------------------

	function st.refresh()
		local rf = getRemote("OwnerCommands")
		local psId = ""
		pcall(function()
			psId = tostring(game.PrivateServerId or "")
		end)
		if rf and psId ~= "" then
			setAccess("vip · owner remote + client puppet")
		elseif rf then
			setAccess("public · client puppet (owner locked)")
		else
			setAccess("public client puppet only")
		end

		if not playerList or type(playerList.values) ~= "table" then
			return
		end

		local labels = { "all" }
		st.nameToUserId = { all = -1 }
		local plist = Players:GetPlayers()
		table.sort(plist, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)
		for i = 1, #plist do
			local plr = plist[i]
			local label = playerLabel(plr)
			if label then
				labels[#labels + 1] = label
				st.nameToUserId[label] = plr.UserId
			end
		end
		if #labels == 1 then
			labels[#labels + 1] = "(none)"
		end

		local keep = {}
		for i = 1, #labels do
			keep[labels[i]] = true
		end

		if type(playerList.AddValue) == "function" and type(playerList.RemoveValue) == "function" then
			local existing = {}
			for i = 1, #playerList.values do
				existing[i] = playerList.values[i]
			end
			for i = 1, #existing do
				if not keep[existing[i]] then
					pcall(function()
						playerList:RemoveValue(existing[i])
					end)
				end
			end
			for i = 1, #labels do
				local v = labels[i]
				if not (playerList.labels and playerList.labels[v]) then
					pcall(function()
						playerList:AddValue(v)
					end)
				end
			end
			local cur = library.flags["Gakuran PS Target"]
			if type(cur) ~= "string" or not keep[cur] then
				if type(playerList.SetValue) == "function" then
					pcall(function()
						playerList:SetValue(labels[1], true)
					end)
				else
					library.flags["Gakuran PS Target"] = labels[1]
				end
			end
		end
	end

	local function setup()
		ensurePuppetLoop()
		task.defer(function()
			if not ctx.state.unloading then
				pcall(st.refresh)
			end
		end)
		if type(ctx.addConnection) == "function" then
			ctx.addConnection(Players.PlayerAdded, function()
				task.defer(function()
					pcall(st.refresh)
				end)
			end)
			ctx.addConnection(Players.PlayerRemoving, function(p)
				if p then
					clearPuppet(p.UserId)
				end
				task.defer(function()
					pcall(st.refresh)
				end)
			end)
		end
	end

	if type(library.AddCleanup) == "function" then
		library:AddCleanup(function()
			clearAllPuppets()
			if st.puppetConn then
				pcall(function()
					st.puppetConn:Disconnect()
				end)
				st.puppetConn = nil
			end
			pcall(function()
				st.spectate(false)
			end)
		end)
	end

	return { setup = setup }
end
