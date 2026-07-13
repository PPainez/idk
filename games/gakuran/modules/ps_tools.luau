--[[
    xanhub | gakuran | ps_tools

    Two paths (never require() game ModuleScripts — Plugin capability taint):

    1) Owner mode (VIP / authorized):
         ReplicatedStorage.Remotes.OwnerCommands:InvokeServer(action, payload)

    2) Public mode (anyone):
         Goto     → CFrame local character to target (replicates for you)
         Bring    → best-effort move target HRP near you (loop; client-side)
         Heal     → set Humanoid.Health = MaxHealth (self solid; others best-effort)
         Respawn  → self: SpawnRequest / LoadCharacter; others: Health=0 then SpawnRequest

    Owner path is tried first when the remote accepts the call; otherwise public fallback.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players or game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = ctx.Workspace or game:GetService("Workspace")
	local LocalPlayer = ctx.LocalPlayer or Players.LocalPlayer

	if not columns or not columns.psLeft or not columns.psRight then
		warn("[xanhub gakuran] ps_tools: Server Ops columns missing — re-exec after UI update")
		return { setup = function() end }
	end

	if type(ctx.state.psTools) ~= "table" then
		ctx.state.psTools = {}
	end
	local st = ctx.state.psTools
	st.nameToUserId = {}
	st.ownerOk = nil -- nil unknown, true/false cached lightly

	local statusSec = columns.psLeft:AddSection("Access")
	ctx.refs.psAccess = statusSec:AddLabel("Access: checking...")
	statusSec:AddLabel("Owner remote if allowed · else public client")

	local listSec = columns.psLeft:AddSection("Players")
	local playerList = listSec:AddList({
		text = "Target",
		flag = "Gakuran PS Target",
		values = { "(none)" },
		value = "(none)",
		max = 8,
		tip = "Select a player, then use actions",
	})
	listSec:AddButton({
		text = "Refresh List",
		callback = function()
			if type(st.refresh) == "function" then
				st.refresh()
			end
		end,
	})

	local actSec = columns.psRight:AddSection("Actions")
	actSec:AddLabel("Bring / Goto / Heal / Respawn")

	local bulkSec = columns.psRight:AddSection("Everyone")
	bulkSec:AddLabel("All players (public = client loop)")

	local modeSec = columns.psRight:AddSection("Mode")
	modeSec:AddToggle({
		text = "Prefer Owner Remote",
		flag = "Gakuran PS Prefer Owner",
		state = true,
		tip = "Try OwnerCommands first (VIP). Falls back to public client methods.",
	})
	modeSec:AddToggle({
		text = "Public Client Fallback",
		flag = "Gakuran PS Public Fallback",
		state = true,
		tip = "When not authorized: Goto/Heal/Respawn self + best-effort Bring",
	})

	-- Helpers --------------------------------------------------------------

	local function flag(name, default)
		local v = library.flags[name]
		if v == nil then
			return default
		end
		return v
	end

	local function setAccessText(text)
		pcall(function()
			if ctx.refs.psAccess then
				ctx.refs.psAccess.Text = "Access: " .. tostring(text)
			end
		end)
	end

	local function getRemote(name)
		local ok, inst = pcall(function()
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			return remotes and remotes:FindFirstChild(name)
		end)
		if ok then
			return inst
		end
		return nil
	end

	local function getOwnerRemote()
		local rf = getRemote("OwnerCommands")
		if rf and rf:IsA("RemoteFunction") then
			return rf
		end
		return nil
	end

	local function ownerInvoke(action, payload)
		local rf = getOwnerRemote()
		if not rf then
			return { ok = false, error = "no remote" }
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

	-- Probe once: does Heal-self authorize?
	local function refreshOwnerStatus()
		if not flag("Gakuran PS Prefer Owner", true) then
			st.ownerOk = false
			return false
		end
		local rf = getOwnerRemote()
		if not rf then
			st.ownerOk = false
			return false
		end
		local res = ownerInvoke("Heal", { TargetUserId = LocalPlayer.UserId })
		local allowed = type(res) == "table" and res.ok == true
		-- "Not authorized." means remote works but we are not op
		if type(res) == "table" and res.ok == false then
			local err = tostring(res.error or "")
			if err:lower():find("not authorized") or err:lower():find("den") then
				allowed = false
			end
		end
		st.ownerOk = allowed
		return allowed
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

	local function hrpOf(character)
		if not character then
			return nil
		end
		local h
		pcall(function()
			h = character:FindFirstChild("HumanoidRootPart")
				or character:FindFirstChild("Torso")
				or character.PrimaryPart
		end)
		return h
	end

	local function humanoidOf(character)
		if not character then
			return nil
		end
		local h
		pcall(function()
			h = character:FindFirstChildOfClass("Humanoid")
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

	local function selectedUserId()
		local value = library.flags["Gakuran PS Target"]
		if type(value) ~= "string" or value == "" or value == "(none)" then
			return nil
		end
		local id = st.nameToUserId[value]
		if type(id) == "number" then
			return id
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			local label = playerLabel(plr)
			if label == value or plr.Name == value or plr.DisplayName == value then
				return plr.UserId
			end
		end
		return nil
	end

	local function playerByUserId(uid)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.UserId == uid then
				return plr
			end
		end
		return nil
	end

	local function notify(msg, t)
		pcall(function()
			ctx.notify(tostring(msg), t or 2)
		end)
	end

	-- Public client actions ------------------------------------------------

	local function publicGoto(targetPlr)
		local myHrp = hrpOf(charOf(LocalPlayer))
		local theirHrp = hrpOf(charOf(targetPlr))
		if not myHrp or not theirHrp then
			return false, "no character"
		end
		local ok, err = pcall(function()
			myHrp.CFrame = theirHrp.CFrame * CFrame.new(0, 0, 3)
		end)
		return ok, err
	end

	local function publicBring(targetPlr)
		local myHrp = hrpOf(charOf(LocalPlayer))
		local theirChar = charOf(targetPlr)
		local theirHrp = hrpOf(theirChar)
		if not myHrp or not theirHrp then
			return false, "no character"
		end
		-- Burst for a short window (same approach many public menus use)
		local ok = true
		local dest = myHrp.CFrame * CFrame.new(0, 0, -3)
		for _ = 1, 25 do
			local h = hrpOf(charOf(targetPlr)) or theirHrp
			local success = pcall(function()
				h.CFrame = dest
				h.AssemblyLinearVelocity = Vector3.zero
				h.AssemblyAngularVelocity = Vector3.zero
			end)
			if not success then
				ok = false
			end
			task.wait()
		end
		return ok, ok and "client bring" or "bring blocked"
	end

	local function publicHeal(targetPlr)
		local hum = humanoidOf(charOf(targetPlr))
		if not hum then
			return false, "no humanoid"
		end
		local ok, err = pcall(function()
			hum.Health = hum.MaxHealth
			-- clear common downed attrs if present
			local ch = charOf(targetPlr)
			if ch then
				pcall(function()
					ch:SetAttribute("Downed", false)
				end)
			end
		end)
		return ok, err
	end

	local function publicRespawn(targetPlr)
		if targetPlr == LocalPlayer then
			local fired = false
			local sr = getRemote("SpawnRequest")
			if sr and sr:IsA("RemoteEvent") then
				fired = pcall(function()
					sr:FireServer()
				end) or fired
			end
			local lc = getRemote("LoadCharacter")
			if lc and lc:IsA("RemoteFunction") then
				fired = pcall(function()
					lc:InvokeServer()
				end) or fired
			end
			local rv = getRemote("Revive")
			if rv and rv:IsA("RemoteEvent") then
				fired = pcall(function()
					rv:FireServer()
				end) or fired
			end
			-- last resort: kill local humanoid so death/respawn flow runs
			if not fired then
				local hum = humanoidOf(charOf(LocalPlayer))
				if hum then
					pcall(function()
						hum.Health = 0
					end)
					fired = true
				end
			end
			return fired, fired and "self respawn" or "failed"
		end

		-- Others: try zero health (best-effort client)
		local hum = humanoidOf(charOf(targetPlr))
		if not hum then
			return false, "no humanoid"
		end
		local ok = pcall(function()
			hum.Health = 0
		end)
		return ok, ok and "client kill" or "blocked"
	end

	-- Unified action -------------------------------------------------------

	local function runAction(action, targetPlr, label)
		if not targetPlr then
			notify("Pick a player first", 2)
			return
		end

		local uid = targetPlr.UserId
		local usedOwner = false
		local ownerRes

		if flag("Gakuran PS Prefer Owner", true) then
			local ownerAction = action
			-- map to OwnerCommands names
			if action == "Goto" then
				ownerAction = "TeleportTo"
			end
			ownerRes = ownerInvoke(ownerAction, { TargetUserId = uid })
			if type(ownerRes) == "table" and ownerRes.ok == true then
				usedOwner = true
				notify((label or action) .. " ok (owner)", 2)
				return
			end
		end

		if not flag("Gakuran PS Public Fallback", true) then
			local err = type(ownerRes) == "table" and tostring(ownerRes.error or "denied") or "denied"
			notify((label or action) .. " " .. err:sub(1, 40), 3)
			return
		end

		local ok, why
		if action == "Bring" then
			ok, why = publicBring(targetPlr)
		elseif action == "Goto" or action == "TeleportTo" then
			ok, why = publicGoto(targetPlr)
		elseif action == "Heal" then
			ok, why = publicHeal(targetPlr)
		elseif action == "Respawn" then
			ok, why = publicRespawn(targetPlr)
		else
			ok, why = false, "unknown"
		end

		if ok then
			notify((label or action) .. " ok (public)", 2)
		else
			notify((label or action) .. " fail " .. tostring(why or ""):sub(1, 36), 3)
		end
	end

	local function runBulk(action, label)
		if flag("Gakuran PS Prefer Owner", true) then
			local map = {
				HealAll = "HealAll",
				BringAll = "BringAll",
				RespawnAll = "RespawnAll",
			}
			local ownerName = map[action]
			if ownerName then
				local res = ownerInvoke(ownerName, {})
				if type(res) == "table" and res.ok == true then
					notify((label or action) .. " ok (owner)", 2)
					return
				end
			end
		end

		if not flag("Gakuran PS Public Fallback", true) then
			notify((label or action) .. " denied", 3)
			return
		end

		local n = 0
		for _, plr in ipairs(Players:GetPlayers()) do
			if action == "HealAll" then
				if publicHeal(plr) then
					n = n + 1
				end
			elseif action == "BringAll" then
				if plr ~= LocalPlayer and publicBring(plr) then
					n = n + 1
				end
			elseif action == "RespawnAll" then
				if publicRespawn(plr) then
					n = n + 1
				end
			end
		end
		notify((label or action) .. " public x" .. tostring(n), 2)
	end

	function st.refresh()
		local owner = st.ownerOk
		if owner == nil then
			-- don't spam Heal probe every refresh — light check only
			local rf = getOwnerRemote()
			local psId = ""
			pcall(function()
				psId = tostring(game.PrivateServerId or "")
			end)
			if rf and psId ~= "" then
				setAccessText("vip remote present · public fallback on")
			elseif rf then
				setAccessText("public · owner remote locked · client fallback")
			else
				setAccessText("public client only")
			end
		elseif owner then
			setAccessText("owner authorized")
		else
			setAccessText("public client fallback")
		end

		if not playerList or type(playerList.values) ~= "table" then
			return
		end

		local labels = {}
		st.nameToUserId = {}
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)
		for i = 1, #list do
			local plr = list[i]
			local label = playerLabel(plr)
			if label then
				labels[#labels + 1] = label
				st.nameToUserId[label] = plr.UserId
			end
		end
		if #labels == 0 then
			labels[1] = "(none)"
		end

		local keep = {}
		for i = 1, #labels do
			keep[labels[i]] = true
		end

		if type(playerList.RemoveValue) == "function" and type(playerList.AddValue) == "function" then
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
			local current = library.flags["Gakuran PS Target"]
			if type(current) ~= "string" or not keep[current] then
				if type(playerList.SetValue) == "function" then
					pcall(function()
						playerList:SetValue(labels[1], true)
					end)
				else
					library.flags["Gakuran PS Target"] = labels[1]
					playerList.value = labels[1]
				end
			end
		end
	end

	local function withTarget(fn)
		local uid = selectedUserId()
		if not uid then
			notify("Pick a player first", 2)
			return
		end
		local plr = playerByUserId(uid)
		if not plr then
			notify("Player left", 2)
			st.refresh()
			return
		end
		fn(plr)
	end

	actSec:AddButton({
		text = "Bring",
		callback = function()
			withTarget(function(plr)
				runAction("Bring", plr, "Bring")
			end)
		end,
	})
	actSec:AddButton({
		text = "Goto",
		callback = function()
			withTarget(function(plr)
				runAction("Goto", plr, "Goto")
			end)
		end,
	})
	actSec:AddButton({
		text = "Heal",
		callback = function()
			withTarget(function(plr)
				runAction("Heal", plr, "Heal")
			end)
		end,
	})
	actSec:AddButton({
		text = "Respawn",
		callback = function()
			withTarget(function(plr)
				runAction("Respawn", plr, "Respawn")
			end)
		end,
	})

	bulkSec:AddButton({
		text = "Heal All",
		callback = function()
			runBulk("HealAll", "Heal All")
		end,
	})
	bulkSec:AddButton({
		text = "Bring All",
		callback = function()
			runBulk("BringAll", "Bring All")
		end,
	})
	bulkSec:AddButton({
		text = "Respawn All",
		callback = function()
			runBulk("RespawnAll", "Respawn All")
		end,
	})

	local function setup()
		task.defer(function()
			if ctx.state.unloading then
				return
			end
			pcall(st.refresh)
			-- one quiet owner probe (may heal you if authorized — rare)
			task.delay(1.2, function()
				if ctx.state.unloading then
					return
				end
				pcall(function()
					refreshOwnerStatus()
					st.refresh()
				end)
			end)
		end)

		if type(ctx.addConnection) == "function" then
			ctx.addConnection(Players.PlayerAdded, function()
				task.defer(function()
					pcall(st.refresh)
				end)
			end)
			ctx.addConnection(Players.PlayerRemoving, function()
				task.defer(function()
					pcall(st.refresh)
				end)
			end)
		end
	end

	if type(library.AddCleanup) == "function" then
		library:AddCleanup(function()
			table.clear(st.nameToUserId)
		end)
	end

	return { setup = setup }
end
