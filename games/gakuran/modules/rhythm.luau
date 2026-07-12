--[[
    xanhub | gakuran | rhythm

    Rhythm game menu outline — logic not wired yet.
]]

return function(ctx)
	local columns = ctx.columns

	local rhythm = columns.rhythmLeft:AddSection("Auto Rhythm")
	rhythm:AddToggle({ text = "Auto Rhythm", flag = "Gakuran Auto Rhythm", state = false })
	rhythm:AddSlider({
		text = "Hit Chance",
		flag = "Gakuran Rhythm Hit Chance",
		min = 0,
		max = 100,
		value = 88,
		float = 1,
		suffix = "%",
	})
	rhythm:AddSlider({
		text = "Perfect Chance",
		flag = "Gakuran Rhythm Perfect Chance",
		min = 0,
		max = 100,
		value = 42,
		float = 1,
		suffix = "%",
	})
	rhythm:AddSlider({
		text = "Humanization",
		flag = "Gakuran Rhythm Humanization",
		min = 0,
		max = 100,
		value = 65,
		float = 1,
		suffix = "%",
	})

	local timing = columns.rhythmRight:AddSection("Timing")
	timing:AddSlider({
		text = "Early Offset",
		flag = "Gakuran Rhythm Early Offset",
		min = 0,
		max = 200,
		value = 35,
		float = 5,
		suffix = " ms",
	})
	timing:AddSlider({
		text = "Late Offset",
		flag = "Gakuran Rhythm Late Offset",
		min = 0,
		max = 200,
		value = 45,
		float = 5,
		suffix = " ms",
	})
	timing:AddSlider({
		text = "Timing Jitter",
		flag = "Gakuran Rhythm Timing Jitter",
		min = 0,
		max = 120,
		value = 18,
		float = 2,
		suffix = " ms",
	})
	timing:AddLabel("Advanced chances + humanization for legit play")

	local function setup()
	end

	return { setup = setup }
end
