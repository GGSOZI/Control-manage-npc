local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local C = {}
C.BLUE = Color3.fromRGB(45, 125, 255)
C.LIGHTBLUE = Color3.fromRGB(120, 175, 255)
C.RED = Color3.fromRGB(255, 0, 0)
C.GREEN = Color3.fromRGB(0, 255, 0)
C.YELLOW = Color3.fromRGB(210, 180, 40)
C.DARK = Color3.fromRGB(22, 23, 27)
C.DARK2 = Color3.fromRGB(38, 40, 46)
C.GRAY3 = Color3.fromRGB(52, 55, 63)
C.STROKE = Color3.fromRGB(70, 74, 84)
C.TEXT = Color3.fromRGB(225, 228, 235)
C.SUBTEXT = Color3.fromRGB(140, 146, 158)
C.KILL_RED = Color3.fromRGB(170, 30, 40)

C.FONT = Enum.Font.Code
C.BOLD_FONT = Enum.Font.Code
local NPC_ATTRIBUTE = "DuaKNoControllable"
local OWNER_USERNAME = "DuaKNo"

local MIN_W, MIN_H, MAX_W, MAX_H = 440, 260, 900, 700

task.spawn(function()
	local icon = ""
	pcall(function()
		local userId = Players:GetUserIdFromNameAsync(OWNER_USERNAME)
		icon = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)

	local function notify(titleText, bodyText, iconId, duration)
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = titleText,
					Text = bodyText,
					Icon = iconId or "",
					Duration = duration or 6,
				})
			end)
			if ok then return end
			task.wait(0.5)
		end
	end

	notify("NPC Manager", "By DuaKNo", icon, 7)
	task.wait(0.6)
	notify("Follow on Instagram", "me_duakno", nil, 7)
	task.wait(0.6)
	notify("Join Discord server for more", "discord.gg/empgqd5qpq", nil, 7)
end)

local simulationRadius = 150
local MAX_RADIUS = 1e9

local npcSpeed = 16
local MIN_NPC_SPEED = 0
local MAX_NPC_SPEED = 500

local npcCount = 0
local npcEntries = {}

local selectedModel = nil
local selectedNPCs = {}
local highlights = {}
local multiSelectEnabled = false

local followConnection = nil
local attackConnection = nil
local wanderConnection = nil
local moveConnection = nil
local activeFollowMode = nil
local selectMode = false
local controlEnabled = false
local attackModeEnabled = false
local clickMoveEnabled = false

local wanderRadius = 40
local wanderState = {}
local moveTargets = {}

local teleportModeNPCs = {}
local disableCollisionInModes = false

local rigChoice = "Auto"
local spawning = false
local npcJump = 50
local selectedOutfitName = nil
local infoLabel = nil
local healthBarsEnabled = true
local toggleKey = Enum.KeyCode.RightShift
local bindingKey = false
local keybindButton = nil
local waypointMode = false
local followTargetPlayer = nil
local patrolConnection = nil
local patrolPoints = {}
local patrolMarkers = {}
local patrolCountLabel = nil

local weakKeys = {__mode = "k"}
local frozenState = setmetatable({}, weakKeys)
local animSets = setmetatable({}, weakKeys)
local animDrivers = setmetatable({}, weakKeys)
local stuckTracker = setmetatable({}, weakKeys)
local patrolState = setmetatable({}, weakKeys)

local originalCharacter = nil
local originalCameraSubject = nil
local originalCameraType = nil
local originalMouseBehavior = nil

local controlToggle
local updateHighlights
local refreshHighlight
local behaviorToggles = {}

local function styleButton(btn, strokeColor, hover)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor or C.STROKE
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	if hover ~= false then
		local base = btn.BackgroundColor3
		local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, info, {BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12)}):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, info, {BackgroundColor3 = base}):Play()
		end)
	end
	return stroke
end

local function getHumanoid(model)
	if not model then return nil end
	return model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function getRealCharacter()
	return originalCharacter or LocalPlayer.Character
end

local function isUnanchoredNPC(model)
	if not model or not model:IsA("Model") then return false end
	local humanoid = getHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return false end
	if model:GetAttribute("DuaKNoFrozen") then return true end
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and not obj.Anchored then
			return true
		end
	end
	return false
end

local function isControllableNPC(model)
	if not model or not model:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	local humanoid = getHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return false end
	if model:GetAttribute(NPC_ATTRIBUTE) == true then return true end
	return isUnanchoredNPC(model)
end

local function isSelectableNPC(model)
	if not model or not model:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	local humanoid = getHumanoid(model)
	return humanoid ~= nil
end

local function isR6(model)
	local humanoid = getHumanoid(model)
	return humanoid and humanoid.RigType == Enum.HumanoidRigType.R6
end

local function findEntry(model)
	for _, entry in ipairs(npcEntries) do
		if entry.model == model then return entry end
	end
	return nil
end

local function isSelected(model)
	for _, m in ipairs(selectedNPCs) do
		if m == model then return true end
	end
	return false
end

local function resolveRigType()
	if rigChoice == "R6" then return Enum.HumanoidRigType.R6 end
	if rigChoice == "R15" then return Enum.HumanoidRigType.R15 end
	local character = getRealCharacter()
	local humanoid = character and getHumanoid(character)
	if humanoid then return humanoid.RigType end
	return Enum.HumanoidRigType.R15
end

local function applySpeedToModel(model)
	local humanoid = getHumanoid(model)
	if humanoid then
		humanoid.WalkSpeed = npcSpeed
	end
end

local function applySpeedToSelection()
	for _, model in ipairs(selectedNPCs) do
		applySpeedToModel(model)
	end
end

local function addSelected(model)
	if not isSelected(model) then
		local humanoid = getHumanoid(model)
		if humanoid and humanoid.JumpPower <= 0 then
			humanoid.JumpPower = 50
		end
		table.insert(selectedNPCs, model)
		selectedModel = model
		applySpeedToModel(model)
	end
	updateHighlights()
	refreshHighlight()
end

local function removeSelected(model)
	for i, m in ipairs(selectedNPCs) do
		if m == model then
			table.remove(selectedNPCs, i)
			break
		end
	end
	if selectedModel == model then
		selectedModel = selectedNPCs[#selectedNPCs] or nil
	end
	updateHighlights()
	refreshHighlight()
end

local function clearSelection()
	selectedNPCs = {}
	selectedModel = nil
	updateHighlights()
	refreshHighlight()
end

local function getRandomDamage()
	local totalWeight = 2016
	local roll = math.random(1, totalWeight)
	local cumulative = 0
	for damage = 5, 67 do
		local weight = 68 - damage
		cumulative = cumulative + weight
		if roll <= cumulative then
			return damage
		end
	end
	return 67
end

local function setModelCollisions(model, enabled)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = enabled
			part.Massless = not enabled
		end
	end
	local humanoid = getHumanoid(model)
	if humanoid then
		humanoid.PlatformStand = not enabled
	end
end

local function applyCollisionState()
	local isTeleportMode = activeFollowMode == "inside" or activeFollowMode == "below" or activeFollowMode == "above"
	for _, model in ipairs(teleportModeNPCs) do
		if model and model.Parent then
			setModelCollisions(model, not isTeleportMode)
		end
	end
end

local npcAnimNames = {
	R6 = {
		idle = {
			{ id = "http://www.roblox.com/asset/?id=180435571", weight = 9 },
			{ id = "http://www.roblox.com/asset/?id=180435792", weight = 1 }
		},
		walk = { { id = "http://www.roblox.com/asset/?id=180426354", weight = 10 } },
		run = { { id = "http://www.roblox.com/asset/?id=180426354", weight = 10 } },
		jump = { { id = "http://www.roblox.com/asset/?id=125750702", weight = 10 } },
		fall = { { id = "http://www.roblox.com/asset/?id=180436148", weight = 10 } },
		climb = { { id = "http://www.roblox.com/asset/?id=180436334", weight = 10 } },
		sit = { { id = "http://www.roblox.com/asset/?id=178130996", weight = 10 } },
		equip = { { id = "http://www.roblox.com/asset/?id=182393478", weight = 10 } },
		toolnone = { { id = "http://www.roblox.com/asset/?id=182393478", weight = 10 } },
		toolslash = { { id = "http://www.roblox.com/asset/?id=129967390", weight = 10 } },
		toollunge = { { id = "http://www.roblox.com/asset/?id=129967478", weight = 10 } },
	},
	R15 = {
		idle = {
			{ id = "rbxassetid://507766666", weight = 8 },
			{ id = "rbxassetid://507766951", weight = 1 },
			{ id = "rbxassetid://507766388", weight = 1 }
		},
		walk = { { id = "rbxassetid://507777826", weight = 10 } },
		run = { { id = "rbxassetid://507767714", weight = 10 } },
		jump = { { id = "rbxassetid://507765000", weight = 10 } },
		fall = { { id = "rbxassetid://507767968", weight = 10 } },
		climb = { { id = "rbxassetid://507765644", weight = 10 } },
		sit = { { id = "rbxassetid://2506281703", weight = 10 } },
		equip = { { id = "rbxassetid://507768375", weight = 10 } },
		toolnone = { { id = "rbxassetid://507768375", weight = 10 } },
		toolslash = { { id = "rbxassetid://522635514", weight = 10 } },
		toollunge = { { id = "rbxassetid://522638767", weight = 10 } },
	},
}

local ANIM_GROUPS = {
	idle = true, walk = true, run = true, jump = true, fall = true, climb = true,
	sit = true, toolnone = true, toolslash = true, toollunge = true,
}

local DESC_ANIM_PROPS = {
	idle = "IdleAnimation", walk = "WalkAnimation", run = "RunAnimation",
	jump = "JumpAnimation", fall = "FallAnimation", climb = "ClimbAnimation",
}

local function looksLikeAnimId(v)
	if type(v) ~= "string" or v == "" then return false end
	if v:find("rbxassetid://", 1, true) then return true end
	if v:find("http", 1, true) then return true end
	if v:match("^%d+$") then return true end
	return false
end

local function getPlayerAnimationIds(rigType)
	local character = getRealCharacter()
	if not character then return nil end
	local charHumanoid = getHumanoid(character)
	if not charHumanoid or charHumanoid.RigType ~= rigType then return nil end
	local animate = character:FindFirstChild("Animate")
	if not animate then return nil end

	local ids = {}
	for _, obj in ipairs(animate:GetDescendants()) do
		local id = nil
		if obj:IsA("Animation") and looksLikeAnimId(obj.AnimationId) then
			id = obj.AnimationId
		elseif obj:IsA("StringValue") and looksLikeAnimId(obj.Value) then
			id = obj.Value
		end

		if id then

			local group = obj
			while group and group.Parent ~= animate do
				group = group.Parent
			end
			if group then
				local key = string.lower(group.Name)
				if ANIM_GROUPS[key] then
					local weight = 10
					local weightValue = obj:FindFirstChild("Weight")
					if weightValue and weightValue:IsA("NumberValue") and weightValue.Value > 0 then
						weight = weightValue.Value
					end
					if not ids[key] then ids[key] = {} end
					table.insert(ids[key], { id = id, weight = weight })
				end
			end
		end
	end

	if not ids.idle or not (ids.walk or ids.run) then return nil end
	if not ids.run then ids.run = ids.walk end
	if not ids.walk then ids.walk = ids.run end
	if ids.toolnone then ids.equip = ids.toolnone end
	return ids
end

local function pickAnimId(list)
	local total = 0
	for _, a in ipairs(list) do total = total + a.weight end
	local roll = math.random() * total
	for _, a in ipairs(list) do
		if roll <= a.weight then return a.id end
		roll = roll - a.weight
	end
	return list[1].id
end

local function buildAnimSet(rigType, usePlayerAnims, desc)
	local base = (rigType == Enum.HumanoidRigType.R6) and npcAnimNames.R6 or npcAnimNames.R15
	local set = {}
	for key, list in pairs(base) do set[key] = list end

	if desc and rigType == Enum.HumanoidRigType.R15 then
		for key, prop in pairs(DESC_ANIM_PROPS) do
			local ok, value = pcall(function() return desc[prop] end)
			if ok and type(value) == "number" and value > 0 then
				set[key] = { { id = "rbxassetid://" .. tostring(value), weight = 10 } }
			end
		end
	end

	if usePlayerAnims then
		local pa = getPlayerAnimationIds(rigType)
		if pa then
			for key, list in pairs(pa) do set[key] = list end
		end
	end
	return set
end

local ANIM_STATES = {"idle", "walk", "run", "jump", "fall", "climb", "sit"}

local function loadReadyTrack(animator, id)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok or not track then return nil end
	pcall(function() ContentProvider:PreloadAsync({anim}) end)
	local startedAt = os.clock()
	while track.Length <= 0 and os.clock() - startedAt < 2.5 do
		task.wait(0.05)
	end
	if track.Length <= 0 then
		pcall(function() track:Destroy() end)
		return nil
	end
	track.Priority = Enum.AnimationPriority.Core
	return track
end

local function attachAnimations(model, set)
	local humanoid = getHumanoid(model)
	if not humanoid or not set then return end

	local previous = animDrivers[model]
	if previous then
		previous:Disconnect()
		animDrivers[model] = nil
	end
	animSets[model] = set

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	pcall(function()
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end)

	local defaults = (humanoid.RigType == Enum.HumanoidRigType.R6) and npcAnimNames.R6 or npcAnimNames.R15

	local tracks = {}
	for _, name in ipairs(ANIM_STATES) do
		task.spawn(function()
			local track = nil
			if set[name] then
				track = loadReadyTrack(animator, pickAnimId(set[name]))
			end
			if not track and defaults[name] and set[name] ~= defaults[name] then
				track = loadReadyTrack(animator, pickAnimId(defaults[name]))
			end
			if track then tracks[name] = track end
		end)
	end

	local currentTrack = nil
	local currentName = nil
	local fallingSince = nil

	local function play(name, fade, animSpeed)
		local track = tracks[name]
		if not track then return false end
		if currentName ~= name then
			if currentTrack then currentTrack:Stop(fade) end
			currentTrack = track
			currentName = name
			track:Play(fade)
		end
		if animSpeed then track:AdjustSpeed(animSpeed) end
		return true
	end

	local function playMovement(speed)
		local animSpeed = math.clamp(speed / 16, 0.3, 2.5)
		if speed > 14 and play("run", 0.15, animSpeed) then return end
		if play("walk", 0.15, animSpeed) then return end
		play("idle", 0.15)
	end

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not model.Parent or not humanoid.Parent or humanoid.Health <= 0 then
			if currentTrack then
				currentTrack:Stop(0.2)
				currentTrack = nil
				currentName = nil
			end
			connection:Disconnect()
			if animDrivers[model] == connection then animDrivers[model] = nil end
			return
		end

		local root = getRoot(model)
		if not root then return end

		if humanoid.Sit then
			play("sit", 0.3)
			return
		end

		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Climbing then
			fallingSince = nil
			play("climb", 0.1)
			return
		end
		if state == Enum.HumanoidStateType.Jumping then
			fallingSince = nil
			play("jump", 0.1)
			return
		end
		if state == Enum.HumanoidStateType.Freefall then
			fallingSince = fallingSince or os.clock()
			if os.clock() - fallingSince > 0.2 then
				play("fall", 0.2)
			end
			return
		end
		fallingSince = nil

		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		if speed > 1 then
			playMovement(speed)
		else
			play("idle", 0.2)
		end
	end)
	animDrivers[model] = connection
