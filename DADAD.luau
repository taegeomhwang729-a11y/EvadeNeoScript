local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()

-- 액센트 색을 무채색(회색)으로 변경
Library.Scheme.AccentColor = Color3.fromRGB(180, 180, 180)
Library:UpdateColorsUsingRegistry()

local Window = Library:CreateWindow({
    Title = "Neo.win",
    Size = UDim2.fromOffset(520, 480),
    Center = true,
    ToggleKeybind = Enum.KeyCode.RightShift,
    AutoShow = true
})

local MiscTab = Window:AddTab("Misc")
local VisualTab = Window:AddTab("Visual")
local ConfigTab = Window:AddTab("Config")

-- ============================================
-- 서비스
-- ============================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local Toggles = {}
local Options = {}

-- ============================================
-- Evade Speed
-- ============================================
getgenv().Evade = getgenv().Evade or {}
local cfg = getgenv().Evade
cfg.topSpeed = 60
cfg.maxSpeed = 90

local evadeEnabled = false
local originalRun, originalAir
local evadeHooked = false

local function enableEvade()
    if evadeHooked then return true end

    local success, funcs = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Objects").Game.Character.Client.Movement.MoveFunction.Functions)
    end)

    if not success or not funcs then
        return false
    end

    local strafeCut, backCut = 0.65, 0.4
    local accel, turn = 80, 10
    local gain, decay, swingRef = 25, 8, 5
    local ease, drag, brake = 70, 18, 200
    local scale = 90

    local function turnTo(cur, goal, max)
        if goal.Magnitude < 1e-4 then return cur end
        if cur.Magnitude < 1e-4 then return goal.Unit end
        local a, b = cur.Unit, goal.Unit
        local ang = math.acos(math.clamp(a.X * b.X + a.Y * b.Y, -1, 1))
        if ang <= max then return b end
        local side = (a.X * b.Y - a.Y * b.X) >= 0 and 1 or -1
        local c, s = math.cos(max * side), math.sin(max * side)
        return Vector2.new(a.X * c - a.Y * s, a.X * s + a.Y * c)
    end

    local spd, extra = 0, 0
    local dir = Vector2.new(0, -1)
    local lastY = 0

    local function step(dt, data, mover, state, grounded)
        if not evadeEnabled then
            return mover, state
        end
        if not (mover and mover.BaseMover) then return mover, state end

        local look = data:Get("LookCFrame")
        local input = data:Get("MoveDirection") or Vector3.zero
        local world = look and look:VectorToWorldSpace(input) or input
        local wish = Vector2.new(world.X, world.Z)
        local moving = wish.Magnitude > 0.05
        local aim = wish
        if not moving and look then
            aim = Vector2.new(look.LookVector.X, look.LookVector.Z)
        end
        dir = turnTo(dir, aim, turn * dt)
        local face = look and Vector2.new(look.LookVector.X, look.LookVector.Z) or dir
        local align = face.Magnitude > 0 and dir:Dot(face.Unit) or 1
        local cut = align >= 0
            and strafeCut + (1 - strafeCut) * align
            or strafeCut + (strafeCut - backCut) * align
        local y = look and math.atan2(look.LookVector.X, look.LookVector.Z) or lastY
        local dy = (y - lastY + math.pi) % (2 * math.pi) - math.pi
        lastY = y
        local swing = dt > 0 and math.clamp(math.abs(dy) / dt / swingRef, 0, 1) or 0
        extra = math.clamp(extra + ((moving and swing * gain or 0) - decay) * dt, 0, cfg.maxSpeed - cfg.topSpeed)
        local target = moving and (cfg.topSpeed + extra) * cut or 0
        if spd < target then
            spd = math.min(target, spd + accel * dt)
        else
            spd = math.max(target, spd - (moving and ease or (grounded and brake or drag)) * dt)
        end
        local v = dir * (spd * scale)
        mover.BaseMover.PlaneVelocity = v
        if state and state.Velocity then
            state.Velocity = Vector3.new(v.X, state.Velocity.Y, v.Y)
        end
        return mover, state
    end

    originalRun = funcs.Run
    originalAir = funcs.Air

    funcs.Run = function(dt, m, data, char, stats)
        local mover, state = originalRun(dt, m, data, char, stats)
        return step(dt, data, mover, state, true)
    end

    funcs.Air = function(dt, m, data, char, stats)
        local mover, state = originalAir(dt, m, data, char, stats)
        return step(dt, data, mover, state, false)
    end

    evadeHooked = true
    return true
