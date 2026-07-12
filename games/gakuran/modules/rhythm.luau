--[[
    xanhub | gakuran | rhythm

    Auto Rhythm for all instruments (Guitar 2-lane, 4-lane charts, etc).
    Uses live RhythmServiceClient._session (RhythmEngine):
      session:_now()
      session._active notes
      session:_handleLanePress(lane) / :_handleLaneRelease(lane)

    Judgement windows (default ms, may be overridden per chart):
      PERFECT ≤ 43 · GOOD ≤ 76 · OKAY ≤ 106 · BAD ≤ 140 · else MISS
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local RunService = ctx.RunService

	-- UI: core -----------------------------------------------------------

	local core = columns.rhythmLeft:AddSection("Auto Rhythm")
	core:AddToggle({
		text = "Auto Rhythm",
		flag = "Gakuran Auto Rhythm",
		state = false,
		tip = "Plays through the real engine for any instrument session",
	})
	core:AddToggle({
		text = "Strict Grade Caps",
		flag = "Gakuran Rhythm Strict Grades",
		state = true,
		tip = "Never lands better than the rolled grade (no accidental perfects)",
	})
	core:AddLabel("Works on Guitar (2 lane) · full charts (4 lane) · holds")

	-- UI: grade mix (weights, auto-normalized) ---------------------------

	local grades = columns.rhythmLeft:AddSection("Grade Mix (weights)")
	grades:AddLabel("Relative weights — do not need to sum to 100")
	grades:AddSlider({
		text = "Perfect Weight",
		flag = "Gakuran Rhythm W Perfect",
		min = 0,
		max = 100,
		value = 45,
		float = 1,
	})
	grades:AddSlider({
		text = "Good Weight",
		flag = "Gakuran Rhythm W Good",
		min = 0,
		max = 100,
		value = 30,
		float = 1,
	})
	grades:AddSlider({
		text = "Okay Weight",
		flag = "Gakuran Rhythm W Okay",
		min = 0,
		max = 100,
		value = 15,
		float = 1,
	})
	grades:AddSlider({
		text = "Bad Weight",
		flag = "Gakuran Rhythm W Bad",
		min = 0,
		max = 100,
		value = 5,
		float = 1,
	})
	grades:AddSlider({
		text = "Miss Weight",
		flag = "Gakuran Rhythm W Miss",
		min = 0,
		max = 100,
		value = 5,
		float = 1,
		tip = "Skip the note entirely (intentional miss)",
	})

	-- UI: timing feel ----------------------------------------------------

	local timing = columns.rhythmRight:AddSection("Timing Feel")
	timing:AddSlider({
		text = "Early Bias",
		flag = "Gakuran Rhythm Early Bias",
		min = 0,
		max = 100,
		value = 48,
		float = 1,
		suffix = "%",
		tip = "Chance a hit is early vs late within its grade band",
	})
	timing:AddSlider({
		text = "Band Jitter",
		flag = "Gakuran Rhythm Band Jitter",
		min = 0,
		max = 100,
		value = 55,
		float = 1,
		suffix = "%",
		tip = "How randomly timing sits inside the grade band",
	})
	timing:AddSlider({
		text = "Reaction Noise",
		flag = "Gakuran Rhythm Reaction Noise",
		min = 0,
		max = 40,
		value = 8,
		float = 1,
		suffix = " ms",
		tip = "Extra per-note noise after grade pick",
	})
	timing:AddSlider({
		text = "Lookahead",
		flag = "Gakuran Rhythm Lookahead",
		min = 200,
		max = 1200,
		value = 700,
		float = 25,
		suffix = " ms",
		tip = "How early notes are planned before they hit",
	})
	timing:AddToggle({
		text = "Human Hold Releases",
		flag = "Gakuran Rhythm Early Hold Release",
		state = true,
		tip = "Slightly early/late hold ends",
	})
	timing:AddSlider({
		text = "Tap Press Length",
		flag = "Gakuran Rhythm Tap Length",
		min = 20,
		max = 120,
		value = 55,
		float = 5,
		suffix = " ms",
	})

	-- UI: presets + debug ------------------------------------------------

	local presets = columns.rhythmRight:AddSection("Presets")
	local function setWeights(p, g, o, b, m)
		local function set(flagName, value)
			local opt = library.options and library.options[flagName]
			if opt and type(opt.SetValue) == "function" then
				opt:SetValue(value)
			else
				library.flags[flagName] = value
			end
		end
		set("Gakuran Rhythm W Perfect", p)
		set("Gakuran Rhythm W Good", g)
		set("Gakuran Rhythm W Okay", o)
		set("Gakuran Rhythm W Bad", b)
		set("Gakuran Rhythm W Miss", m)
	end
	presets:AddButton({
		text = "Godlike",
		callback = function()
			setWeights(92, 6, 2, 0, 0)
			ctx.notify("Rhythm preset: Godlike", 2)
		end,
	})
	presets:AddButton({
		text = "Skilled",
		callback = function()
			setWeights(55, 28, 12, 3, 2)
			ctx.notify("Rhythm preset: Skilled", 2)
		end,
	})
	presets:AddButton({
		text = "Average",
		callback = function()
			setWeights(30, 35, 20, 8, 7)
			ctx.notify("Rhythm preset: Average", 2)
		end,
	})
	presets:AddButton({
		text = "Sloppy",
		callback = function()
			setWeights(12, 25, 28, 18, 17)
			ctx.notify("Rhythm preset: Sloppy", 2)
		end,
	})

	local debugSection = columns.rhythmRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Rhythm Debug Logs", flag = "Gakuran Rhythm Debug", state = false })
	ctx.refs.rhythmStatus = debugSection:AddLabel("Status: idle")
	ctx.refs.rhythmMode = debugSection:AddLabel("Mode: —")
	ctx.refs.rhythmWindows = debugSection:AddLabel("Windows: —")

	-- State --------------------------------------------------------------

	if type(ctx.state.rhythm) ~= "table" then
		ctx.state.rhythm = {}
	end
	local st = ctx.state.rhythm
	st.planned = type(st.planned) == "table" and st.planned or {}
	st.service = nil
	st.sessionToken = nil
	st.hits = 0
	st.skips = 0
	st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }

	local DEFAULT_WINDOWS = { PERFECT = 43, GOOD = 76, OKAY = 106, BAD = 140 }

	-- Helpers ------------------------------------------------------------

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function debugLog(...)
		if flag("Gakuran Rhythm Debug", false) then
			print("[xanhub rhythm]", ...)
		end
	end

	local function setStatus(text)
		pcall(function()
			if ctx.refs.rhythmStatus then
				ctx.refs.rhythmStatus.Text = "Status: " .. tostring(text)
			end
		end)
	end

	local function setModeLabel(text)
		pcall(function()
			if ctx.refs.rhythmMode then
				ctx.refs.rhythmMode.Text = "Mode: " .. tostring(text)
			end
		end)
	end

	local function setWindowsLabel(windows)
		pcall(function()
			if ctx.refs.rhythmWindows and type(windows) == "table" then
				ctx.refs.rhythmWindows.Text = string.format(
					"Windows: P%d G%d O%d B%d",
					tonumber(windows.PERFECT) or 0,
					tonumber(windows.GOOD) or 0,
					tonumber(windows.OKAY) or 0,
					tonumber(windows.BAD) or 0
				)
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

	local function getService(force)
		if force or type(st.service) ~= "table" then
			st.service = findLoaded("RhythmServiceClient")
		end
		return st.service
	end

	local function getSession()
		local service = getService(false)
		if type(service) ~= "table" then
			service = getService(true)
		end
		if type(service) ~= "table" then
			return nil
		end
		local session = service._session
		if type(session) ~= "table" or session._destroyed == true or session._started ~= true then
			-- Session may have been swapped after song end — refresh service once.
			service = getService(true)
			session = service and service._session
		end
		if type(session) ~= "table" then
			return nil
		end
		if session._destroyed == true or session._started ~= true then
			return nil
		end
		if type(session._handleLanePress) ~= "function" then
			return nil
		end
		if type(session._handleLaneRelease) ~= "function" then
			return nil
		end
		if type(session._now) ~= "function" then
			return nil
		end
		return session, service
	end

	local function sessionIdentity(session, service)
		local playable = session._playable
		local songId = type(playable) == "table" and tostring(playable.songId or playable.title or "") or ""
		local mode = type(playable) == "table" and tostring(playable.mode or "") or ""
		local seq = service and tostring(service._startPlaySeq or "") or ""
		local lanes = tostring(session._lanes or "")
		return seq .. "|" .. songId .. "|" .. mode .. "|" .. lanes
	end

	local function clearPlanned()
		if type(st.planned) == "table" then
			table.clear(st.planned)
		else
			st.planned = {}
		end
	end

	local function getWindows(session)
		local windows = session._windows
		if type(windows) ~= "table" then
			return DEFAULT_WINDOWS
		end
		return {
			PERFECT = tonumber(windows.PERFECT) or DEFAULT_WINDOWS.PERFECT,
			GOOD = tonumber(windows.GOOD) or DEFAULT_WINDOWS.GOOD,
			OKAY = tonumber(windows.OKAY) or DEFAULT_WINDOWS.OKAY,
			BAD = tonumber(windows.BAD) or DEFAULT_WINDOWS.BAD,
		}
	end

	local function randRange(a, b)
		if a > b then
			a, b = b, a
		end
		return a + math.random() * (b - a)
	end

	local function pickGrade()
		local weights = {
			{ name = "PERFECT", w = math.max(0, tonumber(flag("Gakuran Rhythm W Perfect", 45)) or 45) },
			{ name = "GOOD", w = math.max(0, tonumber(flag("Gakuran Rhythm W Good", 30)) or 30) },
			{ name = "OKAY", w = math.max(0, tonumber(flag("Gakuran Rhythm W Okay", 15)) or 15) },
			{ name = "BAD", w = math.max(0, tonumber(flag("Gakuran Rhythm W Bad", 5)) or 5) },
			{ name = "MISS", w = math.max(0, tonumber(flag("Gakuran Rhythm W Miss", 5)) or 5) },
		}
		local total = 0
		for _, entry in ipairs(weights) do
			total = total + entry.w
		end
		if total <= 0 then
			return "PERFECT"
		end
		local roll = math.random() * total
		local acc = 0
		for _, entry in ipairs(weights) do
			acc = acc + entry.w
			if roll <= acc then
				return entry.name
			end
		end
		return weights[#weights].name
	end

	-- Map grade -> error ms magnitude range inside that judgement band.
	local function gradeMagnitudeRange(grade, windows)
		local p = windows.PERFECT
		local g = windows.GOOD
		local o = windows.OKAY
		local b = windows.BAD
		local jitter = math.clamp(tonumber(flag("Gakuran Rhythm Band Jitter", 55)) or 55, 0, 100) / 100

		local function band(lo, hi)
			-- jitter shrinks toward band center when low, fills band when high
			local mid = (lo + hi) * 0.5
			local half = (hi - lo) * 0.5
			local use = half * (0.25 + 0.75 * jitter)
			local a = mid - use
			local c = mid + use
			a = math.clamp(a, lo, hi)
			c = math.clamp(c, lo, hi)
			return a, c
		end

		if grade == "PERFECT" then
			return band(0, math.max(1, p - 1))
		elseif grade == "GOOD" then
			return band(p + 1, math.max(p + 2, g - 1))
		elseif grade == "OKAY" then
			return band(g + 1, math.max(g + 2, o - 1))
		elseif grade == "BAD" then
			return band(o + 1, math.max(o + 2, b - 2))
		end
		-- MISS: beyond BAD so engine misses if we somehow pressed (we usually skip)
		return b + 8, b + 40
	end

	local function gradeToOffsetMs(grade, windows)
		local lo, hi = gradeMagnitudeRange(grade, windows)
		local mag = randRange(lo, hi)
		local earlyBias = math.clamp(tonumber(flag("Gakuran Rhythm Early Bias", 48)) or 48, 0, 100)
		local early = math.random(1, 100) <= earlyBias
		local offset = early and -mag or mag

		local noise = math.clamp(tonumber(flag("Gakuran Rhythm Reaction Noise", 8)) or 8, 0, 40)
		offset = offset + randRange(-noise, noise)

		-- Strict: keep final error inside the grade band after noise.
		if flag("Gakuran Rhythm Strict Grades", true) and grade ~= "MISS" then
			local abs = math.abs(offset)
			local minMag, maxMag = gradeMagnitudeRange(grade, windows)
			-- for PERFECT minMag can be 0
			if grade == "PERFECT" then
				abs = math.clamp(abs, 0, windows.PERFECT - 0.5)
			else
				abs = math.clamp(abs, minMag, maxMag)
			end
			offset = (offset < 0 and -1 or 1) * abs
			if offset == 0 and grade ~= "PERFECT" then
				offset = (early and -1 or 1) * minMag
			end
		end

		return offset
	end

	local function planNote(note, now, windows, lookaheadSec)
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
		if eta > lookaheadSec or eta < -0.08 then
			return
		end

		local grade = pickGrade()
		st.gradeRolls[grade] = (st.gradeRolls[grade] or 0) + 1

		if grade == "MISS" then
			st.planned[note] = {
				skip = true,
				grade = "MISS",
				lane = note.lane,
				noteT = note.t,
			}
			st.skips = (tonumber(st.skips) or 0) + 1
			return
		end

		local offsetMs = gradeToOffsetMs(grade, windows)
		local hitAt = note.t + (offsetMs / 1000)

		-- Keep non-miss presses inside BAD window so the engine registers a hit.
		local badSec = (windows.BAD / 1000) - 0.003
		hitAt = math.clamp(hitAt, note.t - badSec, note.t + badSec)

		local len = tonumber(note.len) or 0
		local releaseAt
		if len > 0.05 then
			if flag("Gakuran Rhythm Human Hold Releases", true) or flag("Gakuran Rhythm Early Hold Release", true) then
				local pad = randRange(0.015, 0.09)
				releaseAt = note.t + len - pad
			else
				releaseAt = note.t + len - 0.01
			end
			if releaseAt < hitAt + 0.05 then
				releaseAt = hitAt + 0.05
			end
		else
			local tapMs = math.clamp(tonumber(flag("Gakuran Rhythm Tap Length", 55)) or 55, 20, 120)
			releaseAt = hitAt + (tapMs / 1000) + randRange(-0.01, 0.02)
		end

		st.planned[note] = {
			skip = false,
			grade = grade,
			lane = note.lane,
			noteT = note.t,
			hitAt = hitAt,
			releaseAt = releaseAt,
			offsetMs = offsetMs,
			len = len,
			pressed = false,
			released = false,
		}
	end

	local function cleanupPlanned(now)
		for note, plan in pairs(st.planned) do
			local noteT = tonumber(plan.noteT) or 0
			local aged = now - noteT
			if aged > 2.5 then
				st.planned[note] = nil
			elseif plan.skip and aged > 0.8 then
				st.planned[note] = nil
			elseif plan.pressed and plan.released and aged > 0.6 then
				st.planned[note] = nil
			elseif type(note) == "table" and note.hit and plan.pressed and aged > 0.5 then
				if not plan.released and plan.releaseAt then
					-- still need release
				else
					st.planned[note] = nil
				end
			end
		end
	end

	local function processSession(session, service)
		local okNow, now = pcall(function()
			return session:_now()
		end)
		if not okNow or type(now) ~= "number" then
			return
		end

		local identity = sessionIdentity(session, service)
		if st.sessionToken ~= identity then
			st.sessionToken = identity
			clearPlanned()
			st.hits = 0
			st.skips = 0
			st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
			local playable = session._playable
			local mode = type(playable) == "table" and tostring(playable.mode or "?") or "?"
			local title = type(playable) == "table" and tostring(playable.title or playable.songId or "") or ""
			local lanes = tonumber(session._lanes) or 0
			setModeLabel(string.format("%s · %s lane · %s", mode, tostring(lanes), title))
			setWindowsLabel(getWindows(session))
			debugLog("new session", identity)
		end

		-- Large rewind => seek/restart
		if type(st.lastNow) == "number" and now + 1.25 < st.lastNow then
			clearPlanned()
			debugLog("timeline rewind", st.lastNow, "->", now)
		end
		st.lastNow = now

		local windows = getWindows(session)
		local lookahead = math.clamp(tonumber(flag("Gakuran Rhythm Lookahead", 700)) or 700, 200, 1200) / 1000

		local active = session._active
		if type(active) == "table" then
			for _, note in pairs(active) do
				planNote(note, now, windows, lookahead)
			end
		end

		-- Collect presses due this frame so multi-lane chords fire together.
		local duePress = {}
		local dueRelease = {}

		for note, plan in pairs(st.planned) do
			if plan.skip then
				-- intentional miss
			elseif not plan.pressed and type(plan.hitAt) == "number" and now >= plan.hitAt then
				if type(note) == "table" and (note.hit or note.attempted) then
					plan.pressed = true
					plan.released = true
				else
					table.insert(duePress, { note = note, plan = plan })
				end
			end

			if plan.pressed and not plan.released and type(plan.releaseAt) == "number" and now >= plan.releaseAt then
				table.insert(dueRelease, { note = note, plan = plan })
			end
		end

		for _, item in ipairs(duePress) do
			local plan = item.plan
			local note = item.note
			local lane = plan.lane
			if type(note) == "table" and (note.hit or note.attempted) then
				plan.pressed = true
				plan.released = true
			else
				local ok, err = pcall(function()
					session:_handleLanePress(lane)
				end)
				if ok then
					plan.pressed = true
					st.hits = (tonumber(st.hits) or 0) + 1
					debugLog("press", plan.grade, "L" .. tostring(lane), string.format("%+.0fms", plan.offsetMs or 0))
				else
					debugLog("press fail", err)
					-- retry next frames a few times
					plan.failCount = (plan.failCount or 0) + 1
					if plan.failCount >= 5 then
						plan.pressed = true
						plan.released = true
					end
				end
			end
		end

		for _, item in ipairs(dueRelease) do
			local plan = item.plan
			pcall(function()
				session:_handleLaneRelease(plan.lane)
			end)
			plan.released = true
		end

		cleanupPlanned(now)
	end

	-- Setup --------------------------------------------------------------

	local function setup()
		local statusAccum = 0
		local resolveAccum = 0

		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			if not flag("Gakuran Auto Rhythm", false) then
				if type(st.planned) == "table" and next(st.planned) then
					clearPlanned()
				end
				return
			end

			dt = tonumber(dt) or 0
			statusAccum = statusAccum + dt
			resolveAccum = resolveAccum + dt

			local session, service = getSession()
			if not session then
				if resolveAccum >= 0.8 then
					resolveAccum = 0
					st.service = nil
					st.sessionToken = nil
					clearPlanned()
					setStatus("waiting for rhythm session")
					setModeLabel("—")
				end
				return
			end

			local ok, err = pcall(processSession, session, service)
			if not ok then
				debugLog("tick error", err)
				if statusAccum >= 1 then
					statusAccum = 0
					setStatus("error: " .. tostring(err):sub(1, 80))
				end
				return
			end

			if statusAccum >= 1.0 then
				statusAccum = 0
				local judges = session._judgeCounts
				local rolls = st.gradeRolls or {}
				setStatus(string.format(
					"c%s · hit P%s/G%s/O%s/B%s/M%s · plan P%d/G%d/O%d/B%d/M%d",
					tostring(session._combo),
					tostring(judges and judges.PERFECT),
					tostring(judges and judges.GOOD),
					tostring(judges and judges.OKAY),
					tostring(judges and judges.BAD),
					tostring(judges and judges.MISS),
					tonumber(rolls.PERFECT) or 0,
					tonumber(rolls.GOOD) or 0,
					tonumber(rolls.OKAY) or 0,
					tonumber(rolls.BAD) or 0,
					tonumber(rolls.MISS) or 0
				))
			end
		end)

		setStatus("idle · enable Auto Rhythm in a song")
		setModeLabel("—")
		setWindowsLabel(DEFAULT_WINDOWS)
	end

	library:AddCleanup(function()
		clearPlanned()
		st.service = nil
		st.sessionToken = nil
	end)

	return { setup = setup }
end