end

local function ensureAnimations(model)
	if not isR6(model) then return end
	if model:GetAttribute("DuaKNoAnimationsAttached") then return end
	pcall(function()
		attachAnimations(model, buildAnimSet(Enum.HumanoidRigType.R6, false, nil))
	end)
	model:SetAttribute("DuaKNoAnimationsAttached", true)
end

local function rotateVectorAroundY(vec, angleRad)
	local cos = math.cos(angleRad)
	local sin = math.sin(angleRad)
	return Vector3.new(vec.X * cos - vec.Z * sin, vec.Y, vec.X * sin + vec.Z * cos)
end

local function getBestAvoidanceDirection(model, root, desiredDirection, maxDist)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {model, LocalPlayer.Character}

	local angles = {
		0,
		math.rad(20), math.rad(-20),
		math.rad(45), math.rad(-45),
		math.rad(70), math.rad(-70),
		math.rad(100), math.rad(-100)
	}

	local bestDir = desiredDirection
	local bestScore = -math.huge

	for _, angle in ipairs(angles) do
		local dir = rotateVectorAroundY(desiredDirection, angle)
		dir = Vector3.new(dir.X, 0, dir.Z).Unit

		local rayOrigin = root.Position + Vector3.new(0, 1.5, 0)
		local rayResult = Workspace:Raycast(rayOrigin, dir * maxDist, rayParams)

		local freeDist
		if rayResult then
			freeDist = (rayResult.Position - root.Position).Magnitude
		else
			freeDist = maxDist
		end

		local anglePenalty = math.abs(angle) * 2
		local score = freeDist - anglePenalty

		if freeDist > 1.5 and score > bestScore then
			bestScore = score
			bestDir = dir
		end
	end

	return bestDir
end

local function smartMoveTo(model, targetPosition)
	if not model or not model.Parent then return end
	local humanoid = getHumanoid(model)
	local root = getRoot(model)
	if not humanoid or not root then return end

	local startPos = root.Position
	local desiredDirection = (targetPosition - startPos)
	desiredDirection = Vector3.new(desiredDirection.X, 0, desiredDirection.Z)

	local distance = desiredDirection.Magnitude
	if distance < 1 then
		humanoid:MoveTo(targetPosition)
		return
	end

	desiredDirection = desiredDirection.Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {model, LocalPlayer.Character}

	local forwardRay = Workspace:Raycast(startPos + Vector3.new(0, 1.5, 0), desiredDirection * math.min(distance, 10), rayParams)

	if forwardRay then
		local avoidDir = getBestAvoidanceDirection(model, root, desiredDirection, 8)
		local waypoint = startPos + avoidDir * 6
		humanoid:MoveTo(waypoint)

		local tracker = stuckTracker[model]
		if tracker then
			local moved = (root.Position - tracker.lastPos).Magnitude
			if moved < 0.5 and (os.clock() - tracker.lastTime) > 0.5 then
				if humanoid.FloorMaterial ~= Enum.Material.Air then
					humanoid.Jump = true
				end
				local randomAngle = math.rad(math.random(-120, 120))
				local breakoutDir = rotateVectorAroundY(desiredDirection, randomAngle)
				humanoid:MoveTo(root.Position + breakoutDir * 3)
				tracker.attempts = (tracker.attempts or 0) + 1
				if tracker.attempts > 3 then
					tracker.attempts = 0
				end
			end
			tracker.lastPos = root.Position
			tracker.lastTime = os.clock()
		else
			stuckTracker[model] = {lastPos = root.Position, lastTime = os.clock(), attempts = 0}
		end
	else
		humanoid:MoveTo(targetPosition)
		if stuckTracker[model] then
			stuckTracker[model] = {lastPos = root.Position, lastTime = os.clock(), attempts = 0}
		end
	end
end

local function stopAllConnections()
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
	if attackConnection then
		attackConnection:Disconnect()
		attackConnection = nil
	end

	for _, model in ipairs(teleportModeNPCs) do
		if model and model.Parent then
			setModelCollisions(model, true)
			local root = getRoot(model)
			local playerRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root and playerRoot then
				root.CFrame = playerRoot.CFrame + Vector3.new(5, 0, 0)
			end
		end
	end
	teleportModeNPCs = {}

	activeFollowMode = nil
	attackModeEnabled = false
end

local function freezeModel(model)
	if not model or not model.Parent or frozenState[model] then return end
	local saved = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			saved[part] = part.Anchored
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			part.Anchored = true
		end
	end
	frozenState[model] = saved
	model:SetAttribute("DuaKNoFrozen", true)
	local humanoid = getHumanoid(model)
	local root = getRoot(model)
	if humanoid and root then
		pcall(function() humanoid:MoveTo(root.Position) end)
	end
end

local function unfreezeModel(model)
	local saved = frozenState[model]
	if not saved then return end
	for part, wasAnchored in pairs(saved) do
		if part.Parent then
			part.Anchored = wasAnchored
		end
	end
	frozenState[model] = nil
	if model and model.Parent then
		model:SetAttribute("DuaKNoFrozen", nil)
	end
end

local function showMoveMarker(position)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = C.BLUE
	part.Transparency = 0.2
	part.Size = Vector3.new(0.15, 1.5, 1.5)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = Workspace

	local tween = TweenService:Create(part, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 4, 4),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

local function issueMoveTo(position)
	local list = {}
	for _, model in ipairs(selectedNPCs) do
		local humanoid = getHumanoid(model)
		if model.Parent and model ~= LocalPlayer.Character and humanoid and humanoid.Health > 0 and not frozenState[model] then
			table.insert(list, model)
		end
	end

	local count = #list
	for i, model in ipairs(list) do
		local offset = Vector3.zero
		if count > 1 then
			local angle = (i - 1) * (2 * math.pi / count)
			local radius = 1.5 + count * 0.35
			offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		end
		moveTargets[model] = { pos = position + offset, expire = os.clock() + 25 }
	end
	showMoveMarker(position)
end

local function stopClickMove()
	if moveConnection then
		moveConnection:Disconnect()
		moveConnection = nil
	end
	moveTargets = {}
	clickMoveEnabled = false
end

local function startClickMove()
	clickMoveEnabled = true
	moveTargets = {}
	moveConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for model, target in pairs(moveTargets) do
			local humanoid = getHumanoid(model)
			local root = getRoot(model)
			if not model.Parent or not humanoid or not root or humanoid.Health <= 0 or now > target.expire then
				moveTargets[model] = nil
			else
				local dx = target.pos.X - root.Position.X
				local dz = target.pos.Z - root.Position.Z
				if math.sqrt(dx * dx + dz * dz) < 2.5 then
					moveTargets[model] = nil
					pcall(function() humanoid:MoveTo(root.Position) end)
				else
					smartMoveTo(model, target.pos)
				end
			end
		end
	end)
end

local function stopWander()
	if wanderConnection then
		wanderConnection:Disconnect()
		wanderConnection = nil
	end
	for model, _ in pairs(wanderState) do
		local humanoid = getHumanoid(model)
		local root = getRoot(model)
		if humanoid and root and model.Parent then
			pcall(function() humanoid:MoveTo(root.Position) end)
		end
	end
	wanderState = {}
end

local function startWander()
	wanderState = {}
	wanderConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= LocalPlayer.Character and not frozenState[model] then
				local humanoid = getHumanoid(model)
				local root = getRoot(model)
				if humanoid and root and humanoid.Health > 0 then
					local st = wanderState[model]
					if not st then
						st = { home = root.Position, target = nil, nextAt = 0, expire = 0 }
						wanderState[model] = st
					end

					if st.target then
						local dx = st.target.X - root.Position.X
						local dz = st.target.Z - root.Position.Z
						if math.sqrt(dx * dx + dz * dz) < 3 or now > st.expire then
							st.target = nil
							st.nextAt = now + 1 + math.random() * 3
							pcall(function() humanoid:MoveTo(root.Position) end)
						else
							smartMoveTo(model, st.target)
						end
					elseif now >= st.nextAt then
						local angle = math.random() * math.pi * 2
						local dist = 6 + math.random() * math.max(wanderRadius - 6, 1)
						st.target = st.home + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
						st.expire = now + 10
					end
				end
			end
		end
	end)
end

local activeTeleportPartsCache = {}

local function getTeleportParts(model)
	local cached = activeTeleportPartsCache[model]
	if cached then return cached end
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	activeTeleportPartsCache[model] = parts
	return parts
end

local function startTeleportMode(mode, getPlayerRoot)
	teleportModeNPCs = {}
	for _, model in ipairs(selectedNPCs) do
		if model and model.Parent and model ~= LocalPlayer.Character then
			local hum = getHumanoid(model)
			if hum and hum.Health > 0 then
				table.insert(teleportModeNPCs, model)
			end
		end
	end
	applyCollisionState()

	followConnection = RunService.RenderStepped:Connect(function()
		local playerRoot = getPlayerRoot()
		if not playerRoot then return end

		local targetCF
		if mode == "inside" then
			targetCF = playerRoot.CFrame
		else
			local yOffset = (mode == "below") and -3 or 3
			local pos = playerRoot.Position + Vector3.new(0, yOffset, 0)

			targetCF = CFrame.new(pos, pos + playerRoot.CFrame.LookVector) * CFrame.Angles(math.rad(90), 0, 0)
		end

		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= LocalPlayer.Character then
				local hum = getHumanoid(model)
				if hum and hum.Health > 0 then
					if not table.find(teleportModeNPCs, model) then
						table.insert(teleportModeNPCs, model)
					end
					local npcRoot = getRoot(model)
					if npcRoot then
						npcRoot.CFrame = targetCF
						npcRoot.AssemblyLinearVelocity = Vector3.zero
						npcRoot.AssemblyAngularVelocity = Vector3.zero
						local parts = getTeleportParts(model)
						for _, part in ipairs(parts) do
							if part.CanCollide then part.CanCollide = false end
							if not part.Massless then part.Massless = true end
						end
						if not hum.PlatformStand then hum.PlatformStand = true end
					end
				end
			end
		end
	end)
end

local function startFollowMode(mode)
	activeFollowMode = mode
	attackModeEnabled = false
	activeTeleportPartsCache = {}

	local function getPlayerRoot()
		local character = LocalPlayer.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	if mode == "behind" then
		followConnection = RunService.RenderStepped:Connect(function()
			local root = getPlayerRoot()
			if not root then return end
			local lookVector = root.CFrame.LookVector
			local rightVector = root.CFrame.RightVector
			local index = 0
			for _, model in ipairs(selectedNPCs) do
				if model and model.Parent and model ~= LocalPlayer.Character then
					local hum = getHumanoid(model)
					if hum and hum.Health > 0 then
						index = index + 1
						local side = (index % 2 == 1) and -1 or 1
						local depth = math.floor((index - 1) / 2) * 4 + 4
						local offset = (rightVector * (side * 3)) - (lookVector * depth)
						smartMoveTo(model, root.Position + offset)
					end
				end
			end
		end)
	elseif mode == "ontop" then
		followConnection = RunService.RenderStepped:Connect(function()
			local root = getPlayerRoot()
			if not root then return end
			for _, model in ipairs(selectedNPCs) do
				if model and model.Parent and model ~= LocalPlayer.Character then
					local hum = getHumanoid(model)
					if hum and hum.Health > 0 then
						local targetPos = root.Position + Vector3.new(0, 3, 0)
						local npcRoot = getRoot(model)
						if npcRoot and npcRoot.Position.Y < targetPos.Y - 0.5 and hum.FloorMaterial ~= Enum.Material.Air then
							hum.Jump = true
						end
						hum:MoveTo(targetPos)
					end
				end
			end
		end)
	else
		startTeleportMode(mode, getPlayerRoot)
	end
end

