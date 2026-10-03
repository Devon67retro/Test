local shared = odh_shared_plugins

if not shared or type(shared.CreateTab) ~= "function" then
	warn("[Firefly Timer] Load through the current Overdrive H plugin menu.")
	return
end

local ok, my_own_tab = pcall(function()
	return shared.CreateTab("Firefly Timer", "/Devon67retro/Test/refs/heads/main/icon")
end)

if not ok or not my_own_tab then
	warn("[Firefly Timer] CreateTab failed: " .. tostring(my_own_tab))
	return
end

local ok2, my_own_section = pcall(function()
	return my_own_tab:AddSection("Firefly Timer", "Countdown + auto jump")
end)

if not ok2 or not my_own_section then
	warn("[Firefly Timer] AddSection failed: " .. tostring(my_own_section))
	return
end

my_own_section:AddLabel("Made by: SANGUINE 🤤🤤")
my_own_section:AddParagraph("Firefly Timer", "Jumps at 0.24s remaining, second jump 0.50s later.")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local LocalPlayer = Players.LocalPlayer
local pg = LocalPlayer:WaitForChild("PlayerGui")

pcall(function()
	ContextActionService:UnbindAction("FireflyAutoJump")
end)

for _, name in ipairs({"FireflySettingsGui", "FireflyTimerGui", "FireflyCooldownGui"}) do
	local old = pg:FindFirstChild(name)
	if old then old:Destroy() end
end

local COUNTDOWN = 2.5
local COOLDOWN = 16
local JUMP1_REMAINING = 0.24
local JUMP_GAP = 0.50
local JUMP1_AT = COUNTDOWN - JUMP1_REMAINING
local JUMP2_AT = JUMP1_AT + JUMP_GAP
local JUMP_WINDOW = JUMP2_AT + 0.25
local CD_FONT = 48

local MY_ID = tostring(os.clock()) .. "-" .. tostring(math.random(1000, 9999999))
pcall(function() LocalPlayer:SetAttribute("FireflyRunId", MY_ID) end)

local function isCurrent()
	return LocalPlayer:GetAttribute("FireflyRunId") == MY_ID
end

local enabled = false
local token = 0
local jumpDeadline = 0
local countdownEnd = 0
local cooldownStart = 0
local cooldownEnd = 0
local conns = {}
local tickConn = nil
local hookInstalled = false
local screenGui, frame, label, stroke
local cdScreenGui, cdFrame, cdLabel

local function disconnectAll()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
end

local function stopTick()
	if tickConn then tickConn:Disconnect() tickConn = nil end
end

local function buildGui()
	if screenGui then return end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FireflyTimerGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = pg

	frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 100, 0, 50)
	frame.Position = UDim2.new(0.5, -50, 0.5, -100)
	frame.BackgroundTransparency = 0.7
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screenGui

	stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 0, 0)
	stroke.Thickness = 1
	stroke.Parent = frame

	label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = tostring(COUNTDOWN)
	label.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
end

local function buildCooldownGui()
	if cdScreenGui then return end
	cdScreenGui = Instance.new("ScreenGui")
	cdScreenGui.Name = "FireflyCooldownGui"
	cdScreenGui.ResetOnSpawn = false
	cdScreenGui.Parent = pg

	cdFrame = Instance.new("Frame")
	cdFrame.Size = UDim2.new(0, 150, 0, 60)
	cdFrame.Position = UDim2.new(0, 20, 0.5, 0)
	cdFrame.BackgroundTransparency = 1
	cdFrame.BorderSizePixel = 0
	cdFrame.Active = true
	cdFrame.Visible = false
	cdFrame.Parent = cdScreenGui

	cdLabel = Instance.new("TextLabel")
	cdLabel.Size = UDim2.new(1, 0, 1, 0)
	cdLabel.BackgroundTransparency = 1
	cdLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	cdLabel.TextSize = CD_FONT
	cdLabel.Font = Enum.Font.GothamBold
	cdLabel.TextXAlignment = Enum.TextXAlignment.Left
	cdLabel.Text = "Active"
	cdLabel.Parent = cdFrame

	local dragging, dragStart, startPos
	cdFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, cdFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	cdFrame.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			cdFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local function destroyGuis()
	if screenGui then pcall(function() screenGui:Destroy() end) end
	if cdScreenGui then pcall(function() cdScreenGui:Destroy() end) end
	screenGui, frame, label, stroke = nil, nil, nil, nil
	cdScreenGui, cdFrame, cdLabel = nil, nil, nil
