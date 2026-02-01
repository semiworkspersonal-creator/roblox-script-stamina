-- ================= SERVICES =================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ================= SETTINGS =================
local MAX_STAMINA = 100

local WALK_SPEED = 16
local SPRINT_SPEED = 32

local DAMAGE_WALK = 21
local DAMAGE_SPRINT = 37
local DAMAGE_BOOST_TIME = 0.8

local STAMINA_DRAIN_PER_SEC = 10
local STAMINA_REGEN_PER_SEC = 0.14 -- smooth (7% every 0.5s)
local STAMINA_ZERO_DELAY = 1

local DEFAULT_FOV = 70
local SPRINT_FOV = 80
local FOV_SMOOTH = 7

-- ⚠️ Re-upload this animation to your account if needed
local SPRINT_ANIM_ID = "rbxassetid://3565506007"
-- ============================================

local sprintHeld = false

-- ================= INPUT =================
local function SprintAction(_, state)
	if state == Enum.UserInputState.Begin then
		sprintHeld = true
	elseif state == Enum.UserInputState.End then
		sprintHeld = false
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(
	"Sprint",
	SprintAction,
	true,
	Enum.KeyCode.LeftShift, -- PC
	Enum.KeyCode.ButtonL2  -- Console
)

-- Mobile sprint button
ContextActionService:SetTitle("Sprint", "S")
ContextActionService:SetPosition("Sprint", UDim2.new(1, -110, 0.5, -40))

-- ================= UI =================
local function createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StatsUI"
	gui.ResetOnSpawn = false
	gui.Parent = player.PlayerGui

	local function makeBar(yOffset, color)
		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(0, 220, 0, 20)
		bg.Position = UDim2.new(0, 20, 1, yOffset)
		bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		bg.BorderSizePixel = 0
		bg.Parent = gui

		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 1, 0)
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		bar.Parent = bg

		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, 0, 1, 0)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Parent = bg

		return bar, text
	end

	local healthBar, healthText = makeBar(-80, Color3.fromRGB(0, 255, 0))
	local staminaBar, staminaText = makeBar(-50, Color3.fromRGB(0, 150, 255))

	return healthBar, healthText, staminaBar, staminaText
end

-- ================= CHARACTER =================
local function setupCharacter(char)
	local humanoid = char:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator")

	local stamina = MAX_STAMINA
	local regenBlockedUntil = 0
	local damageBoostUntil = 0

	-- Sprint animation
	local sprintAnim = Instance.new("Animation")
	sprintAnim.AnimationId = SPRINT_ANIM_ID
	local sprintTrack = animator:LoadAnimation(sprintAnim)
	sprintTrack.Priority = Enum.AnimationPriority.Movement

	local healthBar, healthText, staminaBar, staminaText = createUI()

	-- ===== UI CORNERS (ONLY VISUAL) =====
	local function roundBar(bg, fill, radius)
		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, radius)
		bgCorner.Parent = bg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, radius)
		fillCorner.Parent = fill
	end

	roundBar(healthBar.Parent, healthBar, 8)
	roundBar(staminaBar.Parent, staminaBar, 8)
	-- ===================================

	humanoid.HealthChanged:Connect(function()
		damageBoostUntil = os.clock() + DAMAGE_BOOST_TIME
	end)

	humanoid.Died:Connect(function()
		if sprintTrack.IsPlaying then
			sprintTrack:Stop()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if humanoid.Health <= 0 then return end

		local now = os.clock()
		local moving = humanoid.MoveDirection.Magnitude > 0

		-- ===== STAMINA DRAIN =====
		if sprintHeld and moving and stamina > 0 then
			stamina -= STAMINA_DRAIN_PER_SEC * dt
			if stamina <= 0 then
				stamina = 0
				regenBlockedUntil = now + STAMINA_ZERO_DELAY
			end
		end

		-- ===== STAMINA REGEN =====
		if ((not sprintHeld) or (sprintHeld and not moving)) and now >= regenBlockedUntil and stamina < MAX_STAMINA then
			stamina += MAX_STAMINA * STAMINA_REGEN_PER_SEC * dt
		end

		stamina = math.clamp(stamina, 0, MAX_STAMINA)

		-- ===== SPEED =====
		local speed = WALK_SPEED

		if sprintHeld and moving and stamina > 0 then
			speed = SPRINT_SPEED
		elseif os.clock() < damageBoostUntil then
			speed = DAMAGE_WALK
		end

		humanoid.WalkSpeed = speed

		-- ===== SPRINT ANIMATION =====
		if sprintHeld and moving and stamina > 0 then
			if not sprintTrack.IsPlaying then
				sprintTrack:Play(0.15)
			end
			sprintTrack:AdjustSpeed(humanoid.WalkSpeed / SPRINT_SPEED)
		else
			if sprintTrack.IsPlaying then
				sprintTrack:Stop(0.2)
			end
		end

		-- ===== FOV =====
		local targetFOV = (sprintHeld and moving and stamina > 0) and SPRINT_FOV or DEFAULT_FOV
		camera.FieldOfView += (targetFOV - camera.FieldOfView) * dt * FOV_SMOOTH

		-- ===== UI UPDATE =====
		staminaBar.Size = UDim2.new(stamina / MAX_STAMINA, 0, 1, 0)
		staminaText.Text = math.floor(stamina) .. "/" .. MAX_STAMINA

		local hpPercent = humanoid.Health / humanoid.MaxHealth
		healthBar.Size = UDim2.new(hpPercent, 0, 1, 0)
		healthText.Text = math.floor(humanoid.Health) .. "/" .. humanoid.MaxHealth

		if hpPercent > 0.7 then
			healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		elseif hpPercent > 0.4 then
			healthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
		elseif hpPercent > 0.2 then
			healthBar.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
		else
			healthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		end
	end)
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end