end

local function disableEvade()
    if not evadeHooked then return end

    local success, funcs = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Objects").Game.Character.Client.Movement.MoveFunction.Functions)
    end)

    if success and funcs and originalRun and originalAir then
        funcs.Run = originalRun
        funcs.Air = originalAir
    end

    evadeHooked = false
end

-- ============================================
-- Visual Level Changer (수정됨: 토글 꺼짐 완벽 반영)
-- ============================================
local visualLevelEnabled = false
local targetVisualLevel = 999

RunService.Heartbeat:Connect(function()
    -- 토글이 꺼져있으면 함수 내부를 아예 실행하지 않고 중단
    if not visualLevelEnabled then return end

    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end

        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextLabel") or gui:IsA("TextButton") then
                local text = gui.Text
                if text:match("Level") or text:match("LV") or text:match("lv") or gui.Name:lower():match("level") then
                    local prefix = text:match("([A-Za-z%s]+)") or "Level: "
                    gui.Text = prefix .. tostring(targetVisualLevel)
                end
            end
        end
    end)
end)

-- ============================================
-- Fly
-- ============================================
local flyEnabled = false
local flySpeed = 50
local flyConnection
local flyBV

local function stopFly()
    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end
    if flyBV then
        pcall(function() flyBV:Destroy() end)
        flyBV = nil
    end
end

local function startFly()
    stopFly()

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "NeoFlyVelocity"
    flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = hrp

    flyConnection = RunService.RenderStepped:Connect(function()
        if not flyEnabled or not hrp or not hrp.Parent then
            stopFly()
            return
        end

        local cam = workspace.CurrentCamera
        local moveDir = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir -= Vector3.new(0, 1, 0) end

        flyBV.Velocity = moveDir.Magnitude > 0 and moveDir.Unit * flySpeed or Vector3.zero
    end)
end

-- ============================================
-- Noclip
-- ============================================
local noclipEnabled = false
local noclipConnection