local function startAttackMode()
	attackModeEnabled = true
	activeFollowMode = nil

	attackConnection = RunService.RenderStepped:Connect(function()
		for _, attackerModel in ipairs(selectedNPCs) do
			if attackerModel and attackerModel.Parent then
				local attackerHumanoid = getHumanoid(attackerModel)
				if attackerHumanoid and attackerHumanoid.Health > 0 then
					local attackerRoot = getRoot(attackerModel)
					if attackerRoot then
						local nearestEnemy = nil
						local nearestDist = math.huge
						for _, entry in ipairs(npcEntries) do
							local targetModel = entry.model
							if targetModel ~= attackerModel and targetModel.Parent and not isSelected(targetModel) and targetModel ~= LocalPlayer.Character and isControllableNPC(targetModel) then
								local targetHumanoid = getHumanoid(targetModel)
								if targetHumanoid and targetHumanoid.Health > 0 then
									local targetRoot = getRoot(targetModel)
									if targetRoot then
										local dist = (targetRoot.Position - attackerRoot.Position).Magnitude
										if dist < nearestDist then
											nearestDist = dist
											nearestEnemy = targetModel
										end
									end
								end
							end
						end

						if nearestEnemy then
							local targetHumanoid = getHumanoid(nearestEnemy)
							local targetRoot = getRoot(nearestEnemy)
							if targetHumanoid and targetRoot then
								local formationIndex = 1
								for i, m in ipairs(selectedNPCs) do
									if m == attackerModel then formationIndex = i; break end
								end
								local totalAttackers = #selectedNPCs
								local angle = (formationIndex - 1) * (2 * math.pi / totalAttackers)
								local offset = Vector3.new(math.cos(angle) * 2.5, 0, math.sin(angle) * 2.5)
								smartMoveTo(attackerModel, targetRoot.Position + offset)

								if (targetRoot.Position - attackerRoot.Position).Magnitude <= 5 then
									local lastAttack = attackerModel:GetAttribute("LastAttack")
									if not lastAttack or os.clock() - lastAttack > 1 then
										targetHumanoid:TakeDamage(getRandomDamage())
										attackerModel:SetAttribute("LastAttack", os.clock())
										if attackerHumanoid.FloorMaterial ~= Enum.Material.Air then
											attackerHumanoid.Jump = true
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

local function updatePatrolCount()
	if patrolCountLabel then
		patrolCountLabel.Text = "Waypoints: " .. #patrolPoints
	end
end

local function addWaypoint(position)
	table.insert(patrolPoints, position)

	local marker = Instance.new("Part")
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Shape = Enum.PartType.Ball
	marker.Material = Enum.Material.Neon
	marker.Color = C.BLUE
	marker.Size = Vector3.new(1.2, 1.2, 1.2)
	marker.Position = position + Vector3.new(0, 1, 0)
	marker.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(30, 20)
	gui.StudsOffset = Vector3.new(0, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = marker

	local number = Instance.new("TextLabel")
	number.BackgroundTransparency = 1
	number.Size = UDim2.new(1, 0, 1, 0)
	number.Text = tostring(#patrolPoints)
	number.TextColor3 = Color3.fromRGB(255, 255, 255)
	number.Font = C.FONT
	number.TextSize = 14
	number.Parent = gui

	table.insert(patrolMarkers, marker)
	updatePatrolCount()
end

local function clearWaypoints()
	for _, marker in ipairs(patrolMarkers) do
		if marker and marker.Parent then marker:Destroy() end
	end
	patrolPoints = {}
	patrolMarkers = {}
	patrolState = setmetatable({}, weakKeys)
	updatePatrolCount()
end

local function stopPatrol()
	if patrolConnection then
		patrolConnection:Disconnect()
		patrolConnection = nil
	end
	for model, _ in pairs(patrolState) do
		local humanoid = getHumanoid(model)
		local root = getRoot(model)
		if humanoid and root and model.Parent then
			pcall(function() humanoid:MoveTo(root.Position) end)
		end
	end
	patrolState = setmetatable({}, weakKeys)
end

local function startPatrol()
	patrolState = setmetatable({}, weakKeys)
	patrolConnection = RunService.Heartbeat:Connect(function()
		if #patrolPoints == 0 then return end
		local now = os.clock()
		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= LocalPlayer.Character and not frozenState[model] then
				local humanoid = getHumanoid(model)
				local root = getRoot(model)
				if humanoid and root and humanoid.Health > 0 and not humanoid.Sit then
					local st = patrolState[model]
					if not st then
						local nearestIndex = 1
						local nearestDist = math.huge
						for i, point in ipairs(patrolPoints) do
							local dist = (point - root.Position).Magnitude
							if dist < nearestDist then
								nearestIndex = i
								nearestDist = dist
							end
						end
						st = { index = nearestIndex, waitUntil = 0, deadline = nil }
						patrolState[model] = st
					end
					if st.index > #patrolPoints then st.index = 1 end

					if now >= st.waitUntil then
						local target = patrolPoints[st.index]
						local dx = target.X - root.Position.X
						local dz = target.Z - root.Position.Z
						st.deadline = st.deadline or (now + 20)
						if math.sqrt(dx * dx + dz * dz) < 3 or now > st.deadline then
							st.index = st.index % #patrolPoints + 1
							st.waitUntil = now + 1
							st.deadline = nil
							pcall(function() humanoid:MoveTo(root.Position) end)
						else
							smartMoveTo(model, target)
						end
					end
				end
			end
		end
	end)
end

local function startFollowPlayer()
	activeFollowMode = "followplayer"
	attackModeEnabled = false
	followConnection = RunService.RenderStepped:Connect(function()
		local target = followTargetPlayer
		local character = target and target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local lookVector = root.CFrame.LookVector
		local rightVector = root.CFrame.RightVector
		local index = 0
		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= character and model ~= LocalPlayer.Character then
				local hum = getHumanoid(model)
				if hum and hum.Health > 0 then
					index = index + 1
					local side = (index % 2 == 1) and -1 or 1
					local depth = math.floor((index - 1) / 2) * 4 + 4
					local offset = (rightVector * (side * 3)) - (lookVector * depth)
					smartMoveTo(model, root.Position + offset)
				end
			end
		end
	end)
end

local function sitModelOnSeat(model, seat)
	local humanoid = getHumanoid(model)
	if not humanoid then return end
	local startedAt = os.clock()
	while os.clock() - startedAt < 15 do
		local root = getRoot(model)
		if not model.Parent or not root or humanoid.Health <= 0 or not seat.Parent then return end
		if (root.Position - seat.Position).Magnitude < 5 then break end
		smartMoveTo(model, seat.Position)
		task.wait(0.1)
	end

	local root = getRoot(model)
	if not root or not model.Parent or not seat.Parent or seat.Occupant ~= nil then return end
	pcall(function() seat:Sit(humanoid) end)
	task.wait(0.3)
	if humanoid.SeatPart ~= seat and root.Parent then
		root.CFrame = seat.CFrame * CFrame.new(0, 2, 0)
	end
end

local function sitSelectedOnSeats()
	local candidates = {}
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if (obj:IsA("Seat") or obj:IsA("VehicleSeat")) and not obj.Disabled and obj.Occupant == nil then
			table.insert(candidates, obj)
		end
	end

	local claimed = {}
	local sent = 0
	for _, model in ipairs(selectedNPCs) do
		local humanoid = getHumanoid(model)
		local root = getRoot(model)
		if model.Parent and model ~= LocalPlayer.Character and humanoid and root and humanoid.Health > 0 and not frozenState[model] then
			local bestSeat = nil
			local bestDist = 150
			for _, seat in ipairs(candidates) do
				if not claimed[seat] then
					local dist = (seat.Position - root.Position).Magnitude
					if dist < bestDist then
						bestSeat = seat
						bestDist = dist
					end
				end
			end
			if bestSeat then
				claimed[bestSeat] = true
				sent = sent + 1
				task.spawn(sitModelOnSeat, model, bestSeat)
			end
		end
	end
	return sent
end

local function setBehavior(mode, enabled)
	stopAllConnections()
	stopWander()
	stopClickMove()
	stopPatrol()

	for name, api in pairs(behaviorToggles) do
		if name ~= mode or not enabled then
			api:Set(false, true)
		end
	end
	if not enabled then return end

	if mode == "attack" then
		startAttackMode()
	elseif mode == "wander" then
		startWander()
	elseif mode == "clickmove" then
		startClickMove()
	elseif mode == "patrol" then
		startPatrol()
	elseif mode == "followplayer" then
		startFollowPlayer()
	else
		startFollowMode(mode)
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DuaKNoPanel"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = PlayerGui

local gearButton = Instance.new("ImageButton")
gearButton.Name = "GearIcon"
gearButton.AnchorPoint = Vector2.new(0.5, 0.5)
gearButton.Size = UDim2.new(0, 42, 0, 42)
gearButton.Position = UDim2.new(0.94, -48, 0.1, 0)
gearButton.BackgroundColor3 = C.DARK2
gearButton.BackgroundTransparency = 0.05
gearButton.AutoButtonColor = false
gearButton.Image = "rbxthumb://type=Asset&id=7059346386&w=150&h=150"
gearButton.ScaleType = Enum.ScaleType.Fit
gearButton.ZIndex = 10
gearButton.Parent = screenGui

local gearCorner = Instance.new("UICorner")
gearCorner.CornerRadius = UDim.new(0, 8)
gearCorner.Parent = gearButton

local gearStroke = Instance.new("UIStroke")
gearStroke.Name = "ActiveGlow"
gearStroke.Color = C.STROKE
gearStroke.Transparency = 0
gearStroke.Thickness = 1
gearStroke.Parent = gearButton

local mainFrame = Instance.new("Frame")
mainFrame.Name = "SpawnerPanel"
mainFrame.Size = UDim2.new(0, 500, 0, 400)
mainFrame.Position = UDim2.new(1, -520, 0, 64)
mainFrame.BackgroundColor3 = C.DARK
mainFrame.BackgroundTransparency = 0.03
mainFrame.ClipsDescendants = true
mainFrame.Visible = false
mainFrame.ZIndex = 20
mainFrame.Parent = screenGui

local topBar
local closeButton
local tabBar
local body
local leftHost
local rightPane
local pages = {}
local tabButtons = {}
local TAB_NAMES = {"SPAWN", "CONTROL", "BEHAVIOR", "EDIT", "OUTFITS", "SETTINGS"}

;(function()
	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 6)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = C.STROKE
	mainStroke.Thickness = 1
	mainStroke.Transparency = 0
	mainStroke.Parent = mainFrame

	topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 34)
	topBar.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
	topBar.BorderSizePixel = 0
	topBar.ZIndex = 21
	topBar.Parent = mainFrame

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 6)
	topCorner.Parent = topBar

	local topMask = Instance.new("Frame")
	topMask.Size = UDim2.new(1, 0, 0, 10)
	topMask.Position = UDim2.new(0, 0, 1, -10)
	topMask.BackgroundColor3 = topBar.BackgroundColor3
	topMask.BorderSizePixel = 0
	topMask.ZIndex = 21
	topMask.Parent = topBar

	local topLine = Instance.new("Frame")
	topLine.Size = UDim2.new(1, 0, 0, 2)
	topLine.Position = UDim2.new(0, 0, 1, -2)
	topLine.BackgroundColor3 = C.BLUE
	topLine.BorderSizePixel = 0
	topLine.ZIndex = 22
	topLine.Parent = topBar

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0, 140, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Text = "NPC MANAGER"
	title.TextColor3 = C.TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = C.BOLD_FONT
	title.TextSize = 14
	title.ZIndex = 22
	title.Parent = topBar

	local credit = Instance.new("TextLabel")
	credit.BackgroundTransparency = 1
	credit.Size = UDim2.new(0, 120, 1, 0)
	credit.Position = UDim2.new(0, 160, 0, 0)
	credit.Text = "by DuaKNo"
	credit.TextColor3 = C.LIGHTBLUE
	credit.TextXAlignment = Enum.TextXAlignment.Left
	credit.Font = C.FONT
	credit.TextSize = 11
	credit.ZIndex = 22
	credit.Parent = topBar

	closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 24, 0, 22)
	closeButton.Position = UDim2.new(1, -30, 0.5, -11)
	closeButton.BackgroundColor3 = C.KILL_RED
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Font = C.BOLD_FONT
	closeButton.TextSize = 12
	closeButton.AutoButtonColor = false
	closeButton.ZIndex = 23
	closeButton.Parent = topBar
	styleButton(closeButton, Color3.fromRGB(110, 20, 28))

	tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, -20, 0, 24)
	tabBar.Position = UDim2.new(0, 10, 0, 40)
	tabBar.BackgroundTransparency = 1
	tabBar.ZIndex = 21
	tabBar.Parent = mainFrame

	body = Instance.new("Frame")
	body.Size = UDim2.new(1, -20, 1, -116)
	body.Position = UDim2.new(0, 10, 0, 70)
	body.BackgroundTransparency = 1
	body.ZIndex = 21
	body.Parent = mainFrame

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.Padding = UDim.new(0, 10)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	leftHost = Instance.new("Frame")
	leftHost.Size = UDim2.new(0.52, 0, 1, 0)
	leftHost.BackgroundTransparency = 1
	leftHost.LayoutOrder = 1
	leftHost.ZIndex = 21
	leftHost.Parent = body

	rightPane = Instance.new("Frame")
	rightPane.Size = UDim2.new(0.48, -10, 1, 0)
	rightPane.BackgroundTransparency = 1
	rightPane.LayoutOrder = 2
	rightPane.Parent = body

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 5)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Parent = rightPane

	for _, name in ipairs(TAB_NAMES) do
		local page = Instance.new("ScrollingFrame")
		page.Name = name
		page.Size = UDim2.new(1, 0, 1, 0)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 2
		page.ScrollBarImageColor3 = C.BLUE
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.ZIndex = 21
		page.Visible = false
		page.Parent = leftHost

		local pagePadding = Instance.new("UIPadding")
		pagePadding.PaddingRight = UDim.new(0, 6)
		pagePadding.Parent = page

		local pageLayout = Instance.new("UIListLayout")
		pageLayout.Padding = UDim.new(0, 6)
		pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
		pageLayout.Parent = page

		pages[name] = page
	end
end)()

local function selectTab(name)
	for pageName, page in pairs(pages) do
		page.Visible = (pageName == name)
	end
	for tabName, button in pairs(tabButtons) do
		local active = (tabName == name)
		button.BackgroundColor3 = active and C.BLUE or C.GRAY3
		button.TextColor3 = active and Color3.fromRGB(255, 255, 255) or C.TEXT
	end
end

;(function()
	for i, name in ipairs(TAB_NAMES) do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1 / #TAB_NAMES, -4, 1, 0)
		button.Position = UDim2.new((i - 1) / #TAB_NAMES, 2, 0, 0)
		button.BackgroundColor3 = C.GRAY3
		button.Text = name
		button.TextColor3 = C.TEXT
		button.Font = C.BOLD_FONT
		button.TextSize = 10
		button.AutoButtonColor = false
		button.ZIndex = 22
		button.Parent = tabBar
		styleButton(button, C.STROKE, false)
		button.MouseButton1Click:Connect(function() selectTab(name) end)
		tabButtons[name] = button
	end
end)()

local searchBox
local removeAllButton
local selectAllButton
local multiSelectButton
local listFrame

;(function()
	local listTitle = Instance.new("TextLabel")
	listTitle.BackgroundTransparency = 1
	listTitle.Size = UDim2.new(1, 0, 0, 14)
	listTitle.Text = "NPC LIST"
	listTitle.TextColor3 = C.LIGHTBLUE
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.Font = C.BOLD_FONT
	listTitle.TextSize = 11
	listTitle.LayoutOrder = 1
	listTitle.ZIndex = 22
	listTitle.Parent = rightPane

	local searchRow = Instance.new("Frame")
	searchRow.Size = UDim2.new(1, 0, 0, 50)
	searchRow.BackgroundTransparency = 1
	searchRow.LayoutOrder = 2
	searchRow.ZIndex = 22
	searchRow.Parent = rightPane

	searchBox = Instance.new("TextBox")
	searchBox.Size = UDim2.new(1, 0, 0, 22)
	searchBox.Position = UDim2.new(0, 0, 0, 0)
	searchBox.BackgroundColor3 = C.DARK2
	searchBox.PlaceholderText = "Search NPC..."
	searchBox.PlaceholderColor3 = C.SUBTEXT
	searchBox.Text = ""
	searchBox.TextColor3 = C.TEXT
	searchBox.Font = C.FONT
	searchBox.TextSize = 11
	searchBox.ClearTextOnFocus = false
	searchBox.ZIndex = 22
	searchBox.Parent = searchRow
	local searchStroke = styleButton(searchBox, C.STROKE, false)
	searchBox.Focused:Connect(function() searchStroke.Color = C.BLUE end)
	searchBox.FocusLost:Connect(function() searchStroke.Color = C.STROKE end)

	local buttonRow = Instance.new("Frame")
	buttonRow.Size = UDim2.new(1, 0, 0, 22)
	buttonRow.Position = UDim2.new(0, 0, 0, 26)
	buttonRow.BackgroundTransparency = 1
	buttonRow.ZIndex = 22
	buttonRow.Parent = searchRow

	removeAllButton = Instance.new("TextButton")
	removeAllButton.Size = UDim2.new(1/3, -3, 1, 0)
	removeAllButton.Position = UDim2.new(0, 0, 0, 0)
	removeAllButton.BackgroundColor3 = C.YELLOW
	removeAllButton.Text = "Remove All"
	removeAllButton.TextColor3 = Color3.fromRGB(45, 30, 0)
	removeAllButton.Font = C.BOLD_FONT
	removeAllButton.TextSize = 10
	removeAllButton.AutoButtonColor = false
	removeAllButton.ZIndex = 23
	removeAllButton.Parent = buttonRow
	styleButton(removeAllButton, Color3.fromRGB(140, 118, 20))

	selectAllButton = Instance.new("TextButton")
	selectAllButton.Size = UDim2.new(1/3, -3, 1, 0)
	selectAllButton.Position = UDim2.new(1/3, 1, 0, 0)
	selectAllButton.BackgroundColor3 = C.GRAY3
	selectAllButton.Text = "Select All"
	selectAllButton.TextColor3 = C.TEXT
	selectAllButton.Font = C.FONT
	selectAllButton.TextSize = 10
	selectAllButton.AutoButtonColor = false
	selectAllButton.ZIndex = 23
	selectAllButton.Parent = buttonRow
	styleButton(selectAllButton)

	multiSelectButton = Instance.new("TextButton")
	multiSelectButton.Size = UDim2.new(1/3, -3, 1, 0)
	multiSelectButton.Position = UDim2.new(2/3, 2, 0, 0)
	multiSelectButton.BackgroundColor3 = C.GRAY3
	multiSelectButton.Text = "Multi"
	multiSelectButton.TextColor3 = C.TEXT
	multiSelectButton.Font = C.FONT
	multiSelectButton.TextSize = 10
	multiSelectButton.AutoButtonColor = false
	multiSelectButton.ZIndex = 23
	multiSelectButton.Parent = buttonRow
	styleButton(multiSelectButton, C.STROKE, false)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Size = UDim2.new(1, 0, 1, -108)
	listFrame.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
	listFrame.BackgroundTransparency = 0
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 3
	listFrame.ScrollBarImageColor3 = C.BLUE
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.LayoutOrder = 3
	listFrame.ZIndex = 22
	listFrame.Parent = rightPane

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 4)
	listCorner.Parent = listFrame

	local listStroke = Instance.new("UIStroke")
	listStroke.Color = C.STROKE
	listStroke.Thickness = 1
	listStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	listStroke.Parent = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = listFrame

	infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, 0, 0, 28)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = ""
	infoLabel.TextColor3 = C.SUBTEXT
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextYAlignment = Enum.TextYAlignment.Top
	infoLabel.TextWrapped = true
	infoLabel.Font = C.FONT
	infoLabel.TextSize = 10
	infoLabel.LayoutOrder = 4
	infoLabel.ZIndex = 22
	infoLabel.Parent = rightPane
