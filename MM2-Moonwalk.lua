local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local POOL_SIZE = 150 
local running = true
local targets = {}
local pool = {}

-- ==========================================
-- 0. MASTER MODULE CONFIG MUTATION
-- ==========================================
local gameRequire = getrenv and getrenv().require or require

task.spawn(function()
    pcall(function()
        local charConfig = gameRequire(ReplicatedStorage:WaitForChild("Character"):WaitForChild("Configuration"))
        
        -- Silence footstep pings natively
        charConfig.FootstepWeightMultiplier = 0
        charConfig.SplashWeightMultiplier = 0
        charConfig.MaximumFootstepWeight = 0
        
        -- Native Speed Tweaks (if supported by configuration)
        if charConfig.WalkSpeed then charConfig.WalkSpeed = 24 end
        if charConfig.SprintSpeed then charConfig.SprintSpeed = 36 end
        
        -- Native Survival Tweaks
        charConfig.StaminaDeductionRate = 0
        charConfig.HydrationDeductionRate = 0
        charConfig.SatiationDeductionRate = 0
    end)
end)

-- ==========================================
-- 1. INITIALIZE MATCHA DRAWING POOL
-- ==========================================
for i = 1, POOL_SIZE do
    local box = Drawing.new("Square")
    box.Filled = false
    box.Visible = false

    local tag = Drawing.new("Text")
    tag.Size = 14 
    tag.Center = true
    tag.Outline = true
    tag.Visible = false
    
    pcall(function() tag.Font = Drawing.Fonts.UI end)

    pool[i] = { box = box, tag = tag }
end

-- ==========================================
-- 2. BACKGROUND COLLECTOR (Runs every 0.5s)
-- ==========================================
task.spawn(function()
    while running do
        local out = {}
        local itemsFolder = Workspace:FindFirstChild("_Items")
        local monstersFolder = Workspace:FindFirstChild("_Monsters")

        -- Gather Items
        if itemsFolder then
            for _, obj in ipairs(itemsFolder:GetChildren()) do
                local targetPart = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
                if targetPart then
                    out[#out + 1] = { name = obj.Name, handle = targetPart, type = "Item", model = obj }
                end
            end
        end

        -- Gather Monsters
        if monstersFolder then
            for _, obj in ipairs(monstersFolder:GetChildren()) do
                local targetPart = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
                if targetPart then
                    out[#out + 1] = { name = obj.Name or "Monster", handle = targetPart, type = "Monster", model = obj }
                end
            end
        end

        targets = out
        task.wait(0.5) 
    end
end)

-- ==========================================
-- 3. MATCHA NATIVE RENDERER & GOD MODE
-- ==========================================
RunService.RenderStepped:Connect(function(deltaTime)
    if not running then return end

    -- A. FORCE SURVIVAL VALUES & WEAPON BYPASS
    if LocalPlayer.Character then
        local valuesFolder = LocalPlayer.Character:FindFirstChild("Values")
        
        if valuesFolder then
            local stamina = valuesFolder:FindFirstChild("Stamina")
            if stamina and (stamina:IsA("IntValue") or stamina:IsA("NumberValue")) then stamina.Value = 100 end
            
            local satiation = valuesFolder:FindFirstChild("Satiation")
            if satiation and (satiation:IsA("IntValue") or satiation:IsA("NumberValue")) then satiation.Value = 100 end
            
            local hydration = valuesFolder:FindFirstChild("Hydration")
            if hydration and (hydration:IsA("IntValue") or hydration:IsA("NumberValue")) then hydration.Value = 100 end
            
            local weight = valuesFolder:FindFirstChild("Weight")
            if weight and (weight:IsA("IntValue") or weight:IsA("NumberValue")) then weight.Value = 0 end

            -- Weapon Cooldown Bypass
            local equippedItem = valuesFolder:FindFirstChild("Item")
            if equippedItem and equippedItem.Value then
                local itemValues = equippedItem.Value:FindFirstChild("Values")
                if itemValues then
                    local cd = itemValues:FindFirstChild("Cooldown")
                    local using = itemValues:FindFirstChild("Using")
                    local reloading = itemValues:FindFirstChild("Reloading")
                    
                    if cd then cd.Value = false end
                    if using then using.Value = false end
                    if reloading then reloading.Value = false end
                end
            end
        end
    end

    -- B. RENDER ESP & DYNAMIC THREAT TRACKER
    local list = targets
    local n = 0
    local currentCamera = Workspace.CurrentCamera

    for i = 1, #list do
        if n >= POOL_SIZE then break end

        local t = list[i]
        local handlePart = t.handle

        if handlePart and handlePart.Parent then
            local screenPos, onScreen = WorldToScreen(handlePart.Position)

            if onScreen then
                n = n + 1
                local e = pool[n]
                
                local distance = currentCamera and (currentCamera.CFrame.Position - handlePart.Position).Magnitude or 0
                local height = math.clamp(3500 / (distance == 0 and 1 or distance), 20, 500) 
                local width = height * 0.65

                local color = Color3.fromRGB(255, 255, 255)
                local displayText = string.format("[%s] [%ds]", t.name, math.floor(distance))

                if t.type == "Monster" then
                    local hpText = ""
                    local monsterHumanoid = t.model:FindFirstChild("Humanoid")
                    if monsterHumanoid then
                        if monsterHumanoid.Health <= 0 then
                            n = n - 1 
                            continue 
                        end
                        hpText = string.format(" [HP: %d/%d]", math.floor(monsterHumanoid.Health), math.floor(monsterHumanoid.MaxHealth))
                    end
                    
                    -- Dynamic Mathematical Threat Radius
                    if distance <= 100 then
                        color = Color3.fromRGB(255, 0, 0) -- Aggressive Red: INSIDE SIGHT RADIUS
                        displayText = string.format("[DANGER] %s%s [%ds]", t.name, hpText, math.floor(distance))
                    elseif distance <= 200 then
                        color = Color3.fromRGB(255, 165, 0) -- Orange: INSIDE AMBIENCE/SOUND RADIUS
                        displayText = string.format("[WARNING] %s%s [%ds]", t.name, hpText, math.floor(distance))
                    else
                        color = Color3.fromRGB(255, 255, 0) -- Yellow: Distant/Safe
                        displayText = string.format("[%s]%s [%ds]", t.name, hpText, math.floor(distance))
                    end
                elseif t.type == "Item" then
                    color = Color3.fromRGB(50, 255, 50) -- Vibrant Green for items
                end

                e.box.Color = color
                e.tag.Color = color

                e.box.Size = Vector2.new(width, height)
                e.box.Position = Vector2.new(screenPos.X - (width / 2), screenPos.Y - (height / 2))
                e.box.Visible = true

                e.tag.Text = displayText
                e.tag.Position = Vector2.new(screenPos.X, screenPos.Y - (height / 2) - 18) 
                e.tag.Visible = true
            end
        end
    end

    -- C. CLEANUP UNUSED DRAWINGS
    for i = n + 1, POOL_SIZE do
        if pool[i].box.Visible then
            pool[i].box.Visible = false
            pool[i].tag.Visible = false
        end
    end
end)

notify("Survival God Mode Script Updated!", "Matcha Optimized", 3)
