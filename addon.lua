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

pcall(function() my_own_section:AddLabel("Made by: SANGUINE 🙏🙏 ") end)
pcall(function() my_own_section:AddParagraph("Firefly Timer", "Jumps at 0.24s remaining, second jump 0.50s later.") end)

local function note(msg)
	pcall(function() shared.Notify(msg, 3) end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ===== Config =====
local COUNTDOWN = 2.5
local COOLDOWN = 16
local JUMP1_AT = COUNTDOWN - 0.24   -- 0.24s remaining
local JUMP2_AT = JUMP1_AT + 0.50
local WINDOW = JUMP2_AT + 0.25

-- ===== Run identity (old runs go inert) =====
local MY_ID = tostring(os.clock()) .. tostring(math.random(1000, 9999))
pcall(function() LocalPlayer:SetAttribute("FireflyRunId", MY_ID) end)
local function isCurrent()
	return LocalPlayer:GetAttribute("FireflyRunId") == MY_ID
end

-- ===== State =====
local enabled = false
local token = 0
local deadline = 0
local countEnd, cdStart, cdEnd = 0, 0, 0
local conns = {}
local hooked = {}
local scanToken = 0
local gui, countLabel, cdLabel

-- ===== GUI =====
local function guiParent()
	local p
	pcall(function() p = gethui and gethui() end)
	if p then return p end
	pcall(function() p = game:GetService("CoreGui") end)
	if p then return p end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function nukeOld()
	for _, parent in ipairs({ guiParent(), LocalPlayer:FindFirstChild("PlayerGui") }) do
		if parent then
			for _, n in ipairs({ "FireflyLiteGui", "FireflyTimerGui", "FireflyCooldownGui", "FireflySettingsGui" }) do
				local o = parent:FindFirstChild(n)
				if o then pcall(function() o:Destroy() end) end
			end
		end
	end
end
nukeOld()

local function label(parent, pos, size, textSize)
	local l = Instance.new("TextLabel")
	l.Position, l.Size = pos, size
	l.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	l.BackgroundTransparency = 0.5
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.Text = ""
	l.Visible = false
	l.Parent = parent
	Instance.new("UICorner", l)
	return l
end

local function buildGui()
	if gui and gui.Parent then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "FireflyLiteGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = guiParent()
	countLabel = label(gui, UDim2.new(0.5, -50, 0.4, 0), UDim2.fromOffset(100, 50), 32)
	cdLabel = label(gui, UDim2.new(0, 20, 0.5, 0), UDim2.fromOffset(110, 44), 26)
end

local function hideGui()
	if countLabel then countLabel.Visible = false end
	if cdLabel then cdLabel.Visible = false end
end

-- ===== Jump (one-shot, gated) =====
local function doJump(myToken)
	if not enabled or not isCurrent() then return end
	if myToken ~= token or os.clock() > deadline then return end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	hum.Jump = true
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
end

-- ===== Activation =====
local firstActivate = true
local function onActivated()
	if not enabled or not isCurrent() then return end
	local now = os.clock()
	if now < cdEnd then return end
	if firstActivate then firstActivate = false; note("Fireflies activated - timer started") end

	token += 1
	local my = token
	countEnd, cdStart, cdEnd = now + COUNTDOWN, now, now + COOLDOWN
	deadline = now + WINDOW

	local okG, errG = pcall(buildGui)
	if not okG then note("GUI error: " .. tostring(errG)) end

	task.delay(JUMP1_AT, doJump, my)
	task.delay(JUMP2_AT, doJump, my)

	task.spawn(function()
		while enabled and isCurrent() and my == token do
			local t = os.clock()
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

-- ===== Find + hook Fireflies (polling: no event timing issues) =====
local function scan()
	local places = { LocalPlayer:FindFirstChildOfClass("Backpack"), LocalPlayer.Character }
	for _, place in ipairs(places) do
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
	token += 1
	deadline, countEnd, cdEnd = 0, 0, 0
	hideGui()
end

local function start()
	buildGui()
	scanToken += 1
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
	scanToken += 1
	reset()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
	table.clear(hooked)
end

-- ===== Single hub toggle =====
my_own_section:AddToggle("Enable Firefly Timer", function(bool)
	if not isCurrent() then return end
	enabled = bool and true or false
	if enabled then
		local okS, errS = pcall(start)
		if okS then note("Firefly Timer ON - equip Fireflies and use it")
		else note("Start error: " .. tostring(errS)) end
	else
		pcall(stop)
		note("Firefly Timer OFF")
	end
end)
