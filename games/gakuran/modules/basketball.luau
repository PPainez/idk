--[[
    xanhub | gakuran | basketball

    Basketball menu outline — logic not wired yet.
]]

return function(ctx)
	local columns = ctx.columns

	local shoot = columns.basketballLeft:AddSection("Shooting")
	shoot:AddToggle({ text = "Auto Green", flag = "Gakuran Auto Green", state = false })
	shoot:AddToggle({ text = "Humanize", flag = "Gakuran Basketball Humanize", state = true })
	shoot:AddSlider({
		text = "Jitter",
		flag = "Gakuran Basketball Jitter",
		min = 0,
		max = 100,
		value = 22,
		float = 1,
		suffix = "%",
	})
	shoot:AddToggle({ text = "No Dribble Cooldown", flag = "Gakuran No Dribble Cooldown", state = false })

	local esp = columns.basketballRight:AddSection("Basketball ESP")
	esp:AddToggle({ text = "Basketball ESP", flag = "Gakuran Basketball ESP", state = false })
	esp:AddLabel("Ball, hoop, and contest indicators")
	esp:AddLabel("Feature logic coming soon")

	local function setup()
	end

	return { setup = setup }
end
