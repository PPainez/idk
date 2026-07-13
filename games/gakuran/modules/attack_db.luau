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
	["132695766056641"] = true, -- Boxing Idle
	["136970699228453"] = true, -- Boxing BlockHit
	["130267921858674"] = true, -- Karate Walk
	["78370245490631"] = true, -- default Walk
	["113331696487725"] = true, -- Basic Walk
	["124220338099067"] = true, -- Basic Idle
	["134623519349383"] = true, -- Basic Blocking
	["73766443218740"] = true, -- Wrestling Idle
	["101161965631044"] = true, -- Kure Idle
	["102982320608759"] = true, -- MuayThai Idle
	["100542767551399"] = true, -- Striker Idle
	["108636808436488"] = true, -- Hakari Idle
	["108862846290180"] = true, -- Capoeira Idle
	["85845666927963"] = true, -- Capoeira Walk (live scan)
	["79974955602012"] = true, -- Slugger Walk
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
	["71169404124554"] = true, -- Emote Lean Startup3
	["72284079162560"] = true, -- Emote BehindHeadIdle
	["73090768467054"] = true, -- Emote BehindHeadStatic
	["133522894608941"] = true, -- Emote Cortisol dance
	["75158607431737"] = true, -- Bass EquipIdle
	["87932588807124"] = true, -- FlipPhone EquipIdle
	["133128780519783"] = true, -- Drums EquipIdle
	["133952297523350"] = true, -- Chalk EquipIdle
	["111108020510751"] = true, -- Keyboard EquipIdle
	["111355600199981"] = true, -- PhoneTap
	-- User-reported sit / chill emotes (catalog IDs — often not under Animations.Emotes)
	["110521212020909"] = true, -- sit
	["126257562287528"] = true, -- sit
	["132477488202815"] = true, -- sit
	["109178309127603"] = true, -- sit
	["94972279698754"] = true, -- sit
	["109278619250401"] = true, -- sit
	["70540872101043"] = true, -- sit
	["74721225091795"] = true, -- sit
	["74219849384808"] = true, -- sit
	["72822821848529"] = true, -- sit
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
	-- Whole cosmetic trees: never combat.
	for _, folderName in ipairs({
		"Movement",
		"Emotes",
		"Items",
		"Instruments",
		"Basketball",
		"Rhythm",
	}) do
		harvestNonAttackAnims(anims:FindFirstChild(folderName))
	end
	harvestStyleLocomotion(anims:FindFirstChild("BaseCombat"))
	harvestStyleLocomotion(anims:FindFirstChild("Combat"))

	-- Catch sit/lean/chill/lay emotes nested under odd folder names.
	local ok, list = pcall(function()
		return anims:GetDescendants()
	end)
	if ok and type(list) == "table" then
		for _, d in ipairs(list) do
			if d:IsA("Animation") then
				local n = string.lower(d.Name)
				local path = string.lower(d:GetFullName())
				if n:find("sit", 1, true)
					or n:find("chill", 1, true)
					or n:find("lean", 1, true)
					or n:find("lay", 1, true)
					or n:find("sleep", 1, true)
					or n:find("lounge", 1, true)
					or n:find("emote", 1, true)
					or n:find("dance", 1, true)
					or path:find("emotes", 1, true)
					or path:find("%.sit", 1, true)
					or path:find("sit%.", 1, true)
				then
					-- Never blackhole real attack names if they somehow match.
					local raw = d.Name
					if not (
						raw:find("M1")
						or raw:find("M2")
						or raw:find("EHit")
						or raw:find("Grapple")
						or raw:find("Guardbreak")
					)
					then
						markLocomotionId(d.AnimationId)
					end
				end
			end
		end
	end
end

