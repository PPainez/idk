--[[
    xanhub | gakuran | ps_tools

    Mirrors VIP SERVER OPS via the stock remote only:

      ReplicatedStorage.Remotes.OwnerCommands:InvokeServer(action, payload)

    Never require() game ModuleScripts (CommandsServiceClient etc.) — that can
    taint the executor thread with Plugin capability and break all later
    Instance access (UI labels, notifications, devtools).
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players or game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

	local statusSec = columns.psLeft:AddSection("Access")
	ctx.refs.psAccess = statusSec:AddLabel("Access: checking...")
	statusSec:AddLabel("Stock OwnerCommands remote (no game require)")

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
	actSec:AddLabel("Same as SERVER OPS panel")

	local bulkSec = columns.psRight:AddSection("Everyone")
	bulkSec:AddLabel("Server-wide")

	local function setAccessText(text)
		pcall(function()
			if ctx.refs.psAccess then
				ctx.refs.psAccess.Text = "Access: " .. tostring(text)
			end
		end)
	end

	local function getRemote()
		local ok, rf = pcall(function()
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if not remotes then
				return nil
			end
			local remote = remotes:FindFirstChild("OwnerCommands")
			if remote and remote:IsA("RemoteFunction") then
				return remote
			end
			return nil
		end)
		if ok then
			return rf
		end
		return nil
	end

	local function hasAccess()
		local rf = getRemote()
		if not rf then
			return false, "no OwnerCommands remote"
		end
		-- VIP / reserved server
		local psId = ""
		pcall(function()
			psId = tostring(game.PrivateServerId or "")
		end)
		if psId ~= "" then
			return true, "vip remote"
		end
		-- Panel UI present (owner/mod tools loaded)
		local hasUi = false
		pcall(function()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			hasUi = pg ~= nil and pg:FindFirstChild("CommandsScreenGui") ~= nil
		end)
		if hasUi then
			return true, "panel ui"
		end
		-- Remote exists — allow attempt; server rejects if unauthorized
		return true, "remote"
	end

	local function invoke(action, payload)
		payload = type(payload) == "table" and payload or {}
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

	local function notifyResult(action, res)
		local ok = false
		local msg = "failed"
		if type(res) == "table" then
			if res.ok == true then
				ok = true
			elseif res.ok == false then
				msg = tostring(res.error or res.message or res.err or "denied")
			else
				ok = true -- unknown shape, treat as success
			end
		elseif res == true or res == nil then
			ok = true
		else
			msg = tostring(res)
		end
		if ok then
			ctx.notify(tostring(action) .. " ok", 2)
		else
			ctx.notify(tostring(action) .. " " .. msg:sub(1, 48), 3)
		end
	end

	local function playerLabel(plr)
		if typeof(plr) ~= "Instance" then
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
		local list = Players:GetPlayers()
		for i = 1, #list do
			local plr = list[i]
			local label = playerLabel(plr)
			if label == value then
				return plr.UserId
			end
			local n, d
			pcall(function()
				n = plr.Name
				d = plr.DisplayName
			end)
			if n == value or d == value then
				return plr.UserId
			end
		end
		return nil
	end

	function st.refresh()
		local allowed, why = hasAccess()
		setAccessText(allowed and ("yes · " .. tostring(why)) or ("no · " .. tostring(why)))

		if not playerList then
			return
		end

		local labels = {}
		st.nameToUserId = {}
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			local na, nb = "", ""
			pcall(function()
				na = string.lower(a.Name)
				nb = string.lower(b.Name)
			end)
			return na < nb
		end)
		for i = 1, #list do
			local plr = list[i]
			local label = playerLabel(plr)
			if label then
				labels[#labels + 1] = label
				local uid
				pcall(function()
					uid = plr.UserId
				end)
				if type(uid) == "number" then
					st.nameToUserId[label] = uid
				end
			end
		end
		if #labels == 0 then
			labels[1] = "(none)"
		end

		-- Only touch list UI if createList has finished (has labels table / AddValue that builds rows)
		local canMutate = type(playerList.AddValue) == "function"
			and type(playerList.RemoveValue) == "function"
			and type(playerList.values) == "table"

		if not canMutate then
			return
		end

		local keep = {}
		for i = 1, #labels do
			keep[labels[i]] = true
		end

		local existing = {}
		for i = 1, #playerList.values do
			existing[i] = playerList.values[i]
		end
		for i = 1, #existing do
			local v = existing[i]
			if not keep[v] then
				pcall(function()
					playerList:RemoveValue(v)
				end)
			end
		end
		for i = 1, #labels do
			local v = labels[i]
			local has = playerList.labels and playerList.labels[v]
			if not has then
				-- Pre-init AddValue only stores values; post-init creates rows
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

	local function runOnTarget(action, label)
		if not hasAccess() then
			ctx.notify("No OwnerCommands access", 3)
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
		if not hasAccess() then
			ctx.notify("No OwnerCommands access", 3)
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
		-- Defer refresh until list widgets exist post-Init
		task.defer(function()
			if ctx.state.unloading then
				return
			end
			pcall(st.refresh)
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

		task.spawn(function()
			while not ctx.state.unloading do
				task.wait(5)
				local allowed, why = hasAccess()
				setAccessText(allowed and ("yes · " .. tostring(why)) or ("no · " .. tostring(why)))
			end
		end)
	end

	if type(library.AddCleanup) == "function" then
		library:AddCleanup(function()
			table.clear(st.nameToUserId)
		end)
	end

	return { setup = setup }
end
