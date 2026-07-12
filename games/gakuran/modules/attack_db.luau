--[[
    xanhub | gakuran | attack animation database

    Built from ReplicatedStorage combat style folders via CombatAnimationUtils
    when available, with a static seed of known M1/M2/EHit ids.
]]

local AttackDB = {}

-- Static seed (unique anim ids). hitDelay ≈ DefaultHitboxDelay timing from CombatConfig.M1
local SEED = {
	-- Base / shared
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
	["91352556581859"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- Karate
	["137837926745158"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["100981571094705"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["130865087635587"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["86495068205420"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["120393553812903"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["101347661150789"] = { name = "4thEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
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
	["90752347516770"] = { name = "2ndEHit", kind = "EHit", hitDelay = 0.30, window = 0.125 },
	-- Striker
	["127909081017342"] = { name = "1stM1", kind = "M1", hitDelay = 0.30, window = 0.125 },
	["118070233153900"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["122451562066756"] = { name = "4thM1", kind = "M1", hitDelay = 0.35, window = 0.125 },
	["114364673509520"] = { name = "M2", kind = "M2", hitDelay = 0.38, window = 0.125 },
	-- Wrestling
	["119685134442395"] = { name = "2ndM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["107464726433388"] = { name = "3rdM1", kind = "M1", hitDelay = 0.28, window = 0.125 },
	["100794890036133"] = { name = "M2Success", kind = "M2", hitDelay = 0.38, window = 0.125 },
	["109303037515668"] = { name = "M2EHit", kind = "M2", hitDelay = 0.38, window = 0.125 },
}

local function classify(name)
	local kind, delay = "M1", 0.32
	if name:find("M2") then
		kind, delay = "M2", 0.38
	elseif name:find("EHit") or name:find("Guardbreak") then
		kind, delay = "EHit", 0.30
	elseif name:find("1stM1") then
		delay = 0.30
	elseif name:find("2ndM1") then
		delay = 0.28
	elseif name:find("3rdM1") then
		delay = 0.28
	elseif name:find("4thM1") then
		delay = 0.35
	end
	return kind, delay
end

local function isAttackName(name)
	if type(name) ~= "string" then
		return false
	end
	if name:find("Block") then
		return false
	end
	if name:find("Idle") or name:find("Walk") or name:find("Run") or name:find("Parry") then
		return false
	end
	return name:find("M1")
		or name:find("M2")
		or name:find("EHit")
		or name:find("Momentum")
		or name:find("Success")
		or (name:find("Hit") ~= nil)
end

function AttackDB.extractId(animationId)
	if type(animationId) == "number" then
		return tostring(math.floor(animationId))
	end
	if type(animationId) ~= "string" then
		return nil
	end
	return animationId:match("%d+")
end

function AttackDB.create()
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
		-- Pull live combat folders when modules are available.
		local utils
		if type(getloadedmodules) == "function" then
			local ok, modules = pcall(getloadedmodules)
			if ok and type(modules) == "table" then
				for _, moduleScript in ipairs(modules) do
					if moduleScript and moduleScript.Name == "CombatAnimationUtils" then
						local reqOk, result = pcall(require, moduleScript)
						if reqOk and type(result) == "table" then
							utils = result
						end
						break
					end
				end
			end
		end

		local function addAnim(style, anim)
			if not anim or not anim:IsA("Animation") then
				return
			end
			local name = anim.Name
			if not isAttackName(name) then
				return
			end
			local id = AttackDB.extractId(anim.AnimationId)
			if not id then
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
				entry.name = entry.name or name
				entry.kind = entry.kind or kind
				entry.hitDelay = entry.hitDelay or delay
			end
			if style and not entry.styles[style] then
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

		if utils and type(utils.GetAllCombatStyles) == "function" then
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

		-- BaseCombat / Combat folders (defensive — some executors restrict certain trees)
		local anims = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
		if anims then
			local base = anims:FindFirstChild("BaseCombat")
			if base then
				for _, d in ipairs(safeDescendants(base)) do
					pcall(addAnim, "Base", d)
				end
			end
			local combat = anims:FindFirstChild("Combat")
			if combat then
				for _, styleFolder in ipairs(combat:GetChildren()) do
					for _, d in ipairs(safeDescendants(styleFolder)) do
						pcall(addAnim, styleFolder.Name, d)
					end
				end
			end
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
		if not id then
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

	-- Seed only at create-time. Live rebuild is expensive (style folders + getloadedmodules)
	-- and must never block hub boot / the multi-game loader.
	local n = 0
	for _ in pairs(byId) do
		n = n + 1
	end
	db.count = n
	db.built = false
	return db
end

return AttackDB
