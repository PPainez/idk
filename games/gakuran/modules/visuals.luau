--[[
    xanhub | gakuran | visuals

    Player ESP menu outline — logic not wired yet.
]]

return function(ctx)
	local columns = ctx.columns

	local esp = columns.visualsLeft:AddSection("Player ESP")
	esp:AddToggle({ text = "Player ESP", flag = "Gakuran Player ESP", state = false })
	esp:AddToggle({ text = "Boxes", flag = "Gakuran ESP Boxes", state = true })
	esp:AddToggle({ text = "Filled Boxes", flag = "Gakuran ESP Filled Boxes", state = false })
	esp:AddToggle({ text = "Health Bar", flag = "Gakuran ESP Health Bar", state = true })
	esp:AddToggle({ text = "Stamina Bar", flag = "Gakuran ESP Stamina Bar", state = true })

	local info = columns.visualsRight:AddSection("Player Info")
	info:AddToggle({ text = "Names", flag = "Gakuran ESP Names", state = true })
	info:AddToggle({ text = "Real Roblox Name", flag = "Gakuran ESP Real Names", state = false })
	info:AddLabel("Shows DisplayName + optional @Username")
	info:AddToggle({ text = "Distance", flag = "Gakuran ESP Distance", state = true })
	info:AddToggle({ text = "Combat Style", flag = "Gakuran ESP Combat Style", state = true })
	info:AddToggle({ text = "Grade", flag = "Gakuran ESP Grade", state = true })
	info:AddToggle({ text = "Age", flag = "Gakuran ESP Age", state = false })
	info:AddToggle({ text = "Height", flag = "Gakuran ESP Height", state = false })

	local function setup()
	end

	return { setup = setup }
end