local function startNoclip()
    if noclipConnection then noclipConnection:Disconnect() end
    noclipConnection = RunService.Stepped:Connect(function()
        if not noclipEnabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function stopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    local char = LocalPlayer.Character
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

-- ============================================
-- Dash
-- ============================================
local dashEnabled = false
local dashPower = 80
local dashCooldown = 0.6
local lastDash = 0
local dashing = false

local function doDash()
    if not dashEnabled then return end
    if dashing then return end
    if tick() - lastDash < dashCooldown then return end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid or humanoid.Health <= 0 then return end

    lastDash = tick()
    dashing = true

    local cam = workspace.CurrentCamera
    local look = cam.CFrame.LookVector
    local dir = Vector3.new(look.X, 0, look.Z)

    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        dir = -dir
    end

    if dir.Magnitude > 0 then
        dir = dir.Unit
    else
        dir = Vector3.new(0, 0, -1)
    end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "NeoDash"
    bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
    bv.Velocity = dir * dashPower
    bv.Parent = hrp

    task.delay(0.15, function()
        if bv and bv.Parent then
            bv:Destroy()
        end
        dashing = false
    end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Q then
        doDash()
    end
end)

-- ============================================
-- Wall Climb
-- ============================================
local wallClimbEnabled = false
local wallClimbConnection
local climbSpeed = 42
local currentWallNormal = nil

local function startWallClimb()
    if wallClimbConnection then wallClimbConnection:Disconnect() end
    currentWallNormal = nil

    wallClimbConnection = RunService.Heartbeat:Connect(function(dt)
        if not wallClimbEnabled then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not humanoid or humanoid.Health <= 0 then return end

        local dirs = {
            hrp.CFrame.LookVector,
            hrp.CFrame.RightVector,
            -hrp.CFrame.RightVector,
            (hrp.CFrame.LookVector + hrp.CFrame.RightVector).Unit,
            (hrp.CFrame.LookVector - hrp.CFrame.RightVector).Unit,
            -hrp.CFrame.LookVector,
        }

        local hitWall = false
        local wallNormal = nil

        for _, dir in ipairs(dirs) do
            local params = RaycastParams.new()
            params.FilterDescendantsInstances = {char}
            params.FilterType = Enum.RaycastFilterType.Exclude

            local ray = workspace:Raycast(hrp.Position, dir * 2.8, params)
            if ray and ray.Instance and ray.Instance.CanCollide then
                hitWall = true
                wallNormal = ray.Normal
                break
            end
        end

        if hitWall and wallNormal then
            currentWallNormal = wallNormal

            local up = Vector3.new(0, 1, 0)
            local right = wallNormal:Cross(up)
            if right.Magnitude < 0.1 then
                right = wallNormal:Cross(Vector3.new(1, 0, 0))
            end
            right = right.Unit
            local climbUp = right:Cross(wallNormal).Unit

            local targetCF = CFrame.fromMatrix(
                hrp.Position,
                right,
                climbUp,
                -wallNormal
            ) * CFrame.Angles(math.rad(-90), 0, 0)

            hrp.CFrame = hrp.CFrame:Lerp(targetCF, math.clamp(dt * 12, 0, 1))

            hrp.AssemblyLinearVelocity = Vector3.new(
                -wallNormal.X * 12,
                climbSpeed,
                -wallNormal.Z * 12
            )
        else
            currentWallNormal = nil
        end
    end)
end

local function stopWallClimb()
    if wallClimbConnection then
        wallClimbConnection:Disconnect()
        wallClimbConnection = nil
    end
    currentWallNormal = nil
end

-- ============================================
-- Infinity Jump & Jump Power
-- ============================================
local infJumpEnabled = false
local jumpPowerEnabled = false
local customJumpPower = 50

UserInputService.JumpRequest:Connect(function()
    if not infJumpEnabled then return end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if jumpPowerEnabled then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = customJumpPower
        else
            humanoid.JumpPower = 50
        end
    end
end)

-- ============================================
-- Fog
-- ============================================
local fogEnabled = false
local customAtmosphere = nil
local customFogConnection

local function startFog()
    if customAtmosphere then customAtmosphere:Destroy() end
    
    customAtmosphere = Instance.new("Atmosphere")
    customAtmosphere.Name = "NeoCustomAtmosphere"
    customAtmosphere.Density = 0.5
    customAtmosphere.Offset = 0
    customAtmosphere.Color = Color3.fromRGB(180, 180, 180)
    customAtmosphere.Decay = Color3.fromRGB(100, 100, 100)
    customAtmosphere.Glare = 0
    customAtmosphere.Haze = 0
    customAtmosphere.Parent = Lighting

    if customFogConnection then customFogConnection:Disconnect() end
    customFogConnection = RunService.RenderStepped:Connect(function()
        if not fogEnabled then return end
        Lighting.FogEnd = 1000
        Lighting.FogStart = 0
        Lighting.FogColor = Color3.fromRGB(180, 180, 180)
        if customAtmosphere and customAtmosphere.Parent ~= Lighting then
            customAtmosphere.Parent = Lighting
        end
    end)
end

local function stopFog()
    if customFogConnection then
        customFogConnection:Disconnect()
        customFogConnection = nil
    end
    if customAtmosphere then
        customAtmosphere:Destroy()
        customAtmosphere = nil
    end
    Lighting.FogEnd = 100000
end

-- ============================================
-- Stretch
-- ============================================
local stretchEnabled = false
local stretchConnection
local stretchY = 0.6

local function startStretch()
    if stretchConnection then stretchConnection:Disconnect() end
    stretchConnection = RunService.RenderStepped:Connect(function()
        if not stretchEnabled then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local cf = cam.CFrame
        cam.CFrame = CFrame.fromMatrix(cf.Position, cf.RightVector, cf.UpVector * stretchY, -cf.LookVector)
    end)
end

local function stopStretch()
    if stretchConnection then
        stretchConnection:Disconnect()
        stretchConnection = nil
    end
end

-- ============================================
-- Motion Blur
-- ============================================
local motionBlurEnabled = false
local motionBlurEffect = nil
local motionBlurIntensity = 18
local motionBlurConnection

local function startMotionBlur()
    if motionBlurEffect then motionBlurEffect:Destroy() end
    motionBlurEffect = Instance.new("BlurEffect")
    motionBlurEffect.Name = "NeoMotionBlur"
    motionBlurEffect.Size = 0
    motionBlurEffect.Parent = Lighting

    local lastCamPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
    
    motionBlurConnection = RunService.RenderStepped:Connect(function(dt)
        if not motionBlurEnabled or not motionBlurEffect then return end
        local cam = workspace.CurrentCamera
        if not cam then return end

        local currentPos = cam.CFrame.Position
        local deltaDist = (currentPos - lastCamPos).Magnitude
        lastCamPos = currentPos

        local targetBlur = math.clamp(deltaDist * motionBlurIntensity / (dt > 0 and dt or 0.016), 0, 32)
        motionBlurEffect.Size = motionBlurEffect.Size + (targetBlur - motionBlurEffect.Size) * math.clamp(dt * 10, 0, 1)
    end)
end

local function stopMotionBlur()
    if motionBlurConnection then
        motionBlurConnection:Disconnect()
        motionBlurConnection = nil
    end
    if motionBlurEffect then
        motionBlurEffect:Destroy()
        motionBlurEffect = nil
    end
end

-- ============================================
-- Aura
-- ============================================
local auraEnabled = false
local auraObjects = {}
local footprintFolder = Instance.new("Folder")
footprintFolder.Name = "NeoFootprints"
footprintFolder.Parent = workspace

local function clearAura()
    for _, obj in pairs(auraObjects) do
        pcall(function()
            if typeof(obj) == "RBXScriptConnection" then
                obj:Disconnect()
            else
                obj:Destroy()
            end
        end)
    end
    auraObjects = {}
end

local function clearFootprints()
    for _, fp in pairs(footprintFolder:GetChildren()) do
        fp:Destroy()
    end
end

local function attachAura(char)
    clearAura()
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local att = Instance.new("Attachment")
    att.Name = "NeoAuraAtt"
    att.Parent = hrp
    table.insert(auraObjects, att)

    local particles = Instance.new("ParticleEmitter")
    particles.Name = "NeoAura"
    particles.Texture = "rbxassetid://243660364"
    particles.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
    })
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.3),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 1)
    })
    particles.Lifetime = NumberRange.new(0.7, 1.1)
    particles.Rate = 45
    particles.Speed = NumberRange.new(0.4, 1.4)
    particles.SpreadAngle = Vector2.new(360, 360)
    particles.LightEmission = 0.6
    particles.Parent = att
    table.insert(auraObjects, particles)

    local lastPos = hrp.Position
    local footprintConn = RunService.Heartbeat:Connect(function()
        if not auraEnabled or not hrp or not hrp.Parent then return end

        local pos = hrp.Position
        if (pos - lastPos).Magnitude > 0.9 then
            lastPos = pos

            local mark = Instance.new("Part")
            mark.Name = "Footprint"
            mark.Anchored = true
            mark.CanCollide = false
            mark.Size = Vector3.new(1.6, 0.1, 1.6)
            mark.Position = Vector3.new(pos.X, pos.Y - 2.95, pos.Z)
            mark.Orientation = Vector3.new(0, 0, 0)
            mark.Color = Color3.fromRGB(255, 255, 255)
            mark.Material = Enum.Material.Neon
            mark.Transparency = 0.2
            mark.Parent = footprintFolder

            local tween = TweenService:Create(mark, TweenInfo.new(2.5, Enum.EasingStyle.Quad), {
                Transparency = 1,
                Size = Vector3.new(0.8, 0.05, 0.8),
                Color = Color3.fromRGB(0, 0, 0)
            })
            tween:Play()
            tween.Completed:Connect(function()
                mark:Destroy()
            end)
        end
    end)
    table.insert(auraObjects, footprintConn)