end)()

local function refreshSearch()
	local query = string.lower(searchBox.Text)
	for _, entry in ipairs(npcEntries) do
		if entry.listRow and entry.listRow.Parent then
			local name = string.lower(entry.model.Name)
			entry.listRow.Visible = query == "" or string.find(name, query, 1, true) ~= nil
		end
	end
end

searchBox:GetPropertyChangedSignal("Text"):Connect(refreshSearch)

function refreshHighlight()
	for _, entry in ipairs(npcEntries) do
		if entry.listRow and entry.listRow.Parent then
			entry.listRow.BackgroundColor3 = isSelected(entry.model) and C.RED or C.DARK2
		end
	end
end

function updateHighlights()
	for model, hl in pairs(highlights) do
		if not isSelected(model) then
			hl:Destroy()
			highlights[model] = nil
		end
	end
	for _, model in ipairs(selectedNPCs) do
		if not highlights[model] then
			local hl = Instance.new("Highlight")
			hl.Name = "SelectionHighlight"
			hl.FillTransparency = 1
			hl.OutlineColor = C.GREEN
			hl.OutlineTransparency = 0
			hl.Adornee = model
			hl.Parent = model
			highlights[model] = hl
		end
	end
end

local function addNPC(model, spawned)
	if not model or not model.Parent then return end
	if findEntry(model) then return end

	local isPlayerEntry = (Players:GetPlayerFromCharacter(model) ~= nil)
	if not spawned and not isSelectableNPC(model) and not isPlayerEntry then return end

	if not spawned then ensureAnimations(model) end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundColor3 = C.DARK2
	row.BackgroundTransparency = 0
	row.BorderSizePixel = 0
	row.ZIndex = 23
	row.Parent = listFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = row

	local entry = { model = model, listRow = row, ownSpawn = spawned == true, isPlayer = isPlayerEntry }
	table.insert(npcEntries, entry)

	local selectButton = Instance.new("TextButton")
	selectButton.Size = UDim2.new(1, -72, 1, -4)
	selectButton.Position = UDim2.new(0, 4, 0, 0)
	selectButton.BackgroundTransparency = 1
	selectButton.Text = model.Name
	selectButton.TextColor3 = C.TEXT
	selectButton.TextXAlignment = Enum.TextXAlignment.Left
	selectButton.TextTruncate = Enum.TextTruncate.AtEnd
	selectButton.Font = C.FONT
	selectButton.TextSize = 10
	selectButton.AutoButtonColor = false
	selectButton.ZIndex = 24
	selectButton.Parent = row

	local distLabel = Instance.new("TextLabel")
	distLabel.Size = UDim2.new(0, 40, 1, -4)
	distLabel.Position = UDim2.new(1, -70, 0, 0)
	distLabel.BackgroundTransparency = 1
	distLabel.Text = ""
	distLabel.TextColor3 = C.SUBTEXT
	distLabel.TextXAlignment = Enum.TextXAlignment.Right
	distLabel.Font = C.FONT
	distLabel.TextSize = 9
	distLabel.ZIndex = 24
	distLabel.Parent = row

	local hpBack = Instance.new("Frame")
	hpBack.Size = UDim2.new(1, -34, 0, 2)
	hpBack.Position = UDim2.new(0, 4, 1, -4)
	hpBack.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
	hpBack.BorderSizePixel = 0
	hpBack.ZIndex = 24
	hpBack.Parent = row

	local hpFill = Instance.new("Frame")
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	hpFill.BorderSizePixel = 0
	hpFill.ZIndex = 25
	hpFill.Parent = hpBack

	entry.hpFill = hpFill
	entry.distLabel = distLabel

	selectButton.MouseButton1Click:Connect(function()
		if not model.Parent then return end
		if entry.isPlayer then return end
		local humanoid = getHumanoid(model)
		if not humanoid or humanoid.Health <= 0 then return end
		if multiSelectEnabled then
			if isSelected(model) then removeSelected(model) else addSelected(model) end
		else
			clearSelection()
			addSelected(model)
		end
		if controlToggle then controlToggle:SetEnabled(#selectedNPCs > 0) end
	end)

	if entry.ownSpawn then

		local deleteButton = Instance.new("TextButton")
		deleteButton.Size = UDim2.new(0, 22, 0, 20)
		deleteButton.Position = UDim2.new(1, -26, 0.5, -10)
		deleteButton.BackgroundColor3 = C.KILL_RED
		deleteButton.Text = "X"
		deleteButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		deleteButton.Font = C.BOLD_FONT
		deleteButton.TextSize = 10
		deleteButton.AutoButtonColor = false
		deleteButton.ZIndex = 25
		deleteButton.Parent = row

		local deleteCorner = Instance.new("UICorner")
		deleteCorner.CornerRadius = UDim.new(0, 3)
		deleteCorner.Parent = deleteButton

		deleteButton.MouseButton1Click:Connect(function()
			removeSelected(model)
			if model and model.Parent then model:Destroy() end
		end)
	else

		local removeButton = Instance.new("TextButton")
		removeButton.Size = UDim2.new(0, 22, 0, 20)
		removeButton.Position = UDim2.new(1, -26, 0.5, -10)
		removeButton.BackgroundColor3 = C.YELLOW
		removeButton.Text = "X"
		removeButton.TextColor3 = Color3.fromRGB(45, 30, 0)
		removeButton.Font = C.BOLD_FONT
		removeButton.TextSize = 10
		removeButton.AutoButtonColor = false
		removeButton.ZIndex = 25
		removeButton.Parent = row

		local removeCorner = Instance.new("UICorner")
		removeCorner.CornerRadius = UDim.new(0, 3)
		removeCorner.Parent = removeButton

		removeButton.MouseButton1Click:Connect(function()
			removeSelected(model)
			unfreezeModel(model)
			for i, entry2 in ipairs(npcEntries) do
				if entry2.model == model then
					table.remove(npcEntries, i)
					break
				end
			end
			for i, m in ipairs(teleportModeNPCs) do
				if m == model then
					table.remove(teleportModeNPCs, i)
					break
				end
			end
			if row.Parent then row:Destroy() end
			if controlToggle then controlToggle:SetEnabled(#selectedNPCs > 0) end
		end)
	end

	local humanoid = getHumanoid(model)
	if humanoid then
		humanoid.Died:Connect(function()
			removeSelected(model)
			for i, entry2 in ipairs(npcEntries) do
				if entry2.model == model then
					table.remove(npcEntries, i)
					break
				end
			end
			if row.Parent then row:Destroy() end
			if entry.ownSpawn and model and model.Parent then
				task.delay(5, function() if model and model.Parent then model:Destroy() end end)
			end
		end)
	end

	model.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		removeSelected(model)
		for i, entry2 in ipairs(npcEntries) do
			if entry2.model == model then table.remove(npcEntries, i); break end
		end
		if row.Parent then row:Destroy() end
	end)

	refreshSearch()
end

multiSelectButton.MouseButton1Click:Connect(function()
	multiSelectEnabled = not multiSelectEnabled
	multiSelectButton.BackgroundColor3 = multiSelectEnabled and C.BLUE or C.GRAY3
	if not multiSelectEnabled and #selectedNPCs > 1 then
		local last = selectedModel
		clearSelection()
		if last then addSelected(last) end
	end
end)

selectAllButton.MouseButton1Click:Connect(function()
	if not multiSelectEnabled then
		multiSelectEnabled = true
		multiSelectButton.BackgroundColor3 = C.BLUE
	end
	for _, entry in ipairs(npcEntries) do
		if not entry.isPlayer then
			local model = entry.model
			if model and model.Parent then
				local humanoid = getHumanoid(model)
				if humanoid and humanoid.Health > 0 then
					if not isSelected(model) then
						addSelected(model)
					end
				end
			end
		end
	end
	if controlToggle then controlToggle:SetEnabled(#selectedNPCs > 0) end
end)

removeAllButton.MouseButton1Click:Connect(function()
	for i = #npcEntries, 1, -1 do
		local entry = npcEntries[i]
		local model = entry.model
		removeSelected(model)
		unfreezeModel(model)
		for j, m in ipairs(teleportModeNPCs) do
			if m == model then
				table.remove(teleportModeNPCs, j)
				break
			end
		end
		if entry.listRow and entry.listRow.Parent then
			entry.listRow:Destroy()
		end
		if entry.ownSpawn and model and model.Parent then
			model:Destroy()
		end
		table.remove(npcEntries, i)
	end
	if controlToggle then controlToggle:SetEnabled(#selectedNPCs > 0) end
end)

local function trim(s)
	return string.match(s or "", "^%s*(.-)%s*$")
end

local function resolveUser(input)
	input = trim(input)
	if input == "" then
		return LocalPlayer.UserId, LocalPlayer.Name
	end
	if string.match(input, "^%d+$") then
		local id = tonumber(input)
		local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
		if ok and name then return id, name end
	end
	local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(input) end)
	if ok and id then return id, input end
	return nil, nil
end

local OUTFIT_FILE = "DuaKNo_NPC_Outfits.json"

local OUTFIT_VALUE_PROPS = {
	"Shirt", "Pants", "GraphicTShirt", "Face", "Head", "Torso",
	"LeftArm", "RightArm", "LeftLeg", "RightLeg",
	"HatAccessory", "HairAccessory", "FaceAccessory", "NeckAccessory",
	"ShouldersAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory",
	"HeightScale", "WidthScale", "HeadScale", "DepthScale", "BodyTypeScale", "ProportionScale",
	"IdleAnimation", "WalkAnimation", "RunAnimation", "JumpAnimation", "FallAnimation",
	"ClimbAnimation", "SwimAnimation",
}
local OUTFIT_COLOR_PROPS = {
	"HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor",
}
local OUTFIT_COLOR_SET = {}
for _, prop in ipairs(OUTFIT_COLOR_PROPS) do OUTFIT_COLOR_SET[prop] = true end
local OUTFIT_ACCESSORY_SET = {
	HatAccessory = true, HairAccessory = true, FaceAccessory = true, NeckAccessory = true,
	ShouldersAccessory = true, FrontAccessory = true, BackAccessory = true, WaistAccessory = true,
}

local canUseFiles = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
local savedOutfits = {}

local function serializeDescription(desc)
	local data = {}
	for _, prop in ipairs(OUTFIT_VALUE_PROPS) do
		local ok, value = pcall(function() return desc[prop] end)
		if ok and (type(value) == "number" or type(value) == "string") then
			data[prop] = value
		end
	end
	for _, prop in ipairs(OUTFIT_COLOR_PROPS) do
		local ok, value = pcall(function() return desc[prop] end)
		if ok and typeof(value) == "Color3" then
			data[prop] = { r = value.R, g = value.G, b = value.B }
		end
	end

	local ok, list = pcall(function() return desc:GetAccessories(true) end)
	if ok and type(list) == "table" then
		local accessories = {}
		for _, item in ipairs(list) do
			pcall(function()
				table.insert(accessories, {
					AssetId = item.AssetId,
					AccessoryType = item.AccessoryType.Name,
					IsLayered = item.IsLayered,
					Order = item.Order,
					Puffiness = item.Puffiness,
				})
			end)
		end
		data.accessories = accessories
	end
	return data
end

local function deserializeDescription(data)
	local desc = Instance.new("HumanoidDescription")
	local hasAccessories = type(data.accessories) == "table"
	for prop, value in pairs(data) do
		if prop ~= "accessories" then
			if OUTFIT_COLOR_SET[prop] then
				if type(value) == "table" then
					pcall(function() desc[prop] = Color3.new(value.r, value.g, value.b) end)
				end
			elseif not (hasAccessories and OUTFIT_ACCESSORY_SET[prop]) then
				pcall(function() desc[prop] = value end)
			end
		end
	end
	if hasAccessories then
		local list = {}
		for _, item in ipairs(data.accessories) do
			local ok, enumItem = pcall(function() return Enum.AccessoryType[item.AccessoryType] end)
			if ok and enumItem then
				table.insert(list, {
					AssetId = item.AssetId,
					AccessoryType = enumItem,
					IsLayered = item.IsLayered or false,
					Order = item.Order,
					Puffiness = item.Puffiness,
				})
			end
		end
		pcall(function() desc:SetAccessories(list, true) end)
	end
	return desc
end

local function persistOutfits()
	if not canUseFiles then return end
	pcall(function()
		writefile(OUTFIT_FILE, HttpService:JSONEncode(savedOutfits))
	end)
end

if canUseFiles then
	pcall(function()
		if isfile(OUTFIT_FILE) then
			local decoded = HttpService:JSONDecode(readfile(OUTFIT_FILE))
			if type(decoded) == "table" then savedOutfits = decoded end
		end
	end)
end

local function fetchDescription(userId)
	for _ = 1, 2 do
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if ok and result then return result end
		task.wait(0.4)
	end
	return nil
end

local function createModelFromDescription(desc, rigType)
	for _ = 1, 2 do
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, rigType)
		end)
		if ok and result then return result end
		task.wait(0.4)
	end
	return nil
