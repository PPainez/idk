--[[
    xanhub | gakuran | combat

    Auto Parry + rear Auto Dodge.
    Detects known combat attack animations on nearby players, then:
      - behind attacker → Evasive.Evasive()
      - otherwise → Block.Block() timed to PerfectBlockWindow (~0.125s)

    Attack DB: games/gakuran/modules/attack_db.luau (+ live rebuild from style folders)
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local RunService = ctx.RunService
	local LocalPlayer = Players.LocalPlayer

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
	dodge:AddLabel("Front attacks → parry · rear attacks → dodge")

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
	debugSection:AddToggle({ text = "Combat Debug Logs", flag = "Gakuran Combat Debug Logs", state = false })
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

	local function getRoot(character)
		if not character then
			return nil
		end
		return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	end

	local function getLocalRoot()
		return getRoot(LocalPlayer.Character)
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
		local look = Vector3.new(localRoot.CFrame.LookVector.X, 0, localRoot.CFrame.LookVector.Z)
		if look.Magnitude < 0.05 then
			return false
		end
		local dot = look.Unit:Dot(flat.Unit)
		-- rearAngle 115° → cos(115°) ≈ -0.42; behind if angle from look > rearAngle
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

		local character = LocalPlayer.Character
		clearBlockCooldown(character)
		stayEquipped(character)

		local ok, err = pcall(blockApi.Block)
		if not ok then
			debugLog("Block failed", err)
			setStatus("parry failed")
			return
		end

		st.lastParryAt = os.clock()
		setStatus(string.format(
			"parried %s (%s)",
			tostring(entry.name or "?"),
			tostring(entry.kind or "?")
		))
		debugLog("parry", entry.name, entry.kind, entry.hitDelay)

		local hold = math.clamp(numFlag("Gakuran Parry Hold", 110), 40, 250) / 1000
		task.delay(hold, function()
			local unblock = getBlockApi()
			if unblock and type(unblock.Unblock) == "function" then
				pcall(unblock.Unblock)
			end
		end)
	end

	local function doDodge(reason)
		local evasive = getEvasiveApi()
		if not evasive or type(evasive.Evasive) ~= "function" then
			debugLog("Evasive API missing")
			setStatus("Evasive module not loaded")
			return
		end
		if type(evasive.IsDashActive) == "function" then
			local active = false
			pcall(function()
				active = evasive.IsDashActive(LocalPlayer.Character) == true
			end)
			if active then
				return
			end
		end

		local ok, err = pcall(evasive.Evasive)
		if ok then
			st.lastDodgeAt = os.clock()
			setStatus("dodged · " .. tostring(reason or "rear"))
			debugLog("dodge", reason)
		else
			debugLog("dodge failed", err)
		end
	end

	local function scheduleResponse(attacker, track, dbEntry)
		local animId = dbEntry.id
		-- One pending response per attacker+anim (prevents double-fire spam).
		local dedupe = tostring(attacker.UserId) .. ":" .. tostring(animId)
		if st.pending[dedupe] then
			return
		end
		st.pending[dedupe] = true

		local hitDelay = tonumber(dbEntry.hitDelay) or 0.32
		local window = tonumber(dbEntry.window) or 0.125
		local range = numFlag("Gakuran Range Prefilter", 14)

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
		local elapsed = 0
		if track then
			pcall(function()
				elapsed = tonumber(track.TimePosition) or 0
			end)
		end
		local reaction = numFlag("Gakuran Reaction Offset", 40) / 1000
		-- Block slightly before predicted hitbox for the perfect window.
		local target = hitDelay - reaction - (window * 0.35)
		local waitTime = math.max(0, target - elapsed)

		task.delay(waitTime, function()
			st.pending[dedupe] = nil
			if ctx.state.unloading then
				return
			end

			local autoParry = flag("Gakuran Auto Parry", false)
			local autoDodge = flag("Gakuran Auto Dodge", false)
			if not autoParry and not autoDodge then
				return
			end

			-- Soft global cooldown so we don't hammer Block/Evasive.
			local now = os.clock()
			if autoParry and (now - (st.lastParryAt or 0)) < 0.12 then
				return
			end
			if autoDodge and (now - (st.lastDodgeAt or 0)) < 0.18 then
				-- still allow parry path below
			end

			local myChar = LocalPlayer.Character
			local myRoot = getRoot(myChar)
			local theirRoot = getRoot(attacker.Character)
			if not myRoot or not theirRoot then
				return
			end

			local dist = (theirRoot.Position - myRoot.Position).Magnitude
			local maxRange = math.max(range, numFlag("Gakuran Dodge Range", 12))
			if dist > maxRange + 2 then
				debugLog("out of range", dist)
				return
			end

			local rearAngle = numFlag("Gakuran Dodge Rear Angle", 115)
			local behind = isBehind(myRoot, theirRoot, rearAngle)
			local dodgeRange = numFlag("Gakuran Dodge Range", 12)

			if autoDodge and behind and dist <= dodgeRange then
				if (now - (st.lastDodgeAt or 0)) >= 0.18 then
					doDodge(dbEntry.name or "rear")
				end
				return
			end

			if autoParry and dist <= range then
				if not behind or not autoDodge then
					doParry(dbEntry)
				end
				return
			end

			if flag("Gakuran Dodge Fallback", false) and autoDodge then
				local stunned = myChar
					and (myChar:GetAttribute("Stunned") == true or myChar:GetAttribute("CantAnything") == true)
				if stunned and (now - (st.lastDodgeAt or 0)) >= 0.18 then
					doDodge("fallback")
				end
			end
		end)
	end

	local function onAnimationPlayed(attacker, track)
		if ctx.state.unloading then
			return
		end
		if not flag("Gakuran Auto Parry", false) and not flag("Gakuran Auto Dodge", false) then
			return
		end
		if attacker == LocalPlayer then
			return
		end

		local anim = track and track.Animation
		if not anim then
			return
		end
		local id = anim.AnimationId
		local db = st.db
		if not db then
			return
		end

		local entry = db:lookup(id)
		if not entry then
			return
		end

		local myRoot = getLocalRoot()
		local theirRoot = getRoot(attacker.Character)
		if not myRoot or not theirRoot then
			return
		end

		local dist = (theirRoot.Position - myRoot.Position).Magnitude
		local range = math.max(numFlag("Gakuran Range Prefilter", 14), numFlag("Gakuran Dodge Range", 12))
		if dist > range + 4 then
			return
		end

		debugLog("attack seen", entry.name, entry.kind, attacker.Name, string.format("%.1fst", dist))
		scheduleResponse(attacker, track, entry)
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
		if not animator then
			-- wait briefly for animator
			task.spawn(function()
				local t0 = os.clock()
				while character.Parent and os.clock() - t0 < 5 do
					animator = humanoid:FindFirstChildOfClass("Animator")
					if animator then
						break
					end
					task.wait(0.25)
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

		local conn = animator.AnimationPlayed:Connect(function(track)
			onAnimationPlayed(player, track)
		end)
		st.hooks[key] = conn
		ctx.addConnection(conn)
	end

	local function unhookPlayer(player)
		local key = tostring(player.UserId)
		if st.hooks[key] then
			pcall(function()
				st.hooks[key]:Disconnect()
			end)
			st.hooks[key] = nil
		end
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

		if ctx.refs.combatDbLabel then
			ctx.refs.combatDbLabel.Text = "DB: " .. tostring(st.db.count or 0) .. " seed · rebuilding…"
		end
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
				if ok and ctx.refs.combatDbLabel then
					ctx.refs.combatDbLabel.Text = "DB: " .. tostring(n) .. " attack anims"
				end
				if ok then
					setStatus("ready · " .. tostring(n) .. " attacks indexed")
				else
					setStatus("DB rebuild failed · using seed")
					debugLog("rebuild failed", n)
				end
			end

			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer then
					if player.Character then
						pcall(hookCharacter, player, player.Character)
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
				if player.Character then
					task.defer(function()
						pcall(hookCharacter, player, player.Character)
					end)
				end
			end)

			ctx.addConnection(Players.PlayerRemoving, unhookPlayer)
		end)

		-- Stay equipped / cooldown clear (throttled)
		local maintAccum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran Auto Parry", false) and not flag("Gakuran Auto Dodge", false) then
				return
			end
			maintAccum = maintAccum + (tonumber(dt) or 0)
			if maintAccum < 0.2 then
				return
			end
			maintAccum = 0
			local character = LocalPlayer.Character
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
	end)

	return { setup = setup }
end