end

local function setAura(state)
    auraEnabled = state
    if state then
        local char = LocalPlayer.Character
        if char then attachAura(char) end
    else
        clearAura()
        clearFootprints()
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    if auraEnabled then attachAura(char) end
end)

-- ============================================
-- Misc 탭
-- ============================================
local MiscBox = MiscTab:AddLeftGroupbox("Movement")

Toggles.EvadeSpeed = MiscBox:AddToggle("EvadeSpeed", {
    Text = "Evade Speed",
    Default = false,
    Callback = function(Value)
        evadeEnabled = Value
        if Value then enableEvade() else disableEvade() end
    end
})

Toggles.Fly = MiscBox:AddToggle("Fly", {
    Text = "Fly",
    Default = false,
    Callback = function(Value)
        flyEnabled = Value
        if Value then startFly() else stopFly() end
    end
})

Toggles.Noclip = MiscBox:AddToggle("Noclip", {
    Text = "Noclip",
    Default = false,
    Callback = function(Value)
        noclipEnabled = Value
        if Value then startNoclip() else stopNoclip() end
    end
})

Toggles.Dash = MiscBox:AddToggle("Dash", {
    Text = "Dash",
    Default = false,
    Callback = function(Value)
        dashEnabled = Value
    end
})

Toggles.WallClimb = MiscBox:AddToggle("WallClimb", {
    Text = "Wall Climb",
    Default = false,
    Callback = function(Value)
        wallClimbEnabled = Value
        if Value then
            startWallClimb()
        else
            stopWallClimb()
        end
    end
})

