--[[
    xanhub | gakuran | combat

    Auto Parry + rear Auto Dodge + Dodge M2 (forced back dash) + attack visualizers.
    Detects known combat attack animations on nearby players, then:
      - M2 (optional) → force back MoveDirection + Evasive.Evasive()
      - behind attacker → Evasive.Evasive()
      - otherwise → Block.Block() timed to PerfectBlockWindow (~0.125s)
    Visualizers: 3D world boxes on attacker (M1/M2/EHit) with charge fill synced to anim.

    Attack DB: games/gakuran/modules/attack_db.luau (+ live rebuild from style folders)
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local RunService = ctx.RunService
	local Workspace = ctx.Workspace or game:GetService("Workspace")
	local LocalPlayer = Players.LocalPlayer
	local Camera = Workspace.CurrentCamera

	-- Game-aligned attack colors (CombatConfig.Shared.M2HighlightColors / style accents)
	local KIND_COLORS = {
		M1 = Color3.fromRGB(255, 168, 62),
		M2 = Color3.fromRGB(222, 68, 68),
		EHit = Color3.fromRGB(255, 220, 90),
		default = Color3.fromRGB(180, 190, 210),
	}

	-- UI -----------------------------------------------------------------

	local parry = columns.combatLeft:AddSection("Auto Parry")
	parry:AddToggle({
		text = "Auto Parry",
		flag = "Gakuran Auto Parry",
		state = false,
		tip = "Timed block on known M1/M2/EHit animations",
	})
	parry:AddSlider({
		text = "Reaction Offset",
		flag = "Gakuran Reaction Offset",
		min = -100,
		max = 250,
		value = 40,
		float = 5,
		suffix = " ms",
		tip = "Positive = block later (safer). Negative = earlier.",
	})
	parry:AddSlider({
		text = "Range Pre-filter",
		flag = "Gakuran Range Prefilter",
		min = 4,
		max = 40,
		value = 14,
		float = 1,
		suffix = " studs",
	})
	parry:AddSlider({
		text = "Hold Block",
		flag = "Gakuran Parry Hold",
		min = 40,
		max = 250,
		value = 110,
		float = 5,
		suffix = " ms",
		tip = "How long to hold block after press (≈ perfect window)",
	})
	parry:AddToggle({
		text = "Use Builder Profiles",
		flag = "Gakuran Use Parry Profiles",
		state = true,
		tip = "Prefer hitDelay/window from Parry Builder saved profiles",
	})
	parry:AddToggle({
		text = "No Parry Cooldown",
		flag = "Gakuran No Parry Cooldown",
		state = false,
		tip = "Clears BlockCooldown attribute when present",
	})
	parry:AddToggle({
		text = "Stay Equipped",
		flag = "Gakuran Stay Equipped",
		state = false,
		tip = "Keeps combat stance attribute equipped when possible",
	})
	parry:AddToggle({
		text = "Ping Compensation",
		flag = "Gakuran Parry Ping Comp",
		state = true,
		tip = "Starts block earlier by ~avg RTT/2 so the server sees the parry in time",
	})
	parry:AddSlider({
		text = "Ping Comp Strength",
		flag = "Gakuran Parry Ping Strength",
		min = 0,
		max = 100,
		value = 85,
		float = 5,
		suffix = "%",
		tip = "How much of measured ping is applied (100% ≈ full one-way lag)",
	})
	ctx.refs.combatPingLabel = parry:AddLabel("Ping: —")

	local dodge = columns.combatRight:AddSection("Dodge")
	dodge:AddToggle({
		text = "Auto Dodge",
		flag = "Gakuran Auto Dodge",
		state = false,
		tip = "Evasive dash when attacker is behind you",
	})
	dodge:AddSlider({
		text = "Rear Angle",
		flag = "Gakuran Dodge Rear Angle",
		min = 90,
		max = 180,
		value = 115,
		float = 5,
		suffix = "°",
		tip = "Half-angle behind look vector that counts as rear",
	})
	dodge:AddSlider({
		text = "Dodge Range",
		flag = "Gakuran Dodge Range",
		min = 4,
		max = 30,
		value = 12,
		float = 1,
		suffix = " studs",
	})
	dodge:AddToggle({
		text = "Dodge Fallback",
		flag = "Gakuran Dodge Fallback",
		state = false,
		tip = "If parry fails while stunned, try evasive",
	})
	dodge:AddToggle({
		text = "Dodge M2",
		flag = "Gakuran Dodge M2",
		state = false,
		tip = "Back-dash (Evasive DashBack) when someone M2s you",
	})
	dodge:AddSlider({
		text = "M2 Dodge Range",
		flag = "Gakuran M2 Dodge Range",
		min = 4,
		max = 28,
		value = 14,
		float = 1,
		suffix = " studs",
	})
	dodge:AddSlider({
		text = "M2 Dodge Early",
		flag = "Gakuran M2 Dodge Early",
		min = 0,
		max = 250,
		value = 90,
		float = 5,
		suffix = " ms",
		tip = "How early before M2 hitbox to dash (higher = safer escape)",
	})
	dodge:AddLabel("Front → parry · rear → dodge · M2 → back-dash")

	local viz = columns.combatLeft:AddSection("Combat Visualizer")
	viz:AddToggle({
		text = "Attack Visualizer",
		flag = "Gakuran Combat Visualizer",
		state = false,
		tip = "3D world boxes attached to attackers (M1/M2/EHit) that charge with the hit",
	})
	viz:AddToggle({
		text = "Show M1",
		flag = "Gakuran Viz M1",
		state = true,
		tip = "Orange 3D box on light attacks",
	})
	viz:AddToggle({
		text = "Show M2",
		flag = "Gakuran Viz M2",
		state = true,
		tip = "Red 3D box on heavies",
	})
	viz:AddToggle({
		text = "Show EHit",
		flag = "Gakuran Viz EHit",
		state = true,
		tip = "Yellow 3D box on extended hits",
	})
	viz:AddSlider({
		text = "Viz Range",
		flag = "Gakuran Viz Range",
		min = 8,
		max = 60,
		value = 28,
		float = 1,
		suffix = " studs",
	})
	viz:AddSlider({
		text = "Box Opacity",
		flag = "Gakuran Viz Opacity",
		min = 10,
		max = 90,
		value = 45,
		float = 5,
		suffix = "%",
		tip = "How solid the 3D charge fill is at full charge",
	})
	viz:AddToggle({
		text = "Highlight Character",
		flag = "Gakuran Viz Highlight",
		state = true,
		tip = "Also tint attacker with game-style M1/M2 colors",
	})
	viz:AddLabel("3D shell + charge fill welded to torso")

	local dbSec = columns.combatRight:AddSection("Attack Database")
	ctx.refs.combatDbLabel = dbSec:AddLabel("DB: loading…")
	dbSec:AddButton({
		text = "Rebuild Attack DB",
		callback = function()
			if ctx.state.combat and ctx.state.combat.db then
				local n = ctx.state.combat.db:rebuild()
				if ctx.refs.combatDbLabel then
					ctx.refs.combatDbLabel.Text = "DB: " .. tostring(n) .. " attack anims"
				end
				ctx.notify("Attack DB rebuilt: " .. tostring(n), 2)
			end
		end,
	})
	dbSec:AddButton({
		text = "Print DB Summary",
		callback = function()
			local db = ctx.state.combat and ctx.state.combat.db
			if not db then
				return
			end
			local kinds = {}
			for _, e in pairs(db.byId) do
				kinds[e.kind] = (kinds[e.kind] or 0) + 1
			end
			print("[xanhub combat DB]", db.count, "entries", kinds)
			ctx.notify("Printed DB summary to console", 2)
		end,
	})

	local debugSection = columns.combatRight:AddSection("Debug")
	debugSection:AddToggle({
		text = "Combat Debug Logs",
		flag = "Gakuran Combat Debug Logs",
		state = false,
		tip = "Toasts/prints for combat attacks only (not walk/run/idle)",
	})
	debugSection:AddToggle({
		text = "Log Unknown Combat Anims",
		flag = "Gakuran Combat Log Unknown",
		state = true,
		tip = "When debug is on, log combat-looking anims missing from the DB",
	})
	debugSection:AddToggle({
		text = "Parry Unknown Combat Anims",
		flag = "Gakuran Parry Unknown Combat",
		state = true,
		tip = "If name looks like M1/M2/Hit/etc but ID is not in DB, still parry with default timing",
	})
	ctx.refs.combatStatus = debugSection:AddLabel("Status: idle")

	-- State --------------------------------------------------------------

	if type(ctx.state.combat) ~= "table" then
		ctx.state.combat = {}
	end
	local st = ctx.state.combat
	st.hooks = type(st.hooks) == "table" and st.hooks or {}
	st.pending = type(st.pending) == "table" and st.pending or {}
	st.lastParryAt = 0
	st.lastDodgeAt = 0
	st.db = nil
	st.pingSamples = {}
	st.avgPingMs = 0
	st.pingSampleAt = 0
	st.vizEntries = type(st.vizEntries) == "table" and st.vizEntries or {}
	st.vizFolder = st.vizFolder

	-- Helpers ------------------------------------------------------------

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function numFlag(name, default)
		return tonumber(library.flags[name]) or default
	end

	local function debugLog(...)
		if flag("Gakuran Combat Debug Logs", false) then
			print("[xanhub combat]", ...)
		end
	end

	local function setStatus(text)
		pcall(function()
			if ctx.refs.combatStatus then
				ctx.refs.combatStatus.Text = "Status: " .. tostring(text)
			end
		end)
	end

	local function combatToast(typeName, title, message, key)
		if not flag("Gakuran Combat Debug Logs", false) then
			return
		end
		local body = string.format("[%s] %s", tostring(title or "Combat"), tostring(message or ""))
		debugLog(body)

		local sent = false
		if type(ctx.toast) == "function" then
			sent = ctx.toast(typeName or "info", message, {
				title = title or "Combat",
				channel = "combat",
				key = key,
				duration = 2.6,
				group = true,
				replace = true,
			}) == true
		end

		-- Fallback only — avoid double fire (Plugin parent warn spam on every parry).
		if not sent and library and type(library.SendNotification) == "function" and library.base then
			local ok = pcall(function()
				library:SendNotification(2.4, body:gsub("\n", " · "))
			end)
			sent = ok
		end

		if not sent then
			print("[xanhub combat]", body)
		end
	end

	local function samplePingMs()
		local ms = nil
		pcall(function()
			if type(LocalPlayer.GetNetworkPing) == "function" then
				-- GetNetworkPing returns seconds (RTT).
				ms = (LocalPlayer:GetNetworkPing() or 0) * 1000
			end
		end)
		if not ms or ms <= 0 then
			pcall(function()
				local stats = game:GetService("Stats")
				local item = stats.Network.ServerStatsItem["Data Ping"]
				if item and item.GetValueString then
					local text = item:GetValueString()
					ms = tonumber((tostring(text):match("([%d%.]+)")))
				elseif item and item.GetValue then
					ms = tonumber(item:GetValue())
				end
			end)
		end
		if type(ms) ~= "number" or ms ~= ms or ms < 0 then
			return st.avgPingMs or 0
		end
		-- Clamp absurd spikes from executor/stats glitches.
		ms = math.clamp(ms, 0, 500)

		local samples = st.pingSamples
		table.insert(samples, ms)
		while #samples > 12 do
			table.remove(samples, 1)
		end
		local sum = 0
		for _, value in ipairs(samples) do
			sum = sum + value
		end
		st.avgPingMs = sum / math.max(#samples, 1)
		return st.avgPingMs
	end

	local function pingCompensationSeconds()
		if not flag("Gakuran Parry Ping Comp", true) then
			return 0, st.avgPingMs or 0
		end
		local avgMs = samplePingMs()
		local strength = math.clamp(numFlag("Gakuran Parry Ping Strength", 85), 0, 100) / 100
		-- One-way lag approximation from RTT.
		local oneWay = (avgMs / 1000) * 0.5 * strength
		return oneWay, avgMs
	end

	local function findLoaded(name)
		if type(getloadedmodules) ~= "function" then
			return nil
		end
		local ok, modules = pcall(getloadedmodules)
		if not ok or type(modules) ~= "table" then
			return nil
		end
		for _, moduleScript in ipairs(modules) do
			if moduleScript and moduleScript.Name == name then
				local reqOk, result = pcall(require, moduleScript)
				if reqOk and type(result) == "table" then
					return result
				end
			end
		end
		return nil
	end

	local function getBlockApi()
		return findLoaded("Block")
	end

	local function getEvasiveApi()
		return findLoaded("Evasive")
	end

	local function getCharacter(player)
		if not player then
			return nil
		end
		local character = player.Character
		if character and character.Parent then
			return character
		end
		-- Gakuran keeps rigs under Workspace.Players.<Name>
		local folder = Workspace:FindFirstChild("Players")
		if folder then
			local named = folder:FindFirstChild(player.Name)
			if named and named:FindFirstChildOfClass("Humanoid") then
				return named
			end
		end
		return character
	end

	local function getRoot(character)
		if not character then
			return nil
		end
		-- R6: Torso is the reliable root. Some rigs also have HumanoidRootPart.
		return character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("UpperTorso")
			or character.PrimaryPart
	end

	local function getLocalRoot()
		return getRoot(getCharacter(LocalPlayer) or LocalPlayer.Character)
	end

	local function isBehind(localRoot, attackerRoot, rearAngleDeg)
		if not localRoot or not attackerRoot then
			return false
		end
		local toAttacker = attackerRoot.Position - localRoot.Position
		local flat = Vector3.new(toAttacker.X, 0, toAttacker.Z)
		if flat.Magnitude < 0.05 then
			return false
		end
		-- Prefer humanoid move direction when available (more reliable on R6).
		local look = Vector3.new(localRoot.CFrame.LookVector.X, 0, localRoot.CFrame.LookVector.Z)
		local character = localRoot.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
			look = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
		end
		if look.Magnitude < 0.05 then
			return false
		end
		local dot = look.Unit:Dot(flat.Unit)
		-- rearAngle 115° → behind if angle from look > rearAngle
		local threshold = math.cos(math.rad(rearAngleDeg))
		return dot <= threshold
	end

	local function clearBlockCooldown(character)
		if not flag("Gakuran No Parry Cooldown", false) then
			return
		end
		if not character then
			return
		end
		pcall(function()
			character:SetAttribute("BlockCooldown", nil)
		end)
	end

	local function stayEquipped(character)
		if not flag("Gakuran Stay Equipped", false) then
			return
		end
		if not character then
			return
		end
		pcall(function()
			if character:GetAttribute("Equip") == false then
				character:SetAttribute("Equip", true)
			end
		end)
	end

	local function profileOverride(animId, animName)
		if not flag("Gakuran Use Parry Profiles", true) then
			return nil
		end
		local profiles = ctx.state.parry and ctx.state.parry.profiles
		if type(profiles) ~= "table" then
			return nil
		end
		local id = tostring(animId or "")
		for _, profile in pairs(profiles) do
			if type(profile) == "table" and profile.enabled ~= false then
				local pid = tostring(profile.animationId or profile.id or "")
				if pid ~= "" and (pid == id or id:find(pid, 1, true) or pid:find(id, 1, true)) then
					return profile
				end
				if animName and profile.animationName == animName then
					return profile
				end
			end
		end
		return nil
	end

	local function doParry(entry)
		local blockApi = getBlockApi()
		if not blockApi or type(blockApi.Block) ~= "function" then
			debugLog("Block API missing")
			setStatus("Block module not loaded")
			return
		end

		local character = getCharacter(LocalPlayer) or LocalPlayer.Character
		clearBlockCooldown(character)
		stayEquipped(character)

		local ok, err = pcall(blockApi.Block)
		if not ok then
			debugLog("Block failed", err)
			setStatus("parry failed")
			return
		end

		st.lastParryAt = os.clock()
		local statusText = string.format(
			"parried %s (%s)",
			tostring(entry.name or "?"),
			tostring(entry.kind or "?")
		)
		setStatus(statusText)
		debugLog("parry", entry.name, entry.kind, entry.hitDelay, entry._from or "")
		combatToast("success", "Auto Parry", string.format(
			"%s · %s · %s\nwait %.0fms · ping %.0fms%s",
			tostring(entry.name or "attack"),
			tostring(entry.kind or "?"),
			tostring(entry._attackerName or "enemy"),
			(tonumber(entry._waitMs) or 0),
			(tonumber(entry._pingMs) or st.avgPingMs or 0),
			entry._pingComp and " · ping-comp" or ""
		), "combat-parry")

		local hold = math.clamp(numFlag("Gakuran Parry Hold", 110), 40, 250) / 1000
		task.delay(hold, function()
			local unblock = getBlockApi()
			if unblock and type(unblock.Unblock) == "function" then
				pcall(unblock.Unblock)
			end
		end)
	end

	local function combatFeaturesOn()
		return flag("Gakuran Auto Parry", false)
			or flag("Gakuran Auto Dodge", false)
			or flag("Gakuran Dodge M2", false)
			or flag("Gakuran Combat Visualizer", false)
	end

	local function isM2Entry(entry)
		if type(entry) ~= "table" then
			return false
		end
		if entry.kind == "M2" then
			return true
		end
		local name = tostring(entry.name or "")
		return name:find("M2", 1, true) ~= nil
			or name:find("Momentum", 1, true) ~= nil
			or name:find("GrappleAttacker", 1, true) ~= nil
			or name:find("DirtyAttacker", 1, true) ~= nil
	end

	local function kindColor(kind, name)
		if isM2Entry({ kind = kind, name = name }) then
			return KIND_COLORS.M2
		end
		if kind == "EHit" or (type(name) == "string" and name:find("EHit", 1, true)) then
			return KIND_COLORS.EHit
		end
		if kind == "M1" then
			return KIND_COLORS.M1
		end
		return KIND_COLORS.default
	end

	local function forceBackMove(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = getRoot(character)
		if not humanoid or not root then
			return function() end
		end
		-- Evasive uses MoveDirection; zero → DashBack, else we force world-space back.
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local back = look.Magnitude > 0.05 and -look.Unit or Vector3.new(0, 0, 1)
		pcall(function()
			humanoid:Move(back, false)
		end)
		return function()
			pcall(function()
				humanoid:Move(Vector3.zero, false)
			end)
		end
	end

	local function doDodge(reason, meta, opts)
		opts = type(opts) == "table" and opts or {}
		local evasive = getEvasiveApi()
		if not evasive or type(evasive.Evasive) ~= "function" then
			debugLog("Evasive API missing")
			setStatus("Evasive module not loaded")
			return false
		end
		if type(evasive.IsDashActive) == "function" then
			local active = false
			pcall(function()
				active = evasive.IsDashActive() == true
			end)
			if active then
				return false
			end
		end

		local character = getCharacter(LocalPlayer) or LocalPlayer.Character
		-- Evasive refuses while Blocking / attacking.
		if character and character:GetAttribute("Blocking") then
			local blockApi = getBlockApi()
			if blockApi and type(blockApi.Unblock) == "function" then
				pcall(blockApi.Unblock)
			end
		end

		local restoreMove = nil
		if opts.forceBack then
			restoreMove = forceBackMove(character)
		end

		local ok, err = pcall(evasive.Evasive)
		if restoreMove then
			-- Keep back input for a frame so LinearVelocity samples MoveDirection.
			task.delay(0.05, restoreMove)
		end

		if ok then
			st.lastDodgeAt = os.clock()
			setStatus("dodged · " .. tostring(reason or "rear"))
			debugLog("dodge", reason, opts.forceBack and "back" or "")
			meta = type(meta) == "table" and meta or {}
			combatToast("info", opts.forceBack and "Dodge M2" or "Auto Dodge", string.format(
				"%s · %s\n%s",
				tostring(meta.name or reason or "rear"),
				tostring(meta.attackerName or meta._attackerName or "enemy"),
				tostring(reason or "rear attack")
			), opts.forceBack and "combat-dodge-m2" or "combat-dodge")
			return true
		end

		debugLog("dodge failed", err)
		return false
	end

	-- 3D Visualizer (world-space boxes attached to attacker character) ----

	local function getVizWorldFolder()
		if st.vizFolder and st.vizFolder.Parent then
			return st.vizFolder
		end
		local folder = Workspace:FindFirstChild("XanhubCombatViz3D")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "XanhubCombatViz3D"
			local ok = pcall(function()
				folder.Parent = Workspace
			end)
			if not ok then
				return nil
			end
		end
		st.vizFolder = folder
		return folder
	end

	local function makeGhostPart(name, color)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		-- Neon reads better in-world than ForceField on some executors/graphics.
		part.Material = Enum.Material.Neon
		part.Color = color or KIND_COLORS.M1
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end

	local function destroyViz(userId)
		local entry = st.vizEntries[userId]
		if not entry then
			return
		end
		pcall(function()
			if entry.model then
				entry.model:Destroy()
			end
		end)
		pcall(function()
			if entry.highlight then
				entry.highlight:Destroy()
			end
		end)
		st.vizEntries[userId] = nil
	end

	local function characterBounds(character, root)
		local cf, size
		local ok = pcall(function()
			cf, size = character:GetBoundingBox()
		end)
		if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
			-- Pad slightly so the shell sits outside the mesh.
			local padded = Vector3.new(
				math.clamp(size.X + 0.9, 3.2, 7.5),
				math.clamp(size.Y + 0.6, 4.5, 8.5),
				math.clamp(size.Z + 0.9, 2.2, 5.5)
			)
			return cf, padded
		end
		-- R6 fallback around Torso / HRP
		local center = root.CFrame * CFrame.new(0, 0.35, 0)
		return center, Vector3.new(4.2, 5.6, 2.8)
	end

	local function ensureViz(attacker)
		local userId = attacker.UserId
		local existing = st.vizEntries[userId]
		if existing and existing.model and existing.model.Parent then
			return existing
		end

		local folder = getVizWorldFolder()
		if not folder then
			return nil
		end

		local model = Instance.new("Model")
		model.Name = "Viz3D_" .. attacker.Name
		model.Parent = folder

		local shell = makeGhostPart("Shell", KIND_COLORS.M1)
		shell.Transparency = 1
		shell.Parent = model

		local selection = Instance.new("SelectionBox")
		selection.Name = "Outline"
		selection.Adornee = shell
		selection.LineThickness = 0.08
		selection.SurfaceTransparency = 0.85
		selection.Color3 = KIND_COLORS.M1
		selection.Transparency = 0.05
		selection.Parent = shell

		-- Outer shell glass (faint volume so it reads in 3D, not just edges)
		local shellVolume = makeGhostPart("ShellVolume", KIND_COLORS.M1)
		shellVolume.Material = Enum.Material.ForceField
		shellVolume.Transparency = 0.82
		shellVolume.Parent = model

		local fill = makeGhostPart("ChargeFill", KIND_COLORS.M1)
		fill.Material = Enum.Material.Neon
		fill.Transparency = 0.55
		fill.Parent = model

		-- World billboard label above the 3D box
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(160, 28)
		billboard.StudsOffset = Vector3.new(0, 3.6, 0)
		billboard.MaxDistance = 90
		billboard.Adornee = shell
		billboard.Parent = shell

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.TextSize = 14
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.35
		label.Text = ""
		label.Parent = billboard

		local entry = {
			model = model,
			shell = shell,
			shellVolume = shellVolume,
			selection = selection,
			fill = fill,
			label = label,
			billboard = billboard,
			highlight = nil,
			track = nil,
			entry = nil,
			expires = 0,
			attacker = attacker,
			boxSize = Vector3.new(4.2, 5.6, 2.8),
		}
		st.vizEntries[userId] = entry
		return entry
	end

	local function kindAllowed(kind, name)
		if isM2Entry({ kind = kind, name = name }) then
			return flag("Gakuran Viz M2", true)
		end
		if kind == "EHit" or (type(name) == "string" and name:find("EHit", 1, true)) then
			return flag("Gakuran Viz EHit", true)
		end
		-- Default all remaining combat hits to M1 (1st–4th M1, etc.)
		return flag("Gakuran Viz M1", true)
	end

	local function applyVizColor(vizEntry, color)
		vizEntry.selection.Color3 = color
		vizEntry.shellVolume.Color = color
		vizEntry.fill.Color = color
		if vizEntry.highlight then
			vizEntry.highlight.FillColor = color
			vizEntry.highlight.OutlineColor = color
		end
	end

	local function startVisualizer(attacker, track, dbEntry)
		if not flag("Gakuran Combat Visualizer", false) then
			return
		end
		if not kindAllowed(dbEntry.kind, dbEntry.name) then
			return
		end
		local vizEntry = ensureViz(attacker)
		if not vizEntry then
			return
		end
		vizEntry.track = track
		vizEntry.entry = dbEntry
		vizEntry.expires = os.clock() + math.max(0.55, (tonumber(dbEntry.hitDelay) or 0.35) + 0.4)
		vizEntry.attacker = attacker

		local color = kindColor(dbEntry.kind, dbEntry.name)
		applyVizColor(vizEntry, color)
		vizEntry.label.Text = string.format(
			"%s · %s",
			tostring(dbEntry.name or "?"),
			tostring(dbEntry.kind or "?")
		)

		local character = getCharacter(attacker)
		if flag("Gakuran Viz Highlight", true) and character then
			if not vizEntry.highlight or not vizEntry.highlight.Parent then
				local hl = Instance.new("Highlight")
				hl.Name = "XanhubCombatVizHL"
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.FillTransparency = 0.8
				hl.OutlineTransparency = 0.25
				hl.Parent = character
				vizEntry.highlight = hl
			end
			vizEntry.highlight.Adornee = character
			vizEntry.highlight.FillColor = color
			vizEntry.highlight.OutlineColor = color
			vizEntry.highlight.Enabled = true
		elseif vizEntry.highlight then
			vizEntry.highlight.Enabled = false
		end
	end

	local function updateVisualizers()
		if not flag("Gakuran Combat Visualizer", false) then
			for userId in pairs(st.vizEntries) do
				destroyViz(userId)
			end
			return
		end

		local myRoot = getLocalRoot()
		local vizRange = numFlag("Gakuran Viz Range", 28)
		-- Opacity slider: 10–90% → transparency at full charge
		local solidAlpha = numFlag("Gakuran Viz Opacity", 45) / 100
		local fullFillTransparency = math.clamp(1 - solidAlpha, 0.08, 0.9)
		local now = os.clock()

		for userId, vizEntry in pairs(st.vizEntries) do
			local attacker = vizEntry.attacker
			local dbEntry = vizEntry.entry
			local track = vizEntry.track
			local character = attacker and getCharacter(attacker)
			local root = getRoot(character)

			local alive = attacker
				and attacker.Parent
				and character
				and root
				and dbEntry
				and vizEntry.model
				and vizEntry.model.Parent
				and now < (vizEntry.expires or 0)

			if alive and myRoot then
				local dist = (root.Position - myRoot.Position).Magnitude
				if dist > vizRange + 4 then
					alive = false
				end
			end

			if not alive then
				destroyViz(userId)
			else
				local hitDelay = math.max(0.08, tonumber(dbEntry.hitDelay) or 0.32)
				local elapsed = 0
				if track then
					pcall(function()
						elapsed = tonumber(track.TimePosition) or 0
					end)
				end
				local progress = math.clamp(elapsed / hitDelay, 0, 1)
				if elapsed >= hitDelay then
					progress = 1
				end

				local boxCf, boxSize = characterBounds(character, root)
				vizEntry.boxSize = boxSize

				-- Shell outline follows character orientation / bounding box.
				vizEntry.shell.Size = boxSize
				vizEntry.shell.CFrame = boxCf
				vizEntry.shell.Transparency = 1

				vizEntry.shellVolume.Size = boxSize
				vizEntry.shellVolume.CFrame = boxCf
				-- Volume ramps with charge so M1/M2 both read clearly in world.
				vizEntry.shellVolume.Transparency = 0.88 - progress * 0.18

				-- Charge fill grows from the feet upward inside the shell.
				local fillH = math.max(0.12, boxSize.Y * math.max(progress, 0.08))
				local fillSize = Vector3.new(
					math.max(0.35, boxSize.X - 0.25),
					fillH,
					math.max(0.35, boxSize.Z - 0.25)
				)
				vizEntry.fill.Size = fillSize
				vizEntry.fill.CFrame = boxCf * CFrame.new(0, -boxSize.Y * 0.5 + fillH * 0.5, 0)
				vizEntry.fill.Transparency = 0.75 - progress * (0.75 - fullFillTransparency)

				vizEntry.selection.Transparency = 0.2 - progress * 0.15
				vizEntry.billboard.StudsOffset = Vector3.new(0, boxSize.Y * 0.55 + 0.35, 0)
				vizEntry.label.Text = string.format(
					"%s %d%%",
					tostring(dbEntry.name or dbEntry.kind or "?"),
					math.floor(progress * 100 + 0.5)
				)

				if vizEntry.highlight and flag("Gakuran Viz Highlight", true) then
					vizEntry.highlight.Enabled = true
					vizEntry.highlight.FillTransparency = 0.88 - progress * 0.35
					vizEntry.highlight.OutlineTransparency = 0.4 - progress * 0.25
				end
			end
		end
	end

	local function styleHitDelay(attacker, dbEntry)
		local delay = tonumber(dbEntry and dbEntry.hitDelay) or 0.32
		local character = getCharacter(attacker)
		local style = nil
		if character then
			local pd = character:FindFirstChild("PlayerData")
			if pd then
				style = pd:GetAttribute("Style") or pd:GetAttribute("CombatStyle")
			end
		end
		if type(style) ~= "string" or style == "" then
			return delay
		end
		local key = string.lower(style)
		-- CombatConfig style base hitbox delays (live scrape).
		local styleM1 = {
			basic = 0.32,
			boxing = 0.32,
			capoeira = 0.33,
			hakari = 0.28,
			karate = 0.24,
			kure = 0.32,
			muaythai = 0.30,
			slugger = 0.20,
			striker = 0.32,
			wrestling = 0.32,
			default = 0.32,
		}
		local styleM2 = {
			basic = 0.525,
			boxing = 0.43,
			capoeira = 0.45,
			hakari = 0.59,
			karate = 0.4875,
			kure = 0.30,
			muaythai = 0.60,
			slugger = 0.82,
			striker = 0.30,
			wrestling = 0.525,
			default = 0.30,
		}
		local kind = dbEntry and dbEntry.kind
		local name = tostring(dbEntry and dbEntry.name or "")
		if kind == "M2" or name:find("M2", 1, true) or name:find("Crit", 1, true) then
			return styleM2[key] or delay
		end
		if kind == "EHit" or name:find("EHit", 1, true) then
			return delay
		end
		local base = styleM1[key] or delay
		if name:find("4th", 1, true) then
			return base + 0.03
		end
		return base
	end

	local function trackTime(track)
		local t = 0
		if track then
			pcall(function()
				t = tonumber(track.TimePosition) or 0
			end)
		end
		return t
	end

	local function attackerCombo(attacker)
		local character = getCharacter(attacker)
		if not character then
			return 0
		end
		return tonumber(character:GetAttribute("Combo")) or 0
	end

	local function attackerHoldingM1(attacker)
		local character = getCharacter(attacker)
		if not character then
			return false
		end
		return character:GetAttribute("M1Hold") == true
			or character:GetAttribute("CombatAttacking") == true
	end

	-- Hold-M1 reuses AnimationTrack instances / rewinds TimePosition.
	-- Key swings by anim + swing index so each punch in a held string can parry.
	local function swingKey(attacker, track, animId)
		st.swingState = st.swingState or {}
		local uid = attacker.UserId
		local ps = st.swingState[uid]
		if not ps then
			ps = {
				byTrack = setmetatable({}, { __mode = "k" }),
				lastCombo = -1,
			}
			st.swingState[uid] = ps
		end

		local tpos = trackTime(track)
		local combo = attackerCombo(attacker)
		local ts = ps.byTrack[track]
		if not ts then
			ts = { swing = 0, lastTime = tpos, lastCombo = combo }
			ps.byTrack[track] = ts
		end

		-- Track replayed (TimePosition went backwards) → new swing
		if tpos + 0.1 < (ts.lastTime or 0) then
			ts.swing = (ts.swing or 0) + 1
		end
		-- Combo attribute advanced (hold M1 1→2→3→4)
		if combo > 0 and combo ~= ts.lastCombo then
			if combo ~= ps.lastCombo then
				ts.swing = (ts.swing or 0) + 1
			end
		end
		ts.lastTime = tpos
		ts.lastCombo = combo
		ps.lastCombo = combo

		return string.format("%s:%s:%d:%d", tostring(uid), tostring(animId), ts.swing or 0, combo)
	end

	local function scheduleResponse(attacker, track, dbEntry)
		local animId = dbEntry.id
		local dedupe = swingKey(attacker, track, animId)
		if st.pending[dedupe] then
			startVisualizer(attacker, track, dbEntry)
			return
		end
		-- Short TTL handled set (replaces permanent track lock that broke hold combos)
		st.handledSwings = st.handledSwings or {}
		if st.handledSwings[dedupe] then
			startVisualizer(attacker, track, dbEntry)
			return
		end
		st.pending[dedupe] = true
		st.handledSwings[dedupe] = true
		task.delay(1.6, function()
			if st.handledSwings then
				st.handledSwings[dedupe] = nil
			end
		end)

		startVisualizer(attacker, track, dbEntry)

		-- Style-aware hitbox delay (slugger M1 ~0.2s, hakari ~0.45s, slugger M2 ~0.82s).
		local hitDelay = styleHitDelay(attacker, dbEntry)
		local window = tonumber(dbEntry.window) or 0.125
		local range = numFlag("Gakuran Range Prefilter", 14)
		local m2Attack = isM2Entry(dbEntry)

		local profile = profileOverride(animId, dbEntry.name)
		if profile then
			if profile.startupMs then
				hitDelay = (tonumber(profile.startupMs) or 0) / 1000
			end
			if profile.windowMs then
				window = (tonumber(profile.windowMs) or 125) / 1000
			end
			if profile.rangeStuds then
				range = tonumber(profile.rangeStuds) or range
			end
			debugLog("profile override", profile.name or profile.animationName)
		end

		-- Prefer remaining time from the live track when available.
		local elapsed = trackTime(track)
		local reaction = numFlag("Gakuran Reaction Offset", 40) / 1000
		local pingComp, pingMs = pingCompensationSeconds()

		-- M2 dodge fires earlier (escape before hitbox); parry aims for perfect window.
		local waitTime
		if m2Attack and flag("Gakuran Dodge M2", false) then
			local early = numFlag("Gakuran M2 Dodge Early", 90) / 1000
			waitTime = math.max(0, hitDelay - early - pingComp - elapsed)
		else
			local target = hitDelay - reaction - (window * 0.35) - pingComp
			waitTime = target - elapsed
			-- Late detect during hold string: still try if inside hitbox duration.
			if waitTime < 0 then
				if elapsed <= hitDelay + 0.14 then
					waitTime = 0
				else
					-- Too late for this swing — free the key so a replay can re-arm.
					st.pending[dedupe] = nil
					st.handledSwings[dedupe] = nil
					return
				end
			end
		end

		if flag("Gakuran Combat Debug Logs", false) then
			local hold = attackerHoldingM1(attacker)
			combatToast("debug", "Attack Seen", string.format(
				"%s · %s from %s%s\nbase %.0fms · wait %.0fms · ping %.0fms%s%s",
				tostring(dbEntry.name or "?"),
				tostring(dbEntry.kind or "?"),
				tostring(attacker.Name),
				hold and " · HOLD" or "",
				hitDelay * 1000,
				waitTime * 1000,
				pingMs,
				pingComp > 0 and string.format(" (−%.0fms)", pingComp * 1000) or "",
				m2Attack and flag("Gakuran Dodge M2", false) and " · m2-dodge" or ""
			), "combat-seen-" .. tostring(animId))
		end

		task.delay(waitTime, function()
			st.pending[dedupe] = nil
			if ctx.state.unloading then
				return
			end

			local autoParry = flag("Gakuran Auto Parry", false)
			local autoDodge = flag("Gakuran Auto Dodge", false)
			local dodgeM2 = flag("Gakuran Dodge M2", false)
			if not autoParry and not autoDodge and not dodgeM2 then
				return
			end

			-- Soft cooldown — very low so held M1 strings (1st→4th) all parry.
			local now = os.clock()
			local holdCd = attackerHoldingM1(attacker) and 0.03 or 0.045
			if autoParry and (now - (st.lastParryAt or 0)) < holdCd and not (dodgeM2 and m2Attack) then
				return
			end

			local myChar = getCharacter(LocalPlayer) or LocalPlayer.Character
			local myRoot = getRoot(myChar)
			local theirRoot = getRoot(getCharacter(attacker))
			if not myRoot or not theirRoot then
				return
			end

			local dist = (theirRoot.Position - myRoot.Position).Magnitude
			local m2Range = numFlag("Gakuran M2 Dodge Range", 14)
			local dodgeRange = numFlag("Gakuran Dodge Range", 12)
			local maxRange = math.max(range, dodgeRange, dodgeM2 and m2Range or 0)
			if dist > maxRange + 2 then
				debugLog("out of range", dist)
				return
			end

			local rearAngle = numFlag("Gakuran Dodge Rear Angle", 115)
			local behind = isBehind(myRoot, theirRoot, rearAngle)

			local entryMeta = {
				name = dbEntry.name,
				kind = dbEntry.kind,
				hitDelay = dbEntry.hitDelay,
				_attackerName = attacker.DisplayName or attacker.Name,
				attackerName = attacker.DisplayName or attacker.Name,
				_waitMs = waitTime * 1000,
				_pingMs = pingMs,
				_pingComp = pingComp > 0,
			}

			-- Priority 1: Dodge M2 with forced back dash (uses game DashBack when MoveDir ~ 0/back).
			if dodgeM2 and m2Attack and dist <= m2Range + 1 then
				if (now - (st.lastDodgeAt or 0)) >= 0.18 then
					doDodge("m2-back", entryMeta, { forceBack = true })
				end
				return
			end

			if autoDodge and behind and dist <= dodgeRange then
				if (now - (st.lastDodgeAt or 0)) >= 0.18 then
					doDodge(dbEntry.name or "rear", entryMeta)
				end
				return
			end

			if autoParry and dist <= range then
				if not behind or not autoDodge then
					doParry(entryMeta)
				end
				return
			end

			if flag("Gakuran Dodge Fallback", false) and autoDodge then
				local stunned = myChar
					and (myChar:GetAttribute("Stunned") == true or myChar:GetAttribute("CantAnything") == true)
				if stunned and (now - (st.lastDodgeAt or 0)) >= 0.18 then
					doDodge("fallback", entryMeta)
				end
			end
		end)
	end

	local function animNameOf(track)
		local anim = track and track.Animation
		if anim and type(anim.Name) == "string" and anim.Name ~= "" then
			return anim.Name
		end
		if type(track.Name) == "string" and track.Name ~= "" then
			return track.Name
		end
		return ""
	end

	local function isLocomotionName(name)
		name = string.lower(tostring(name or ""))
		if name == "" then
			return false
		end
		return name:find("walk", 1, true)
			or name:find("run", 1, true)
			or name:find("idle", 1, true)
			or name:find("jump", 1, true)
			or name:find("fall", 1, true)
			or name:find("climb", 1, true)
			or name:find("swim", 1, true)
			or name:find("sit", 1, true)
			or name:find("chill", 1, true)
			or name:find("lean", 1, true)
			or name:find("lay", 1, true)
			or name:find("sleep", 1, true)
			or name:find("lounge", 1, true)
			or name:find("dance", 1, true)
			or name:find("emote", 1, true)
			or name:find("toolnone", 1, true)
			or name:find("equipidle", 1, true)
			or name:find("backpedal", 1, true)
			or name:find("strum", 1, true)
	end

	local function looksLikeCombatName(name)
		name = tostring(name or "")
		if name == "" or isLocomotionName(name) then
			return false
		end
		local lower = string.lower(name)
		if lower:find("block", 1, true) and not lower:find("guardbreak", 1, true) and not lower:find("ehit", 1, true) then
			return false
		end
		if lower:find("parry", 1, true) then
			return false
		end
		if lower:find("guard", 1, true) and not lower:find("guardbreak", 1, true) then
			return false
		end
		return lower:find("m1", 1, true)
			or lower:find("m2", 1, true)
			or lower:find("ehit", 1, true)
			or lower:find("hit", 1, true)
			or lower:find("punch", 1, true)
			or lower:find("kick", 1, true)
			or lower:find("attack", 1, true)
			or lower:find("swing", 1, true)
			or lower:find("strike", 1, true)
			or lower:find("combo", 1, true)
			or lower:find("grapple", 1, true)
			or lower:find("throw", 1, true)
			or lower:find("momentum", 1, true)
			or lower:find("guardbreak", 1, true)
			or lower:find("crit", 1, true)
			or lower:find("grab", 1, true)
			or lower:find("slam", 1, true)
	end

	local function isActionPriority(track)
		local pri = nil
		pcall(function()
			pri = track.Priority
		end)
		if not pri then
			return false
		end
		-- Remote combat M1/M2 play as Action / Action2 / Action3 / Action4.
		return pri == Enum.AnimationPriority.Action
			or pri == Enum.AnimationPriority.Action2
			or pri == Enum.AnimationPriority.Action3
			or pri == Enum.AnimationPriority.Action4
	end

	local function classifyFallback(name)
		local lower = string.lower(tostring(name or ""))
		if lower:find("m2", 1, true) or lower:find("crit", 1, true) then
			return "M2", 0.40
		end
		if lower:find("ehit", 1, true) or lower:find("guardbreak", 1, true) then
			return "EHit", 0.30
		end
		if lower:find("4th", 1, true) then
			return "M1", 0.35
		end
		if lower:find("1st", 1, true) then
			return "M1", 0.30
		end
		if lower:find("2nd", 1, true) or lower:find("3rd", 1, true) then
			return "M1", 0.28
		end
		return "M1", 0.32
	end

	local function onAttackTrack(attacker, track)
		if ctx.state.unloading then
			return
		end
		if not combatFeaturesOn() then
			return
		end
		if attacker == LocalPlayer then
			return
		end
		if not track then
			return
		end

		-- Ignore non-playing tracks (hold strings leave spent tracks at end time).
		local playing = true
		pcall(function()
			playing = track.IsPlaying == true
		end)
		if not playing then
			return
		end

		local anim = track.Animation
		local name = animNameOf(track)
		local id = anim and anim.AnimationId
		if not id and type(track.AnimationId) == "string" then
			id = track.AnimationId
		end
		local pure = tostring(id or ""):match("%d+") or tostring(id or "")

		-- Drop walk/run/idle/emote/instrument IDs even when the track is named "Animation".
		local isLoco = isLocomotionName(name)
		if not isLoco and pure ~= "" and st.attackDbMod and type(st.attackDbMod.isLocomotionId) == "function" then
			isLoco = st.attackDbMod.isLocomotionId(pure)
		end
		if isLoco then
			return
		end

		local db = st.db
		if not db then
			return
		end

		-- Primary path: match by AnimationId (remote names are almost always "Animation").
		local entry = db:lookup(id)

		if not entry then
			local combatName = looksLikeCombatName(name)
			local actionPri = isActionPriority(track)
			local trackLen = 0
			pcall(function()
				trackLen = tonumber(track.Length) or 0
			end)
			local shortCombatLen = trackLen > 0.12 and trackLen < 1.85
			local allowActionGuess = actionPri
				and pure ~= ""
				and shortCombatLen
				and flag("Gakuran Parry Unknown Combat", true)

			if combatName or allowActionGuess then
				if flag("Gakuran Combat Debug Logs", false) and flag("Gakuran Combat Log Unknown", true) then
					debugLog("unknown combat anim", name, pure, attacker.Name, actionPri and "ActionPri" or "", string.format("len=%.2f", trackLen))
					combatToast("warning", "Unknown Combat Anim", string.format(
						"%s · id %s\nfrom %s · len %.2fs · not in DB yet",
						name ~= "" and name or (actionPri and "Action" or "?"),
						pure,
						attacker.Name,
						trackLen
					), "combat-unknown-" .. pure)
				end

				if flag("Gakuran Parry Unknown Combat", true) or flag("Gakuran Combat Visualizer", false) then
					local kind, delay = classifyFallback(name)
					entry = {
						id = pure,
						name = (name ~= "" and name ~= "Animation") and name or ("Unknown_" .. pure),
						kind = kind,
						hitDelay = delay,
						window = 0.125,
					}
					if pure and pure ~= "" and db.byId then
						db.byId[pure] = entry
						db.count = (tonumber(db.count) or 0) + 1
					end
				else
					return
				end
			else
				if pure ~= "" and st.attackDbMod and type(st.attackDbMod.ignoreId) == "function" then
					if actionPri and not shortCombatLen then
						pcall(st.attackDbMod.ignoreId, pure)
					end
				end
				return
			end
		end

		local myRoot = getLocalRoot()
		local theirRoot = getRoot(getCharacter(attacker))
		if not myRoot or not theirRoot then
			return
		end

		local dist = (theirRoot.Position - myRoot.Position).Magnitude
		local parryRange = math.max(
			numFlag("Gakuran Range Prefilter", 14),
			numFlag("Gakuran Dodge Range", 12),
			numFlag("Gakuran M2 Dodge Range", 14)
		)
		local vizRange = flag("Gakuran Combat Visualizer", false) and numFlag("Gakuran Viz Range", 28) or 0
		local maxAwareness = math.max(parryRange, vizRange)

		if flag("Gakuran Combat Visualizer", false) and dist <= vizRange + 4 then
			startVisualizer(attacker, track, entry)
		end

		if dist > maxAwareness + 4 then
			return
		end

		if dist > parryRange + 4 then
			return
		end

		debugLog(
			"attack seen",
			entry.name,
			entry.kind,
			attacker.Name,
			string.format("%.1fst", dist),
			attackerHoldingM1(attacker) and "HOLD" or "",
			"c" .. tostring(attackerCombo(attacker))
		)
		scheduleResponse(attacker, track, entry)
	end

	local function collectPlayingTracks(character)
		local tracks = {}
		local seen = {}
		if not character then
			return tracks
		end

		local function push(list)
			if type(list) ~= "table" then
				return
			end
			for _, track in ipairs(list) do
				if track and not seen[track] then
					seen[track] = true
					table.insert(tracks, track)
				end
			end
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		-- R6 combat often only shows up on Humanoid:GetPlayingAnimationTracks.
		if humanoid and type(humanoid.GetPlayingAnimationTracks) == "function" then
			local ok, list = pcall(function()
				return humanoid:GetPlayingAnimationTracks()
			end)
			if ok then
				push(list)
			end
		end

		local animator = (humanoid and humanoid:FindFirstChildOfClass("Animator"))
			or character:FindFirstChildWhichIsA("Animator", true)
		if animator and type(animator.GetPlayingAnimationTracks) == "function" then
			local ok, list = pcall(function()
				return animator:GetPlayingAnimationTracks()
			end)
			if ok then
				push(list)
			end
		end

		return tracks
	end

	local function hookCharacter(player, character)
		if not character or player == LocalPlayer then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
			or character:FindFirstChildWhichIsA("Animator", true)
		if not animator then
			task.spawn(function()
				local t0 = os.clock()
				while character.Parent and os.clock() - t0 < 6 do
					animator = humanoid:FindFirstChildOfClass("Animator")
						or character:FindFirstChildWhichIsA("Animator", true)
					if animator then
						break
					end
					task.wait(0.2)
				end
				if animator and character.Parent then
					hookCharacter(player, character)
				end
			end)
			return
		end

		local key = tostring(player.UserId)
		if st.hooks[key] then
			pcall(function()
				st.hooks[key]:Disconnect()
			end)
			st.hooks[key] = nil
		end
		if st.comboHooks and st.comboHooks[key] then
			pcall(function()
				st.comboHooks[key]:Disconnect()
			end)
			st.comboHooks[key] = nil
		end
		if st.holdHooks and st.holdHooks[key] then
			pcall(function()
				st.holdHooks[key]:Disconnect()
			end)
			st.holdHooks[key] = nil
		end

		local conn = ctx.addConnection(animator.AnimationPlayed, function(track)
			onAttackTrack(player, track)
		end)
		st.hooks[key] = conn

		-- Hold-M1: Combo / M1Hold attribute changes → re-scan tracks immediately.
		st.comboHooks = st.comboHooks or {}
		st.holdHooks = st.holdHooks or {}
		st.comboHooks[key] = ctx.addConnection(character:GetAttributeChangedSignal("Combo"), function()
			if not combatFeaturesOn() then
				return
			end
			for _, track in ipairs(collectPlayingTracks(character)) do
				onAttackTrack(player, track)
			end
		end)
		st.holdHooks[key] = ctx.addConnection(character:GetAttributeChangedSignal("M1Hold"), function()
			if character:GetAttribute("M1Hold") == true then
				for _, track in ipairs(collectPlayingTracks(character)) do
					onAttackTrack(player, track)
				end
			end
		end)

		debugLog("hooked", player.Name)
	end

	local function unhookPlayer(player)
		local key = tostring(player.UserId)
		if st.hooks[key] then
			pcall(function()
				st.hooks[key]:Disconnect()
			end)
			st.hooks[key] = nil
		end
		if st.comboHooks and st.comboHooks[key] then
			pcall(function()
				st.comboHooks[key]:Disconnect()
			end)
			st.comboHooks[key] = nil
		end
		if st.holdHooks and st.holdHooks[key] then
			pcall(function()
				st.holdHooks[key]:Disconnect()
			end)
			st.holdHooks[key] = nil
		end
		if st.swingState then
			st.swingState[player.UserId] = nil
		end
	end

	local function scanNearbyAttacks()
		if not combatFeaturesOn() then
			return
		end
		local myRoot = getLocalRoot()
		if not myRoot then
			return
		end
		local range = math.max(
			numFlag("Gakuran Range Prefilter", 14),
			numFlag("Gakuran Dodge Range", 12),
			numFlag("Gakuran M2 Dodge Range", 14),
			flag("Gakuran Combat Visualizer", false) and numFlag("Gakuran Viz Range", 28) or 0
		) + 6

		local anyHold = false
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				local character = getCharacter(player)
				local root = getRoot(character)
				if character and root then
					local dist = (root.Position - myRoot.Position).Magnitude
					if dist <= range then
						if character:GetAttribute("M1Hold") == true
							or character:GetAttribute("CombatAttacking") == true
						then
							anyHold = true
						end
						for _, track in ipairs(collectPlayingTracks(character)) do
							onAttackTrack(player, track)
						end
					end
				end
			end
		end
		st.nearbyHoldM1 = anyHold
	end

	-- Setup --------------------------------------------------------------

	local function setup()
		-- Load attack DB (seed only — never block boot on live rebuild).
		local AttackDBMod
		if ctx.moduleLoader and type(ctx.moduleLoader.load) == "function" then
			local ok, mod = pcall(function()
				return ctx.moduleLoader.load("games/gakuran/modules/attack_db.luau")
			end)
			if ok then
				AttackDBMod = mod
			end
		end
		if type(AttackDBMod) == "table" and type(AttackDBMod.create) == "function" then
			st.attackDbMod = AttackDBMod
			st.db = AttackDBMod.create()
		else
			st.db = {
				byId = {},
				count = 0,
				rebuild = function(self)
					return self.count
				end,
				lookup = function(self, id)
					local pure = tostring(id or ""):match("%d+")
					return pure and self.byId[pure]
				end,
			}
		end

		pcall(function()
			if ctx.refs.combatDbLabel then
				ctx.refs.combatDbLabel.Text = "DB: " .. tostring(st.db.count or 0) .. " seed · rebuilding…"
			end
		end)
		setStatus("idle · DB " .. tostring(st.db.count or 0) .. " (seed)")

		-- Heavy work after hub + loader are fully up.
		task.defer(function()
			if ctx.state.unloading then
				return
			end

			if st.db and type(st.db.rebuild) == "function" then
				local ok, n = pcall(function()
					return st.db:rebuild()
				end)
				pcall(function()
					if ok and ctx.refs.combatDbLabel then
						ctx.refs.combatDbLabel.Text = "DB: " .. tostring(n) .. " attack anims"
					elseif ctx.refs.combatDbLabel then
						ctx.refs.combatDbLabel.Text = "DB: " .. tostring(st.db.count or 0) .. " seed (rebuild failed)"
					end
				end)
				if ok then
					setStatus("ready · " .. tostring(n) .. " attacks · scan+hooks")
				else
					setStatus("ready · seed DB · scan+hooks")
					debugLog("rebuild failed", n)
				end
			end

			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer then
					local character = getCharacter(player)
					if character then
						pcall(hookCharacter, player, character)
					end
					ctx.addConnection(player.CharacterAdded, function(character)
						task.defer(function()
							pcall(hookCharacter, player, character)
						end)
					end)
				end
			end

			ctx.addConnection(Players.PlayerAdded, function(player)
				ctx.addConnection(player.CharacterAdded, function(character)
					task.defer(function()
						pcall(hookCharacter, player, character)
					end)
				end)
				task.defer(function()
					local character = getCharacter(player)
					if character then
						pcall(hookCharacter, player, character)
					end
				end)
			end)

			ctx.addConnection(Players.PlayerRemoving, unhookPlayer)
		end)

		-- Stay equipped / cooldown clear / ping sample / attack scan
		local maintAccum = 0
		local scanAccum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			dt = tonumber(dt) or 0

			-- High-rate track scan (AnimationPlayed alone is unreliable for remote combat).
			if combatFeaturesOn() then
				scanAccum = scanAccum + dt
				-- Hold-M1 strings need a faster poll so 2nd/3rd/4th aren't missed.
				local interval = st.nearbyHoldM1 and 0.016 or 0.03
				if scanAccum >= interval then
					scanAccum = 0
					pcall(scanNearbyAttacks)
				end
			end

			-- Visualizer updates every frame for smooth charge fill.
			if flag("Gakuran Combat Visualizer", false) then
				pcall(updateVisualizers)
			elseif next(st.vizEntries) then
				pcall(updateVisualizers)
			end

			maintAccum = maintAccum + dt
			if maintAccum < 0.25 then
				return
			end
			maintAccum = 0

			if flag("Gakuran Parry Ping Comp", true) or flag("Gakuran Auto Parry", false) then
				local avg = samplePingMs()
				pcall(function()
					if ctx.refs.combatPingLabel then
						local comp = flag("Gakuran Parry Ping Comp", true)
						local strength = numFlag("Gakuran Parry Ping Strength", 85)
						ctx.refs.combatPingLabel.Text = string.format(
							"Ping: %.0f ms avg%s",
							avg,
							comp and string.format(" · comp %d%% (−%.0fms)", strength, avg * 0.5 * (strength / 100)) or " · off"
						)
					end
				end)
			end

			if not combatFeaturesOn() then
				return
			end
			local character = getCharacter(LocalPlayer) or LocalPlayer.Character
			if flag("Gakuran No Parry Cooldown", false) then
				clearBlockCooldown(character)
			end
			if flag("Gakuran Stay Equipped", false) then
				stayEquipped(character)
			end
		end)
	end

	library:AddCleanup(function()
		for key, conn in pairs(st.hooks) do
			pcall(function()
				conn:Disconnect()
			end)
			st.hooks[key] = nil
		end
		table.clear(st.pending)
		for userId in pairs(st.vizEntries) do
			destroyViz(userId)
		end
		pcall(function()
			if st.vizFolder then
				st.vizFolder:Destroy()
			end
		end)
		st.vizFolder = nil
	end)

	return { setup = setup }
end
