--[[
    xanhub | gakuran | combat

    Combat menu outline — logic not wired yet.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns

	local parry = columns.combatLeft:AddSection("Auto Parry")
	parry:AddToggle({ text = "Auto Parry", flag = "Gakuran Auto Parry", state = false })
	parry:AddBind({
		text = "Auto Parry Key",
		flag = "Gakuran Auto Parry Key",
		key = "F",
	})
	parry:AddSlider({
		text = "Reaction Offset",
		flag = "Gakuran Reaction Offset",
		min = 0,
		max = 500,
		value = 120,
		float = 5,
		suffix = " ms",
	})
	parry:AddSlider({
		text = "Range Pre-filter",
		flag = "Gakuran Range Prefilter",
		min = 4,
		max = 40,
		value = 14,
		float = 1,
		suffix = " studs",
	})
	parry:AddToggle({ text = "No Parry Cooldown", flag = "Gakuran No Parry Cooldown", state = false })
	parry:AddToggle({ text = "Stay Equipped", flag = "Gakuran Stay Equipped", state = false })

	local dodge = columns.combatRight:AddSection("Dodge")
	dodge:AddToggle({ text = "Auto Dodge", flag = "Gakuran Auto Dodge", state = false })
	dodge:AddLabel("Dodges behind incoming attacks")
	dodge:AddToggle({ text = "Dodge Fallback", flag = "Gakuran Dodge Fallback", state = false })
	dodge:AddLabel("Recovery when stunned or ragdolled")

	local debugSection = columns.combatRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Combat Debug Logs", flag = "Gakuran Combat Debug Logs", state = false })
	debugSection:AddLabel("Print parry/dodge decisions to console")

	local function setup()
	end

	return { setup = setup }
end
