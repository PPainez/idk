--[[
    xanhub | gakuran | attack animation database

    Complete combat attack IDs scraped from ReplicatedStorage.Animations.Combat/*
    and BaseCombat (Wrestling/MuayThai/Kure/Karate/Boxing/etc).

    NOTE: Remote clients often expose track.Animation.Name as just "Animation".
    Matching is by numeric AnimationId only — names are for debug/toasts.
]]

local AttackDB = {}

function AttackDB.extractId(animationId)
	if type(animationId) == "number" then
		return tostring(math.floor(animationId))
	end
	if type(animationId) ~= "string" then
		return nil
	end
	return animationId:match("%d+")
end

-- Locomotion / non-attack IDs to ignore even when the anim object is named "Animation".
-- Hardcoded seed covers common spam from combat logs; rebuild also harvests Movement/Emotes/Items.
local LOCOMOTION_IDS = {
	-- Movement
	["99661732639863"] = true, -- Idle1
	["122843775061652"] = true, -- Idle2
	["83600639547203"] = true, -- MaleWalk
	["85823794654077"] = true, -- MaleRun
	["117293898907979"] = true, -- FemaleWalk
	["137015026151472"] = true, -- FemaleRun
	["132695091086148"] = true, -- Backpedal
	["109816855387997"] = true, -- DashBack
	["106268941365574"] = true, -- DashRight
	["106858554878235"] = true, -- DashBack alt
	["105936443843545"] = true, -- GoalboundFemaleRun
	["115103415399723"] = true, -- FemaleWalk2
	["101681156645386"] = true, -- ToolNone
	["101758912482710"] = true, -- Fall
	["80742414334394"] = true, -- Jump
	["96856467950733"] = true, -- Sit
	-- Style walk / idle
	["76945839486275"] = true, -- style Walk (Muay/Kure)
	["111699625251889"] = true, -- Wrestling Walk
	["91658474738843"] = true, -- Wrestling Walk alt
	["135133599113049"] = true, -- Boxing Walk
	["130267921858674"] = true, -- Karate Walk
	["78370245490631"] = true, -- default Walk
	["113331696487725"] = true, -- Basic Walk
	["73766443218740"] = true, -- Wrestling Idle
	["101161965631044"] = true, -- Kure Idle
	["102982320608759"] = true, -- MuayThai Idle
	["100542767551399"] = true, -- Striker Idle
	["108636808436488"] = true, -- Hakari Idle
	["108862846290180"] = true, -- Capoeira Idle
	["115351567178592"] = true, -- HakariOther Idle
	["113694931951279"] = true, -- Base Idle
	-- Block / non-offensive combat
	["118147060185189"] = true, -- Blocking
	["108925352376719"] = true, -- Kure BlockHit
	-- Instruments / dances / emotes (flooded logs while players idle with bass/guitar)
	["118268327660267"] = true, -- Bass Dance1
	["138707781762636"] = true, -- Guitar Dance1
	["89040957520196"] = true, -- Bass Strumming1
	["81384818367841"] = true, -- Emote Sit ChillStartup
}

local function markLocomotionId(animationId)
	local id = AttackDB.extractId(animationId)
	if id then
		LOCOMOTION_IDS[id] = true
	end
end

local function harvestNonAttackAnims(root)
	if not root then
		return
	end
	local ok, list = pcall(function()
		return root:GetDescendants()
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	for _, d in ipairs(list) do
		if d:IsA("Animation") then
			local n = d.Name
			-- Never blackhole actual attack names even if under Items by mistake.
			if n:find("M1")
				or n:find("M2")
				or n:find("EHit")
				or n:find("Grapple")
				or n:find("Dirty")
				or n:find("Attacker")
				or n:find("Victim")
				or n:find("Success")
				or n:find("Momentum")
				or n:find("Guardbreak")
			then
				-- skip
			else
				markLocomotionId(d.AnimationId)
			end
		end
	end
end

local function harvestStyleLocomotion(root)
	if not root then
		return
	end
	local ok, list = pcall(function()
		return root:GetDescendants()
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	for _, d in ipairs(list) do
		if d:IsA("Animation") then
			local n = d.Name
			if n:find("Idle")
				or n:find("Walk")
				or n:find("Run")
				or n:find("Block")
				or n:find("Parry")
				or n:find("Stun")
				or n:find("Dodge")
				or n:find("Dash")
				or n:find("Fall")
				or n:find("Jump")
				or n:find("GetUp")
				or n:find("Knock")
				or n:find("Hurt")
				or n:find("React")
				or n:find("Blocking")
			then
				if not (n:find("EHit") or n:find("Guardbreak") or n:find("M1") or n:find("M2")) then
					markLocomotionId(d.AnimationId)
				end
			end
		end
	end
end

function AttackDB.seedLocomotionFromGame()
	local anims = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
	if not anims then
		return
	end
	harvestNonAttackAnims(anims:FindFirstChild("Movement"))
	harvestNonAttackAnims(anims:FindFirstChild("Emotes"))
	harvestNonAttackAnims(anims:FindFirstChild("Items"))
	harvestStyleLocomotion(anims:FindFirstChild("BaseCombat"))
	harvestStyleLocomotion(anims:FindFirstChild("Combat"))
end

-- Full attack seed (unique ids). hitDelay ≈ CombatConfig M1 hitbox timing.
local SEED = {
	-- Base
	["113961476814500"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["82165070516177"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["138197524717835"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["81174027972159"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["113480104450803"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["108045962864902"] = { name = "1stEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["122541287927198"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["104407197874289"] = { name = "3rdEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["85931837451298"] = { name = "4thEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["114511731321756"] = { name = "GuardbreakEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["74690341409113"] = { name = "GuardbreakEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- Basic
	["83491849294956"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["89420531853362"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["83730275893449"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["106980660082799"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["78888626472394"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Boxing
	["137980914350618"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["100408082509740"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["94803478352691"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["78695517680318"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["132022052139564"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Capoeira
	["125976167173936"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["134945199381140"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["117877243065533"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["106965238908791"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["131071815103338"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Hakari
	["76236532060812"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["74206130671324"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["71919935695307"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["122861547142657"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["92851992709496"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- HakariOther
	["126612786608030"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["113719263885794"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["136305578634960"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["89039586375625"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["101619248052969"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["82855179231529"] = { name = "MomentumM2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Karate
	["137837926745158"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["100981571094705"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["130865087635587"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["86495068205420"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["120393553812903"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["101347661150789"] = { name = "4thEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["90752347516770"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- Kure
	["82904229252991"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["103732110215321"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["103964436023727"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["71676634048602"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["102407060635393"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["107394966937565"] = { name = "M2EHit", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["88619229552579"] = { name = "M2Success", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["92787945841620"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- MuayThai
	["96726284968458"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["139911027872047"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["104515319350296"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["74960202100098"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["137034747040618"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Slugger
	["134829666925953"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["104867156139010"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["112759168172605"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["114647502301740"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["118943955490014"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Striker
	["127909081017342"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["132840225082238"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["79563637573277"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["88761422474765"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["118070233153900"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["98462236639320"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["122451562066756"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["77710266587706"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["114364673509520"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Wrestling (these were the big missers)
	["82903450925391"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["119685134442395"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["107464726433388"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["91485623489753"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["73748315742870"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["109303037515668"] = { name = "M2EHit", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["100794890036133"] = { name = "M2Success", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["80309578200579"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["91352556581859"] = { name = "GuardbreakEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- Grappling
	["97783129267001"] = { name = "GrappleAttacker", kind = "M2", hitDelay = 0.40, window = 0.125 },
	["72258480653932"] = { name = "DirtyAttacker", kind = "M2", hitDelay = 0.40, window = 0.125 },
	["84792890110748"] = { name = "DirtyVictim", kind = "M2", hitDelay = 0.40, window = 0.125 },
	["128307941333158"] = { name = "GrappleVictim", kind = "M2", hitDelay = 0.40, window = 0.125 },
	-- Striker Crit / Kure crit startup (shared id with Kure M2 already covered)
	["103967416396872"] = { name = "Crit", kind = "M2", hitDelay = 0.40, window = 0.125 },
}

function AttackDB.isLocomotionId(id)
	id = AttackDB.extractId(id) or tostring(id or "")
	-- Never treat known attack SEED ids as locomotion.
	if SEED[id] then
		return false
	end
	return LOCOMOTION_IDS[id] == true
end

local function classify(name)
	local kind, delay = "M1", 0.32
	if name:find("M2") then
		kind, delay = "M2", 0.38
	elseif name:find("EHit") or name:find("Guardbreak") or name:find("Grapple") or name:find("Dirty") then
		if name:find("M2") then
			kind, delay = "M2", 0.38
		else
			kind, delay = "EHit", 0.30
		end
	elseif name:find("1stM1") or name:find("1st") then
		delay = 0.30
	elseif name:find("2ndM1") or name:find("3rdM1") or name:find("2nd") or name:find("3rd") then
		delay = 0.28
	elseif name:find("4thM1") or name:find("4th") then
		delay = 0.35
	end
	return kind, delay
end

local function isNonAttackCombatName(name)
	if type(name) ~= "string" then
		return true
	end
	if name:find("Idle") or name:find("Walk") or name:find("Run") or name:find("Dash") then
		return true
	end
	if name:find("Block") and not name:find("Guardbreak") then
		return true
	end
	if name:find("Parry") then
		return true
	end
	return false
end

local function isAttackName(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	if isNonAttackCombatName(name) then
		return false
	end
	return name:find("M1")
		or name:find("M2")
		or name:find("EHit")
		or name:find("Momentum")
		or name:find("Success")
		or name:find("Grapple")
		or name:find("Attacker")
		or name:find("Victim")
		or name:find("Dirty")
		or name:find("Crit")
		or name:find("Grab")
		or name:find("Slam")
		or name:find("Startup")
		or (name:find("Hit") ~= nil)
end

function AttackDB.create()
	pcall(AttackDB.seedLocomotionFromGame)

	local byId = {}
	for id, info in pairs(SEED) do
		byId[id] = {
			id = id,
			name = info.name,
			kind = info.kind,
			hitDelay = info.hitDelay,
			window = info.window or 0.125,
			styles = {},
		}
	end

	local db = {
		byId = byId,
		count = 0,
		built = false,
	}

	function db:rebuild()
		pcall(AttackDB.seedLocomotionFromGame)

		local function addAnim(style, anim)
			if not anim or not anim:IsA("Animation") then
				return
			end
			local name = anim.Name
			if not isAttackName(name) then
				return
			end
			local id = AttackDB.extractId(anim.AnimationId)
			if not id or AttackDB.isLocomotionId(id) then
				return
			end
			local kind, delay = classify(name)
			local entry = self.byId[id]
			if not entry then
				entry = {
					id = id,
					name = name,
					kind = kind,
					hitDelay = delay,
					window = 0.125,
					styles = {},
				}
				self.byId[id] = entry
			else
				if name and name ~= "Animation" then
					entry.name = name
				end
				entry.kind = entry.kind or kind
				entry.hitDelay = entry.hitDelay or delay
			end
			if style then
				entry.styles[style] = true
			end
		end

		local function safeDescendants(root)
			local ok, list = pcall(function()
				return root:GetDescendants()
			end)
			if ok and type(list) == "table" then
				return list
			end
			return {}
		end

		if type(getloadedmodules) == "function" then
			local okMods, modules = pcall(getloadedmodules)
			if okMods and type(modules) == "table" then
				for _, moduleScript in ipairs(modules) do
					if moduleScript and moduleScript.Name == "CombatAnimationUtils" then
						local reqOk, utils = pcall(require, moduleScript)
						if reqOk and type(utils) == "table" and type(utils.GetAllCombatStyles) == "function" then
							local ok, styles = pcall(utils.GetAllCombatStyles)
							if ok and type(styles) == "table" then
								for _, style in ipairs(styles) do
									local folderOk, folder = pcall(utils.GetCombatAnimsFolder, style)
									if folderOk and typeof(folder) == "Instance" then
										for _, d in ipairs(safeDescendants(folder)) do
											pcall(addAnim, style, d)
										end
									end
								end
							end
						end
						break
					end
				end
			end
		end

		local anims = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
		if anims then
			for _, folderName in ipairs({ "BaseCombat", "Combat" }) do
				local folder = anims:FindFirstChild(folderName)
				if folder then
					for _, d in ipairs(safeDescendants(folder)) do
						if d:IsA("Animation") then
							local n = d.Name
							local id = AttackDB.extractId(d.AnimationId)
							if id then
								if isNonAttackCombatName(n) then
									LOCOMOTION_IDS[id] = true
								elseif isAttackName(n) then
									pcall(addAnim, folderName, d)
								else
									-- Named oddly (e.g. Crit-only folders) — if under combat tree and not loco, keep as attack.
									if n ~= "" and not isNonAttackCombatName(n) then
										pcall(addAnim, folderName, d)
									end
								end
							end
						end
					end
				end
			end
		end

		-- Never blackhole real seed attacks if a folder also tagged them as loco by mistake.
		for id in pairs(SEED) do
			LOCOMOTION_IDS[id] = nil
		end

		local n = 0
		for _ in pairs(self.byId) do
			n = n + 1
		end
		self.count = n
		self.built = true
		return n
	end

	function db:lookup(animationId)
		local id = AttackDB.extractId(animationId)
		if not id or AttackDB.isLocomotionId(id) then
			return nil
		end
		return self.byId[id]
	end

	function db:list()
		local list = {}
		for _, entry in pairs(self.byId) do
			table.insert(list, entry)
		end
		table.sort(list, function(a, b)
			return tostring(a.name) < tostring(b.name)
		end)
		return list
	end

	local n = 0
	for _ in pairs(byId) do
		n = n + 1
	end
	db.count = n
	db.built = false
	return db
end

return AttackDB
