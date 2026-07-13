--[[
    xanhub | gakuran | rhythm

    RhythmEngine (live):
      Tap  → press near note.t, judged by |press - note.t|
      Hold → press head, keep lane down until note.t+len, engine scores at end
             hold PERFECT needs ratio >= 0.95 and non-MISS head
      _reconcileStaleKeyboardReleases drops synthetic presses unless
      _laneTouchActive[lane] is true — we latch that while we own the key

    Grade weights control the *intended* judgment. hitAt is always kept inside
    the rolled grade band. Lane conflicts shorten previous taps — they never
    shove the next note into a worse band.

    v2 stability changes:
      • never marks _laneKeyDown before RhythmEngine sees the press
      • dual-phase scheduler (Heartbeat + RenderStepped)
      • frame-lag compensation learned from real press lateness
      • unexpected-miss recovery temporarily favors safe PERFECT hits
      • lane re-arm verification/retry for dense same-lane patterns

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
		tip = "Press timing always stays inside the rolled grade band",
	})
	core:AddToggle({
		text = "Safe Holds (recommended)",
		flag = "Gakuran Rhythm Safe Holds",
		state = true,
		tip = "Holds use tight PERFECT/GOOD heads + full tail (no early release)",
	})
	core:AddToggle({
		text = "Adaptive Timing",
		flag = "Gakuran Rhythm Adaptive Timing",
		state = true,
		tip = "Learns frame delay and presses slightly ahead to cancel scheduler lateness",
	})
	core:AddToggle({
		text = "Miss Guard",
		flag = "Gakuran Rhythm Miss Guard",
		state = true,
		tip = "Unexpected misses trigger a short recovery period with safer timing",
	})
	core:AddLabel("Weights = intended judgments · system misses are auto-corrected")

	local grades = columns.rhythmLeft:AddSection("Grade Mix")
	grades:AddLabel("Weights auto-normalize · rare grades anti-streak")
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
		tip = "Taps only — holds never intentional-miss when Safe Holds is on",
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
		tip = "How long taps stay held (shorter = denser same-lane streams OK)",
	})
	feel:AddSlider({
		text = "Hold Extra After End",
		flag = "Gakuran Rhythm Hold Extra Ms",
		min = 10,
		max = 80,
		value = 25,
		float = 1,
		suffix = " ms",
		tip = "Keep key down after hold end (engine auto-scores at end)",
	})
	feel:AddSlider({
		text = "Maximum Auto Lead",
		flag = "Gakuran Rhythm Max Lead Ms",
		min = 2,
		max = 20,
		value = 12,
		float = 1,
		suffix = " ms",
		tip = "Upper limit for learned frame-delay compensation",
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
	ctx.refs.rhythmTiming = debugSection:AddLabel("Timing: —")
	ctx.refs.rhythmMix = debugSection:AddLabel("Mix: —")

	-- State --------------------------------------------------------------

	if type(ctx.state.rhythm) ~= "table" then
		ctx.state.rhythm = {}
	end
	local st = ctx.state.rhythm
	st.planned = {}
	st.laneDown = {}
	st.service = nil
	st.sessionToken = nil
	st.hits = 0
	st.skips = 0
	st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
	st.gradeActual = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
	st.recentGrades = {}
	st.lastNow = nil
	st.frameDt = 1 / 60
	st.schedulerLateMs = 0
	st.adaptiveLeadMs = 3
	st.recoveryUntil = 0
	st.unexpectedMisses = 0
	st.intentionalMissBudget = 0
	st.lastJudgeMiss = nil
	st.lastSuccessfulPressAt = 0
	st.processBusy = false

	local DEFAULT_WINDOWS = { PERFECT = 43, GOOD = 76, OKAY = 106, BAD = 140 }
	local GRADE_ORDER = { "PERFECT", "GOOD", "OKAY", "BAD", "MISS" }

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

	local function currentLeadMs()
		if not flag("Gakuran Rhythm Adaptive Timing", true) then
			return 0
		end
		local maximum = math.clamp(numFlag("Gakuran Rhythm Max Lead Ms", 12), 2, 20)
		local learned = tonumber(st.adaptiveLeadMs) or 3
		if (tonumber(st.recoveryUntil) or 0) > (tonumber(st.lastNow) or 0) then
			learned = learned + 2
		end
		return math.clamp(learned, 0, maximum)
	end

	local function observePressLateness(now, plan)
		if not flag("Gakuran Rhythm Adaptive Timing", true) or not plan then
			return
		end
		local target = tonumber(plan.hitAt)
		if not target then
			return
		end
		local lateMs = math.max(0, (now - target) * 1000)
		st.schedulerLateMs = (tonumber(st.schedulerLateMs) or 0) * 0.82 + lateMs * 0.18
		local maximum = math.clamp(numFlag("Gakuran Rhythm Max Lead Ms", 12), 2, 20)
		local desired = math.clamp(2 + st.schedulerLateMs * 0.72, 2, maximum)
		st.adaptiveLeadMs = (tonumber(st.adaptiveLeadMs) or 3) * 0.90 + desired * 0.10
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

	local function hardenSession(session)
		-- Older builds replaced _reconcileStaleKeyboardReleases with a no-op.
		-- That can leave RhythmEngine in a poisoned state and make later presses
		-- disappear. We only identify the session here; owned lanes are protected
		-- through _laneTouchActive instead.
		if type(session) ~= "table" then
			return
		end
		session.__xhRhythmHoldFix = true
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
		hardenSession(session)
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

	local function noteLen(note)
		local len = tonumber(note.len) or 0
		if len <= 0 and type(note.endT) == "number" and type(note.t) == "number" then
			len = note.endT - note.t
		end
		return len
	end

	-- Grade bands (ms absolute). Outer edge kept clear of next worse / MISS.
	local function gradeBandMs(grade, windows)
		local p, g, o, b = windows.PERFECT, windows.GOOD, windows.OKAY, windows.BAD
		if grade == "PERFECT" then
			return 0, math.max(0, p - 2)
		elseif grade == "GOOD" then
			return p + 1, math.max(p + 1, g - 2)
		elseif grade == "OKAY" then
			return g + 1, math.max(g + 1, o - 2)
		elseif grade == "BAD" then
			return o + 1, math.max(o + 1, b - 16)
		elseif grade == "MISS" then
			return b + 12, b + 40
		end
		return 0, math.max(0, p - 2)
	end

	local function rawWeights(isHold)
		local w = {
			PERFECT = math.max(0, numFlag("Gakuran Rhythm W Perfect", 40)),
			GOOD = math.max(0, numFlag("Gakuran Rhythm W Good", 35)),
			OKAY = math.max(0, numFlag("Gakuran Rhythm W Okay", 16)),
			BAD = math.max(0, numFlag("Gakuran Rhythm W Bad", 6)),
			MISS = math.max(0, numFlag("Gakuran Rhythm W Miss", 3)),
		}
		if isHold and flag("Gakuran Rhythm Safe Holds", true) then
			-- Holds: PERFECT/GOOD heads only so ratio can stay ≥0.95
			w.OKAY = 0
			w.BAD = 0
			w.MISS = 0
			if w.PERFECT + w.GOOD <= 0 then
				w.PERFECT = 1
			end
		end
		return w
	end

	-- Quota + anti-streak: rare grades (e.g. OKAY=1) won't clump in a row.
	local function pickGrade(isHold)
		if flag("Gakuran Rhythm Miss Guard", true)
			and (tonumber(st.recoveryUntil) or 0) > (tonumber(st.lastNow) or 0) then
			return "PERFECT"
		end
		local w = rawWeights(isHold)
		local totalW = 0
		for _, name in ipairs(GRADE_ORDER) do
			totalW = totalW + w[name]
		end
		if totalW <= 0 then
			return "PERFECT"
		end

		local rolled = st.gradeRolls
		local totalRolled = 0
		for _, name in ipairs(GRADE_ORDER) do
			totalRolled = totalRolled + (rolled[name] or 0)
		end

		-- Effective weight = base * (how far behind quota) * anti-streak
		local bestName, bestScore = "PERFECT", -1e9
		for _, name in ipairs(GRADE_ORDER) do
			local base = w[name]
			if base > 0 then
				local share = base / totalW
				local expected = (totalRolled + 1) * share
				local have = rolled[name] or 0
				local deficit = expected - have

				-- Anti-streak: if this grade appeared recently and is rare, crush weight
				local recentHit = 0
				local look = st.recentGrades
				local window = math.min(#look, 12)
				for i = #look, #look - window + 1, -1 do
					if look[i] == name then
						recentHit = recentHit + 1
					end
				end
				local rarity = share
				local streakPenalty = 1
				if rarity < 0.08 and recentHit > 0 then
					streakPenalty = 0.02 -- almost never back-to-back rare grades
				elseif rarity < 0.20 and recentHit >= 2 then
					streakPenalty = 0.15
				elseif recentHit >= 3 then
					streakPenalty = 0.35
				end

				-- Prefer grades we're behind on; small random so not fully deterministic
				local score = (deficit + 0.35) * base * streakPenalty * randRange(0.85, 1.15)
				if score > bestScore then
					bestScore = score
					bestName = name
				end
			end
		end

		return bestName
	end

	local function rememberGrade(grade)
		local look = st.recentGrades
		look[#look + 1] = grade
		if #look > 24 then
			table.remove(look, 1)
		end
		st.gradeRolls[grade] = (st.gradeRolls[grade] or 0) + 1
	end

	-- Offset strictly inside the rolled grade band (signed ms).
	local function gradeOffsetMs(grade, windows)
		local lo, hi = gradeBandMs(grade, windows)
		local depth = math.clamp(numFlag("Gakuran Rhythm Band Jitter", 50), 0, 100) / 100
		local cons = math.clamp(numFlag("Gakuran Rhythm Consistency", 75), 0, 100) / 100
		depth = depth * (1 - cons * 0.55)

		local mid = (lo + hi) * 0.5
		local half = (hi - lo) * 0.5 * (0.12 + 0.88 * depth)
		local mag = randRange(math.max(lo, mid - half), math.min(hi, mid + half))

		local early = math.random(1, 100) <= numFlag("Gakuran Rhythm Early Bias", 48)
		local off = early and -mag or mag

		local noise = numFlag("Gakuran Rhythm Reaction Noise", 6) * (1 - cons * 0.55)
		off = off + randRange(-noise, noise)

		-- Always re-clamp into band (noise must not change the judgment)
		local abs = math.abs(off)
		if flag("Gakuran Rhythm Strict Grades", true) or grade ~= "MISS" then
			abs = math.clamp(abs, lo, hi)
			off = (off < 0 and -1 or 1) * abs
			if abs == 0 then
				off = 0
			end
		end
		return off
	end

	-- Clamp hitAt to the plan's rolled grade band (not the full BAD window).
	local function clampHitAtToGrade(plan, windows)
		if not plan or type(plan.noteT) ~= "number" then
			return
		end
		local grade = plan.grade or "PERFECT"
		if grade == "MISS" then
			return
		end
		local lo, hi = gradeBandMs(grade, windows)
		local noteT = plan.noteT
		local offMs = ((plan.hitAt or noteT) - noteT) * 1000
		local sign = offMs < 0 and -1 or 1
		local abs = math.clamp(math.abs(offMs), lo, hi)
		-- Prefer preserving side; if zero-ish, use original sign from offsetMs
		if math.abs(offMs) < 0.25 then
			sign = (plan.offsetMs or 0) < 0 and -1 or 1
			if (plan.offsetMs or 0) == 0 then
				sign = 1
			end
		end
		plan.hitAt = noteT + (sign * abs) / 1000
		plan.offsetMs = sign * abs
	end

	local function latchLane(session, lane, on)
		if type(session) ~= "table" or type(lane) ~= "number" then
			return
		end
		pcall(function()
			if type(session._laneTouchActive) == "table" then
				session._laneTouchActive[lane] = on and true or false
			end
			-- Critical: never set _laneKeyDown=true before _handleLanePress.
			-- RhythmEngine commonly uses that field as its duplicate-input guard.
			if not on and type(session._laneKeyDown) == "table" then
				session._laneKeyDown[lane] = false
			end
		end)
	end

	local function clearAll(session)
		if session then
			for lane, plan in pairs(st.laneDown) do
				if plan and plan.pressed and not plan.released then
					latchLane(session, lane, false)
					pcall(function()
						session:_handleLaneRelease(lane)
					end)
				end
			end
		end
		table.clear(st.planned)
		table.clear(st.laneDown)
	end

	local function releasePlan(session, plan, why)
		if not plan or plan.released then
			return
		end
		local lane = plan.lane
		if plan.pressed and st.laneDown[lane] == plan then
			latchLane(session, lane, false)
			pcall(function()
				session:_handleLaneRelease(lane)
			end)
			st.laneDown[lane] = nil
		elseif plan.pressed then
			latchLane(session, lane, false)
			pcall(function()
				if session._laneKeyDown and session._laneKeyDown[lane] then
					session:_handleLaneRelease(lane)
				end
			end)
		end
		plan.released = true
		debugLog("↑", "L" .. tostring(lane), plan.isHold and "HOLD" or "TAP", why or "")
	end

	local function pressPlan(session, note, plan, now, windows)
		if plan.pressed then
			return true
		end
		if type(note) == "table" and (note.hit or note.attempted) and not note.holding then
			if note.hit and (tonumber(note.len) or 0) <= 0 then
				plan.pressed = true
				plan.released = true
				return true
			end
		end

		local lane = plan.lane
		local noteT = plan.noteT or (type(note) == "table" and note.t) or now
		local _, gradeHi = gradeBandMs(plan.grade or "PERFECT", windows)
		if (plan.grade or "PERFECT") == "MISS" then
			gradeHi = windows.BAD + 40
		end
		-- Latest press still inside rolled grade (with tiny frame slack)
		local maxLate = noteT + (gradeHi + 4) / 1000

		local owner = st.laneDown[lane]
		if owner and owner ~= plan and owner.pressed and not owner.released then
			if owner.isHold then
				local freeAt = owner.releaseAt or ((owner.holdEnd or now) + 0.02)
				if now < freeAt then
					-- Wait for hold; do NOT schedule past our grade band
					if freeAt <= maxLate then
						plan.hitAt = freeAt + 0.004
					else
						-- Hold blocks past our band — wait; press ASAP when free
						-- (grade may degrade; rare, only dense chart after long holds)
						plan.hitAt = freeAt + 0.004
						plan.forcedLate = true
					end
					return false
				end
			end
			releasePlan(session, owner, "chain")
		end

		if session._laneKeyDown and session._laneKeyDown[lane] and st.laneDown[lane] ~= plan then
			latchLane(session, lane, false)
			pcall(function()
				session:_handleLaneRelease(lane)
			end)
		end

		-- If we are early vs planned hitAt, wait (unless already past)
		if type(plan.hitAt) == "number" and now + 0.0005 < plan.hitAt and not plan.forcedLate then
			return false
		end

		-- If lag put us past grade band, snap to band edge (same grade), not BAD edge
		if type(plan.hitAt) == "number" and now > maxLate and not plan.forcedLate then
			-- Too late for rolled grade — still try if within BAD so we don't miss
			local badCap = noteT + (windows.BAD - 8) / 1000
			if now > badCap then
				plan.pressed = true
				plan.released = true
				st.skips = (st.skips or 0) + 1
				debugLog("drop late", "L" .. tostring(lane))
				return false
			end
		end

		-- Protect the lane from stale-release cleanup, but leave _laneKeyDown
		-- untouched until RhythmEngine processes the press itself.
		pcall(function()
			if type(session._laneTouchActive) == "table" then
				session._laneTouchActive[lane] = true
			end
		end)
		local ok, err = pcall(function()
			session:_handleLanePress(lane)
		end)
		if not ok then
			latchLane(session, lane, false)
			debugLog("press fail", err)
			plan.hitAt = now + 0.004
			return false
		end

		-- Some engine builds can ignore the first call during a same-lane re-arm.
		-- Verify state and retry once without pre-marking the lane as down.
		local registered = true
		if type(session._laneKeyDown) == "table" then
			registered = session._laneKeyDown[lane] == true
		end
		if not registered and type(note) == "table" and not note.hit and not note.attempted then
			pcall(function()
				if type(session._laneKeyDown) == "table" then
					session._laneKeyDown[lane] = false
				end
				session:_handleLanePress(lane)
			end)
		end
		latchLane(session, lane, true)
		observePressLateness(now, plan)

		plan.pressed = true
		plan.pressedAt = now
		st.laneDown[lane] = plan
		st.hits = (st.hits or 0) + 1

		if plan.isHold and type(note) == "table" then
			if note.hit ~= true and note.attempted == true then
				debugLog("hold head MISS", "L" .. tostring(lane))
				releasePlan(session, plan, "head-miss")
				return false
			end
		end

		debugLog("↓", "L" .. tostring(lane), plan.isHold and "HOLD" or "TAP", plan.grade, string.format("%+.0fms", (now - noteT) * 1000))
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
		if eta > lookahead or eta < -0.12 then
			return
		end

		local len = noteLen(note)
		local isHold = len > 0.05
		local grade = pickGrade(isHold)

		if grade == "MISS" then
			if isHold then
				grade = "PERFECT"
			else
				rememberGrade("MISS")
				st.planned[note] = {
					skip = true,
					grade = "MISS",
					lane = note.lane,
					noteT = note.t,
					isHold = false,
					pressed = false,
					released = false,
				}
				st.skips = (st.skips or 0) + 1
				st.intentionalMissBudget = (st.intentionalMissBudget or 0) + 1
				return
			end
		end

		rememberGrade(grade)

		local offsetMs = gradeOffsetMs(grade, windows)
		if isHold and flag("Gakuran Rhythm Safe Holds", true) then
			-- Keep head inside PERFECT window so hold ratio can stay ≥0.95
			local cap = math.min(windows.PERFECT * 0.55, 16)
			offsetMs = math.clamp(offsetMs, -cap, cap)
			if math.abs(offsetMs) > windows.PERFECT then
				offsetMs = (offsetMs < 0 and -1 or 1) * cap
			end
			-- Re-label if we forced perfect head
			if grade ~= "PERFECT" and grade ~= "GOOD" then
				grade = "PERFECT"
			end
		end

		-- Compensate for frame scheduling delay. The final clamp below keeps the
		-- result inside the chosen judgment band, so this cannot silently turn a
		-- PERFECT/GOOD plan into a worse grade.
		local leadMs = grade == "MISS" and 0 or currentLeadMs()
		local hitAt = note.t + (offsetMs - leadMs) / 1000
		local holdEnd = isHold and (note.t + len) or nil
		local holdExtra = math.clamp(numFlag("Gakuran Rhythm Hold Extra Ms", 25), 10, 80) / 1000
		local tapLen = math.clamp(numFlag("Gakuran Rhythm Tap Length", 40), 20, 100) / 1000

		local plan = {
			skip = false,
			grade = grade,
			lane = note.lane,
			noteT = note.t,
			hitAt = hitAt,
			releaseAt = isHold and (holdEnd + holdExtra) or (hitAt + tapLen),
			holdEnd = holdEnd,
			len = len,
			isHold = isHold,
			offsetMs = offsetMs,
			pressed = false,
			released = false,
			note = note,
		}
		clampHitAtToGrade(plan, windows)
		if not plan.isHold then
			plan.releaseAt = plan.hitAt + tapLen
		end
		st.planned[note] = plan
	end

	--[[
	  Same-lane schedule:
	  - Never push next.hitAt outside its rolled grade band
	  - Resolve conflicts by shortening previous TAP release
	  - Holds keep full tail; next waits only if still inside its grade band
	]]
	local function fixLaneSchedule(windows)
		local byLane = {}
		for _, plan in pairs(st.planned) do
			if plan and not plan.skip and not plan.released then
				byLane[plan.lane] = byLane[plan.lane] or {}
				table.insert(byLane[plan.lane], plan)
			end
		end

		local tapLen = math.clamp(numFlag("Gakuran Rhythm Tap Length", 40), 20, 100) / 1000
		local holdExtra = math.clamp(numFlag("Gakuran Rhythm Hold Extra Ms", 25), 10, 80) / 1000

		for _, list in pairs(byLane) do
			table.sort(list, function(a, b)
				return (a.noteT or 0) < (b.noteT or 0)
			end)

			for i = 1, #list - 1 do
				local a, b = list[i], list[i + 1]
				if a.pressed then
					-- live owner handled in pressPlan
				else
					clampHitAtToGrade(a, windows)
				end
				if not b.pressed then
					clampHitAtToGrade(b, windows)
				end

				local bLo, bHi = gradeBandMs(b.grade or "PERFECT", windows)
				local bNoteT = b.noteT or 0
				local bEarliest = bNoteT - bHi / 1000
				local bLatest = bNoteT + bHi / 1000
				-- keep intended side if possible
				local bTarget = b.hitAt or bNoteT

				if a.isHold then
					local freeAt = (a.releaseAt or a.holdEnd or a.hitAt or 0) + 0.006
					if bTarget < freeAt then
						if freeAt <= bLatest then
							b.hitAt = freeAt
						else
							-- Cannot both finish hold and keep next grade — keep hold,
							-- next presses ASAP after free (forcedLate path)
							b.hitAt = freeAt
							b.forcedLate = true
						end
					end
				else
					-- Previous is tap: free lane before next target
					local needFreeBy = math.min(bTarget, bLatest) - 0.006
					local minTapEnd = (a.hitAt or a.noteT or 0) + 0.016
					if needFreeBy < minTapEnd then
						needFreeBy = minTapEnd
					end
					a.releaseAt = math.min(a.releaseAt or (a.hitAt + tapLen), needFreeBy)
					if a.releaseAt < minTapEnd then
						a.releaseAt = minTapEnd
					end
					if a.releaseAt + 0.004 > bTarget then
						local pushed = a.releaseAt + 0.005
						if pushed <= bLatest then
							b.hitAt = math.max(pushed, bEarliest)
						else
							-- Stay in band: keep b at latest in-band, cut a more
							b.hitAt = bLatest
							a.releaseAt = math.min(a.releaseAt, b.hitAt - 0.005)
							if a.releaseAt < minTapEnd then
								a.releaseAt = minTapEnd
							end
						end
					end
				end

				if not b.pressed and not b.forcedLate then
					clampHitAtToGrade(b, windows)
				end
				if b.isHold and b.holdEnd then
					b.releaseAt = b.holdEnd + holdExtra
				elseif not b.isHold then
					b.releaseAt = (b.hitAt or bNoteT) + tapLen
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
			st.gradeActual = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
			st.recentGrades = {}
			st.intentionalMissBudget = 0
			st.lastJudgeMiss = nil
			st.unexpectedMisses = 0
			st.recoveryUntil = 0
			st.schedulerLateMs = 0
			st.adaptiveLeadMs = 3
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

		-- Distinguish intentional weighted misses from actual system misses.
		-- Unexpected misses trigger a short safe-timing recovery and increase
		-- learned lead slightly, instead of letting one bad frame snowball.
		local counts = session._judgeCounts
		local missCount = counts and tonumber(counts.MISS)
		if missCount then
			if st.lastJudgeMiss == nil then
				st.lastJudgeMiss = missCount
			elseif missCount > st.lastJudgeMiss then
				local delta = missCount - st.lastJudgeMiss
				local intentional = math.min(delta, tonumber(st.intentionalMissBudget) or 0)
				st.intentionalMissBudget = math.max(0, (tonumber(st.intentionalMissBudget) or 0) - intentional)
				local unexpected = delta - intentional
				if unexpected > 0 then
					st.unexpectedMisses = (st.unexpectedMisses or 0) + unexpected
					if flag("Gakuran Rhythm Miss Guard", true) then
						st.recoveryUntil = now + 3.5
						st.adaptiveLeadMs = math.min(
							math.clamp(numFlag("Gakuran Rhythm Max Lead Ms", 12), 2, 20),
							(tonumber(st.adaptiveLeadMs) or 3) + 1.5
						)
					end
					debugLog("unexpected miss", unexpected, "lead", string.format("%.1f", st.adaptiveLeadMs or 0))
				end
				st.lastJudgeMiss = missCount
			end
		end

		local windows = getWindows(session)
		local lookahead = math.clamp(numFlag("Gakuran Rhythm Lookahead", 900), 300, 1500) / 1000

		local active = session._active
		if type(active) == "table" then
			for _, note in pairs(active) do
				if type(note) == "table" then
					planNote(note, now, windows, lookahead)
				end
			end
		end

		fixLaneSchedule(windows)

		-- Hold latch reassert
		for lane, plan in pairs(st.laneDown) do
			if plan and plan.pressed and not plan.released then
				latchLane(session, lane, true)
				if plan.isHold then
					local note = plan.note
					local needEnd = plan.holdEnd
					local stillNeed = type(needEnd) == "number" and now < needEnd - 0.01
					local keyDown = session._laneKeyDown and session._laneKeyDown[lane]
					if stillNeed and type(note) == "table" and not note.holdJudgment then
						if not keyDown or (note.hit and not note.holding and note.t and now >= note.t) then
							pcall(function()
								session:_handleLanePress(lane)
							end)
							latchLane(session, lane, true)
						end
					end
				end
			end
		end

		-- Releases
		for _, plan in pairs(st.planned) do
			if plan and plan.pressed and not plan.released then
				local note = plan.note
				if plan.isHold and type(note) == "table" and note.holdJudgment then
					releasePlan(session, plan, "engine-done")
				elseif type(plan.releaseAt) == "number" and now >= plan.releaseAt then
					if plan.isHold and plan.holdEnd and now < plan.holdEnd then
						plan.releaseAt = plan.holdEnd + 0.02
						latchLane(session, plan.lane, true)
					else
						releasePlan(session, plan, "time")
					end
				end
			end
		end

		-- Presses
		local due = {}
		for note, plan in pairs(st.planned) do
			if plan and not plan.skip and not plan.pressed and type(plan.hitAt) == "number" then
				if now >= plan.hitAt - 0.0005 then
					table.insert(due, { note = note, plan = plan })
				end
			end
		end
		table.sort(due, function(a, b)
			local da, db_ = a.plan.hitAt or 0, b.plan.hitAt or 0
			if math.abs(da - db_) < 0.0005 then
				return (a.plan.lane or 0) < (b.plan.lane or 0)
			end
			return da < db_
		end)
		for _, item in ipairs(due) do
			pressPlan(session, item.note, item.plan, now, windows)
		end

		-- Cleanup
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

		-- Kill any leftover live V2 bot from earlier hotpatches
		pcall(function()
			local env = (type(getgenv) == "function" and getgenv()) or _G
			local fix = env.__xhRhythmLegitFix
			if type(fix) == "table" then
				if fix.conn then
					pcall(function()
						fix.conn:Disconnect()
					end)
				end
				if fix.guardConn then
					pcall(function()
						fix.guardConn:Disconnect()
					end)
				end
				env.__xhRhythmLegitFix = nil
			end
		end)

		local function schedulerStep(dt, phase)
			if ctx.state.unloading or st.processBusy then
				return
			end
			if not flag("Gakuran Auto Rhythm", false) then
				if next(st.planned) then
					clearAll(getSession())
				end
				return
			end

			dt = tonumber(dt) or 0
			if dt > 0 and dt < 0.25 then
				st.frameDt = (tonumber(st.frameDt) or dt) * 0.90 + dt * 0.10
			end
			if phase == "heartbeat" then
				statusAccum = statusAccum + dt
				resolveAccum = resolveAccum + dt
			end

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

			st.processBusy = true
			local ok, err = pcall(process, session, service)
			st.processBusy = false
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
				local recovering = (tonumber(st.recoveryUntil) or 0) > (tonumber(st.lastNow) or 0)
				setLabel(
					"rhythmTiming",
					"Timing: ",
					string.format(
						"lead %.1fms · late %.1fms · %s · uM%d",
						currentLeadMs(),
						tonumber(st.schedulerLateMs) or 0,
						recovering and "RECOVERY" or "stable",
						tonumber(st.unexpectedMisses) or 0
					)
				)
				local r = st.gradeRolls
				local tw = rawWeights(false)
				local sum = tw.PERFECT + tw.GOOD + tw.OKAY + tw.BAD + tw.MISS
				setLabel(
					"rhythmMix",
					"Mix: ",
					string.format(
						"w %d/%d/%d/%d/%d · plan P%d G%d O%d B%d M%d",
						tw.PERFECT,
						tw.GOOD,
						tw.OKAY,
						tw.BAD,
						tw.MISS,
						r.PERFECT or 0,
						r.GOOD or 0,
						r.OKAY or 0,
						r.BAD or 0,
						r.MISS or 0
					)
				)
			end
		end

		-- Heartbeat sees newly activated notes after simulation; RenderStepped gives
		-- a second chance in the same frame on clients where session updates happen
		-- later than our Heartbeat connection. process() is idempotent per plan.
		ctx.addConnection(RunService.Heartbeat, function(dt)
			schedulerStep(dt, "heartbeat")
		end)
		ctx.addConnection(RunService.RenderStepped, function(dt)
			schedulerStep(dt, "render")
		end)

		setLabel("rhythmStatus", "Status: ", "idle")
		setLabel("rhythmMode", "Mode: ", "—")
		setLabel("rhythmWindows", "Windows: ", "—")
		setLabel("rhythmHolds", "Holds: ", "—")
		setLabel("rhythmTiming", "Timing: ", "—")
		setLabel("rhythmMix", "Mix: ", "—")
	end

	library:AddCleanup(function()
		clearAll(getSession())
		st.service = nil
		st.sessionToken = nil
	end)

	return { setup = setup }
end
