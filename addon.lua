local shared = odh_shared_plugins

if not shared or type(shared.CreateTab) ~= "function" then
	warn("[Firefly Timer] Load through the current Overdrive H plugin menu.")
	return
end

local ok, my_own_tab = pcall(function()
	return shared.CreateTab("Firefly Timer", "/Devon67retro/Debug/refs/heads/main/icon")
end)
if not ok or not my_own_tab then return end

local ok2, my_own_section = pcall(function()
	return my_own_tab:AddSection("Firefly Timer", "Countdown + auto jump")
end)
if not ok2 or not my_own_section then return end

local function note(msg)
	pcall(function() shared.Notify(msg, 4) end)
end

-- ===== TOGGLES FIRST: nothing above can fail, so they always appear =====
local impl = {
	ready = false,
	desired = false,        -- Enable Firefly Timer
	desiredMove = false,    -- Move Cooldown Window
}

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local okA, errA = pcall(fn, ...)
	if not okA then note("Error: " .. tostring(errA)) end
end

pcall(function()
	my_own_section:AddToggle("Enable Firefly Timer", function(bool)
		impl.desired = bool and true or false
		if impl.ready then safeCall(impl.apply, impl.desired) end
	end)
end)

pcall(function()
	my_own_section:AddToggle("Move Cooldown Window", function(bool)
		impl.desiredMove = bool and true or false
		if impl.ready then safeCall(impl.setMove, impl.desiredMove) end
	end)
end)

pcall(function()
	-- Saves only on a user flip after load (never from the hub restoring state on join)
	my_own_section:AddToggle("Save Cooldown Position", function(bool)
		if bool and impl.ready then safeCall(impl.savePos) end
	end)
end)

pcall(function() my_own_section:AddLabel("Made by: SANGUINE 🤤🤤") end)