Toggles.InfiniteJump = MiscBox:AddToggle("InfiniteJump", {
    Text = "Infinite Jump",
    Default = false,
    Callback = function(Value)
        infJumpEnabled = Value
    end
})

Toggles.JumpPowerToggle = MiscBox:AddToggle("JumpPowerToggle", {
    Text = "Jump Power",
    Default = false,
    Callback = function(Value)
        jumpPowerEnabled = Value
        if not Value then
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.JumpPower = 50
            end
        end
    end
})

local FlyBox = MiscTab:AddRightGroupbox("Settings")
Options.FlySpeed = FlyBox:AddSlider("FlySpeed", {
    Text = "Fly Speed",
    Default = 50,
    Min = 10,
    Max = 1000,
    Rounding = 0,
    Callback = function(Value)
        flySpeed = Value
    end
})

Options.DashPower = FlyBox:AddSlider("DashPower", {
    Text = "Dash Power",
    Default = 80,
    Min = 30,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        dashPower = Value
    end
})

Options.JumpPowerSlider = FlyBox:AddSlider("JumpHeight", {
    Text = "Jump Height",
    Default = 50,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(Value)
        customJumpPower = Value
    end
})

-- ============================================
-- Visual 탭 (넥봇 ESP 완전 제거됨)
-- ============================================
local ScreenBox = VisualTab:AddLeftGroupbox("Screen")

Toggles.Stretch = ScreenBox:AddToggle("Stretch", {
    Text = "Stretch",
    Default = false,
    Callback = function(Value)
        stretchEnabled = Value
        if Value then startStretch() else stopStretch() end
    end
})

Toggles.MotionBlur = ScreenBox:AddToggle("MotionBlur", {
    Text = "Motion Blur",
    Default = false,
    Callback = function(Value)
        motionBlurEnabled = Value
        if Value then startMotionBlur() else stopMotionBlur() end
    end
})

Toggles.Aura = ScreenBox:AddToggle("Aura", {
    Text = "Aura",
    Default = false,
    Callback = function(Value)
        setAura(Value)
    end
})

Toggles.FogToggle = ScreenBox:AddToggle("Fog", {
    Text = "Fog",
    Default = false,
    Callback = function(Value)
        fogEnabled = Value
        if Value then startFog() else stopFog() end
    end
})

local AccountBox = VisualTab:AddLeftGroupbox("Account")

Toggles.VisualLevelToggle = AccountBox:AddToggle("VisualLevelToggle", {
    Text = "Level Changer",
    Default = false,
    Callback = function(Value)
        visualLevelEnabled = Value
    end
})

Options.VisualLevelInput = AccountBox:AddInput("VisualLevelInput", {
    Text = "Target Level",
    Default = "999",
    Placeholder = "Enter target level...",
    Callback = function(Value)
        local num = tonumber(Value)
        if num then
            targetVisualLevel = num
        end
    end
})

local BlurBox = VisualTab:AddRightGroupbox("Settings")
Options.BlurIntensity = BlurBox:AddSlider("BlurIntensity", {
    Text = "Blur Intensity",
    Default = 18,
    Min = 5,
    Max = 50,
    Rounding = 0,
    Callback = function(Value)
        motionBlurIntensity = Value
    end
})