end

local function placeModelOnGround(model, aroundPos, ignore, minDist, maxDist)
	local angle = math.random() * math.pi * 2
	local dist = minDist + math.random() * (maxDist - minDist)
	local x = aroundPos.X + math.cos(angle) * dist
	local z = aroundPos.Z + math.sin(angle) * dist

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(x, aroundPos.Y + 5, z), Vector3.new(0, -60, 0), params)
	local groundY = hit and hit.Position.Y or (aroundPos.Y - 3)

	model:PivotTo(CFrame.new(Vector3.new(x, groundY + 5, z), Vector3.new(aroundPos.X, groundY + 5, aroundPos.Z)))

	local lowest = math.huge
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local bottom = part.Position.Y - part.Size.Y / 2
			if bottom < lowest then lowest = bottom end
		end
	end
	if lowest == math.huge then
		local boxCF, boxSize = model:GetBoundingBox()
		lowest = boxCF.Position.Y - boxSize.Y / 2
	end
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - lowest + 0.1, 0))
end

local function collectIgnoreList()
	local ignore = {}
	local character = LocalPlayer.Character
	if character then table.insert(ignore, character) end
	local real = getRealCharacter()
	if real and real ~= character then table.insert(ignore, real) end
	for _, entry in ipairs(npcEntries) do
		if entry.model then table.insert(ignore, entry.model) end
	end
	return ignore
end

local function showRobloxHealthBar(humanoid)
	pcall(function()
		if healthBarsEnabled then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
			humanoid.NameDisplayDistance = 100
			humanoid.HealthDisplayDistance = 100
		else
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end)
end

local function doSpawn(input, outfit)
	local character = LocalPlayer.Character
	local root = character and getRoot(character)
	if not root then return false, "No character to spawn near" end

	local rigType = resolveRigType()
	local desc, userId, displayName
	if outfit then
		desc = deserializeDescription(outfit.data)
		displayName = outfit.name
	else
		local resolvedName
		userId, resolvedName = resolveUser(input)
		if not userId then return false, "User not found" end
		displayName = resolvedName
		desc = fetchDescription(userId)
		if not desc then return false, "Couldn't load that avatar" end
	end

	local model = createModelFromDescription(desc, rigType)
	if not model then return false, "Couldn't build that avatar" end

	local humanoid = getHumanoid(model)
	if not humanoid then
		model:Destroy()
		return false, "Bad avatar model"
	end

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Script") or obj:IsA("LocalScript") then
			obj:Destroy()
		elseif obj:IsA("BasePart") and obj.Anchored then

			obj.Anchored = false
		end
	end

	npcCount = npcCount + 1
	model.Name = displayName .. " " .. npcCount
	model:SetAttribute(NPC_ATTRIBUTE, true)
	local modelRoot = model:FindFirstChild("HumanoidRootPart")
	if modelRoot then model.PrimaryPart = modelRoot end
	model.Archivable = true

	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = npcSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = npcJump
	showRobloxHealthBar(humanoid)

	placeModelOnGround(model, root.Position, collectIgnoreList(), 4, 8)
	model.Parent = Workspace

	addNPC(model, true)

	local set = buildAnimSet(humanoid.RigType, userId ~= nil and userId == LocalPlayer.UserId, desc)
	pcall(function() attachAnimations(model, set) end)
	model:SetAttribute("DuaKNoAnimationsAttached", true)

	local rigName = (humanoid.RigType == Enum.HumanoidRigType.R6) and "R6" or "R15"
	return true, "Spawned " .. model.Name .. " (" .. rigName .. ")"
end

local function runSpawn(input, onStatus, outfit)
	if spawning then return end
	spawning = true
	onStatus("Spawning...", false)
	local ok, success, message = pcall(doSpawn, input, outfit)
	spawning = false
	if not ok then
		onStatus("Error: " .. tostring(success), true)
	elseif success then
		onStatus(message, false)
	else
		onStatus(message, true)
	end
end

local function cloneSelectedNPC()
	if #selectedNPCs == 0 then return end
	local original = selectedModel or selectedNPCs[1]
	if not original or not original.Parent then return end
	if not original.Archivable then return end

	local clone = original:Clone()
	if not clone then return end

	for _, child in ipairs(clone:GetDescendants()) do
		if child.Name == "SelectionHighlight" then child:Destroy() end
		if child:IsA("Script") or child:IsA("LocalScript") then child:Destroy() end
	end

	if frozenState[original] then
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then part.Anchored = false end
		end
	end
	clone:SetAttribute("DuaKNoFrozen", nil)

	local baseName = string.gsub(original.Name, " Clone%d*$", "")
	clone.Name = baseName .. " Clone"
	clone:SetAttribute(NPC_ATTRIBUTE, true)
	clone:SetAttribute("DuaKNoAnimationsAttached", nil)

	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	if cloneRoot then clone.PrimaryPart = cloneRoot end

	local originalRoot = getRoot(original)
	if originalRoot then
		placeModelOnGround(clone, originalRoot.Position, collectIgnoreList(), 3, 5)
	else
		clone:PivotTo(original:GetPivot() + Vector3.new(2, 0, 0))
	end
	clone.Parent = Workspace

	local cloneHumanoid = getHumanoid(clone)
	if cloneHumanoid then
		cloneHumanoid.MaxHealth = 100
		cloneHumanoid.Health = 100
		cloneHumanoid.WalkSpeed = npcSpeed
		showRobloxHealthBar(cloneHumanoid)
	end

	addNPC(clone, true)
	pcall(function()
		local set = animSets[original]
		if not set and cloneHumanoid then
			set = buildAnimSet(cloneHumanoid.RigType, false, nil)
		end
		attachAnimations(clone, set)
		clone:SetAttribute("DuaKNoAnimationsAttached", true)
	end)
end

local function scanForNPCs()
	local added = 0
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Model") and obj:FindFirstChild("HumanoidRootPart") then
			if not findEntry(obj) then
				local isPlayerChar = Players:GetPlayerFromCharacter(obj) ~= nil
				if not isPlayerChar then
					addNPC(obj, false)
					added = added + 1
				end
			end
		end
	end
	return added
end

local buildPage = nil
local layoutCounter = 0

local function adopt(obj)
	layoutCounter = layoutCounter + 1
	obj.LayoutOrder = layoutCounter
	obj.Parent = buildPage
end

local function createLabel(text)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Text = text
	label.TextColor3 = C.SUBTEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = C.FONT
	label.TextSize = 10
	label.ZIndex = 22
	adopt(label)
	return label
end

local function createButton(text, bg, textColor, strokeColor)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 30)
	button.BackgroundColor3 = bg
	button.Text = text
	button.TextColor3 = textColor or C.TEXT
	button.Font = C.BOLD_FONT
	button.TextSize = 12
	button.AutoButtonColor = false
	button.ZIndex = 22
	adopt(button)
	styleButton(button, strokeColor)
	return button
end

local function createToggle(text, callback, config)
	config = config or {}
	local trackWidth = config.trackWidth or 46
	local trackHeight = config.trackHeight or 22
	local trackColor = config.trackColor or C.GRAY3
	local onColor = config.onColor or C.BLUE
	local knobSize = config.knobSize or 18

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	adopt(row)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -trackWidth - 10, 1, 0)
	label.Text = text
	label.TextColor3 = C.TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = C.FONT
	label.TextSize = 11
	label.ZIndex = 22
	label.Parent = row

	local track = Instance.new("TextButton")
	track.Name = "ToggleTrack"
	track.Size = UDim2.new(0, trackWidth, 0, trackHeight)
	track.Position = UDim2.new(1, -trackWidth, 0.5, -trackHeight / 2)
	track.BackgroundColor3 = trackColor
	track.Text = ""
	track.AutoButtonColor = false
	track.ZIndex = 23
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = C.STROKE
	trackStroke.Thickness = 1
	trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackStroke.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "ToggleKnob"
	knob.Size = UDim2.new(0, knobSize, 0, knobSize)
	knob.Position = UDim2.new(0, 2, 0.5, -knobSize / 2)
	knob.BackgroundColor3 = Color3.fromRGB(210, 214, 222)
	knob.ZIndex = 24
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0, 3)
	knobCorner.Parent = knob

	local state = false
	local api = {}

	local function refresh()
		if state then
			knob.Position = UDim2.new(1, -knobSize - 2, 0.5, -knobSize / 2)
			track.BackgroundColor3 = onColor
		else
			knob.Position = UDim2.new(0, 2, 0.5, -knobSize / 2)
			track.BackgroundColor3 = trackColor
		end
	end

	track.MouseButton1Click:Connect(function()
		state = not state
		refresh()
		if callback then callback(state) end
	end)

	function api:Get() return state end
	function api:Set(value, silent)
		state = value
		refresh()
		if callback and not silent then callback(state) end
	end
	function api:SetEnabled(enabled)
		track.Active = enabled
		label.TextTransparency = enabled and 0 or 0.45
		track.BackgroundTransparency = enabled and 0 or 0.35
	end
	refresh()
	return api, row
end

local function createSubmenuToggle(text, callback)
	return createToggle(text, callback, {
		trackWidth = 32,
		trackHeight = 18,
		trackColor = C.GRAY3,
		onColor = C.BLUE,
		knobSize = 14
	})
end

local function makeStepper(parent, initialText, placeholder)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 22)
	row.Position = UDim2.new(0, 0, 0, 14)
	row.BackgroundTransparency = 1
	row.ZIndex = 22
	row.Parent = parent

	local minus = Instance.new("TextButton")
	minus.Size = UDim2.new(0, 22, 0, 20)
	minus.Position = UDim2.new(0, 0, 0, 1)
	minus.BackgroundColor3 = C.GRAY3
	minus.Text = "-"
	minus.TextColor3 = C.TEXT
	minus.Font = C.FONT
	minus.TextSize = 14
	minus.AutoButtonColor = false
	minus.ZIndex = 23
	minus.Parent = row
	styleButton(minus)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 56, 0, 20)
	box.Position = UDim2.new(0, 26, 0, 1)
	box.BackgroundColor3 = C.DARK2
	box.Text = initialText
	box.TextColor3 = C.LIGHTBLUE
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.SUBTEXT
	box.Font = C.FONT
	box.TextSize = 11
	box.ClearTextOnFocus = false
	box.ZIndex = 23
	box.Parent = row
	styleButton(box, C.STROKE, false)

	local plus = Instance.new("TextButton")
	plus.Size = UDim2.new(0, 22, 0, 20)
	plus.Position = UDim2.new(0, 86, 0, 1)
	plus.BackgroundColor3 = C.GRAY3
	plus.Text = "+"
	plus.TextColor3 = C.TEXT
	plus.Font = C.FONT
	plus.TextSize = 14
	plus.AutoButtonColor = false
	plus.ZIndex = 23
	plus.Parent = row
	styleButton(plus)

	return minus, box, plus
end

local function createTitledFrame(titleText, height)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 22
	adopt(frame)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 12)
	label.Text = titleText
	label.TextColor3 = C.TEXT
	label.Font = C.FONT
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 22
	label.Parent = frame
	return frame
end

;(function()
	buildPage = pages.SPAWN

	createLabel("AVATAR USERNAME (BLANK = YOU)")

	local usernameBox = Instance.new("TextBox")
	usernameBox.Size = UDim2.new(1, 0, 0, 26)
	usernameBox.BackgroundColor3 = C.DARK2
	usernameBox.PlaceholderText = "Roblox username or UserId"
	usernameBox.PlaceholderColor3 = C.SUBTEXT
	usernameBox.Text = ""
	usernameBox.TextColor3 = C.TEXT
	usernameBox.Font = C.FONT
	usernameBox.TextSize = 11
	usernameBox.ClearTextOnFocus = false
	usernameBox.ZIndex = 22
	adopt(usernameBox)
	local usernameStroke = styleButton(usernameBox, C.STROKE, false)
	usernameBox.Focused:Connect(function() usernameStroke.Color = C.BLUE end)
	usernameBox.FocusLost:Connect(function() usernameStroke.Color = C.STROKE end)

	createLabel("RIG TYPE (AUTO = MATCH YOURS)")

	local rigRow = Instance.new("Frame")
	rigRow.Size = UDim2.new(1, 0, 0, 24)
	rigRow.BackgroundTransparency = 1
	rigRow.ZIndex = 22
	adopt(rigRow)

	local rigButtons = {}
	local rigOptions = {"Auto", "R6", "R15"}
	local function refreshRigButtons()
		for name, button in pairs(rigButtons) do
			local active = (name == rigChoice)
			button.BackgroundColor3 = active and C.BLUE or C.GRAY3
			button.TextColor3 = active and Color3.fromRGB(255, 255, 255) or C.TEXT
		end
	end
	for i, name in ipairs(rigOptions) do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1/3, -4, 1, 0)
		button.Position = UDim2.new((i - 1) / 3, 2, 0, 0)
		button.BackgroundColor3 = C.GRAY3
		button.Text = string.upper(name)
		button.TextColor3 = C.TEXT
		button.Font = C.BOLD_FONT
		button.TextSize = 11
		button.AutoButtonColor = false
		button.ZIndex = 23
		button.Parent = rigRow
		styleButton(button, C.STROKE, false)
		button.MouseButton1Click:Connect(function()
			rigChoice = name
			refreshRigButtons()
		end)
		rigButtons[name] = button
	end
	refreshRigButtons()

	local summonButton = createButton("SPAWN NPC", C.BLUE, Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 85, 180))

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0, 14)
	statusLabel.Text = "Ready"
	statusLabel.TextColor3 = C.SUBTEXT
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.Font = C.FONT
	statusLabel.TextSize = 10
	statusLabel.ZIndex = 22
	adopt(statusLabel)

	local function setStatus(text, isError)
		statusLabel.Text = text
		statusLabel.TextColor3 = isError and Color3.fromRGB(255, 90, 90) or C.LIGHTBLUE
	end

	summonButton.MouseButton1Click:Connect(function()
		if spawning then return end
		local input = usernameBox.Text
		task.spawn(function() runSpawn(input, setStatus) end)
	end)

	local cloneButton = createButton("CLONE SELECTED NPC", C.GRAY3)
	cloneButton.MouseButton1Click:Connect(cloneSelectedNPC)

	local SCAN_TEXT = "SCAN ALL NPCS"
	local scanButton = createButton(SCAN_TEXT, C.GRAY3)
	scanButton.MouseButton1Click:Connect(function()
		local added = scanForNPCs()
		scanButton.Text = "SCANNED " .. added .. " NEW NPC(S)"
		task.delay(2, function()
			if scanButton and scanButton.Parent then
				scanButton.Text = SCAN_TEXT
			end
		end)
	end)
