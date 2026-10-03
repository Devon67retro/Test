local shared = odh_shared_plugins

if not shared or type(shared.CreateTab) ~= "function" then
	warn("[Firefly Timer] Load through the current Overdrive H plugin menu.")
	return
end

local ok, my_own_tab = pcall(function()
	return shared.CreateTab("Firefly Timer", "/Devon67retro/Test/refs/heads/main/icon")
end)
if not ok or not my_own_tab then return end

local ok2, my_own_section = pcall(function()
	return my_own_tab:AddSection("Firefly Timer", "Countdown + auto jump")
end)
if not ok2 or not my_own_section then return end

local function note(msg)
	pcall(function() shared.Notify(msg, 4) end)
end

-- ===== TOGGLE FIRST: nothing above can fail, so it always appears =====
local impl = { ready = false, desired = false }

pcall(function()
	my_own_section:AddToggle("Enable Firefly Timer", function(bool)
		impl.desired = bool and true or false
		if impl.ready then
			local okA, errA = pcall(impl.apply, impl.desired)
			if not okA then note("Toggle error: " .. tostring(errA)) end
		end
	end)
end)

pcall(function() my_own_section:AddLabel("Made by: SANGUINE 🙏🙏 ") end)
pcall(function() my_own_section:AddParagraph("Firefly Timer", "Jumps at 0.24s remaining, second jump 0.50s later.") end)

-- ===== Everything else, guarded; errors are shown on screen =====
local function init()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local pg = LocalPlayer:WaitForChild("PlayerGui")

	local COUNTDOWN = 2.5
	local COOLDOWN = 16
	local JUMP1_AT = COUNTDOWN - 0.24
	local JUMP_GAP = 0.50   -- second jump this long after the first ACTUALLY fires
	local GRACE = 0.35      -- how long to keep waiting to be grounded before giving up

	local MY_ID = tostring(os.clock()) .. tostring(math.random(1000, 9999))
	pcall(function() LocalPlayer:SetAttribute("FireflyRunId", MY_ID) end)
	local function isCurrent()
		local okA, v = pcall(function() return LocalPlayer:GetAttribute("FireflyRunId") end)
		if not okA then return true end
		return v == MY_ID
	end

	local enabled = false
	local token, deadline = 0, 0
	local countEnd, cdStart, cdEnd = 0, 0, 0
	local conns, hooked = {}, {}
	local scanToken = 0
	local gui, countLabel, cdLabel
	local firstActivate = true

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

	local function buildGui()
		if gui and gui.Parent then return end
		gui = Instance.new("ScreenGui")
		gui.Name = "FireflyLiteGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 999
		gui.Parent = pg
		countLabel = makeLabel(gui, UDim2.new(0.5, -50, 0.4, 0), UDim2.fromOffset(100, 50), 32)
		cdLabel = makeLabel(gui, UDim2.new(0, 20, 0.5, 0), UDim2.fromOffset(110, 44), 26)
	end

	local function hideGui()
		if countLabel then countLabel.Visible = false end
		if cdLabel then cdLabel.Visible = false end
	end

	-- returns true = jumped, false = still airborne (retry), nil = no living character
	local function tryJump()
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return nil end
		if hum.FloorMaterial == Enum.Material.Air then return false end
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		return true
	end

	local function onActivated()
		if not enabled or not isCurrent() then return end
		local now = os.clock()
		if now < cdEnd then return end
		if firstActivate then
			firstActivate = false
			note("Fireflies activated - timer started")
		end

		token = token + 1
		local my = token
		countEnd, cdStart, cdEnd = now + COUNTDOWN, now, now + COOLDOWN

		local okG, errG = pcall(buildGui)
		if not okG then note("GUI error: " .. tostring(errG)) end

		local actStart = now
		local phase, phaseT = 0, 0
		-- 0 wait for jump1 time | 1 trying jump1 | 2 wait gap | 3 trying jump2 | 4 done
		task.spawn(function()
			while enabled and isCurrent() and my == token do
				local t = os.clock()

				if phase == 0 and t >= actStart + JUMP1_AT then
					phase, phaseT = 1, t
				end
				if phase == 1 then
					local r = tryJump()
					if r then phase, phaseT = 2, t
					elseif r == nil or t > phaseT + GRACE then phase = 4 end
				elseif phase == 2 then
					if t >= phaseT + JUMP_GAP then phase, phaseT = 3, t end
				elseif phase == 3 then
					local r = tryJump()
					if r or r == nil or t > phaseT + GRACE then phase = 4 end
				end

				local c, k = countEnd - t, cdEnd - t
				if countLabel then
					countLabel.Visible = c > 0
					if c > 0 then countLabel.Text = string.format("%.1f", c) end
				end
				if cdLabel then
					cdLabel.Visible = k > 0
					if k > 0 then cdLabel.Text = string.format("CD %.1f", t - cdStart) end
				end
				if c <= 0 and k <= 0 then break end
				RunService.Heartbeat:Wait()
			end
			if my == token then hideGui() end
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
						table.insert(conns, child.Activated:Connect(onActivated))
						note("Fireflies hooked")
					end
				end
			end
		end
	end

	local function reset()
		token = token + 1
		deadline, countEnd, cdEnd = 0, 0, 0
		hideGui()
	end

	local function start()
		buildGui()
		scanToken = scanToken + 1
		local my = scanToken
		table.insert(conns, LocalPlayer.CharacterAdded:Connect(function()
			if enabled and isCurrent() then reset() end
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
		reset()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		table.clear(conns)
		table.clear(hooked)
	end

	impl.apply = function(bool)
		if not isCurrent() then return end
		enabled = bool
		if enabled then
			local okS, errS = pcall(start)
			if okS then note("Firefly Timer ON - equip Fireflies and use it")
			else note("Start error: " .. tostring(errS)) end
		else
			pcall(stop)
			note("Firefly Timer OFF")
		end
	end
end

local okInit, errInit = xpcall(init, function(e) return tostring(e) end)
if not okInit then
	note("Init error: " .. tostring(errInit))
	warn("[Firefly Timer] init failed: " .. tostring(errInit))
else
	impl.ready = true
	if impl.desired then pcall(impl.apply, true) end -- hub restored ON early
end