-- ===== Everything else, guarded; errors are shown on screen =====
local function init()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local HttpService = game:GetService("HttpService")
	local LocalPlayer = Players.LocalPlayer
	local pg = LocalPlayer:WaitForChild("PlayerGui")

	local COUNTDOWN = 2.5             -- copy of the game's own jar cooldown
	local COOLDOWN = 16               -- cooldown tracker length
	local FIRST_JUMP_REMAINING = 0.24 -- fire jump 1 when the displayed countdown reaches this
	local JUMP_GAP = 0.40             -- jump 2 fires this long after jump 1 fired

	local POS_FILE = "FireflyTimer_CDPos.json"

	local MY_ID = tostring(os.clock()) .. tostring(math.random(1000, 9999))
	pcall(function() LocalPlayer:SetAttribute("FireflyRunId", MY_ID) end)
	local function isCurrent()
		local okA, v = pcall(function() return LocalPlayer:GetAttribute("FireflyRunId") end)
		if not okA then return true end
		return v == MY_ID
	end

	local enabled = false
	local moveMode = false
	local hasCd = false        -- true after the first fire (or a reset): box stays visible showing "Active"
	local token = 0
	local cdStart, cdEnd = 0, 0
	local conns, hooked = {}, {}
	local scanToken = 0
	local gui, countLabel, cdLabel

	-- ===== Saved cooldown-window position =====
	local savedPos = nil -- UDim2 (scale), loaded from file

	local function loadPos()
		pcall(function()
			if isfile and readfile and isfile(POS_FILE) then
				local d = HttpService:JSONDecode(readfile(POS_FILE))
				if type(d) == "table" and type(d.x) == "number" and type(d.y) == "number" then
					savedPos = UDim2.fromScale(math.clamp(d.x, 0, 0.95), math.clamp(d.y, 0, 0.95))
				end
			end
		end)
	end
	loadPos()

	-- remove old guis (PlayerGui only, every step guarded)
	for _, n in ipairs({ "FireflyLiteGui", "FireflyTimerGui", "FireflyCooldownGui", "FireflySettingsGui" }) do
		pcall(function()
			local o = pg:FindFirstChild(n)
			if o then o:Destroy() end
		end)
	end

	local function makeLabel(parent, pos, size, textSize)
		local l = Instance.new("TextLabel")
		l.Position = pos
		l.Size = size
		l.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		l.BackgroundTransparency = 0.5
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
		l.Font = Enum.Font.GothamBold
		l.TextSize = textSize
		l.Text = ""
		l.Visible = false
		l.Parent = parent
		pcall(function() Instance.new("UICorner", l) end)
		return l
	end

	local function setupDrag(label)
		local dragging, dragStart, startPos = false, nil, nil
		label.InputBegan:Connect(function(input)
			if not moveMode or not isCurrent() then return end
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				startPos = label.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not dragging or not moveMode or not isCurrent() then return end
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
				local d = input.Position - dragStart
				label.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
	end

	local function buildGui()
		if gui and gui.Parent then return end
		gui = Instance.new("ScreenGui")
		gui.Name = "FireflyLiteGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 999
		gui.Parent = pg
		countLabel = makeLabel(gui, UDim2.new(0.5, -50, 0.4, 0), UDim2.fromOffset(100, 50), 32)
		cdLabel = makeLabel(gui, savedPos or UDim2.new(0, 20, 0.5, 0), UDim2.fromOffset(110, 44), 26)
		cdLabel.Active = false
		setupDrag(cdLabel)
	end

	-- Cooldown box: hidden before the first fire, then always visible
	-- (counting during the 16s, "Active" the rest of the time).
	local function hideGui()
		if countLabel then countLabel.Visible = false end
		if cdLabel then
			if moveMode then
				cdLabel.Visible = true
				cdLabel.Text = hasCd and "Active" or "CD 0.0"
			elseif hasCd then
				cdLabel.Visible = true
				cdLabel.Text = "Active"
			else
				cdLabel.Visible = false
			end
		end
	end

	-- ===== Jump (original version) =====
	local function fireJump()
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	-- ===== Timer (the jar tool itself is never touched) =====
	local function onActivated()
		if not enabled or not isCurrent() then return end
		local now = os.clock()
		if now < cdEnd then return end

		token = token + 1
		local my = token
		cdStart, cdEnd = now, now + COOLDOWN
		hasCd = true

		local okG, errG = pcall(buildGui)
		if not okG then note("GUI error: " .. tostring(errG)) end

		local timeLeft = COUNTDOWN
		local j1 = false
		task.spawn(function()
			while enabled and isCurrent() and my == token do
				local dt = RunService.Heartbeat:Wait()
				timeLeft = timeLeft - dt
				if timeLeft < 0 then timeLeft = 0 end

				-- jump 1: when the displayed countdown reaches FIRST_JUMP_REMAINING
				if not j1 and timeLeft <= FIRST_JUMP_REMAINING then
					j1 = true
					fireJump()
					-- jump 2: JUMP_GAP after jump 1 actually fired
					task.delay(JUMP_GAP, function()
						if enabled and isCurrent() and my == token then fireJump() end
					end)
				end

				local t = os.clock()
				local k = cdEnd - t
				if countLabel then
					countLabel.Visible = timeLeft > 0
					if timeLeft > 0 then countLabel.Text = string.format("%.1f", timeLeft) end
				end
				if cdLabel then
					if k > 0 then
						cdLabel.Visible = true
						cdLabel.Text = string.format("CD %.1f", t - cdStart)
					end
				end
				if timeLeft <= 0 and k <= 0 then break end
			end
			if my == token then hideGui() end -- shows "Active" once the 16s is over
		end)
	end

	local function scan()
		local places = { LocalPlayer:FindFirstChildOfClass("Backpack"), LocalPlayer.Character }
		for i = 1, 2 do
			local place = places[i]
			if place then
				for _, child in ipairs(place:GetChildren()) do
					if child:IsA("Tool") and child.Name == "Fireflies" and not hooked[child] then
						hooked[child] = true
						table.insert(conns, child.Activated:Connect(function() onActivated() end))
					end
				end
			end
		end
	end

	-- Respawn: cancel everything and show "Active" (jar usable again)
	local function resetCooldown()
		token = token + 1
		cdEnd = 0
		hasCd = true
		hideGui()
	end

	local function start()
		buildGui()
		scanToken = scanToken + 1
		local my = scanToken
		table.insert(conns, LocalPlayer.CharacterAdded:Connect(function()
			if enabled and isCurrent() then resetCooldown() end
		end))
		task.spawn(function()
			while enabled and isCurrent() and my == scanToken do
				pcall(scan)
				task.wait(0.5)
			end
		end)
	end

	local function stop()
		scanToken = scanToken + 1
		token = token + 1
		cdEnd = 0
		hasCd = false
		hideGui()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		table.clear(conns)
		table.clear(hooked)
	end

	impl.apply = function(bool)
		if not isCurrent() then return end
		enabled = bool
		if enabled then
			local okS, errS = pcall(start)
			if okS then note("Firefly Timer enabled")
			else note("Start error: " .. tostring(errS)) end
		else
			pcall(stop)
			note("Firefly Timer disabled")
		end
	end

	-- ===== Movable cooldown window =====
	impl.setMove = function(bool)
		if not isCurrent() then return end
		moveMode = bool
		buildGui()
		cdLabel.Active = bool
		if os.clock() >= cdEnd then hideGui() end
	end

	impl.savePos = function()
		if not isCurrent() then return end
		buildGui()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		-- Position is already relative to the ScreenGui's own area, so convert it directly
		local lp = cdLabel.Position
		local x = math.clamp(lp.X.Scale + lp.X.Offset / size.X, 0, 0.95)
		local y = math.clamp(lp.Y.Scale + lp.Y.Offset / size.Y, 0, 0.95)
		savedPos = UDim2.fromScale(x, y) -- stored only; the label stays exactly where it is
		local wrote = false
		pcall(function()
			if writefile then
				writefile(POS_FILE, HttpService:JSONEncode({ x = x, y = y }))
				wrote = true
			end
		end)
		if wrote then
			note("Cooldown position saved")
		else
			note("Position kept for this session (executor can't save files)")
		end
	end
end

local okInit, errInit = xpcall(init, function(e) return tostring(e) end)
if not okInit then
	note("Init error: " .. tostring(errInit))
	warn("[Firefly Timer] init failed: " .. tostring(errInit))
else
	impl.ready = true
	if impl.desired then safeCall(impl.apply, true) end
	if impl.desiredMove then safeCall(impl.setMove, true) end
end