end)()

;(function()
	buildPage = pages.CONTROL

	createToggle("Select Mode", function(value) selectMode = value end)

	controlToggle = createToggle("Control NPC", function(value)
		if not value then

			local character = originalCharacter
			local cameraSubject = originalCameraSubject
			controlEnabled = false

			if character and character.Parent then
				LocalPlayer.Character = character
				local camera = Workspace.CurrentCamera
				if camera then
					if cameraSubject and cameraSubject.Parent then
						camera.CameraSubject = cameraSubject
					else
						local humanoid = getHumanoid(character)
						if humanoid then camera.CameraSubject = humanoid end
					end
					camera.CameraType = originalCameraType or Enum.CameraType.Custom
					UserInputService.MouseBehavior = originalMouseBehavior or Enum.MouseBehavior.Default
				end
			else
				LocalPlayer.CharacterAdded:Wait()
				character = LocalPlayer.Character
				if character then
					LocalPlayer.Character = character
					local camera = Workspace.CurrentCamera
					if camera then
						camera.CameraType = originalCameraType or Enum.CameraType.Custom
						UserInputService.MouseBehavior = originalMouseBehavior or Enum.MouseBehavior.Default
						local humanoid = getHumanoid(character)
						if humanoid then camera.CameraSubject = humanoid end
					end
				end
			end

			originalCharacter = nil
			originalCameraSubject = nil
			originalCameraType = nil
			originalMouseBehavior = nil

			if controlToggle and controlToggle:Get() then
				controlToggle:Set(false, true)
			end
			return
		end

		if #selectedNPCs == 0 then controlToggle:Set(false, true); return end
		local target = selectedModel
		if not target or not target.Parent then controlToggle:Set(false, true); return end
		if not isControllableNPC(target) then controlToggle:Set(false, true); return end
		local humanoid = getHumanoid(target)
		if not humanoid or humanoid.Health <= 0 then controlToggle:Set(false, true); return end

		originalCharacter = LocalPlayer.Character
		local camera = Workspace.CurrentCamera
		if camera then
			originalCameraSubject = camera.CameraSubject
			originalCameraType = camera.CameraType
			originalMouseBehavior = UserInputService.MouseBehavior
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end

		controlEnabled = true
		LocalPlayer.Character = target
	end)
	controlToggle:SetEnabled(false)

	local clickMoveToggle = createToggle("Click to Move", function(value)
		setBehavior("clickmove", value)
	end)
	behaviorToggles.clickmove = clickMoveToggle

	local freezeRow = Instance.new("Frame")
	freezeRow.Size = UDim2.new(1, 0, 0, 30)
	freezeRow.BackgroundTransparency = 1
	freezeRow.ZIndex = 22
	adopt(freezeRow)

	local freezeButton = Instance.new("TextButton")
	freezeButton.Size = UDim2.new(0.5, -3, 1, 0)
	freezeButton.Position = UDim2.new(0, 0, 0, 0)
	freezeButton.BackgroundColor3 = C.BLUE
	freezeButton.Text = "FREEZE"
	freezeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	freezeButton.Font = C.BOLD_FONT
	freezeButton.TextSize = 12
	freezeButton.AutoButtonColor = false
	freezeButton.ZIndex = 23
	freezeButton.Parent = freezeRow
	styleButton(freezeButton, Color3.fromRGB(30, 85, 180))

	local unfreezeButton = Instance.new("TextButton")
	unfreezeButton.Size = UDim2.new(0.5, -3, 1, 0)
	unfreezeButton.Position = UDim2.new(0.5, 3, 0, 0)
	unfreezeButton.BackgroundColor3 = C.GRAY3
	unfreezeButton.Text = "UNFREEZE"
	unfreezeButton.TextColor3 = C.TEXT
	unfreezeButton.Font = C.BOLD_FONT
	unfreezeButton.TextSize = 12
	unfreezeButton.AutoButtonColor = false
	unfreezeButton.ZIndex = 23
	unfreezeButton.Parent = freezeRow
	styleButton(unfreezeButton)

	freezeButton.MouseButton1Click:Connect(function()
		for _, model in ipairs(selectedNPCs) do
			if model ~= LocalPlayer.Character then freezeModel(model) end
		end
	end)
	unfreezeButton.MouseButton1Click:Connect(function()
		for _, model in ipairs(selectedNPCs) do
			unfreezeModel(model)
		end
	end)

	local bringButton = createButton("BRING SELECTED NPC(S)", C.GRAY3)
	bringButton.MouseButton1Click:Connect(function()
		if #selectedNPCs == 0 then return end
		local character = LocalPlayer.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not playerRoot then return end

		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= character then
				local root = getRoot(model)
				if root then
					local offset = Vector3.new(math.random(-6, 6), 3, math.random(-6, 6))
					root.CFrame = CFrame.new(playerRoot.Position + offset)
					local humanoid = getHumanoid(model)
					if humanoid then
						pcall(function()
							humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						end)
					end
				end
			end
		end
	end)

	local tpButton = createButton("TP TO SELECTED NPC(S)", C.BLUE, Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 85, 180))
	tpButton.MouseButton1Click:Connect(function()
		if #selectedNPCs == 0 then return end
		local valid = {}
		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= LocalPlayer.Character then
				local humanoid = getHumanoid(model)
				if humanoid and humanoid.Health > 0 and getRoot(model) then
					table.insert(valid, model)
				end
			end
		end
		if #valid == 0 then return end
		local randomModel = valid[math.random(1, #valid)]
		local character = LocalPlayer.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not playerRoot then return end
		local npcRoot = getRoot(randomModel)
		if not npcRoot then return end
		playerRoot.CFrame = CFrame.new(npcRoot.Position + Vector3.new(0, 3, 0))
	end)

	local killButton = createButton("KILL SELECTED NPC(S)", C.KILL_RED, Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 20, 28))
	killButton.MouseButton1Click:Connect(function()
		for _, model in ipairs(selectedNPCs) do
			local hum = getHumanoid(model)
			if hum and hum.Health > 0 then hum.Health = 0 end
		end
	end)
end)()

;(function()
	buildPage = pages.BEHAVIOR

	local followBehindToggle, followRow = createToggle("Follow (Behind)", function(value)
		setBehavior("behind", value)
	end)
	behaviorToggles.behind = followBehindToggle

	local followContainer = Instance.new("Frame")
	followContainer.Size = UDim2.new(1, 0, 0, 28)
	followContainer.BackgroundTransparency = 1
	followContainer.ZIndex = 22
	adopt(followContainer)

	followRow.Parent = followContainer
	followRow.Size = UDim2.new(1, -50, 0, 28)

	local modesButton = Instance.new("TextButton")
	modesButton.Size = UDim2.new(0, 44, 0, 22)
	modesButton.Position = UDim2.new(1, -44, 0.5, -11)
	modesButton.BackgroundColor3 = C.GRAY3
	modesButton.Text = "Modes"
	modesButton.TextColor3 = C.TEXT
	modesButton.Font = C.FONT
	modesButton.TextSize = 10
	modesButton.AutoButtonColor = false
	modesButton.ZIndex = 23
	modesButton.Parent = followContainer
	local modesStroke = styleButton(modesButton, C.STROKE, false)

	local submenuFrame = Instance.new("Frame")
	submenuFrame.Size = UDim2.new(1, 0, 0, 0)
	submenuFrame.BackgroundTransparency = 1
	submenuFrame.Visible = false
	submenuFrame.ZIndex = 24
	adopt(submenuFrame)

	local submenuLayout = Instance.new("UIListLayout")
	submenuLayout.Padding = UDim.new(0, 4)
	submenuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	submenuLayout.Parent = submenuFrame

	modesButton.MouseButton1Click:Connect(function()
		submenuFrame.Visible = not submenuFrame.Visible
		submenuFrame.Size = submenuFrame.Visible and UDim2.new(1, 0, 0, 5 * 28 + 4 * 4) or UDim2.new(1, 0, 0, 0)
		if submenuFrame.Visible then
			modesStroke.Color = C.BLUE
			modesButton.BackgroundColor3 = C.BLUE
		else
			modesStroke.Color = C.STROKE
			modesButton.BackgroundColor3 = C.GRAY3
		end
	end)

	local insideToggle, insideRow = createSubmenuToggle("Inside", function(value) setBehavior("inside", value) end)
	insideRow.Parent = submenuFrame
	behaviorToggles.inside = insideToggle

	local onTopToggle, onTopRow = createSubmenuToggle("On Top", function(value) setBehavior("ontop", value) end)
	onTopRow.Parent = submenuFrame
	behaviorToggles.ontop = onTopToggle

	local belowToggle, belowRow = createSubmenuToggle("Below", function(value) setBehavior("below", value) end)
	belowRow.Parent = submenuFrame
	behaviorToggles.below = belowToggle

	local aboveToggle, aboveRow = createSubmenuToggle("Above", function(value) setBehavior("above", value) end)
	aboveRow.Parent = submenuFrame
	behaviorToggles.above = aboveToggle

	local _, disableCollisionRow = createSubmenuToggle("Disable NPC Collision", function(value)
		disableCollisionInModes = value
		applyCollisionState()
	end)
	disableCollisionRow.Parent = submenuFrame

	behaviorToggles.attack = createToggle("Attack Mode", function(value)
		setBehavior("attack", value)
	end)

	behaviorToggles.wander = createToggle("Wander", function(value)
		setBehavior("wander", value)
	end)

	local wanderFrame = createTitledFrame("Wander Radius (studs)", 40)
	local wMinus, wBox, wPlus = makeStepper(wanderFrame, tostring(wanderRadius), "10-500")

	local function updateWanderRadius(newValue)
		newValue = math.clamp(math.floor(newValue), 10, 500)
		wanderRadius = newValue
		wBox.Text = tostring(newValue)
	end
	wMinus.MouseButton1Click:Connect(function() updateWanderRadius(wanderRadius - 10) end)
	wPlus.MouseButton1Click:Connect(function() updateWanderRadius(wanderRadius + 10) end)
	wBox.FocusLost:Connect(function()
		local num = tonumber(wBox.Text)
		if num then updateWanderRadius(num) else wBox.Text = tostring(wanderRadius) end
	end)
end)()

;(function()
	buildPage = pages.SETTINGS

	local speedFrame = createTitledFrame("NPC Walk Speed", 62)
	local speedMinus, speedBox, speedPlus = makeStepper(speedFrame, tostring(npcSpeed), "0-500")

	local function updateNPCSpeed(newValue)
		newValue = math.clamp(math.floor(newValue), MIN_NPC_SPEED, MAX_NPC_SPEED)
		npcSpeed = newValue
		speedBox.Text = tostring(newValue)
		applySpeedToSelection()
	end

	speedMinus.MouseButton1Click:Connect(function() updateNPCSpeed(npcSpeed - 1) end)
	speedPlus.MouseButton1Click:Connect(function() updateNPCSpeed(npcSpeed + 1) end)
	speedBox.FocusLost:Connect(function()
		local num = tonumber(speedBox.Text)
		if num then updateNPCSpeed(num) else speedBox.Text = tostring(npcSpeed) end
	end)

	local presetsRow = Instance.new("Frame")
	presetsRow.Size = UDim2.new(1, 0, 0, 18)
	presetsRow.Position = UDim2.new(0, 0, 0, 42)
	presetsRow.BackgroundTransparency = 1
	presetsRow.ZIndex = 22
	presetsRow.Parent = speedFrame

	local speedPresets = {
		{label = "Slow", value = 8},
		{label = "Normal", value = 16},
		{label = "Fast", value = 32},
		{label = "V.Fast", value = 100},
		{label = "Max", value = 500},
	}
	for i, preset in ipairs(speedPresets) do
		local presetButton = Instance.new("TextButton")
		presetButton.Size = UDim2.new(1 / #speedPresets, -4, 1, 0)
		presetButton.Position = UDim2.new((i - 1) / #speedPresets, 2, 0, 0)
		presetButton.BackgroundColor3 = C.GRAY3
		presetButton.Text = preset.label
		presetButton.TextColor3 = C.TEXT
		presetButton.Font = C.FONT
		presetButton.TextSize = 9
		presetButton.AutoButtonColor = false
		presetButton.ZIndex = 23
		presetButton.Parent = presetsRow
		styleButton(presetButton)
		presetButton.MouseButton1Click:Connect(function()
			updateNPCSpeed(preset.value)
		end)
	end

	createToggle("Show Network Owners", function(value)
		task.spawn(function()
			pcall(function()
				settings().Physics.AreOwnersShown = value
			end)
		end)
	end)

	local rangeFrame = createTitledFrame("Range (OWNERSHIP)", 62)
	local minusBtn, rangeBox, plusBtn = makeStepper(rangeFrame, tostring(simulationRadius), "0-INF")

	local function updateRadius(newValue)
		newValue = math.clamp(math.floor(newValue), 0, MAX_RADIUS)
		simulationRadius = newValue
		if newValue > 99999 then
			rangeBox.Text = "INF"
		else
			rangeBox.Text = tostring(newValue)
		end
	end

	minusBtn.MouseButton1Click:Connect(function() updateRadius(simulationRadius - 10) end)
	plusBtn.MouseButton1Click:Connect(function() updateRadius(simulationRadius + 10) end)
	rangeBox.FocusLost:Connect(function()
		local text = rangeBox.Text:lower()
		if text == "inf" or text == "infinite" or text == "∞" then
			updateRadius(MAX_RADIUS)
		else
			local num = tonumber(rangeBox.Text)
			if num then updateRadius(num) else rangeBox.Text = tostring(simulationRadius) end
		end
	end)

	local warning1 = Instance.new("TextLabel")
	warning1.BackgroundTransparency = 1
	warning1.Size = UDim2.new(1, -10, 0, 12)
	warning1.Position = UDim2.new(0, 5, 0, 38)
	warning1.Text = "HIGH RANGE = MORE LAG"
	warning1.TextColor3 = C.SUBTEXT
	warning1.Font = C.FONT
	warning1.TextSize = 8
	warning1.TextXAlignment = Enum.TextXAlignment.Left
	warning1.ZIndex = 22
	warning1.Parent = rangeFrame

	local warning2 = Instance.new("TextLabel")
	warning2.BackgroundTransparency = 1
	warning2.Size = UDim2.new(1, -10, 0, 12)
	warning2.Position = UDim2.new(0, 5, 0, 48)
	warning2.Text = "LOW RANGE = LESS LAG"
	warning2.TextColor3 = C.SUBTEXT
	warning2.Font = C.FONT
	warning2.TextSize = 8
	warning2.TextXAlignment = Enum.TextXAlignment.Left
	warning2.ZIndex = 22
	warning2.Parent = rangeFrame

	local resetSizeButton = createButton("RESET GUI SIZE", C.GRAY3)
	resetSizeButton.MouseButton1Click:Connect(function()
		mainFrame.Size = UDim2.new(0, 500, 0, 400)
	end)
end)()

local function createSlider(titleText, minValue, maxValue, initial, onChange)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 40)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 22
	adopt(frame)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.6, 0, 0, 14)
	label.Text = titleText
	label.TextColor3 = C.TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = C.FONT
	label.TextSize = 11
	label.ZIndex = 22
	label.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0.4, 0, 0, 14)
	valueLabel.Position = UDim2.new(0.6, 0, 0, 0)
	valueLabel.Text = ""
	valueLabel.TextColor3 = C.LIGHTBLUE
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Font = C.FONT
	valueLabel.TextSize = 11
	valueLabel.ZIndex = 22
	valueLabel.Parent = frame

	local track = Instance.new("TextButton")
	track.Size = UDim2.new(1, -10, 0, 8)
	track.Position = UDim2.new(0, 5, 0, 24)
	track.BackgroundColor3 = C.GRAY3
	track.Text = ""
	track.AutoButtonColor = false
	track.ZIndex = 23
	track.Parent = frame
	styleButton(track, C.STROKE, false)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.BLUE
	fill.BorderSizePixel = 0
	fill.ZIndex = 24
	fill.Parent = track

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 10, 0, 16)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.BackgroundColor3 = Color3.fromRGB(210, 214, 222)
	knob.BorderSizePixel = 0
	knob.ZIndex = 25
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0, 3)
	knobCorner.Parent = knob

	local function setValue(newValue, fire)
		newValue = math.clamp(math.floor(newValue + 0.5), minValue, maxValue)
		local ratio = (newValue - minValue) / (maxValue - minValue)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
		valueLabel.Text = tostring(newValue)
		if fire and onChange then onChange(newValue) end
	end

	local dragging = false
	local function fromInput(input)
		local width = math.max(track.AbsoluteSize.X, 1)
		local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
		setValue(minValue + ratio * (maxValue - minValue), true)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			fromInput(input)
		end
	end)

	setValue(initial, false)
	return frame
