--[[
    xanhub | gakuran | ps_tools

    Wraps the game's private-server OwnerCommands remote (same path as
    CommandsScreenGui SERVER OPS → Bring / Goto / Heal / Respawn).

      CommandsServiceClient:Invoke(action, { TargetUserId = userId })
      OwnerCommands RemoteFunction under ReplicatedStorage.Remotes

    Only useful when HasPanelAccess / private-server owner tools are available.
    Does not invent admin powers — just mirrors the stock panel.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players or game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = ctx.LocalPlayer or Players.LocalPlayer

	if type(ctx.state.psTools) ~= "table" then
		ctx.state.psTools = {}
	end
	local st = ctx.state.psTools
	st.nameToUserId = st.nameToUserId or {}
	st.service = nil

	local statusSec = columns.psLeft:AddSection("Access")
	ctx.refs.psAccess = statusSec:AddLabel("Access: checking…")
	ctx.refs.psHint = statusSec:AddLabel("Uses game OwnerCommands (stock VIP tools)")

	local listSec = columns.psLeft:AddSection("Players")
	local playerList = listSec:AddList({
		text = "Target",
		flag = "Gakuran PS Target",
		values = { "(none)" },
		value = "(none)",
		max = 8,
		tip = "Select a player, then use actions on the right",
	})
	listSec:AddButton({
		text = "Refresh List",
		callback = function()
			if st.refresh then
				st.refresh()
			end
		end,
	})

	local actSec = columns.psRight:AddSection("Actions")
	actSec:AddLabel("Same as SERVER OPS panel")

	local bulkSec = columns.psRight:AddSection("Everyone")
	bulkSec:AddLabel("Server-wide (owner panel)")

	-- Resolve CommandsServiceClient (preferred) or raw remote ----------------

	local function findLoaded(name)
		if type(getloadedmodules) ~= "function" then
			return nil
		end
		local ok, modules = pcall(getloadedmodules)
		if not ok or type(modules) ~= "table" then
			return nil
		end
		for _, m in ipairs(modules) do
			if m and m.Name == name then
				local rok, result = pcall(require, m)
				if rok and type(result) == "table" then
					return result
				end
			end
		end
		return nil
	end

	local function getClient()
		if type(st.service) == "table" and type(st.service.Invoke) == "function" then
			return st.service
		end
		local mod = findLoaded("CommandsServiceClient")
		if type(mod) == "table" then
			local client = mod
			if type(mod.Get) == "function" then
				local ok, got = pcall(function()
					return mod:Get()
				end)
				if ok and type(got) == "table" then
					client = got
				end
			end
			if type(client.Invoke) == "function" then
				st.service = client
				return client
			end
		end
		return nil
	end

	local function getRemote()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local rf = remotes and remotes:FindFirstChild("OwnerCommands")
		if rf and rf:IsA("RemoteFunction") then
			return rf
		end
		return nil
	end

	local function hasAccess()
		local client = getClient()
		if client then
			if type(client.HasPanelAccess) == "function" then
				local ok, v = pcall(function()
					return client:HasPanelAccess()
				end)
				if ok and v == true then
					return true, "panel"
				end
			end
			if type(client.IsPrivateServerOwner) == "function" then
				local ok, v = pcall(function()
					return client:IsPrivateServerOwner()
				end)
				if ok and v == true then
					return true, "ps-owner"
				end
			end
			if type(client.IsOwner) == "function" then
				local ok, v = pcall(function()
					return client:IsOwner()
				end)
				if ok and v == true then
					return true, "owner"
				end
			end
		end
		-- Remote present in VIP session even if client methods fail
		if getRemote() and game.PrivateServerId ~= "" then
			return true, "remote"
		end
		return false, "none"
	end

	local function invoke(action, payload)
		payload = type(payload) == "table" and payload or {}
		local client = getClient()
		if client and type(client.Invoke) == "function" then
			local ok, res = pcall(function()
				return client:Invoke(action, payload)
			end)
			if ok then
				return res
			end
			return { ok = false, error = tostring(res) }
		end
		local rf = getRemote()
		if not rf then
			return { ok = false, error = "OwnerCommands missing" }
		end
		local ok, res = pcall(function()
			return rf:InvokeServer(action, payload)
		end)
		if ok then
			return res
		end
		return { ok = false, error = tostring(res) }
	end

	local function resultOk(res)
		if type(res) == "table" then
			if res.ok == true then
				return true, res
			end
			if res.ok == false then
				return false, res
			end
			-- some actions return bare tables
			return true, res
		end
		if res == true or res == nil then
			return true, res
		end
		return false, res
	end

	local function notifyResult(action, res)
		local ok, body = resultOk(res)
		if ok then
			ctx.notify(action .. " ✓", 2)
		else
			local msg = "failed"
			if type(body) == "table" then
				msg = tostring(body.error or body.message or body.err or "failed")
			elseif body ~= nil then
				msg = tostring(body)
			end
			ctx.notify(action .. " ✗ " .. msg:sub(1, 48), 3)
		end
	end

	local function playerLabel(plr)
		if not plr then
			return nil
		end
		local display = plr.DisplayName
		local name = plr.Name
		if display and display ~= "" and display ~= name then
			return string.format("%s (@%s)", display, name)
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
		-- fallback: match by name substring
		for _, plr in ipairs(Players:GetPlayers()) do
			if playerLabel(plr) == value or plr.Name == value or plr.DisplayName == value then
				return plr.UserId
			end
		end
		return nil
	end

	function st.refresh()
		local allowed, why = hasAccess()
		if ctx.refs.psAccess then
			ctx.refs.psAccess.Text = allowed and ("Access: yes · " .. tostring(why)) or "Access: no (need VIP / panel perms)"
		end

		if not playerList then
			return
		end

		-- rebuild values
		local labels = {}
		table.clear(st.nameToUserId)
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)
		for _, plr in ipairs(players) do
			local label = playerLabel(plr)
			if label then
				labels[#labels + 1] = label
				st.nameToUserId[label] = plr.UserId
			end
		end
		if #labels == 0 then
			labels[1] = "(none)"
		end

		-- remove old entries not in list
		local keep = {}
		for _, v in ipairs(labels) do
			keep[v] = true
		end
		local existing = {}
		for _, v in ipairs(playerList.values) do
			existing[#existing + 1] = v
		end
		for _, v in ipairs(existing) do
			if not keep[v] then
				pcall(function()
					playerList:RemoveValue(v)
				end)
			end
		end
		for _, v in ipairs(labels) do
			if not playerList.labels or not playerList.labels[v] then
				pcall(function()
					playerList:AddValue(v)
				end)
			end
		end

		local current = library.flags["Gakuran PS Target"]
		if type(current) ~= "string" or not keep[current] then
			pcall(function()
				playerList:SetValue(labels[1], true)
			end)
		end
	end

	local function runOnTarget(action, label)
		local allowed = hasAccess()
		if not allowed then
			ctx.notify("No private-server panel access", 3)
			return
		end
		local uid = selectedUserId()
		if not uid then
			ctx.notify("Pick a player first", 2)
			return
		end
		local res = invoke(action, { TargetUserId = uid })
		notifyResult(label or action, res)
	end

	local function runBulk(action, label)
		local allowed = hasAccess()
		if not allowed then
			ctx.notify("No private-server panel access", 3)
			return
		end
		local res = invoke(action, {})
		notifyResult(label or action, res)
	end

	actSec:AddButton({
		text = "Bring",
		callback = function()
			runOnTarget("Bring", "Bring")
		end,
	})
	actSec:AddButton({
		text = "Goto",
		callback = function()
			runOnTarget("TeleportTo", "Goto")
		end,
	})
	actSec:AddButton({
		text = "Heal",
		callback = function()
			runOnTarget("Heal", "Heal")
		end,
	})
	actSec:AddButton({
		text = "Respawn",
		callback = function()
			runOnTarget("Respawn", "Respawn")
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
		st.refresh()

		ctx.addConnection(Players.PlayerAdded, function()
			task.defer(st.refresh)
		end)
		ctx.addConnection(Players.PlayerRemoving, function()
			task.defer(st.refresh)
		end)

		-- light access refresh
		task.spawn(function()
			while not ctx.state.unloading do
				task.wait(4)
				local allowed, why = hasAccess()
				if ctx.refs.psAccess then
					ctx.refs.psAccess.Text = allowed and ("Access: yes · " .. tostring(why))
						or "Access: no (need VIP / panel perms)"
				end
			end
		end)
	end

	library:AddCleanup(function()
		st.service = nil
		table.clear(st.nameToUserId)
	end)

	return { setup = setup }
end
