--[[
    xanhub | gakuran | rhythm

    Auto Rhythm driven by live RhythmServiceClient._session (RhythmEngine).
    Calls session:_handleLanePress / _handleLaneRelease with humanized timing.

    Windows (ms error): PERFECT 43 · GOOD 76 · OKAY 106 · BAD 140
    Keys: 1=Left/X  2=Down/C  3=Up/N  4=Right/M
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local RunService = ctx.RunService

	local rhythm = columns.rhythmLeft:AddSection("Auto Rhythm")
	rhythm:AddToggle({
		text = "Auto Rhythm",
		flag = "Gakuran Auto Rhythm",
		state = false,
		tip = "Plays notes through the real rhythm engine with humanized timing",
	})
	rhythm:AddSlider({
		text = "Hit Chance",
		flag = "Gakuran Rhythm Hit Chance",
		min = 0,
		max = 100,
		value = 92,
		float = 1,
		suffix = "%",
		tip = "Chance to attempt a note (rest are intentional misses)",
	})
	rhythm:AddSlider({
		text = "Perfect Chance",
		flag = "Gakuran Rhythm Perfect Chance",
		min = 0,
		max = 100,
		value = 55,
		float = 1,
		suffix = "%",
		tip = "Among hits, chance to land in the Perfect window",
	})
	rhythm:AddSlider({
		text = "Humanization",
		flag = "Gakuran Rhythm Humanization",
		min = 0,
		max = 100,
		value = 60,
		float = 1,
		suffix = "%",
		tip = "Spreads non-perfect hits into GOOD/OKAY and adds natural variance",
	})

	local timing = columns.rhythmRight:AddSection("Timing")
	timing:AddSlider({
		text = "Early Offset",
		flag = "Gakuran Rhythm Early Offset",
		min = 0,
		max = 120,
		value = 28,
		float = 1,
		suffix = " ms",
		tip = "Max earliness for planned hits",
	})
	timing:AddSlider({
		text = "Late Offset",
		flag = "Gakuran Rhythm Late Offset",
		min = 0,
		max = 120,
		value = 32,
		float = 1,
		suffix = " ms",
		tip = "Max lateness for planned hits",
	})
	timing:AddSlider({
		text = "Timing Jitter",
		flag = "Gakuran Rhythm Timing Jitter",
		min = 0,
		max = 80,
		value = 14,
		float = 1,
		suffix = " ms",
		tip = "Per-note random noise",
	})
	timing:AddToggle({
		text = "Release Holds Early",
		flag = "Gakuran Rhythm Early Hold Release",
		state = true,
		tip = "Slightly early hold releases look more human",
	})
	timing:AddLabel("Uses real session:_handleLanePress · no remotes")

	local debugSection = columns.rhythmRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Rhythm Debug Logs", flag = "Gakuran Rhythm Debug", state = false })
	ctx.refs.rhythmStatus = debugSection:AddLabel("Status: idle")

	if type(ctx.state.rhythm) ~= "table" then
		ctx.state.rhythm = {}
	end
	local st = ctx.state.rhythm
	st.planned = type(st.planned) == "table" and st.planned or {}
	st.service = nil
	st.lastNow = 0
	st.hits = 0
	st.skips = 0

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

	local function getSession()
		local service = st.service
		if type(service) ~= "table" or type(service._session) ~= "table" then
			service = findLoaded("RhythmServiceClient")
			st.service = service
		end
		if type(service) ~= "table" then
			return nil
		end
		local session = service._session
		if type(session) ~= "table" then
			return nil
		end
		if session._destroyed == true then
			return nil
		end
		if type(session._handleLanePress) ~= "function" or type(session._now) ~= "function" then
			return nil
		end
		return session
	end

	local function randRange(minValue, maxValue)
		return minValue + (math.random() * (maxValue - minValue))
	end

	local function planOffsetMs()
		local hitChance = math.clamp(tonumber(flag("Gakuran Rhythm Hit Chance", 92)) or 92, 0, 100)
		if math.random(1, 100) > hitChance then
			return nil, true -- skip / intentional miss
		end

		local perfectChance = math.clamp(tonumber(flag("Gakuran Rhythm Perfect Chance", 55)) or 55, 0, 100)
		local human = math.clamp(tonumber(flag("Gakuran Rhythm Humanization", 60)) or 60, 0, 100) / 100
		local earlyMax = math.clamp(tonumber(flag("Gakuran Rhythm Early Offset", 28)) or 28, 0, 120)
		local lateMax = math.clamp(tonumber(flag("Gakuran Rhythm Late Offset", 32)) or 32, 0, 120)
		local jitter = math.clamp(tonumber(flag("Gakuran Rhythm Timing Jitter", 14)) or 14, 0, 80)

		local offsetMs
		if math.random(1, 100) <= perfectChance then
			-- Stay inside PERFECT window (~43ms) with human noise.
			local spread = 6 + human * 18 -- up to ~24ms
			offsetMs = randRange(-spread, spread)
		else
			-- Bias into GOOD / OKAY bands so it doesn't look like a bot.
			-- GOOD edge ~44-76, OKAY ~77-106. Humanization pushes outward.
			local bandRoll = math.random()
			local mag
			if bandRoll < (0.55 - human * 0.15) then
				mag = randRange(44, 72) -- GOOD
			elseif bandRoll < (0.88 - human * 0.1) then
				mag = randRange(72, 100) -- OKAY
			else
				mag = randRange(100, 125) -- late BAD-ish, still often lands
			end
			offsetMs = (math.random() < 0.48 and -1 or 1) * mag
		end

		offsetMs = offsetMs + randRange(-jitter, jitter)
		offsetMs = math.clamp(offsetMs, -earlyMax, lateMax)

		-- Tiny reaction lag so perfects aren't all sub-frame early.
		if offsetMs < 0 and math.random() < 0.35 then
			offsetMs = offsetMs * 0.55
		end

		return offsetMs, false
	end

	local function planNote(note, now)
		if type(note) ~= "table" then
			return
		end
		if st.planned[note] then
			return
		end
		if note.hit or note.attempted then
			return
		end
		if type(note.t) ~= "number" or type(note.lane) ~= "number" then
			return
		end

		local eta = note.t - now
		-- Plan shortly before the note arrives.
		if eta > 0.75 or eta < -0.12 then
			return
		end

		local offsetMs, skip = planOffsetMs()
		if skip then
			st.planned[note] = {
				skip = true,
				lane = note.lane,
				noteT = note.t,
			}
			st.skips = (tonumber(st.skips) or 0) + 1
			return
		end

		local len = tonumber(note.len) or 0
		local hitAt = note.t + ((offsetMs or 0) / 1000)

		-- Never plan so late we auto-miss if we can help it (unless humanization asked for it).
		local missSec = 0.14
		if type(note) == "table" then
			-- keep hitAt within BAD window of note.t for non-skips
			hitAt = math.clamp(hitAt, note.t - missSec + 0.004, note.t + missSec - 0.004)
		end

		local releaseAt = nil
		if len > 0.05 then
			local earlyHold = flag("Gakuran Rhythm Early Hold Release", true)
			local holdPad = earlyHold and randRange(0.02, 0.08 + (tonumber(flag("Gakuran Rhythm Humanization", 60)) or 60) / 100 * 0.06) or 0.01
			releaseAt = note.t + len - holdPad
			if releaseAt < hitAt + 0.05 then
				releaseAt = hitAt + 0.05
			end
		else
			-- Tap notes: short press then release so receptors don't stick.
			releaseAt = hitAt + randRange(0.035, 0.09)
		end

		st.planned[note] = {
			skip = false,
			lane = note.lane,
			noteT = note.t,
			hitAt = hitAt,
			releaseAt = releaseAt,
			len = len,
			pressed = false,
			released = false,
			offsetMs = offsetMs,
		}
	end

	local function cleanupPlanned(now)
		for note, plan in pairs(st.planned) do
			local noteT = plan.noteT or 0
			local done = plan.skip or (plan.pressed and plan.released) or (plan.pressed and not plan.releaseAt)
			if done and (now - noteT) > 1.5 then
				st.planned[note] = nil
			elseif type(note) == "table" and (note.hit or note.attempted) and plan.pressed and (now - noteT) > 1.0 then
				st.planned[note] = nil
			elseif (now - noteT) > 3 then
				st.planned[note] = nil
			end
		end
	end

	local function processSession(session)
		local okNow, now = pcall(function()
			return session:_now()
		end)
		if not okNow or type(now) ~= "number" then
			return
		end
		st.lastNow = now

		local active = session._active
		if type(active) == "table" then
			for _, note in pairs(active) do
				planNote(note, now)
			end
		end

		for note, plan in pairs(st.planned) do
			if plan.skip then
				continue
			end

			if not plan.pressed and type(plan.hitAt) == "number" and now >= plan.hitAt then
				if type(note) == "table" and (note.hit or note.attempted) then
					plan.pressed = true
					plan.released = true
				else
					local lane = plan.lane
					local pressOk, pressErr = pcall(function()
						session:_handleLanePress(lane)
					end)
					plan.pressed = true
					if pressOk then
						st.hits = (tonumber(st.hits) or 0) + 1
						debugLog("press", lane, string.format("%+.0fms", plan.offsetMs or 0))
					else
						debugLog("press fail", pressErr)
						plan.pressed = false
					end
				end
			end

			if plan.pressed and not plan.released and type(plan.releaseAt) == "number" and now >= plan.releaseAt then
				local lane = plan.lane
				pcall(function()
					session:_handleLaneRelease(lane)
				end)
				plan.released = true
			end
		end

		cleanupPlanned(now)

		if flag("Gakuran Rhythm Debug", false) then
			local judges = session._judgeCounts
			local combo = session._combo
			setStatus(string.format(
				"t=%.1f c=%s h=%d s=%d P:%s G:%s M:%s",
				now,
				tostring(combo),
				tonumber(st.hits) or 0,
				tonumber(st.skips) or 0,
				tostring(judges and judges.PERFECT),
				tostring(judges and judges.GOOD),
				tostring(judges and judges.MISS)
			))
		end
	end

	local function setup()
		local resolveAccum = 0
		local statusAccum = 0

		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			if not flag("Gakuran Auto Rhythm", false) then
				if next(st.planned) then
					table.clear(st.planned)
				end
				return
			end

			dt = tonumber(dt) or 0
			resolveAccum = resolveAccum + dt
			statusAccum = statusAccum + dt

			local session = getSession()
			if not session then
				if resolveAccum >= 1 then
					resolveAccum = 0
					st.service = nil
					setStatus("waiting for rhythm session")
				end
				return
			end

			local ok, err = pcall(processSession, session)
			if not ok then
				debugLog("tick error", err)
				if statusAccum >= 1 then
					statusAccum = 0
					setStatus("error: " .. tostring(err))
				end
			elseif not flag("Gakuran Rhythm Debug", false) and statusAccum >= 1.2 then
				statusAccum = 0
				local judges = session._judgeCounts
				setStatus(string.format(
					"playing · combo %s · P %s / G %s / M %s",
					tostring(session._combo),
					tostring(judges and judges.PERFECT),
					tostring(judges and judges.GOOD),
					tostring(judges and judges.MISS)
				))
			end
		end)

		setStatus("idle · start a song, enable Auto Rhythm")
	end

	library:AddCleanup(function()
		if type(st.planned) == "table" then
			table.clear(st.planned)
		end
	end)

	return { setup = setup }
end