end

;(function()
	buildPage = pages.EDIT

	local function forEachSelected(callback)
		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= LocalPlayer.Character then
				local humanoid = getHumanoid(model)
				if humanoid and humanoid.Health > 0 then
					callback(model, humanoid)
				end
			end
		end
	end

	createSlider("Jump Power", 0, 300, npcJump, function(value)
		npcJump = value
		forEachSelected(function(_, humanoid)
			humanoid.UseJumpPower = true
			humanoid.JumpPower = value
		end)
	end)
	createLabel("Also used for NPCs you spawn next")

	createLabel("HEALTH EDITOR (SELECTED NPCS)")

	local healthBox = Instance.new("TextBox")
	healthBox.Size = UDim2.new(1, 0, 0, 26)
	healthBox.BackgroundColor3 = C.DARK2
	healthBox.PlaceholderText = "Health value (1 - 1000000)"
	healthBox.PlaceholderColor3 = C.SUBTEXT
	healthBox.Text = ""
	healthBox.TextColor3 = C.TEXT
	healthBox.Font = C.FONT
	healthBox.TextSize = 11
	healthBox.ClearTextOnFocus = false
	healthBox.ZIndex = 22
	adopt(healthBox)
	local healthStroke = styleButton(healthBox, C.STROKE, false)
	healthBox.Focused:Connect(function() healthStroke.Color = C.BLUE end)
	healthBox.FocusLost:Connect(function() healthStroke.Color = C.STROKE end)

	local healthRow = Instance.new("Frame")
	healthRow.Size = UDim2.new(1, 0, 0, 30)
	healthRow.BackgroundTransparency = 1
	healthRow.ZIndex = 22
	adopt(healthRow)

	local setHealthButton = Instance.new("TextButton")
	setHealthButton.Size = UDim2.new(0.5, -3, 1, 0)
	setHealthButton.Position = UDim2.new(0, 0, 0, 0)
	setHealthButton.BackgroundColor3 = C.BLUE
	setHealthButton.Text = "SET HEALTH"
	setHealthButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	setHealthButton.Font = C.BOLD_FONT
	setHealthButton.TextSize = 11
	setHealthButton.AutoButtonColor = false
	setHealthButton.ZIndex = 23
	setHealthButton.Parent = healthRow
	styleButton(setHealthButton, Color3.fromRGB(30, 85, 180))

	local setMaxButton = Instance.new("TextButton")
	setMaxButton.Size = UDim2.new(0.5, -3, 1, 0)
	setMaxButton.Position = UDim2.new(0.5, 3, 0, 0)
	setMaxButton.BackgroundColor3 = C.GRAY3
	setMaxButton.Text = "SET MAX HEALTH"
	setMaxButton.TextColor3 = C.TEXT
	setMaxButton.Font = C.BOLD_FONT
	setMaxButton.TextSize = 11
	setMaxButton.AutoButtonColor = false
	setMaxButton.ZIndex = 23
	setMaxButton.Parent = healthRow
	styleButton(setMaxButton)

	local function readHealthValue()
		local number = tonumber(healthBox.Text)
		if not number then return nil end
		return math.clamp(math.floor(number), 1, 1000000)
	end

	setHealthButton.MouseButton1Click:Connect(function()
		local value = readHealthValue()
		if not value then return end
		forEachSelected(function(_, humanoid)
			if value > humanoid.MaxHealth then humanoid.MaxHealth = value end
			humanoid.Health = value
		end)
	end)

	setMaxButton.MouseButton1Click:Connect(function()
		local value = readHealthValue()
		if not value then return end
		forEachSelected(function(_, humanoid)
			humanoid.MaxHealth = value
			humanoid.Health = value
		end)
	end)

	local healFullButton = createButton("HEAL FULL", C.GRAY3)
	healFullButton.MouseButton1Click:Connect(function()
		forEachSelected(function(_, humanoid)
			humanoid.Health = humanoid.MaxHealth
		end)
	end)

	createLabel("Server-owned NPCs: edits may only show for you")
end)()

;(function()
	buildPage = pages.OUTFITS

	createLabel("OUTFIT NAME (BLANK = NPC NAME)")

	local nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(1, 0, 0, 26)
	nameBox.BackgroundColor3 = C.DARK2
	nameBox.PlaceholderText = "My outfit"
	nameBox.PlaceholderColor3 = C.SUBTEXT
	nameBox.Text = ""
	nameBox.TextColor3 = C.TEXT
	nameBox.Font = C.FONT
	nameBox.TextSize = 11
	nameBox.ClearTextOnFocus = false
	nameBox.ZIndex = 22
	adopt(nameBox)
	local nameStroke = styleButton(nameBox, C.STROKE, false)
	nameBox.Focused:Connect(function() nameStroke.Color = C.BLUE end)
	nameBox.FocusLost:Connect(function() nameStroke.Color = C.STROKE end)

	local saveButton = createButton("SAVE SELECTED NPC OUTFIT", C.BLUE, Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 85, 180))

	createLabel("SAVED OUTFITS")

	local outfitList = Instance.new("ScrollingFrame")
	outfitList.Size = UDim2.new(1, 0, 0, 110)
	outfitList.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
	outfitList.BorderSizePixel = 0
	outfitList.ScrollBarThickness = 3
	outfitList.ScrollBarImageColor3 = C.BLUE
	outfitList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	outfitList.CanvasSize = UDim2.new(0, 0, 0, 0)
	outfitList.ZIndex = 22
	adopt(outfitList)

	local outfitListCorner = Instance.new("UICorner")
	outfitListCorner.CornerRadius = UDim.new(0, 4)
	outfitListCorner.Parent = outfitList

	local outfitListStroke = Instance.new("UIStroke")
	outfitListStroke.Color = C.STROKE
	outfitListStroke.Thickness = 1
	outfitListStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outfitListStroke.Parent = outfitList

	local outfitLayout = Instance.new("UIListLayout")
	outfitLayout.Padding = UDim.new(0, 2)
	outfitLayout.SortOrder = Enum.SortOrder.LayoutOrder
	outfitLayout.Parent = outfitList

	local applyButton = createButton("APPLY TO SELECTED NPC(S)", C.GRAY3)
	local spawnOutfitButton = createButton("SPAWN NPC FROM OUTFIT", C.BLUE, Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 85, 180))
	local deleteOutfitButton = createButton("DELETE OUTFIT", C.KILL_RED, Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 20, 28))

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0, 14)
	statusLabel.Text = "Ready"
	statusLabel.TextColor3 = C.SUBTEXT
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.Font = C.FONT
	statusLabel.TextSize = 10
	statusLabel.ZIndex = 22
	adopt(statusLabel)

	createLabel(canUseFiles and "Outfits are saved to a file between sessions" or "No file access: outfits last this session only")

	local function setStatus(text, isError)
		statusLabel.Text = text
		statusLabel.TextColor3 = isError and Color3.fromRGB(255, 90, 90) or C.LIGHTBLUE
	end

	local function refreshOutfitList()
		for _, child in ipairs(outfitList:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		local names = {}
		for name in pairs(savedOutfits) do table.insert(names, name) end
		table.sort(names)
		for i, name in ipairs(names) do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, 22)
			row.LayoutOrder = i
			row.BackgroundColor3 = (name == selectedOutfitName) and C.BLUE or C.GRAY3
			row.Text = name
			row.TextColor3 = (name == selectedOutfitName) and Color3.fromRGB(255, 255, 255) or C.TEXT
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.Font = C.FONT
			row.TextSize = 10
			row.AutoButtonColor = false
			row.ZIndex = 23
			row.Parent = outfitList

			local rowPadding = Instance.new("UIPadding")
			rowPadding.PaddingLeft = UDim.new(0, 6)
			rowPadding.Parent = row

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 3)
			rowCorner.Parent = row

			row.MouseButton1Click:Connect(function()
				selectedOutfitName = name
				refreshOutfitList()
			end)
		end
	end
	refreshOutfitList()

	saveButton.MouseButton1Click:Connect(function()
		local model = selectedModel
		local humanoid = model and getHumanoid(model)
		if not humanoid then
			setStatus("Select an NPC first", true)
			return
		end
		local ok, desc = pcall(function() return humanoid:GetAppliedDescription() end)
		if not ok or not desc then
			setStatus("Couldn't read that NPC's outfit", true)
			return
		end
		local name = trim(nameBox.Text)
		if name == "" then name = model.Name end
		savedOutfits[name] = serializeDescription(desc)
		selectedOutfitName = name
		persistOutfits()
		refreshOutfitList()
		setStatus("Saved '" .. name .. "'", false)
	end)

	applyButton.MouseButton1Click:Connect(function()
		local data = selectedOutfitName and savedOutfits[selectedOutfitName]
		if not data then
			setStatus("Pick an outfit from the list", true)
			return
		end
		local targets = {}
		for _, model in ipairs(selectedNPCs) do
			if model and model.Parent and model ~= LocalPlayer.Character then
				table.insert(targets, model)
			end
		end
		if #targets == 0 then
			setStatus("Select NPC(s) first", true)
			return
		end
		setStatus("Applying...", false)
		task.spawn(function()
			local done, failed = 0, 0
			for _, model in ipairs(targets) do
				local humanoid = getHumanoid(model)
				if humanoid and model.Parent then
					local desc = deserializeDescription(data)
					local ok = pcall(function() humanoid:ApplyDescription(desc) end)
					if ok then done = done + 1 else failed = failed + 1 end
				end
			end
			if failed > 0 then
				setStatus("Applied " .. done .. ", failed " .. failed, true)
			else
				setStatus("Applied to " .. done .. " NPC(s)", false)
			end
		end)
	end)

	spawnOutfitButton.MouseButton1Click:Connect(function()
		local name = selectedOutfitName
		local data = name and savedOutfits[name]
		if not data then
			setStatus("Pick an outfit from the list", true)
			return
		end
		if spawning then return end
		task.spawn(function() runSpawn("", setStatus, { name = name, data = data }) end)
	end)

	deleteOutfitButton.MouseButton1Click:Connect(function()
		local name = selectedOutfitName
		if not name or not savedOutfits[name] then
			setStatus("Pick an outfit from the list", true)
			return
		end
		savedOutfits[name] = nil
		selectedOutfitName = nil
		persistOutfits()
		refreshOutfitList()
		setStatus("Deleted '" .. name .. "'", false)
	end)
end)()

;(function()
	buildPage = pages.BEHAVIOR

	behaviorToggles.patrol = createToggle("Patrol Waypoints", function(value)
		setBehavior("patrol", value)
	end)

	patrolCountLabel = createLabel("Waypoints: 0")

	local waypointRow = Instance.new("Frame")
	waypointRow.Size = UDim2.new(1, 0, 0, 30)
	waypointRow.BackgroundTransparency = 1
	waypointRow.ZIndex = 22
	adopt(waypointRow)

	local addHereButton = Instance.new("TextButton")
	addHereButton.Size = UDim2.new(0.5, -3, 1, 0)
	addHereButton.Position = UDim2.new(0, 0, 0, 0)
	addHereButton.BackgroundColor3 = C.BLUE
	addHereButton.Text = "ADD AT ME"
	addHereButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	addHereButton.Font = C.BOLD_FONT
	addHereButton.TextSize = 11
	addHereButton.AutoButtonColor = false
	addHereButton.ZIndex = 23
	addHereButton.Parent = waypointRow
	styleButton(addHereButton, Color3.fromRGB(30, 85, 180))

	local clearWaypointsButton = Instance.new("TextButton")
	clearWaypointsButton.Size = UDim2.new(0.5, -3, 1, 0)
	clearWaypointsButton.Position = UDim2.new(0.5, 3, 0, 0)
	clearWaypointsButton.BackgroundColor3 = C.GRAY3
	clearWaypointsButton.Text = "CLEAR"
	clearWaypointsButton.TextColor3 = C.TEXT
	clearWaypointsButton.Font = C.BOLD_FONT
	clearWaypointsButton.TextSize = 11
	clearWaypointsButton.AutoButtonColor = false
	clearWaypointsButton.ZIndex = 23
	clearWaypointsButton.Parent = waypointRow
	styleButton(clearWaypointsButton)

	addHereButton.MouseButton1Click:Connect(function()
		local character = getRealCharacter()
		local root = character and getRoot(character)
		if root then
			addWaypoint(root.Position - Vector3.new(0, 2.5, 0))
		end
	end)
	clearWaypointsButton.MouseButton1Click:Connect(clearWaypoints)

	createToggle("Click to Add Waypoints", function(value)
		waypointMode = value
	end)

	createLabel("FOLLOW PLAYER")

	local playerList = Instance.new("ScrollingFrame")
	playerList.Size = UDim2.new(1, 0, 0, 90)
	playerList.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
	playerList.BorderSizePixel = 0
	playerList.ScrollBarThickness = 3
	playerList.ScrollBarImageColor3 = C.BLUE
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.CanvasSize = UDim2.new(0, 0, 0, 0)
	playerList.ZIndex = 22
	adopt(playerList)

	local playerListCorner = Instance.new("UICorner")
	playerListCorner.CornerRadius = UDim.new(0, 4)
	playerListCorner.Parent = playerList

	local playerListStroke = Instance.new("UIStroke")
	playerListStroke.Color = C.STROKE
	playerListStroke.Thickness = 1
	playerListStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	playerListStroke.Parent = playerList

	local playerLayout = Instance.new("UIListLayout")
	playerLayout.Padding = UDim.new(0, 2)
	playerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	playerLayout.Parent = playerList

	local function refreshPlayerList()
		for _, child in ipairs(playerList:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		local list = Players:GetPlayers()
		table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
		for i, player in ipairs(list) do
			local chosen = (player == followTargetPlayer)
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, 22)
			row.LayoutOrder = i
			row.BackgroundColor3 = chosen and C.BLUE or C.GRAY3
			local label = player.DisplayName .. " (@" .. player.Name .. ")"
			if player == LocalPlayer then label = label .. " [you]" end
			row.Text = label
			row.TextColor3 = chosen and Color3.fromRGB(255, 255, 255) or C.TEXT
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.Font = C.FONT
			row.TextSize = 10
			row.AutoButtonColor = false
			row.ZIndex = 23
			row.Parent = playerList

			local rowPadding = Instance.new("UIPadding")
			rowPadding.PaddingLeft = UDim.new(0, 6)
			rowPadding.Parent = row

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 3)
			rowCorner.Parent = row

			row.MouseButton1Click:Connect(function()
				followTargetPlayer = player
				refreshPlayerList()
			end)
		end
	end
	refreshPlayerList()

	Players.PlayerAdded:Connect(function()
		task.defer(refreshPlayerList)
	end)
	Players.PlayerRemoving:Connect(function(player)
		if followTargetPlayer == player then followTargetPlayer = nil end
		task.defer(refreshPlayerList)
	end)

	local followPlayerToggle
	followPlayerToggle = createToggle("Follow Chosen Player", function(value)
		if value and not followTargetPlayer then
			followPlayerToggle:Set(false, true)
			return
		end
		setBehavior("followplayer", value)
	end)
	behaviorToggles.followplayer = followPlayerToggle