function AttackDB.ignoreId(animationId)
	markLocomotionId(animationId)
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
	-- Basic (0.32+0.02 flat · M2 0.525)
	["83491849294956"] = { name = "1stM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["89420531853362"] = { name = "2ndM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["83730275893449"] = { name = "3rdM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["106980660082799"] = { name = "4thM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["78888626472394"] = { name = "M2", kind = "M2", hitDelay = 0.525, window = 0.15 },

	-- Boxing (0.32+0.02/0.02/0.02/0.06 · M2 0.43)
	["137980914350618"] = { name = "1stM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["100408082509740"] = { name = "2ndM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["94803478352691"] = { name = "3rdM1", kind = "M1", hitDelay = 0.34, window = 0.15 },
	["78695517680318"] = { name = "4thM1", kind = "M1", hitDelay = 0.38, window = 0.15 },
	["132022052139564"] = { name = "M2", kind = "M2", hitDelay = 0.43, window = 0.15 },
	-- Capoeira (0.33+0.02/0.10/0.02/-0.05 · M2 0.45 / dur 0.32)
	["125976167173936"] = { name = "1stM1", kind = "M1", hitDelay = 0.35, window = 0.15 },
	["134945199381140"] = { name = "2ndM1", kind = "M1", hitDelay = 0.43, window = 0.15 },
	["117877243065533"] = { name = "3rdM1", kind = "M1", hitDelay = 0.35, window = 0.15 },
	["106965238908791"] = { name = "4thM1", kind = "M1", hitDelay = 0.28, window = 0.15 },
	-- Capoeira table-kick spin — dodgeImmediate: backdash the frame the track starts
	["131071815103338"] = {
		name = "M2",
		kind = "M2",
		hitDelay = 0.45,
		window = 0.32,
		dodgeImmediate = true,
	},
	-- Hakari (0.28+0.16/0.18/0.16/0.21 · M2 0.59)
	["76236532060812"] = { name = "1stM1", kind = "M1", hitDelay = 0.44, window = 0.15 },
	["74206130671324"] = { name = "2ndM1", kind = "M1", hitDelay = 0.46, window = 0.15 },
	["71919935695307"] = { name = "3rdM1", kind = "M1", hitDelay = 0.44, window = 0.15 },
	["122861547142657"] = { name = "4thM1", kind = "M1", hitDelay = 0.49, window = 0.15 },
	["92851992709496"] = { name = "M2", kind = "M2", hitDelay = 0.59, window = 0.16 },
	-- HakariOther (same delays as Hakari)
	["126612786608030"] = { name = "1stM1", kind = "M1", hitDelay = 0.44, window = 0.15 },
	["113719263885794"] = { name = "2ndM1", kind = "M1", hitDelay = 0.46, window = 0.15 },
	["136305578634960"] = { name = "3rdM1", kind = "M1", hitDelay = 0.44, window = 0.15 },
	["89039586375625"] = { name = "4thM1", kind = "M1", hitDelay = 0.49, window = 0.15 },
	["101619248052969"] = { name = "M2", kind = "M2", hitDelay = 0.59, window = 0.16 },
	["82855179231529"] = { name = "MomentumM2", kind = "M2", hitDelay = 0.59, window = 0.16 },
	-- Karate (0.24+0.0375/0.075/0.15/0.225 · M2 0.4875) live Cl0wn_sh1111 EHits also seen
	["137837926745158"] = { name = "1stM1", kind = "M1", hitDelay = 0.277, window = 0.15 },
	["100981571094705"] = { name = "2ndM1", kind = "M1", hitDelay = 0.315, window = 0.15 },
	["130865087635587"] = { name = "3rdM1", kind = "M1", hitDelay = 0.39, window = 0.15 },
	["86495068205420"] = { name = "4thM1", kind = "M1", hitDelay = 0.465, window = 0.15 },
	["120393553812903"] = { name = "M2", kind = "M2", hitDelay = 0.4875, window = 0.15 },
	["101347661150789"] = { name = "4thEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["90752347516770"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- Kure (flat 0.32)
	["82904229252991"] = { name = "1stM1", kind = "M1", hitDelay = 0.32, window = 0.15 },
	["103732110215321"] = { name = "2ndM1", kind = "M1", hitDelay = 0.32, window = 0.15 },
	["103964436023727"] = { name = "3rdM1", kind = "M1", hitDelay = 0.32, window = 0.15 },
	["71676634048602"] = { name = "4thM1", kind = "M1", hitDelay = 0.32, window = 0.15 },
	["102407060635393"] = { name = "M2", kind = "M2", hitDelay = 0.32, window = 0.15 },
	["107394966937565"] = { name = "M2EHit", kind = "M2", hitDelay = 0.32, window = 0.15 },
	["88619229552579"] = { name = "M2Success", kind = "M2", hitDelay = 0.32, window = 0.15 },
	["92787945841620"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- MuayThai (CombatConfig M1HitboxDelay=0.3 flat, no per-step offsets; M2=0.6)
	-- Folder IDs confirmed; 1stM1 live-seen on sugarsku1lz (len=1.0)
	["96726284968458"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.15 },
	["139911027872047"] = { name = "2ndM1", kind = "M1", hitDelay = 0.30, window = 0.15 },
	["104515319350296"] = { name = "3rdM1", kind = "M1", hitDelay = 0.30, window = 0.15 },
	["74960202100098"] = { name = "4thM1", kind = "M1", hitDelay = 0.30, window = 0.15 },
	["137034747040618"] = { name = "M2", kind = "M2", hitDelay = 0.60, window = 0.16 },
	-- MuayThai EHits (style-specific 2nd/3rd/4th differ from slugger/base)
	["108045962864902"] = { name = "1stEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["92787945841620"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["104407197874289"] = { name = "3rdEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["85931837451298"] = { name = "4thEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["114511731321756"] = { name = "GuardbreakEHit", kind = "EHit", hitDelay = 0.35, window = 0.130 },
	-- Slugger (live scan Cramless + CombatConfig M1 base 0.2 + off 0.30/0.25/0.25/0.17)
	-- Track lens: 1st/2nd≈1.0s, 3rd≈0.90s, 4th≈1.47s · Action4 priority · combo edge tpos≈0.02–0.08
	["134829666925953"] = { name = "1stM1", kind = "M1", hitDelay = 0.50, window = 0.15 },
	["104867156139010"] = { name = "2ndM1", kind = "M1", hitDelay = 0.45, window = 0.15 },
	["112759168172605"] = { name = "3rdM1", kind = "M1", hitDelay = 0.45, window = 0.15 },
	["114647502301740"] = { name = "4thM1", kind = "M1", hitDelay = 0.37, window = 0.15 },
	["118943955490014"] = { name = "M2", kind = "M2", hitDelay = 0.82, window = 0.18 },
	-- Slugger EHits (folder scrape)
	["108045962864902"] = { name = "1stEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["90752347516770"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["122541287927198"] = { name = "3rdEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["101347661150789"] = { name = "4thEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	["74690341409113"] = { name = "GuardbreakEHit", kind = "EHit", hitDelay = 0.35, window = 0.130 },
	-- Striker
	["127909081017342"] = { name = "1stM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["132840225082238"] = { name = "1stM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["79563637573277"] = { name = "2ndM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["88761422474765"] = { name = "2ndM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["118070233153900"] = { name = "3rdM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["98462236639320"] = { name = "3rdM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["122451562066756"] = { name = "4thM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
	["77710266587706"] = { name = "4thM1", kind = "M1", hitDelay = 0.332, window = 0.125 },
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
			-- Re-apply seed timing so live harvest can't soft-overwrite with classify() defaults
			local seed = SEED[id]
			local entry = self.byId[id]
			if seed and entry then
				entry.hitDelay = seed.hitDelay
				entry.window = seed.window or entry.window or 0.125
				entry.kind = seed.kind or entry.kind
				if seed.name then
					entry.name = seed.name
				end
			end
		end

		-- Prefer CombatConfig style delays when available (slugger etc.)
		pcall(function()
			local cfg = require(game:GetService("ReplicatedStorage").Shared.Config.CombatConfig)
			if type(cfg) ~= "table" then
				return
			end
			local anims = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
			local combat = anims and anims:FindFirstChild("Combat")
			if not combat then
				return
			end
			local folderToStyle = {
				SluggerAnims = "slugger",
				BoxingAnims = "boxing",
				BasicAnims = "basic",
				CapoeiraAnims = "capoeira",
				KarateAnims = "karate",
				KureAnims = "kure",
				MuayThaiAnims = "muaythai",
				WrestlingAnims = "wrestling",
				HakariAnims = "hakari",
				HakariOtherAnims = "hakari",
				StrikerAnims = "wild",
			}
			for folderName, styleKey in pairs(folderToStyle) do
				local folder = combat:FindFirstChild(folderName)
				if folder then
					local baseM1 = 0.32
					local m2Delay = 0.45
					pcall(function()
						local sc = cfg.GetStyleConfig and cfg.GetStyleConfig(styleKey)
						if type(sc) == "table" then
							baseM1 = tonumber(sc.M1HitboxDelay) or baseM1
							m2Delay = tonumber(sc.M2HitboxDelay) or m2Delay
						end
					end)
					local offsets = { 0, 0, 0, 0 }
					pcall(function()
						local sc = cfg.GetStyleConfig and cfg.GetStyleConfig(styleKey)
						local off = sc and sc.M1HitboxDelayOffsets
						if type(off) == "table" then
							for i = 1, 4 do
								offsets[i] = tonumber(off[i] or off[tostring(i)]) or 0
							end
						end
					end)
					for _, d in ipairs(folder:GetDescendants()) do
						if d:IsA("Animation") then
							local id = AttackDB.extractId(d.AnimationId)
							local entry = id and self.byId[id]
							local n = d.Name
							if entry and n then
								if n:find("M2") and not n:find("EHit") then
									entry.hitDelay = m2Delay
									entry.kind = "M2"
								elseif n:find("1stM1") then
									entry.hitDelay = baseM1 + offsets[1]
									entry.kind = "M1"
								elseif n:find("2ndM1") then
									entry.hitDelay = baseM1 + offsets[2]
									entry.kind = "M1"
								elseif n:find("3rdM1") then
									entry.hitDelay = baseM1 + offsets[3]
									entry.kind = "M1"
								elseif n:find("4thM1") then
									entry.hitDelay = baseM1 + offsets[4]
									entry.kind = "M1"
								end
								entry.styles[styleKey] = true
							end
						end
					end
				end
			end
		end)

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
