--[[
    xanhub | gakuran | rhythm (rework)

    Auto Rhythm for all instruments via RhythmServiceClient._session:
      session:_now()
      session._active notes { t, lane, len, hit, attempted, ... }
      session:_handleLanePress(lane) / :_handleLaneRelease(lane)

    Holds: press at graded hit time, keep lane owned until hold end (note.t+len),
    then humanized release. Same-lane notes are serialized so holds never clobber.

    Judgement windows default (ms): PERFECT 43 · GOOD 76 · OKAY 106 · BAD 140
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
		tip = "Plays via the real engine (any instrument / lane count)",
	})
	core:AddToggle({
		text = "Strict Grade Caps",
		flag = "Gakuran Rhythm Strict Grades",
		state = true,
		tip = "Final timing stays inside the rolled grade band",
	})
	core:AddToggle({
		text = "Never Miss Holds",
		flag = "Gakuran Rhythm Hold No Miss",
		state = true,
		tip = "Hold notes never roll pure MISS (still can get bad grades)",
	})
	core:AddToggle({
		text = "Serialize Same Lane",
		flag = "Gakuran Rhythm Lane Mutex",
		state = true,
		tip = "Wait for hold release before next press on that lane (fixes broken holds)",
	})
	core:AddLabel("Guitar 2-lane · 4-lane charts · holds · chords")

	local grades = columns.rhythmLeft:AddSection("Grade Mix")
	grades:AddLabel("Weights auto-normalize (need not sum to 100)")
	grades:AddSlider({
		text = "Perfect",
		flag = "Gakuran Rhythm W Perfect",
		min = 0,
		max = 100,
		value = 38,
		float = 1,
	})
	grades:AddSlider({
		text = "Good",
		flag = "Gakuran Rhythm W Good",
		min = 0,
		max = 100,
		value = 34,
		float = 1,
	})
	grades:AddSlider({
		text = "Okay",
		flag = "Gakuran Rhythm W Okay",
		min = 0,
		max = 100,
		value = 18,
		float = 1,
	})
	grades:AddSlider({
		text = "Bad",
		flag = "Gakuran Rhythm W Bad",
		min = 0,
		max = 100,
		value = 7,
		float = 1,
	})
	grades:AddSlider({
		text = "Miss",
		flag = "Gakuran Rhythm W Miss",
		min = 0,
		max = 100,
		value = 3,
		float = 1,
		tip = "Tap notes only (holds ignored if Never Miss Holds)",
	})

	local feel = columns.rhythmLeft:AddSection("Human Feel")
	feel:AddSlider({
		text = "Early Bias",
		flag = "Gakuran Rhythm Early Bias",
		min = 0,
		max = 100,
		value = 46,
		float = 1,
		suffix = "%",
		tip = "Chance hit is early vs late inside grade band",
	})
	feel:AddSlider({
		text = "Band Depth",
		flag = "Gakuran Rhythm Band Jitter",
		min = 0,
		max = 100,
		value = 62,
		float = 1,
		suffix = "%",
		tip = "How deep into the grade band timings go (low = near center)",
	})
	feel:AddSlider({
		text = "Micro Noise",
		flag = "Gakuran Rhythm Reaction Noise",
		min = 0,
		max = 50,
		value = 10,
		float = 1,
		suffix = " ms",
	})
	feel:AddSlider({
		text = "Consistency",
		flag = "Gakuran Rhythm Consistency",
		min = 0,
		max = 100,
		value = 70,
		float = 1,
		suffix = "%",
		tip = "High = less wild variance note-to-note (legit skilled)",
	})
	feel:AddSlider({
		text = "Fatigue",
		flag = "Gakuran Rhythm Fatigue",
		min = 0,
		max = 100,
		value = 25,
		float = 1,
		suffix = "%",
		tip = "Slowly worsens grades over a long song",
	})
	feel:AddSlider({
		text = "Chord Stagger",
		flag = "Gakuran Rhythm Chord Stagger",
		min = 0,
		max = 40,
		value = 12,
		float = 1,
		suffix = " ms",
		tip = "Slight desync between simultaneous lane presses",
	})
	feel:AddSlider({
		text = "Lookahead",
		flag = "Gakuran Rhythm Lookahead",
		min = 250,
		max = 1500,
		value = 850,
		float = 25,
		suffix = " ms",
	})

	local holds = columns.rhythmRight:AddSection("Holds")
	holds:AddToggle({
		text = "Human Hold Releases",
		flag = "Gakuran Rhythm Human Hold Releases",
		state = true,
		tip = "Slight early/late release at hold end (never drops mid-hold)",
	})
	holds:AddSlider({
		text = "Hold Release Bias",
		flag = "Gakuran Rhythm Hold Release Bias",
		min = 0,
		max = 100,
		value = 62,
		float = 1,
		suffix = "% late",
		tip = "Higher = prefer releasing slightly AFTER hold end (safer for engine)",
	})
	holds:AddSlider({
		text = "Hold Release Spread",
		flag = "Gakuran Rhythm Hold Release Spread",
		min = 0,
		max = 80,
		value = 28,
		float = 1,
		suffix = " ms",
		tip = "Random ± spread around hold end",
	})
	holds:AddSlider({
		text = "Min Hold After Press",
		flag = "Gakuran Rhythm Min Hold Ms",
		min = 40,
		max = 200,
		value = 70,
		float = 5,
		suffix = " ms",
	})
	holds:AddSlider({
		text = "Tap Press Length",
		flag = "Gakuran Rhythm Tap Length",
		min = 25,
		max = 140,
		value = 48,
		float = 1,
		suffix = " ms",
	})
	holds:AddToggle({
		text = "Hold Grade Link",
		flag = "Gakuran Rhythm Hold Grade Link",
		state = true,
		tip = "Worse grades also release a bit more loosely",
	})

	local presets = columns.rhythmRight:AddSection("Legit Presets")
	local function setFlag(flagName, value)
		local opt = library.options and library.options[flagName]
		if opt and type(opt.SetValue) == "function" then
			pcall(function()
				opt:SetValue(value)
			end)
		end
		library.flags[flagName] = value
	end
	local function setWeights(p, g, o, b, m)
		setFlag("Gakuran Rhythm W Perfect", p)
		setFlag("Gakuran Rhythm W Good", g)
		setFlag("Gakuran Rhythm W Okay", o)
		setFlag("Gakuran Rhythm W Bad", b)
		setFlag("Gakuran Rhythm W Miss", m)
	end
	presets:AddButton({
		text = "Legit Casual",
		callback = function()
			setWeights(28, 36, 22, 9, 5)
			setFlag("Gakuran Rhythm Early Bias", 44)
			setFlag("Gakuran Rhythm Band Jitter", 68)
			setFlag("Gakuran Rhythm Reaction Noise", 14)
			setFlag("Gakuran Rhythm Consistency", 55)
			setFlag("Gakuran Rhythm Fatigue", 40)
			setFlag("Gakuran Rhythm Chord Stagger", 16)
			setFlag("Gakuran Rhythm Hold Release Bias", 58)
			setFlag("Gakuran Rhythm Hold Release Spread", 35)
			ctx.notify("Rhythm: Legit Casual", 2)
		end,
	})
	presets:AddButton({
		text = "Legit Skilled",
		callback = function()
			setWeights(42, 34, 16, 5, 3)
			setFlag("Gakuran Rhythm Early Bias", 47)
			setFlag("Gakuran Rhythm Band Jitter", 55)
			setFlag("Gakuran Rhythm Reaction Noise", 9)
			setFlag("Gakuran Rhythm Consistency", 72)
			setFlag("Gakuran Rhythm Fatigue", 22)
			setFlag("Gakuran Rhythm Chord Stagger", 10)
			setFlag("Gakuran Rhythm Hold Release Bias", 65)
			setFlag("Gakuran Rhythm Hold Release Spread", 24)
			ctx.notify("Rhythm: Legit Skilled", 2)
		end,
	})
	presets:AddButton({
		text = "Sweaty",
		callback = function()
			setWeights(70, 22, 6, 1, 1)
			setFlag("Gakuran Rhythm Early Bias", 50)
			setFlag("Gakuran Rhythm Band Jitter", 40)
			setFlag("Gakuran Rhythm Reaction Noise", 5)
			setFlag("Gakuran Rhythm Consistency", 88)
			setFlag("Gakuran Rhythm Fatigue", 8)
			setFlag("Gakuran Rhythm Chord Stagger", 6)
			setFlag("Gakuran Rhythm Hold Release Bias", 70)
			setFlag("Gakuran Rhythm Hold Release Spread", 14)
			ctx.notify("Rhythm: Sweaty", 2)
		end,
	})
	presets:AddButton({
		text = "Godlike",
		callback = function()
			setWeights(94, 5, 1, 0, 0)
			setFlag("Gakuran Rhythm Early Bias", 50)
			setFlag("Gakuran Rhythm Band Jitter", 25)
			setFlag("Gakuran Rhythm Reaction Noise", 2)
			setFlag("Gakuran Rhythm Consistency", 96)
			setFlag("Gakuran Rhythm Fatigue", 0)
			setFlag("Gakuran Rhythm Chord Stagger", 2)
			setFlag("Gakuran Rhythm Hold Release Bias", 75)
			setFlag("Gakuran Rhythm Hold Release Spread", 8)
			ctx.notify("Rhythm: Godlike", 2)
		end,
	})
	presets:AddButton({
		text = "Sloppy",
		callback = function()
			setWeights(12, 24, 28, 20, 16)
			setFlag("Gakuran Rhythm Early Bias", 40)
			setFlag("Gakuran Rhythm Band Jitter", 85)
			setFlag("Gakuran Rhythm Reaction Noise", 22)
			setFlag("Gakuran Rhythm Consistency", 30)
			setFlag("Gakuran Rhythm Fatigue", 55)
			setFlag("Gakuran Rhythm Chord Stagger", 22)
			setFlag("Gakuran Rhythm Hold Release Bias", 45)
			setFlag("Gakuran Rhythm Hold Release Spread", 50)
			ctx.notify("Rhythm: Sloppy", 2)
		end,
	})

	local debugSection = columns.rhythmRight:AddSection("Session")
	debugSection:AddToggle({ text = "Rhythm Debug Logs", flag = "Gakuran Rhythm Debug", state = false })
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
	st.planned = type(st.planned) == "table" and st.planned or {}
	st.laneOwner = type(st.laneOwner) == "table" and st.laneOwner or {} -- lane -> plan
	st.service = nil
	st.sessionToken = nil
	st.hits = 0
	st.skips = 0
	st.holdCount = 0
	st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
	st.sessionStartNow = nil
	st.biasSmoothed = 0

	local DEFAULT_WINDOWS = { PERFECT = 43, GOOD = 76, OKAY = 106, BAD = 140 }

	-- Helpers ------------------------------------------------------------

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function numFlag(name, default)
		return tonumber(flag(name, default)) or default
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
					"Windows: P%d G%d O%d B%d ms",
					tonumber(windows.PERFECT) or 0,
					tonumber(windows.GOOD) or 0,
					tonumber(windows.OKAY) or 0,
					tonumber(windows.BAD) or 0
				)
			end
		end)
	end

	local function setHoldsLabel(text)
		pcall(function()
			if ctx.refs.rhythmHolds then
				ctx.refs.rhythmHolds.Text = "Holds: " .. tostring(text)
			end
		end)
	end

	local function setMixLabel()
		pcall(function()
			if not ctx.refs.rhythmMix then
				return
			end
			local r = st.gradeRolls or {}
			ctx.refs.rhythmMix.Text = string.format(
				"Plan P%d G%d O%d B%d M%d · hits %d",
				tonumber(r.PERFECT) or 0,
				tonumber(r.GOOD) or 0,
				tonumber(r.OKAY) or 0,
				tonumber(r.BAD) or 0,
				tonumber(r.MISS) or 0,
				tonumber(st.hits) or 0
			)
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
			service = getService(true)
			session = service and service._session
		end
		if type(session) ~= "table" then
			return nil
		end
		if session._destroyed == true or session._started ~= true then
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

	local function sessionIdentity(session, service)
		local playable = session._playable
		local songId = type(playable) == "table" and tostring(playable.songId or playable.title or "") or ""
		local mode = type(playable) == "table" and tostring(playable.mode or "") or ""
		local seq = service and tostring(service._startPlaySeq or "") or ""
		local lanes = tostring(session._lanes or "")
		return seq .. "|" .. songId .. "|" .. mode .. "|" .. lanes
	end

	local function clearPlanned()
		-- Release any held lanes cleanly if session still alive
		local session = getSession()
		if session and type(st.laneOwner) == "table" then
			for lane, plan in pairs(st.laneOwner) do
				if plan and not plan.released then
					pcall(function()
						session:_handleLaneRelease(lane)
					end)
				end
			end
		end
		if type(st.planned) == "table" then
			table.clear(st.planned)
		else
			st.planned = {}
		end
		st.laneOwner = {}
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

	local function gaussian01()
		-- Box-Muller, clamped
		local u1 = math.max(1e-6, math.random())
		local u2 = math.random()
		local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
		return math.clamp(z, -2.5, 2.5)
	end

	local function fatigueFactor(now)
		local fatigue = math.clamp(numFlag("Gakuran Rhythm Fatigue", 25), 0, 100) / 100
		if fatigue <= 0 or type(st.sessionStartNow) ~= "number" then
			return 0
		end
		local elapsed = math.max(0, now - st.sessionStartNow)
		-- ramps over ~3 minutes
		return math.clamp(elapsed / 180, 0, 1) * fatigue
	end

	local function pickGrade(isHold, now)
		local weights = {
			{ name = "PERFECT", w = math.max(0, numFlag("Gakuran Rhythm W Perfect", 38)) },
			{ name = "GOOD", w = math.max(0, numFlag("Gakuran Rhythm W Good", 34)) },
			{ name = "OKAY", w = math.max(0, numFlag("Gakuran Rhythm W Okay", 18)) },
			{ name = "BAD", w = math.max(0, numFlag("Gakuran Rhythm W Bad", 7)) },
			{ name = "MISS", w = math.max(0, numFlag("Gakuran Rhythm W Miss", 3)) },
		}

		-- Fatigue shifts weight from Perfect → Okay/Bad
		local fat = fatigueFactor(now or 0)
		if fat > 0 then
			local shift = weights[1].w * 0.45 * fat
			weights[1].w = weights[1].w - shift
			weights[3].w = weights[3].w + shift * 0.55
			weights[4].w = weights[4].w + shift * 0.45
		end

		if isHold and flag("Gakuran Rhythm Hold No Miss", true) then
			weights[5].w = 0
		end

		local total = 0
		for _, entry in ipairs(weights) do
			total = total + entry.w
		end
		if total <= 0 then
			return "GOOD"
		end
		local roll = math.random() * total
		local acc = 0
		for _, entry in ipairs(weights) do
			acc = acc + entry.w
			if roll <= acc then
				return entry.name
			end
		end
		return "GOOD"
	end

	local function gradeMagnitudeRange(grade, windows)
		local p = windows.PERFECT
		local g = windows.GOOD
		local o = windows.OKAY
		local b = windows.BAD
		local depth = math.clamp(numFlag("Gakuran Rhythm Band Jitter", 62), 0, 100) / 100
		local consistency = math.clamp(numFlag("Gakuran Rhythm Consistency", 70), 0, 100) / 100
		-- Higher consistency → tighter toward band edge near center of band
		depth = depth * (1 - consistency * 0.45)

		local function band(lo, hi)
			local mid = (lo + hi) * 0.5
			local half = (hi - lo) * 0.5
			local use = half * (0.2 + 0.8 * depth)
			local a = math.clamp(mid - use, lo, hi)
			local c = math.clamp(mid + use, lo, hi)
			return a, c
		end

		if grade == "PERFECT" then
			return band(0, math.max(1, p - 1))
		elseif grade == "GOOD" then
			return band(p + 0.5, math.max(p + 1, g - 0.5))
		elseif grade == "OKAY" then
			return band(g + 0.5, math.max(g + 1, o - 0.5))
		elseif grade == "BAD" then
			return band(o + 0.5, math.max(o + 1, b - 1.5))
		end
		return b + 10, b + 45
	end

	local function gradeToOffsetMs(grade, windows)
		local lo, hi = gradeMagnitudeRange(grade, windows)
		local consistency = math.clamp(numFlag("Gakuran Rhythm Consistency", 70), 0, 100) / 100
		-- Blend uniform + gaussian for more human density near center
		local uniform = randRange(lo, hi)
		local gauss = (lo + hi) * 0.5 + (hi - lo) * 0.35 * gaussian01()
		gauss = math.clamp(gauss, lo, hi)
		local mag = uniform * (1 - consistency * 0.55) + gauss * (consistency * 0.55)

		local earlyBias = math.clamp(numFlag("Gakuran Rhythm Early Bias", 46), 0, 100)
		-- Smooth bias drift so patterns aren't pure 50/50 coin flips
		st.biasSmoothed = (st.biasSmoothed or 0) * 0.85 + (math.random() - 0.5) * 0.15
		local earlyChance = earlyBias + st.biasSmoothed * 12
		local early = math.random() * 100 <= earlyChance
		local offset = early and -mag or mag

		local noise = math.clamp(numFlag("Gakuran Rhythm Reaction Noise", 10), 0, 50)
		offset = offset + randRange(-noise, noise) * (1 - consistency * 0.4)

		if flag("Gakuran Rhythm Strict Grades", true) and grade ~= "MISS" then
			local abs = math.abs(offset)
			local minMag, maxMag = gradeMagnitudeRange(grade, windows)
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

	-- Holds ALWAYS release after chart hold end. Early release = broken holds.
	local function holdReleaseOffsetSec(grade)
		if not flag("Gakuran Rhythm Human Hold Releases", true) then
			return 0.02
		end
		local lateBias = math.clamp(numFlag("Gakuran Rhythm Hold Release Bias", 62), 0, 100) / 100
		-- Force mostly-late: floor lateBias at 0.85 for reliability
		lateBias = math.max(0.85, lateBias)
		local spreadMs = math.clamp(numFlag("Gakuran Rhythm Hold Release Spread", 28), 0, 80)
		local spread = (spreadMs / 1000) * (0.35 + 0.65 * math.random())
		local off
		if math.random() < lateBias then
			off = math.min(0.06, 0.012 + spread) -- 12–60ms after end
		else
			off = math.max(-0.006, -spread * 0.25) -- at most 6ms early
		end
		if flag("Gakuran Rhythm Hold Grade Link", true) then
			if grade == "OKAY" or grade == "BAD" then
				off = math.max(off, 0.015) + randRange(0.005, 0.02)
			elseif grade == "PERFECT" then
				off = math.max(0.01, off * 0.55) -- still after end
			end
		end
		return off
	end

	local function noteLength(note)
		local len = tonumber(note.len) or tonumber(note.length) or tonumber(note.holdLen) or 0
		if len <= 0 and type(note.endT) == "number" and type(note.t) == "number" then
			len = note.endT - note.t
		end
		if len <= 0 and type(note.duration) == "number" then
			len = note.duration
		end
		if len <= 0 and type(note.hold) == "number" then
			len = note.hold
		end
		if len <= 0 and note.isHold == true then
			len = 0.2 -- fallback so we never treat unknown holds as taps
		end
		return len
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
		-- Holds: plan earlier and allow slightly later catch-up
		local len = noteLength(note)
		local isHold = len > 0.05
		local earlyWindow = isHold and -0.05 or -0.12
		if eta > lookaheadSec or eta < earlyWindow then
			return
		end

		local grade = pickGrade(isHold, now)
		-- Perfect-weight overload: still never miss holds
		if isHold and grade == "MISS" and flag("Gakuran Rhythm Hold No Miss", true) then
			grade = "PERFECT"
		end
		st.gradeRolls[grade] = (st.gradeRolls[grade] or 0) + 1

		if grade == "MISS" then
			st.planned[note] = {
				skip = true,
				grade = "MISS",
				lane = note.lane,
				noteT = note.t,
				len = len,
				isHold = isHold,
			}
			st.skips = (tonumber(st.skips) or 0) + 1
			return
		end

		local offsetMs = gradeToOffsetMs(grade, windows)
		-- Holds: keep head timing tight so we don't start late and clip the tail
		if isHold then
			local maxHoldOffset = math.min(windows.PERFECT * 0.85, 28)
			offsetMs = math.clamp(offsetMs, -maxHoldOffset, maxHoldOffset)
		end
		local hitAt = note.t + (offsetMs / 1000)
		local badSec = (windows.BAD / 1000) - 0.004
		hitAt = math.clamp(hitAt, note.t - badSec, note.t + badSec)

		local releaseAt
		local holdEnd = nil
		if isHold then
			holdEnd = note.t + len
			-- ALWAYS release at/after hold end — never mid-tail
			releaseAt = holdEnd + holdReleaseOffsetSec(grade)
			if releaseAt < holdEnd + 0.008 then
				releaseAt = holdEnd + 0.012
			end
			local minHold = math.clamp(numFlag("Gakuran Rhythm Min Hold Ms", 70), 40, 200) / 1000
			if releaseAt < hitAt + minHold then
				releaseAt = hitAt + minHold
				-- still must cover hold end
				if releaseAt < holdEnd + 0.008 then
					releaseAt = holdEnd + 0.015
				end
			end
			st.holdCount = (tonumber(st.holdCount) or 0) + 1
		else
			local tapMs = math.clamp(numFlag("Gakuran Rhythm Tap Length", 48), 25, 140)
			-- Short taps so the next note/hold on the same lane can press ASAP
			releaseAt = hitAt + (tapMs / 1000) + randRange(-0.004, 0.01)
		end

		-- Chord stagger ONLY for taps — never desync simultaneous holds / hold+tap chords
		if not isHold then
			local staggerMs = math.clamp(numFlag("Gakuran Rhythm Chord Stagger", 12), 0, 40)
			if staggerMs > 0 then
				local laneJitter = ((note.lane * 17) % 7 - 3) / 3 * (staggerMs / 1000)
				hitAt = hitAt + laneJitter * randRange(0.35, 1)
				releaseAt = releaseAt + laneJitter * 0.25
			end
		end

		st.planned[note] = {
			skip = false,
			grade = grade,
			lane = note.lane,
			noteT = note.t,
			hitAt = hitAt,
			releaseAt = releaseAt,
			holdEnd = holdEnd,
			offsetMs = offsetMs,
			len = len,
			isHold = isHold,
			pressed = false,
			released = false,
			pressAttempts = 0,
			deferred = 0,
		}
	end

	local function nowSafe()
		return st.lastNow or 0
	end

	-- Same-lane scheduling: shrink taps before holds, serialize consecutive holds.
	local function resolveLaneConflicts(windows)
		local byLane = {}
		for _, plan in pairs(st.planned) do
			if plan and not plan.skip and not plan.released then
				local lane = plan.lane
				byLane[lane] = byLane[lane] or {}
				table.insert(byLane[lane], plan)
			end
		end

		local gap = 0.012
		for _, list in pairs(byLane) do
			table.sort(list, function(a, b)
				local ta = a.hitAt or 0
				local tb = b.hitAt or 0
				if math.abs(ta - tb) < 1e-4 then
					-- Simultaneous: holds take the press (shared head)
					if a.isHold ~= b.isHold then
						return a.isHold == true
					end
				end
				return ta < tb
			end)

			for i = 1, #list - 1 do
				local cur = list[i]
				local nxt = list[i + 1]
				if cur.released or nxt.released then
					-- skip
				elseif cur.isHold then
					-- Hold then anything: next waits until hold fully released
					local freeAt = (cur.releaseAt or cur.holdEnd or cur.hitAt or 0) + gap
					if (nxt.hitAt or 0) < freeAt then
						nxt.hitAt = freeAt
						if not nxt.isHold then
							local tapMs = math.clamp(numFlag("Gakuran Rhythm Tap Length", 48), 25, 140) / 1000
							nxt.releaseAt = nxt.hitAt + tapMs
						elseif nxt.holdEnd then
							nxt.releaseAt = math.max(nxt.releaseAt or 0, nxt.holdEnd + 0.012)
						end
					end
				else
					-- Tap then next: force early tap release so hold/note can press on time
					local needFree = (nxt.hitAt or 0) - gap
					local minTap = (cur.hitAt or 0) + 0.022
					if cur.pressed then
						cur.releaseAt = math.min(cur.releaseAt or needFree, needFree)
						if cur.releaseAt < minTap then
							cur.releaseAt = minTap
						end
					else
						cur.releaseAt = math.min(cur.releaseAt or (minTap + 0.03), needFree)
						if cur.releaseAt < minTap then
							cur.releaseAt = minTap
						end
					end
					-- If tap still overlaps a hold head, nudge hold press within window
					if cur.releaseAt + gap > (nxt.hitAt or 0) and nxt.isHold then
						local maxLate = (windows.BAD / 1000) - 0.01
						local push = cur.releaseAt + gap
						nxt.hitAt = math.min(push, (nxt.noteT or push) + maxLate)
						if nxt.holdEnd then
							nxt.releaseAt = math.max(nxt.releaseAt or 0, nxt.holdEnd + 0.015)
						end
					end
				end
			end
		end
	end

	local function tryReleasePlan(session, plan, reason)
		if not plan or plan.released then
			return
		end
		local lane = plan.lane
		if st.laneOwner[lane] == plan or not plan.pressed then
			if plan.pressed then
				pcall(function()
					session:_handleLaneRelease(lane)
				end)
			end
			if st.laneOwner[lane] == plan then
				st.laneOwner[lane] = nil
			end
		end
		plan.released = true
		debugLog("release", "L" .. tostring(lane), plan.isHold and "HOLD" or "TAP", reason or "")
	end

	local function tryPressPlan(session, note, plan, now)
		local lane = plan.lane
		if type(note) == "table" and (note.hit or note.attempted) then
			plan.pressed = true
			plan.released = true
			return true
		end

		local owner = st.laneOwner[lane]
		if owner and owner ~= plan and not owner.released then
			-- Preempt short taps so holds/chords can land
			if owner.pressed and not owner.isHold then
				tryReleasePlan(session, owner, "preempt-tap")
			elseif owner.pressed and owner.isHold then
				-- Cannot cut a hold early — reschedule this press after hold end
				local freeAt = (owner.releaseAt or owner.holdEnd or now) + 0.012
				plan.hitAt = math.max(plan.hitAt or now, freeAt)
				plan.deferred = (plan.deferred or 0) + 1
				return false
			elseif not owner.pressed then
				-- Owner queued but not pressed — if we are sooner/hold, take priority
				if plan.isHold and not owner.isHold then
					-- let us press; drop owner later
				elseif (plan.hitAt or 0) + 0.001 < (owner.hitAt or 0) then
					-- we are earlier
				else
					plan.hitAt = now + 0.008
					return false
				end
			end
		end

		local ok, err = pcall(function()
			session:_handleLanePress(lane)
		end)
		if ok then
			plan.pressed = true
			plan.pressAttempts = 0
			st.laneOwner[lane] = plan
			st.hits = (tonumber(st.hits) or 0) + 1
			debugLog(
				"press",
				plan.grade,
				"L" .. tostring(lane),
				plan.isHold and "HOLD" or "TAP",
				string.format("%+.0fms", plan.offsetMs or 0),
				plan.isHold and string.format("until %.2f", plan.releaseAt or 0) or ""
			)
			return true
		end

		debugLog("press fail", err)
		plan.pressAttempts = (plan.pressAttempts or 0) + 1
		if plan.pressAttempts >= 10 then
			plan.pressed = true
			plan.released = true
			return false
		end
		plan.hitAt = now + 0.012
		return false
	end

	local function cleanupPlanned(now)
		for note, plan in pairs(st.planned) do
			local noteT = tonumber(plan.noteT) or 0
			local holdEnd = tonumber(plan.holdEnd) or noteT
			local maxAge = plan.isHold and (holdEnd - noteT + 3) or 2.2
			local aged = now - noteT

			if aged > maxAge then
				if st.laneOwner[plan.lane] == plan then
					st.laneOwner[plan.lane] = nil
				end
				st.planned[note] = nil
			elseif plan.skip and aged > 0.9 then
				st.planned[note] = nil
			elseif plan.pressed and plan.released and now > (plan.releaseAt or noteT) + 0.4 then
				if st.laneOwner[plan.lane] == plan then
					st.laneOwner[plan.lane] = nil
				end
				st.planned[note] = nil
			elseif type(note) == "table" and note.hit and plan.pressed and plan.released then
				if st.laneOwner[plan.lane] == plan then
					st.laneOwner[plan.lane] = nil
				end
				st.planned[note] = nil
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
			st.holdCount = 0
			st.gradeRolls = { PERFECT = 0, GOOD = 0, OKAY = 0, BAD = 0, MISS = 0 }
			st.sessionStartNow = now
			st.biasSmoothed = 0
			local playable = session._playable
			local mode = type(playable) == "table" and tostring(playable.mode or "?") or "?"
			local title = type(playable) == "table" and tostring(playable.title or playable.songId or "") or ""
			local lanes = tonumber(session._lanes) or 0
			setModeLabel(string.format("%s · %dl · %s", mode, lanes, title))
			setWindowsLabel(getWindows(session))
			debugLog("new session", identity)
		end

		if type(st.lastNow) == "number" and now + 1.25 < st.lastNow then
			clearPlanned()
			debugLog("timeline rewind", st.lastNow, "->", now)
		end
		st.lastNow = now

		local windows = getWindows(session)
		local lookahead = math.clamp(numFlag("Gakuran Rhythm Lookahead", 850), 250, 1500) / 1000

		local active = session._active
		if type(active) == "table" then
			for _, note in pairs(active) do
				planNote(note, now, windows, lookahead)
			end
		end

		-- Fix same-lane tap→hold / hold→hold collisions every frame
		resolveLaneConflicts(windows)

		-- Preempt: if a hold/tap is due soon and a short tap owns the lane, release tap now
		for _, plan in pairs(st.planned) do
			if plan and not plan.skip and not plan.pressed and type(plan.hitAt) == "number" then
				if plan.hitAt <= now + 0.04 then
					local owner = st.laneOwner[plan.lane]
					if owner and owner ~= plan and owner.pressed and not owner.released and not owner.isHold then
						owner.releaseAt = now -- release this frame
					end
				end
			end
		end

		local duePress = {}
		local dueRelease = {}

		for note, plan in pairs(st.planned) do
			if plan.skip then
				-- miss
			elseif not plan.pressed and type(plan.hitAt) == "number" and now >= plan.hitAt then
				table.insert(duePress, { note = note, plan = plan })
			end

			if plan.pressed and not plan.released and type(plan.releaseAt) == "number" and now >= plan.releaseAt then
				table.insert(dueRelease, { note = note, plan = plan })
			end
		end

		-- Releases first so same-frame tap→hold chains work
		table.sort(dueRelease, function(a, b)
			return (a.plan.releaseAt or 0) < (b.plan.releaseAt or 0)
		end)
		for _, item in ipairs(dueRelease) do
			tryReleasePlan(session, item.plan, "scheduled")
		end

		-- Presses: same-time chords press together (all free lanes)
		table.sort(duePress, function(a, b)
			-- Holds slightly first when equal time
			local da, db = a.plan.hitAt or 0, b.plan.hitAt or 0
			if math.abs(da - db) < 0.001 then
				if a.plan.isHold ~= b.plan.isHold then
					return a.plan.isHold
				end
			end
			return da < db
		end)

		for _, item in ipairs(duePress) do
			tryPressPlan(session, item.note, item.plan, now)
		end

		cleanupPlanned(now)

		local held = 0
		for _, plan in pairs(st.laneOwner) do
			if plan and plan.pressed and not plan.released then
				held = held + 1
			end
		end
		setHoldsLabel(string.format("%d held · %d holds planned", held, tonumber(st.holdCount) or 0))
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
				if resolveAccum >= 0.75 then
					resolveAccum = 0
					st.service = nil
					st.sessionToken = nil
					clearPlanned()
					setStatus("waiting for rhythm session")
					setModeLabel("—")
					setHoldsLabel("—")
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

			if statusAccum >= 0.85 then
				statusAccum = 0
				local judges = session._judgeCounts
				setStatus(string.format(
					"live · eng P%s/G%s/O%s/B%s/M%s · combo %s",
					tostring(judges and judges.PERFECT),
					tostring(judges and judges.GOOD),
					tostring(judges and judges.OKAY),
					tostring(judges and judges.BAD),
					tostring(judges and judges.MISS),
					tostring(session._combo)
				))
				setMixLabel()
			end
		end)

		setStatus("idle · enable Auto Rhythm in a song")
		setModeLabel("—")
		setWindowsLabel(DEFAULT_WINDOWS)
		setHoldsLabel("—")
		setMixLabel()
	end

	library:AddCleanup(function()
		clearPlanned()
		st.service = nil
		st.sessionToken = nil
	end)

	return { setup = setup }
end