end)()

;(function()
	buildPage = pages.CONTROL

	createLabel("SEATS")

	local sitSeatButton = createButton("SIT ON NEAREST SEAT", C.BLUE, Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 85, 180))

	local sitRow = Instance.new("Frame")
	sitRow.Size = UDim2.new(1, 0, 0, 30)
	sitRow.BackgroundTransparency = 1
	sitRow.ZIndex = 22
	adopt(sitRow)

	local sitHereButton = Instance.new("TextButton")
	sitHereButton.Size = UDim2.new(0.5, -3, 1, 0)
	sitHereButton.Position = UDim2.new(0, 0, 0, 0)
	sitHereButton.BackgroundColor3 = C.GRAY3
	sitHereButton.Text = "SIT HERE"
	sitHereButton.TextColor3 = C.TEXT
	sitHereButton.Font = C.BOLD_FONT
	sitHereButton.TextSize = 11
	sitHereButton.AutoButtonColor = false
	sitHereButton.ZIndex = 23
	sitHereButton.Parent = sitRow
	styleButton(sitHereButton)

	local standUpButton = Instance.new("TextButton")
	standUpButton.Size = UDim2.new(0.5, -3, 1, 0)
	standUpButton.Position = UDim2.new(0.5, 3, 0, 0)
	standUpButton.BackgroundColor3 = C.GRAY3
	standUpButton.Text = "STAND UP"
	standUpButton.TextColor3 = C.TEXT
	standUpButton.Font = C.BOLD_FONT
	standUpButton.TextSize = 11
	standUpButton.AutoButtonColor = false
	standUpButton.ZIndex = 23
	standUpButton.Parent = sitRow
	styleButton(standUpButton)

	local sitStatus = createLabel("")

	sitSeatButton.MouseButton1Click:Connect(function()
		if #selectedNPCs == 0 then
			sitStatus.Text = "Select NPC(s) first"
			return
		end
		local sent = sitSelectedOnSeats()
		if sent > 0 then
			sitStatus.Text = "Sending " .. sent .. " NPC(s) to seats"
		else
			sitStatus.Text = "No free seats within 150 studs"
		end
	end)

	sitHereButton.MouseButton1Click:Connect(function()
		for _, model in ipairs(selectedNPCs) do
			local humanoid = getHumanoid(model)
			if model.Parent and model ~= LocalPlayer.Character and humanoid and humanoid.Health > 0 then
				humanoid.Sit = true
			end
		end
	end)

	standUpButton.MouseButton1Click:Connect(function()
		for _, model in ipairs(selectedNPCs) do
			local humanoid = getHumanoid(model)
			if model.Parent and model ~= LocalPlayer.Character and humanoid then
				humanoid.Sit = false
				humanoid.Jump = true
			end
		end
	end)
end)()

;(function()
	buildPage = pages.SETTINGS

	local healthBarToggle = createToggle("NPC Health Bars", function(value)
		healthBarsEnabled = value
		for _, entry in ipairs(npcEntries) do
			if entry.ownSpawn and entry.model and entry.model.Parent then
				local humanoid = getHumanoid(entry.model)
				if humanoid then showRobloxHealthBar(humanoid) end
			end
		end
	end)
	healthBarToggle:Set(true, true)

	createLabel("Panel keybind: click, then press a key")
	keybindButton = createButton("KEYBIND: " .. toggleKey.Name, C.GRAY3)
	keybindButton.MouseButton1Click:Connect(function()
		if bindingKey then
			bindingKey = false
			keybindButton.Text = "KEYBIND: " .. toggleKey.Name
		else
			bindingKey = true
			keybindButton.Text = "PRESS A KEY... (CLICK TO CANCEL)"
		end
	end)
end)()

selectTab("SPAWN")

local function animateTextColor(button)
	local colors = {C.BLUE, C.LIGHTBLUE, Color3.fromRGB(235, 240, 255), C.LIGHTBLUE}
	local currentIdx = 1
	while true do
		local nextIdx = currentIdx % #colors + 1
		local tween = TweenService:Create(button, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {TextColor3 = colors[nextIdx]})
		tween:Play()
		tween.Completed:Wait()
		currentIdx = nextIdx
	end
end

local resizeGrip

;(function()
	local footerFrame = Instance.new("Frame")
	footerFrame.Size = UDim2.new(0, 230, 0, 28)
	footerFrame.Position = UDim2.new(0, 10, 1, -36)
	footerFrame.BackgroundTransparency = 1
	footerFrame.ZIndex = 21
	footerFrame.Parent = mainFrame

	local instaBtn = Instance.new("TextButton")
	instaBtn.Size = UDim2.new(0.48, 0, 1, 0)
	instaBtn.Position = UDim2.new(0, 0, 0, 0)
	instaBtn.BackgroundColor3 = C.DARK2
	instaBtn.Text = "INSTAGRAM"
	instaBtn.TextColor3 = C.BLUE
	instaBtn.Font = C.BOLD_FONT
	instaBtn.TextSize = 11
	instaBtn.AutoButtonColor = false
	instaBtn.ZIndex = 23
	instaBtn.Parent = footerFrame
	styleButton(instaBtn, C.BLUE)

	local discordBtn = Instance.new("TextButton")
	discordBtn.Size = UDim2.new(0.48, 0, 1, 0)
	discordBtn.Position = UDim2.new(0.52, 0, 0, 0)
	discordBtn.BackgroundColor3 = C.DARK2
	discordBtn.Text = "DISCORD"
	discordBtn.TextColor3 = C.BLUE
	discordBtn.Font = C.BOLD_FONT
	discordBtn.TextSize = 11
	discordBtn.AutoButtonColor = false
	discordBtn.ZIndex = 23
	discordBtn.Parent = footerFrame
	styleButton(discordBtn, C.BLUE)

	instaBtn.MouseButton1Click:Connect(function()
		pcall(setclipboard, "https://www.instagram.com/me_duakno?igsh=MXNqZDU4ZHR6aGZpcw==")
	end)
	discordBtn.MouseButton1Click:Connect(function()
		pcall(setclipboard, "discord.gg/empgqd5qpq")
	end)

	task.spawn(function() animateTextColor(instaBtn) end)
	task.spawn(function() animateTextColor(discordBtn) end)

	resizeGrip = Instance.new("TextButton")
	resizeGrip.Name = "ResizeGrip"
	resizeGrip.Size = UDim2.new(0, 20, 0, 20)
	resizeGrip.AnchorPoint = Vector2.new(1, 1)
	resizeGrip.Position = UDim2.new(1, -2, 1, -2)
	resizeGrip.BackgroundTransparency = 1
	resizeGrip.Text = ""
	resizeGrip.AutoButtonColor = false
	resizeGrip.ZIndex = 30
	resizeGrip.Parent = mainFrame

	for i = 0, 2 do
		for j = 0, 2 - i do
			local dot = Instance.new("Frame")
			dot.Size = UDim2.new(0, 2, 0, 2)
			dot.Position = UDim2.new(0, 15 - j * 5, 0, 15 - i * 5)
			dot.BackgroundColor3 = C.SUBTEXT
			dot.BorderSizePixel = 0
			dot.ZIndex = 31
			dot.Parent = resizeGrip
		end
	end

	resizeGrip.MouseEnter:Connect(function()
		for _, dot in ipairs(resizeGrip:GetChildren()) do
			if dot:IsA("Frame") then dot.BackgroundColor3 = C.BLUE end
		end
	end)
	resizeGrip.MouseLeave:Connect(function()
		for _, dot in ipairs(resizeGrip:GetChildren()) do
			if dot:IsA("Frame") then dot.BackgroundColor3 = C.SUBTEXT end
		end
	end)
end)()

local function setPanelVisible(visible)
	mainFrame.Visible = visible
	if visible then
		gearStroke.Color = C.BLUE
		gearStroke.Thickness = 2
	else
		gearStroke.Color = C.STROKE
		gearStroke.Thickness = 1
	end
end

gearButton.MouseButton1Click:Connect(function()
	setPanelVisible(not mainFrame.Visible)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == Enum.KeyCode.Unknown then return end
	if bindingKey then
		bindingKey = false
		if input.KeyCode ~= Enum.KeyCode.Escape then
			toggleKey = input.KeyCode
		end
		if keybindButton then
			keybindButton.Text = "KEYBIND: " .. toggleKey.Name
		end
		return
	end
	if input.KeyCode == toggleKey then
		setPanelVisible(not mainFrame.Visible)
	end
end)

;(function()
	local dragging = false
	local dragStart, startPos
	local resizing = false
	local resizeStartMouse, resizeStartSize

	topBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = mainFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)

	resizeGrip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStartMouse = input.Position
			resizeStartSize = mainFrame.AbsoluteSize

			local abs = mainFrame.AbsolutePosition
			mainFrame.Position = UDim2.fromOffset(abs.X, abs.Y)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then resizing = false end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end

		if dragging then
			local delta = input.Position - dragStart
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		elseif resizing then
			local delta = input.Position - resizeStartMouse
			local viewport = screenGui.AbsoluteSize
			local abs = mainFrame.AbsolutePosition
			local maxW = math.max(MIN_W, math.min(MAX_W, viewport.X - abs.X - 4))
			local maxH = math.max(MIN_H, math.min(MAX_H, viewport.Y - abs.Y - 4))
			local newW = math.clamp(resizeStartSize.X + delta.X, MIN_W, maxW)
			local newH = math.clamp(resizeStartSize.Y + delta.Y, MIN_H, maxH)
			mainFrame.Size = UDim2.fromOffset(newW, newH)
		end
	end)
end)()

local function getWorldRay(input)
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	if input.UserInputType == Enum.UserInputType.Touch then
		return camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	end
	local location = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(location.X, location.Y)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not selectMode and not clickMoveEnabled and not waypointMode then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end

	local ray = getWorldRay(input)
	if not ray then return end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if LocalPlayer.Character then params.FilterDescendantsInstances = {LocalPlayer.Character} end
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not result then return end

	local handled = false
	if selectMode then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model then
			addNPC(model, false)
			local entry = findEntry(model)
			if entry and not entry.isPlayer and isSelectableNPC(model) then
				if multiSelectEnabled then
					if isSelected(model) then removeSelected(model) else addSelected(model) end
				else
					clearSelection()
					addSelected(model)
				end
				if controlToggle then controlToggle:SetEnabled(#selectedNPCs > 0) end
				handled = true
			end
		end
	end

	if not handled and waypointMode then
		addWaypoint(result.Position)
		handled = true
	end

	if not handled and clickMoveEnabled then
		issueMoveTo(result.Position)
	end
end)

LocalPlayer.CharacterAdded:Connect(function(character)
	if controlEnabled and selectedModel and character ~= selectedModel then
		controlEnabled = false
		if controlToggle then controlToggle:Set(false, true) end
	end
end)

RunService.RenderStepped:Connect(function()
	if sethiddenproperty then
		sethiddenproperty(LocalPlayer, "SimulationRadius", simulationRadius)
	else
		LocalPlayer.SimulationRadius = simulationRadius
	end
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		pcall(function()
			local real = getRealCharacter()
			local playerRoot = real and getRoot(real)

			for _, entry in ipairs(npcEntries) do
				local model = entry.model
				local hum = getHumanoid(model)
				local root = getRoot(model)
				if entry.hpFill and entry.hpFill.Parent and hum then
					local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					entry.hpFill.Size = UDim2.new(ratio, 0, 1, 0)
					entry.hpFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50):Lerp(Color3.fromRGB(60, 200, 90), ratio)
				end
				if entry.distLabel and entry.distLabel.Parent then
					if playerRoot and root then
						entry.distLabel.Text = tostring(math.floor((root.Position - playerRoot.Position).Magnitude)) .. "m"
					else
						entry.distLabel.Text = ""
					end
				end
			end

			if infoLabel then
				local text = "NPCs: " .. #npcEntries .. "   Selected: " .. #selectedNPCs
				if #selectedNPCs == 1 then
					local model = selectedNPCs[1]
					local hum = getHumanoid(model)
					if hum then
						local rigName = (hum.RigType == Enum.HumanoidRigType.R6) and "R6" or "R15"
						text = text .. "\n" .. model.Name .. " | HP " .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth) .. " | " .. rigName .. " | Jump " .. math.floor(hum.JumpPower)
					end
				end
				infoLabel.Text = text
			end
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		for i = #npcEntries, 1, -1 do
			local entry = npcEntries[i]
			local model = entry.model
			local invalid = false

			if not model then
				invalid = true
			elseif not model.Parent then
				invalid = true
			elseif not model:FindFirstChild("HumanoidRootPart") then
				invalid = true
			else
				local hum = getHumanoid(model)
				if not hum or hum.Health <= 0 then
					invalid = true
				end
			end

			if invalid then
				removeSelected(model)
				for j, m in ipairs(teleportModeNPCs) do
					if m == model then
						table.remove(teleportModeNPCs, j)
						break
					end
				end
				if entry.listRow and entry.listRow.Parent then
					entry.listRow:Destroy()
				end
				table.remove(npcEntries, i)
			end
		end
	end
end)
