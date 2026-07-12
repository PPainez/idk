--[[
    xanhub | gakuran | rhythm

    Engine truth (RhythmEngine, live decompile):
      Tap:  press near note.t → score from head timing immediately
      Hold: press near note.t → note.hit=true, holding starts at max(press, note.t)
            keep lane DOWN until note.t+len
            engine auto-scores at hold end while still holding (_judgeHoldNote)
            release AFTER hold end (or after holdJudgment is set)
      Hold grade needs ratio held/len >= 0.95 for PERFECT (with good head timing)
      Early release → EARLY_RELEASE path with ratio often < 0.95 → BAD/OKAY

    NO getgc. Session via getloadedmodules → RhythmServiceClient._session only.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local RunService = ctx.RunService

	-- UI -----------------------------------------------------------------

	local core = columns.rhythmLeft:AddSection("Auto Rhythm")
	core:AddToggle({
		text = "Auto Rhythm",
		flag = "Gakuran Auto Rhythm",
		state = false,
		tip = "Uses real RhythmEngine press/release (all instruments)",
	})
	core:AddToggle({
		text = "Strict Grade Caps",
		flag = "Gakuran Rhythm Strict Grades",
		state = true,
		tip = "Keep head timing inside rolled grade band",
	})
	core:AddToggle({
		text = "Safe Holds (recommended)",
		flag = "Gakuran Rhythm Safe Holds",
		state = true,
		tip = "Holds use tight head timing + release only after chart end (fixes drops)",
	})
	core:AddLabel("Holds need ~95% of tail held — we never early-release")

	local grades = columns.rhythmLeft:AddSection("Grade Mix")
	grades:AddLabel("Weights auto-normalize")
	grades:AddSlider({ text = "Perfect", flag = "Gakuran Rhythm W Perfect", min = 0, max = 100, value = 40, float = 1 })
	grades:AddSlider({ text = "Good", flag = "Gakuran Rhythm W Good", min = 0, max = 100, value = 35, float = 1 })
	grades:AddSlider({ text = "Okay", flag = "Gakuran Rhythm W Okay", min = 0, max = 100, value = 16, float = 1 })
	grades:AddSlider({ text = "Bad", flag = "Gakuran Rhythm W Bad", min = 0, max = 100, value = 6, float = 1 })
	grades:AddSlider({
		text = "Miss",
		flag = "Gakuran Rhythm W Miss",
		min = 0,
		max = 100,
		value = 3,
		float = 1,
		tip = "Taps only — holds never miss when Safe Holds is on",
	})

	local feel = columns.rhythmLeft:AddSection("Human Feel")
	feel:AddSlider({
		text = "Early Bias",
		flag = "Gakuran Rhythm Early Bias",
		min = 0,
		max = 100,
		value = 48,
		float = 1,
		suffix = "%",
	})
	feel:AddSlider({
		text = "Band Depth",
		flag = "Gakuran Rhythm Band Jitter",
		min = 0,
		max = 100,
		value = 50,
		float = 1,
		suffix = "%",
	})
	feel:AddSlider({
		text = "Micro Noise",
		flag = "Gakuran Rhythm Reaction Noise",
		min = 0,
		max = 40,
		value = 6,
		float = 1,
		suffix = " ms",
	})
	feel:AddSlider({
		text = "Consistency",
		flag = "Gakuran Rhythm Consistency",
		min = 0,
		max = 100,
		value = 75,
		float = 1,
		suffix = "%",
	})
	feel:AddSlider({
		text = "Lookahead",
		flag = "Gakuran Rhythm Lookahead",
		min = 300,
		max = 1500,
		value = 900,
		float = 25,
		suffix = " ms",
	})
	feel:AddSlider({
		text = "Tap Length",
		flag = "Gakuran Rhythm Tap Length",
		min = 20,
		max = 100,
		value = 40,
		float = 1,
		suffix = " ms",
		tip = "How long taps stay held (short = next same-lane note can press sooner)",
	})
	feel:AddSlider({
		text = "Hold Extra After End",
		flag = "Gakuran Rhythm Hold Extra Ms",
		min = 10,
		max = 80,
		value = 25,
		float = 1,
		suffix = " ms",
		tip = "Keep key down this long AFTER hold end (engine auto-scores at end)",
	})

	local presets = columns.rhythmRight:AddSection("Presets")
	local function setFlag(name, value)
		local opt = library.options and library.options[name]
		if opt and type(opt.SetValue) == "function" then
			pcall(function()
				opt:SetValue(value)
			end)
		end
		library.flags[name] = value
	end
	local function setWeights(p, g, o, b, m)
		setFlag("Gakuran Rhythm W Perfect", p)
		setFlag("Gakuran Rhythm W Good", g)
		setFlag("Gakuran Rhythm W Okay", o)
		setFlag("Gakuran Rhythm W Bad", b)
		setFlag("Gakuran Rhythm W Miss", m)
	end
	presets:AddButton({
		text = "Legit Skilled",
		callback = function()
			setWeights(40, 35, 16, 6, 3)
			setFlag("Gakuran Rhythm Early Bias", 48)
			setFlag("Gakuran Rhythm Band Jitter", 48)
			setFlag("Gakuran Rhythm Reaction Noise", 6)
			setFlag("Gakuran Rhythm Consistency", 78)
			setFlag("Gakuran Rhythm Safe Holds", true)
			setFlag("Gakuran Rhythm Hold Extra Ms", 25)
			setFlag("Gakuran Rhythm Tap Length", 38)
			ctx.notify("Rhythm: Legit Skilled", 2)
		end,
	})
	presets:AddButton({
		text = "Almost FC",
		callback = function()
			setWeights(78, 16, 5, 1, 0)
			setFlag("Gakuran Rhythm Early Bias", 50)
			setFlag("Gakuran Rhythm Band Jitter", 35)
			setFlag("Gakuran Rhythm Reaction Noise", 3)
			setFlag("Gakuran Rhythm Consistency", 90)
			setFlag("Gakuran Rhythm Safe Holds", true)
			setFlag("Gakuran Rhythm Hold Extra Ms", 30)
			setFlag("Gakuran Rhythm Tap Length", 35)
			ctx.notify("Rhythm: Almost FC", 2)
		end,
	})
	presets:AddButton({
		text = "Godlike",
		callback = function()
			setWeights(100, 0, 0, 0, 0)
			setFlag("Gakuran Rhythm Early Bias", 50)
			setFlag("Gakuran Rhythm Band Jitter", 15)
			setFlag("Gakuran Rhythm Reaction Noise", 1)
			setFlag("Gakuran Rhythm Consistency", 98)
			setFlag("Gakuran Rhythm Safe Holds", true)
			setFlag("Gakuran Rhythm Hold Extra Ms", 30)
			setFlag("Gakuran Rhythm Tap Length", 32)
			ctx.notify("Rhythm: Godlike", 2)
		end,
	})
	presets:AddButton({
		text = "Casual",
		callback = function()
			setWeights(25, 35, 25, 10, 5)
			setFlag("Gakuran Rhythm Early Bias", 45)
			setFlag("Gakuran Rhythm Band Jitter", 70)
			setFlag("Gakuran Rhythm Reaction Noise", 12)
			setFlag("Gakuran Rhythm Consistency", 50)
			setFlag("Gakuran Rhythm Safe Holds", true)
			ctx.notify("Rhythm: Casual", 2)
		end,
	})

	local debugSection = columns.rhythmRight:AddSection("Session")
	debugSection:AddToggle({ text = "Debug Logs", flag = "Gakuran Rhythm Debug", state = false })
	ctx.refs.rhythmStatus = debugSection:AddLabel("Status: idle")
	ctx.refs.rhythmMode = debugSection:AddLabel("Mode: —")
	ctx.refs.rhythmWindows = debugSection:AddLabel("Windows: —")
	ctx.refs.rhythmHolds = debugSection:AddLabel("Holds: —")
	ctx.refs.rhythmMix = debugSection:AddLabel("Mix: —")

	-- State --------------------------------------------------------------

	if type(ctx.state.rhythm) ~= "table" then
		ctx.state.rhythm = {}
	end
	local st = ctx.state.rhythm
	st.planned = {}
	st.laneDown = {} -- lane -> plan currently holding key
	st.service = nil
	st.sessionToken = nil
	st.hits = 0
	st.skips = 0
	st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
	st.lastNow = nil

	local DEFAULT_WINDOWS = { PERFECT = 43, GOOD = 76, OKAY = 106, BAD = 140 }

	-- Helpers ------------------------------------------------------------

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

	local function debugLog(...)
		if flag("Gakuran Rhythm Debug", false) then
			print("[xanhub rhythm]", ...)
		end
	end

	local function setLabel(ref, prefix, text)
		pcall(function()
			if ctx.refs[ref] then
				ctx.refs[ref].Text = prefix .. tostring(text)
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

	local function getSession()
		local service = st.service
		if type(service) ~= "table" then
			service = findLoaded("RhythmServiceClient")
			st.service = service
		end
		if type(service) ~= "table" then
			return nil
		end
		local session = service._session
		if type(session) ~= "table" or session._destroyed or not session._started then
			service = findLoaded("RhythmServiceClient")
			st.service = service
			session = service and service._session
		end
		if type(session) ~= "table" or session._destroyed or not session._started then
			return nil
		end
		if type(session._handleLanePress) ~= "function" or type(session._handleLaneRelease) ~= "function" then
			return nil
		end
		if type(session._now) ~= "function" then
			return nil
		end
		return session, service
	end

	local function sessionId(session, service)
		local p = session._playable
		return table.concat({
			tostring(service and service._startPlaySeq or ""),
			tostring(type(p) == "table" and (p.songId or p.title) or ""),
			tostring(type(p) == "table" and p.mode or ""),
			tostring(session._lanes or ""),
		}, "|")
	end

	local function getWindows(session)
		local w = session._windows
		if type(w) ~= "table" then
			return DEFAULT_WINDOWS
		end
		return {
			PERFECT = tonumber(w.PERFECT) or 43,
			GOOD = tonumber(w.GOOD) or 76,
			OKAY = tonumber(w.OKAY) or 106,
			BAD = tonumber(w.BAD) or 140,
		}
	end

	local function randRange(a, b)
		if a > b then
			a, b = b, a
		end
		return a + math.random() * (b - a)
	end

	local function pickGrade(isHold)
		local weights = {
			{ "PERFECT", math.max(0, numFlag("Gakuran Rhythm W Perfect", 40)) },
			{ "GOOD", math.max(0, numFlag("Gakuran Rhythm W Good", 35)) },
			{ "OKAY", math.max(0, numFlag("Gakuran Rhythm W Okay", 16)) },
			{ "BAD", math.max(0, numFlag("Gakuran Rhythm W Bad", 6)) },
			{ "MISS", math.max(0, numFlag("Gakuran Rhythm W Miss", 3)) },
		}
		if isHold and flag("Gakuran Rhythm Safe Holds", true) then
			weights[5][2] = 0
		end
		local total = 0
		for _, e in ipairs(weights) do
			total = total + e[2]
		end
		if total <= 0 then
			return "PERFECT"
		end
		local r = math.random() * total
		local a = 0
		for _, e in ipairs(weights) do
			a = a + e[2]
			if r <= a then
				return e[1]
			end
		end
		return "PERFECT"
	end

	local function gradeOffsetMs(grade, windows)
		local p, g, o, b = windows.PERFECT, windows.GOOD, windows.OKAY, windows.BAD
		local depth = math.clamp(numFlag("Gakuran Rhythm Band Jitter", 50), 0, 100) / 100
		local cons = math.clamp(numFlag("Gakuran Rhythm Consistency", 75), 0, 100) / 100
		depth = depth * (1 - cons * 0.5)

		local lo, hi = 0, p - 1
		if grade == "GOOD" then
			lo, hi = p + 0.5, g - 0.5
		elseif grade == "OKAY" then
			lo, hi = g + 0.5, o - 0.5
		elseif grade == "BAD" then
			lo, hi = o + 0.5, b - 1
		elseif grade == "MISS" then
			lo, hi = b + 8, b + 30
		end
		hi = math.max(lo, hi)
		local mid = (lo + hi) * 0.5
		local half = (hi - lo) * 0.5 * (0.15 + 0.85 * depth)
		local mag = randRange(math.max(lo, mid - half), math.min(hi, mid + half))
		local early = math.random(1, 100) <= numFlag("Gakuran Rhythm Early Bias", 48)
		local off = early and -mag or mag
		local noise = numFlag("Gakuran Rhythm Reaction Noise", 6) * (1 - cons * 0.5)
		off = off + randRange(-noise, noise)
		if flag("Gakuran Rhythm Strict Grades", true) and grade ~= "MISS" then
			local abs = math.abs(off)
			if grade == "PERFECT" then
				abs = math.clamp(abs, 0, p - 0.5)
			else
				abs = math.clamp(abs, lo, hi)
			end
			off = (off < 0 and -1 or 1) * abs
		end
		return off
	end

	local function noteLen(note)
		local len = tonumber(note.len) or 0
		if len <= 0 and type(note.endT) == "number" then
			len = note.endT - note.t
		end
		return len
	end

	local function clearAll(session)
		if session then
			for lane, plan in pairs(st.laneDown) do
				if plan and plan.pressed and not plan.released then
					pcall(function()
						session:_handleLaneRelease(lane)
					end)
				end
			end
		end
		table.clear(st.planned)
		table.clear(st.laneDown)
	end

	-- Lane free? (no key currently held by us)
	local function laneHeld(lane)
		local p = st.laneDown[lane]
		return p and p.pressed and not p.released
	end

	local function releasePlan(session, plan, why)
		if not plan or plan.released then
			return
		end
		local lane = plan.lane
		if plan.pressed and st.laneDown[lane] == plan then
			pcall(function()
				session:_handleLaneRelease(lane)
			end)
			st.laneDown[lane] = nil
		elseif plan.pressed and not st.laneDown[lane] then
			-- lost ownership tracking; still try release if key stuck
			pcall(function()
				if session._laneKeyDown and session._laneKeyDown[lane] then
					session:_handleLaneRelease(lane)
				end
			end)
		end
		plan.released = true
		debugLog("↑", "L" .. tostring(lane), plan.isHold and "HOLD" or "TAP", why or "")
	end

	local function pressPlan(session, note, plan, now)
		if plan.pressed then
			return true
		end
		if type(note) == "table" and (note.hit or note.attempted) and not note.holding then
			-- already consumed by engine without us — mark done
			if note.hit and note.len <= 0 then
				plan.pressed = true
				plan.released = true
				return true
			end
		end

		local lane = plan.lane

		-- If we still hold this lane for a previous plan, free it first (same-frame chain)
		local owner = st.laneDown[lane]
		if owner and owner ~= plan and owner.pressed and not owner.released then
			if owner.isHold then
				-- Never cut a hold early — wait until its releaseAt
				local freeAt = owner.releaseAt or ((owner.holdEnd or now) + 0.02)
				if now < freeAt then
					plan.hitAt = freeAt + 0.008
					return false
				end
			end
			releasePlan(session, owner, "chain")
		end

		-- If engine thinks key is down but we don't own it, release first
		if session._laneKeyDown and session._laneKeyDown[lane] and st.laneDown[lane] ~= plan then
			pcall(function()
				session:_handleLaneRelease(lane)
			end)
		end

		local ok, err = pcall(function()
			session:_handleLanePress(lane)
		end)
		if not ok then
			debugLog("press fail", err)
			plan.hitAt = now + 0.01
			return false
		end

		plan.pressed = true
		st.laneDown[lane] = plan
		st.hits = (st.hits or 0) + 1

		-- Verify engine accepted head (holds set hit=true; taps may clear from active)
		if plan.isHold and type(note) == "table" then
			if note.hit ~= true and note.attempted == true then
				-- Head was MISS — holding won't work. Release immediately.
				debugLog("hold head MISS", "L" .. tostring(lane))
				releasePlan(session, plan, "head-miss")
				return false
			end
		end

		debugLog(
			"↓",
			"L" .. tostring(lane),
			plan.isHold and "HOLD" or "TAP",
			plan.grade,
			string.format("%+.0fms", plan.offsetMs or 0)
		)
		return true
	end

	local function planNote(note, now, windows, lookahead)
		if type(note) ~= "table" or st.planned[note] then
			return
		end
		if note.hit or note.attempted then
			return
		end
		if type(note.t) ~= "number" or type(note.lane) ~= "number" then
			return
		end

		local eta = note.t - now
		if eta > lookahead or eta < -0.15 then
			return
		end

		local len = noteLen(note)
		local isHold = len > 0.05
		local grade = pickGrade(isHold)
		if isHold and grade == "MISS" then
			grade = "PERFECT"
		end
		st.gradeRolls[grade] = (st.gradeRolls[grade] or 0) + 1

		if grade == "MISS" then
			st.planned[note] = {
				skip = true,
				grade = "MISS",
				lane = note.lane,
				noteT = note.t,
				isHold = false,
			}
			st.skips = (st.skips or 0) + 1
			return
		end

		local offsetMs = gradeOffsetMs(grade, windows)
		-- Holds: keep head VERY tight (late head kills 95% ratio)
		if isHold and flag("Gakuran Rhythm Safe Holds", true) then
			local cap = math.min(windows.PERFECT * 0.7, 22)
			offsetMs = math.clamp(offsetMs, -cap, cap)
		end

		local hitAt = note.t + offsetMs / 1000
		local bad = windows.BAD / 1000 - 0.005
		hitAt = math.clamp(hitAt, note.t - bad, note.t + bad)

		local holdEnd = isHold and (note.t + len) or nil
		local releaseAt
		if isHold then
			-- Engine auto-scores at holdEnd while key still down.
			-- Release slightly AFTER so ratio hits 1.0.
			local extra = math.clamp(numFlag("Gakuran Rhythm Hold Extra Ms", 25), 10, 80) / 1000
			releaseAt = holdEnd + extra
		else
			local tap = math.clamp(numFlag("Gakuran Rhythm Tap Length", 40), 20, 100) / 1000
			releaseAt = hitAt + tap
		end

		st.planned[note] = {
			skip = false,
			grade = grade,
			lane = note.lane,
			noteT = note.t,
			hitAt = hitAt,
			releaseAt = releaseAt,
			holdEnd = holdEnd,
			len = len,
			isHold = isHold,
			offsetMs = offsetMs,
			pressed = false,
			released = false,
			note = note, -- live ref for engine state
		}
	end

	-- Serialize same-lane plans so holds never get cut and taps free the lane for holds
	local function fixLaneSchedule(windows)
		local byLane = {}
		for _, plan in pairs(st.planned) do
			if plan and not plan.skip and not plan.released then
				byLane[plan.lane] = byLane[plan.lane] or {}
				table.insert(byLane[plan.lane], plan)
			end
		end

		for _, list in pairs(byLane) do
			table.sort(list, function(a, b)
				return (a.hitAt or 0) < (b.hitAt or 0)
			end)

			for i = 1, #list - 1 do
				local a, b = list[i], list[i + 1]
				local aEnd = a.isHold and (a.releaseAt or a.holdEnd) or (a.releaseAt or a.hitAt)
				local need = (aEnd or 0) + 0.01

				if a.isHold then
					-- Next must start after this hold fully ends
					if (b.hitAt or 0) < need then
						b.hitAt = need
						if not b.isHold then
							local tap = math.clamp(numFlag("Gakuran Rhythm Tap Length", 40), 20, 100) / 1000
							b.releaseAt = b.hitAt + tap
						else
							-- keep full hold length from original noteT
							if b.holdEnd then
								b.releaseAt = b.holdEnd + math.clamp(numFlag("Gakuran Rhythm Hold Extra Ms", 25), 10, 80) / 1000
							end
						end
					end
				else
					-- Tap: release before next needs the lane
					local freeBy = (b.hitAt or 0) - 0.01
					local minTap = (a.hitAt or 0) + 0.02
					a.releaseAt = math.clamp(math.min(a.releaseAt or freeBy, freeBy), minTap, freeBy + 0.05)
					if a.releaseAt + 0.01 > (b.hitAt or 0) then
						-- push next slightly if still tight (within BAD)
						local maxLate = (windows.BAD / 1000) - 0.01
						b.hitAt = math.min(a.releaseAt + 0.012, (b.noteT or b.hitAt) + maxLate)
						if b.isHold and b.holdEnd then
							b.releaseAt = b.holdEnd + 0.025
						end
					end
				end
			end
		end
	end

	local function process(session, service)
		local ok, now = pcall(function()
			return session:_now()
		end)
		if not ok or type(now) ~= "number" then
			return
		end

		local id = sessionId(session, service)
		if st.sessionToken ~= id then
			clearAll(session)
			st.sessionToken = id
			st.hits = 0
			st.skips = 0
			st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
			local p = session._playable
			local title = type(p) == "table" and tostring(p.title or p.songId or "") or ""
			local mode = type(p) == "table" and tostring(p.mode or "?") or "?"
			setLabel("rhythmMode", "Mode: ", string.format("%s · %dl · %s", mode, tonumber(session._lanes) or 0, title))
			local w = getWindows(session)
			setLabel("rhythmWindows", "Windows: ", string.format("P%d G%d O%d B%d", w.PERFECT, w.GOOD, w.OKAY, w.BAD))
			debugLog("session", id)
		end

		if type(st.lastNow) == "number" and now + 1.2 < st.lastNow then
			clearAll(session)
			debugLog("seek/rewind")
		end
		st.lastNow = now

		local windows = getWindows(session)
		local lookahead = math.clamp(numFlag("Gakuran Rhythm Lookahead", 900), 300, 1500) / 1000

		local active = session._active
		if type(active) == "table" then
			-- _active can be array or map
			for _, note in pairs(active) do
				if type(note) == "table" then
					planNote(note, now, windows, lookahead)
				end
			end
		end

		fixLaneSchedule(windows)

		-- Releases first (so same-frame tap→hold works)
		for _, plan in pairs(st.planned) do
			if plan and plan.pressed and not plan.released then
				local note = plan.note
				-- Hold finished by engine (auto-score at end) → release key
				if plan.isHold and type(note) == "table" and note.holdJudgment then
					releasePlan(session, plan, "engine-done")
				elseif type(plan.releaseAt) == "number" and now >= plan.releaseAt then
					-- For holds: only if past hold end
					if plan.isHold and plan.holdEnd and now < plan.holdEnd then
						-- not yet — force wait
						plan.releaseAt = plan.holdEnd + 0.02
					else
						releasePlan(session, plan, "time")
					end
				end
			end
		end

		-- Presses
		local due = {}
		for note, plan in pairs(st.planned) do
			if plan and not plan.skip and not plan.pressed and type(plan.hitAt) == "number" and now >= plan.hitAt then
				table.insert(due, { note = note, plan = plan })
			end
		end
		table.sort(due, function(a, b)
			local da, db_ = a.plan.hitAt or 0, b.plan.hitAt or 0
			if math.abs(da - db_) < 0.0005 then
				-- simultaneous: all lanes press; holds slightly first on same lane already scheduled
				return (a.plan.lane or 0) < (b.plan.lane or 0)
			end
			return da < db_
		end)

		for _, item in ipairs(due) do
			pressPlan(session, item.note, item.plan, now)
		end

		-- Cleanup old plans
		for note, plan in pairs(st.planned) do
			local t0 = plan.noteT or 0
			local maxAge = plan.isHold and ((plan.holdEnd or t0) - t0 + 2.5) or 2
			if now - t0 > maxAge then
				if st.laneDown[plan.lane] == plan then
					releasePlan(session, plan, "timeout")
				end
				st.planned[note] = nil
			elseif plan.skip and now - t0 > 1 then
				st.planned[note] = nil
			elseif plan.pressed and plan.released and now > (plan.releaseAt or t0) + 0.3 then
				st.planned[note] = nil
			end
		end

		local held = 0
		for _, p in pairs(st.laneDown) do
			if p and p.pressed and not p.released then
				held = held + 1
			end
		end
		setLabel("rhythmHolds", "Holds: ", string.format("%d keys down", held))
	end

	local function setup()
		local statusAccum = 0
		local resolveAccum = 0

		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran Auto Rhythm", false) then
				if next(st.planned) then
					local session = getSession()
					clearAll(session)
				end
				return
			end

			dt = tonumber(dt) or 0
			statusAccum = statusAccum + dt
			resolveAccum = resolveAccum + dt

			local session, service = getSession()
			if not session then
				if resolveAccum >= 0.7 then
					resolveAccum = 0
					st.service = nil
					st.sessionToken = nil
					clearAll(nil)
					setLabel("rhythmStatus", "Status: ", "waiting for song")
				end
				return
			end

			local ok, err = pcall(process, session, service)
			if not ok then
				debugLog("err", err)
				if statusAccum >= 1 then
					statusAccum = 0
					setLabel("rhythmStatus", "Status: ", "error " .. tostring(err):sub(1, 60))
				end
				return
			end

			if statusAccum >= 0.8 then
				statusAccum = 0
				local j = session._judgeCounts
				setLabel(
					"rhythmStatus",
					"Status: ",
					string.format(
						"P%s G%s O%s B%s M%s · c%s",
						tostring(j and j.PERFECT),
						tostring(j and j.GOOD),
						tostring(j and j.OKAY),
						tostring(j and j.BAD),
						tostring(j and j.MISS),
						tostring(session._combo)
					)
				)
				local r = st.gradeRolls
				setLabel(
					"rhythmMix",
					"Mix: ",
					string.format(
						"plan P%d G%d O%d B%d M%d · hits %d",
						r.PERFECT or 0,
						r.GOOD or 0,
						r.OKAY or 0,
						r.BAD or 0,
						r.MISS or 0,
						st.hits or 0
					)
				)
			end
		end)

		setLabel("rhythmStatus", "Status: ", "idle")
		setLabel("rhythmMode", "Mode: ", "—")
		setLabel("rhythmWindows", "Windows: ", "—")
		setLabel("rhythmHolds", "Holds: ", "—")
		setLabel("rhythmMix", "Mix: ", "—")
	end

	library:AddCleanup(function()
		local session = getSession()
		clearAll(session)
		st.service = nil
		st.sessionToken = nil
	end)

	return { setup = setup }
end