end

local function startTick()
	if tickConn then return end
	tickConn = RunService.Heartbeat:Connect(function()
		if not isCurrent() or not enabled or not frame then
			stopTick()
			return
		end
		local now = os.clock()
		local c = countdownEnd - now
		if c > 0 then
			frame.Visible = true
			label.Text = string.format("%.1f", c)
		else
			frame.Visible = false
		end
		local k = cooldownEnd - now
		if k > 0 then
			if cdFrame then
				cdFrame.Visible = true
				cdLabel.Text = string.format("%.1f", now - cooldownStart)
			end
		else
			if cdLabel then cdLabel.Text = "Active" end
		end
		if c <= 0 and k <= 0 then stopTick() end
	end)
end

local function doJump(myToken)
	if not isCurrent() or not enabled then return end
	if myToken ~= token then return end
	if os.clock() > jumpDeadline then return end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	hum.Jump = true
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
end

local function resetCooldown()
	token += 1
	jumpDeadline, countdownEnd, cooldownEnd = 0, 0, 0
	if frame then frame.Visible = false end
	if cdLabel then cdLabel.Text = "Active" end
	if cdFrame then cdFrame.Visible = true end
end

local function onActivated()
	if not isCurrent() or not enabled then return end
	local now = os.clock()
	if now < cooldownEnd then return end
	token += 1
	local myToken = token
	countdownEnd = now + COUNTDOWN
	cooldownStart = now
	cooldownEnd = now + COOLDOWN
	jumpDeadline = now + JUMP_WINDOW
	buildGui()
	buildCooldownGui()
	cdFrame.Visible = true
	startTick()
	task.delay(JUMP1_AT, doJump, myToken)
	task.delay(JUMP2_AT, doJump, myToken)
end

local function hookTool(tool)
	if tool.Name == "Fireflies" and tool:IsA("Tool") then
		table.insert(conns, tool.Activated:Connect(onActivated))
	end
end

local function watchContainer(container)
	if not container then return end
	for _, t in ipairs(container:GetChildren()) do hookTool(t) end
	table.insert(conns, container.ChildAdded:Connect(hookTool))
end

local function installRoundHook()
	if hookInstalled or not hookmetamethod or not getnamecallmethod then return end
	local remote
	pcall(function() remote = ReplicatedStorage.Remotes.Gameplay.GetLastRoundRewards end)
	if not remote then return end

	hookInstalled = true
	local old = hookmetamethod(game, "__namecall", function(self, ...)
		if self == remote and getnamecallmethod() == "InvokeServer" and isCurrent() and enabled then
			pcall(resetCooldown)
		end
		return old(self, ...)
	end)
end

local function hookAll()
	disconnectAll()
	watchContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
	watchContainer(LocalPlayer.Character)
	table.insert(conns, LocalPlayer.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchContainer(child) end
	end))
	table.insert(conns, LocalPlayer.CharacterAdded:Connect(function(char)
		if not isCurrent() or not enabled then return end
		resetCooldown()
		watchContainer(char)
	end))
	installRoundHook()
	if not hookInstalled then
		task.spawn(function()
			for _ = 1, 20 do
				if hookInstalled or not isCurrent() or not enabled then break end
				installRoundHook()
				task.wait(0.5)
			end
		end)
	end
end

my_own_section:AddToggle("Enable Firefly Timer", function(bool)
	if not isCurrent() then return end
	enabled = bool
	if bool then
		resetCooldown()
		buildGui()
		buildCooldownGui()
		hookAll()
		shared.Notify("Firefly Timer enabled", 2)
	else
		resetCooldown()
		stopTick()
		disconnectAll()
		destroyGuis()
		shared.Notify("Firefly Timer disabled", 2)
	end
end)

print("[Firefly Timer] Loaded successfully")