-- ============================================
-- Config 탭
-- ============================================
local ConfigBox = ConfigTab:AddLeftGroupbox("Manage Configs")
local folderName = "NeowinConfigs"

pcall(function()
    if not isfolder or not isfolder(folderName) then
        if makefolder then makefolder(folderName) end
    else
        if listfiles and delfile then
            for _, file in ipairs(listfiles(folderName)) do
                local fileName = file:match("[^/\\]+$")
                if fileName ~= "BB.json" and (not fileName:match("%.json$") or fileName:sub(1, 14) == "NeowinConfigs") then
                    pcall(function() delfile(file) end)
                end
            end
        end
    end
end)

local function getConfigFileList()
    local list = {}
    pcall(function()
        if listfiles and isfolder(folderName) then
            for _, file in ipairs(listfiles(folderName)) do
                local fileName = file:match("[^/\\]+$")
                if fileName and fileName:match("%.json$") and fileName ~= "NeowinConfigs" then
                    local name = fileName:gsub("%.json$", "")
                    table.insert(list, name)
                end
            end
        end
    end)
    if #list == 0 then table.insert(list, "BB") end
    return list
end

Options.ConfigNameInput = ConfigBox:AddInput("ConfigNameInput", {
    Text = "Config Name",
    Default = "my_config",
    Placeholder = "Enter config file name..."
})

Options.ConfigDropdown = ConfigBox:AddDropdown("ConfigDropdown", {
    Text = "Select Config",
    Values = getConfigFileList(),
    Default = 1,
    AllowNull = false
})

ConfigBox:AddButton("Create Config", function()
    local name = Options.ConfigNameInput.Value
    if not name or name == "" then return end
    
    pcall(function()
        if not isfolder(folderName) and makefolder then makefolder(folderName) end
    end)
    
    local filePath = folderName .. "/" .. name .. ".json"
    pcall(function()
        if writefile then writefile(filePath, HttpService:JSONEncode({})) end
    end)
    
    Options.ConfigDropdown:SetValues(getConfigFileList())
end)

ConfigBox:AddButton("Save Config", function()
    local selectedConfig = Options.ConfigDropdown.Value
    if not selectedConfig or selectedConfig == "" then return end

    local saveData = {}
    for idx, toggle in pairs(Toggles) do saveData[idx] = toggle.Value end
    for idx, slider in pairs(Options) do
        if idx ~= "ConfigNameInput" and idx ~= "ConfigDropdown" and idx ~= "VisualLevelInput" then 
            saveData[idx] = slider.Value 
        end
    end

    pcall(function()
        if not isfolder(folderName) and makefolder then makefolder(folderName) end
    end)

    local filePath = folderName .. "/" .. selectedConfig .. ".json"
    pcall(function()
        if writefile then writefile(filePath, HttpService:JSONEncode(saveData)) end
    end)
end)

ConfigBox:AddButton("Load Config", function()
    local selectedConfig = Options.ConfigDropdown.Value
    if not selectedConfig or selectedConfig == "" then return end

    local filePath = folderName .. "/" .. selectedConfig .. ".json"
    local decoded = nil
    
    pcall(function()
        if readfile and isfile and isfile(filePath) then
            decoded = HttpService:JSONDecode(readfile(filePath))
        end
    end)

    if type(decoded) == "table" then
        for idx, val in pairs(decoded) do
            if Toggles[idx] then 
                Toggles[idx]:SetValue(val)
            elseif Options[idx] and idx ~= "ConfigNameInput" and idx ~= "ConfigDropdown" and idx ~= "VisualLevelInput" then 
                Options[idx]:SetValue(val) 
            end
        end
    end
end)

ConfigBox:AddButton("Delete Config", function()
    local selectedConfig = Options.ConfigDropdown.Value
    if not selectedConfig or selectedConfig == "" then return end

    local filePath = folderName .. "/" .. selectedConfig .. ".json"
    pcall(function()
        if isfile and isfile(filePath) and delfile then
            delfile(filePath)
        end
    end)
    
    Options.ConfigDropdown:SetValues(getConfigFileList())
end)

ConfigBox:AddButton("Refresh List", function()
    Options.ConfigDropdown:SetValues(getConfigFileList())
end)