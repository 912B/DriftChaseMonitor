-- Drift Chase Monitor v6.1 (Debug Path)
-- Server Script compatible

-- 配置
local CONFIG = {
  minDriftAngle = 10, -- 最小漂移角度
  minSpeed = 20,      -- 最小速度
  distPraise = 3.5,   -- TIER 3: 贴贴 (赞扬/阴阳)
  distMock = 20.0,    -- TIER 2: 嘲讽 (中距离)
  distProvoke = 40.0, -- TIER 1: 挑衅 (远距离 - Extended to 40m)
  
  messageLife = 5.0,  -- 消息停留时间

  warmupTime = 2.0,   -- 预热时间 (秒)
  
  messageCooldown = 15.0, -- [New] 消息冷却时间 (秒) - 防止刷屏
  
  enableFaces = true -- [New] 是否启用表情包 (SDK Mode Safe)
}

-- 状态变量
local carPopups = {} -- 每辆车的飘字 {text, age, color, offset}
local particles = {} -- 3D 粒子
local lastMessageTime = {} -- [New] 记录上一次消息触发时间 {pairKey -> time}
local perfectChaseStats = {} -- [New] 完美追走统计 {activeTime, graceTimer}

-- 辅助: 简单哈希函数
local function stringHash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + string.byte(str, i)) % 4294967296
    end
    return h
end

-- 资源配置
local ZIP_URL = "https://hub.rotown.cn/scripts/Images.zip"

-- 图片路径配置 (动态加载)
local FACES_CONFIG = {
    A = nil,
    B = nil,
    C = nil
}
local ASSETS_READY = false

-- 使用 SDK 内置的 loadRemoteAssets 安全加载资源
web.loadRemoteAssets(ZIP_URL, function(err, folder)
    if err then
        ac.log("DriftChaseMonitor: Failed to load assets: " .. tostring(err))
        return
    end
    
    -- folder 是资源解压后的临时目录
    ac.log("DriftChaseMonitor: Assets loaded at " .. folder)
    
    -- Images.zip structure: Images/A.png
    -- We assume the zip structure is maintained.
    -- Manual check: folder .. "/Images/A.png"
    local imgDir = folder .. "/Images"
    
    FACES_CONFIG.A = imgDir .. "/A.png"
    FACES_CONFIG.B = imgDir .. "/B.png"
    FACES_CONFIG.C = imgDir .. "/C.png"
    ASSETS_READY = true
end)

-- 纹理管理器 (Canvas 代理版)
local TextureManager = {
    cache = {}, 
    failedPaths = {} 
}

function TextureManager:get(path)
    if not path then return nil end
    if self.failedPaths[path] then return nil end -- 如果已知失败，直接返回 nil
    
    -- 1. 验证图片尺寸
    local size = ui.imageSize(path)
    if size.x <= 0 then
        -- 尝试 Windows 路径格式
        local winPath = path:gsub("/", "\\")
        size = ui.imageSize(winPath)
        
        if size.x <= 0 then
            -- 仅记录一次错误
            if not self.failedPaths[path] then
                ac.log("Invalid image size (Load failed): " .. path)
                self.failedPaths[path] = true
            end
            return nil 
        end
        path = winPath
    end
    
    -- 2. 直接返回路径 (ui.drawImage 支持路径)
    return path
end

local lastDistances = {}
local chaseTimers = {} 

-- 工具：HSV 转 RGB
local function hsvToRgb(h, s, v, a)
  local r, g, b
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  elseif i == 5 then r, g, b = v, p, q
  end
  return rgbm(r, g, b, a or 1)
end

-- 工具：获取漂移角度
local function getSlipAngle(car)
  local velocity = car.velocity
  local speed = velocity:length()
  if speed < 1 then return 0 end
  
  local forward = car.look
  local vDir = velocity:clone():normalize()
  local dot = math.clamp(forward:dot(vDir), -1, 1)
  return math.deg(math.acos(dot))
end


local MSG_POOL = {
  -- (A) 后车视角 (Chaser -> Leader)
  -- TIER 3: 贴贴 (<3m) - 阴阳/赞扬
  FRONT_TIER3 = {
    "让让弟弟!", "这就是领跑?", "小心屁股！", "贴贴!", "亲一个!",
    "甚至想推你!", "别挡道!", "太近了喂!", "真爱粉!", "胶水做的?",
    "这种距离要怀孕了!", "甚至想帮你推车!", "您是NPC吗?", "这屁股我收下了!"
  },
  -- TIER 2: 嘲讽 (3-10m) - 施压
  FRONT_TIER2 = { 
    "开太慢了!", "在散步?", "给点力啊!", "算了，你自己跑吧", "这速度认真的?",
    "杂鱼杂鱼", "我闭着眼都能追!", "路太宽了吗?", "甚至想按喇叭!",
    "奶奶买菜都比你快!", "您在热身吗?", "倒车都能追!", "你知道油门在哪吗？"
  },
  -- TIER 1: 挑衅 (10-40m) - 远距离
  FRONT_TIER1 = { 
    "快点啊!", "前面有人吗?", "要推头了?", "能不能行?", "我来了!", 
    "小心屁股!", "就在你后面!", "追上来了!", "有种你等我!",
    "前面是安全车吗?", "我要开始认真了!"
  },
  
  -- (B) 前车视角 (Leader -> Chaser)
  -- TIER 3: 贴贴 (<3m) - 惊恐/阴阳
  REAR_TIER3 = { 
    "别亲我屁股!", "杂鱼杂鱼!", "你没有刹车吗?", "太近了喂!", "想同归于尽?", 
    "负距离!", "车漆要蹭掉了!", "真爱粉!", "胶水做的?",
    "甚至想上我的车?", "在此地不要走动!", "这就是你的极限?", "想看我底盘?"
  },
  -- TIER 2: 嘲讽 (3-10m) - 嘲笑
  REAR_TIER2 = { 
    "这就粘上了?", "通过考核!", "想超车吗?", "跟紧点弟弟!", "杂鱼杂鱼!",
    "不仅快还稳!", "这种距离也没谁了!", "你是牛皮糖吗?", "甚至想给你颁奖!",
    "还不赖嘛!", "稍微有点意思!"
  },
  -- TIER 1: 挑衅 (10-40m) - 勾引
  REAR_TIER1 = { 
    "来追我呀!", "闻闻尾气!", "就这点本事?", "靠近点!", "太慢了!", 
    "这就虚了?", "甚至看不到灯!", "油门踩进油箱里!", "我在前面!",
    "看得到我尾灯算我输!", "需要导航吗?", "不仅慢还菜!"
  },
  
  -- LOST (通用)
  LOST = { 
	"迷路了?", "人呢?", "驾照买的?", "我在终点等你", "回家练练吧!",
	"完全跟不住!", "这就放弃了?", "甚至看不到尾灯...", "慢得像蜗牛!",
    "甚至以为你掉线了!", "打个车过来吧!", "回家练练吧!"
  }
}

-- 随机获取文本
local function getRandomMsg(pool)
  return pool[math.random(#pool)]
end

-- [New] 添加 3D 飘字 (绑定到车辆 ID)
local function add3DMessage(carIndex, text, mood)
  local col = rgbm(1, 1, 1, 1)
  if mood == 2 then col = rgbm(1, 0.8, 0, 1) -- Gold
  elseif mood == 1 then col = rgbm(0, 1, 1, 1) -- Cyan
  elseif mood == 3 then col = rgbm(1, 0.2, 0.2, 1) -- Red
  end
  
  carPopups[carIndex] = {
    text = text,
    age = 0,
    color = col,
    offset = vec3(0, 0, 0)
  }
end

-- 活跃的追踪目标 (用于 UI 显示)
local activeTarget = {
    index = -1,
    dist = 0,
    stats = nil
}

-- 主更新逻辑 (Global Loop)
function script.update(dt)
  -- 2. 更新 3D 粒子 (已移除)
  
  -- 3. 更新 3D 飘字
  for idx, popup in pairs(carPopups) do
    popup.age = popup.age + dt
    if popup.age > CONFIG.messageLife then
      carPopups[idx] = nil
    end
  end

  -- 4. 全局漂移追走检测 (N * N)
  local sim = ac.getSim()
  local player = ac.getCar(sim.focusedCar)
  
  -- 重置本帧最佳目标
  local frameBestTarget = nil
  local minFrontDist = 99999
  
  -- 遍历所有可能的追击者 (Chaser)
  for i = 0, sim.carsCount - 1 do 
    local chaser = ac.getCar(i)
    if chaser and chaser.isConnected then
       -- 检查 Chaser 状态
       local chaserSlip = getSlipAngle(chaser)
       local isChaserDrifting = chaserSlip > CONFIG.minDriftAngle and chaser.speedKmh > CONFIG.minSpeed
       
       -- 遍历前车 (Leader)
       for j = 0, sim.carsCount - 1 do 
         if i ~= j then
            local leader = ac.getCar(j)
            if leader and leader.isConnected then
                local rawDist = math.distance(chaser.position, leader.position)
                -- [Refactor] 统一使用补偿后的距离 (减去 2.0m 车宽)
                local dist = math.max(0, rawDist - 2.0)
                
                -- 判断前后关系: Chaser 必须在 Leader 后方/侧后方
                local dirToChaser = (chaser.position - leader.position):normalize()
                local isBehind = leader.look:dot(dirToChaser) < 0.2
                
                -- Key for this pair
                local pairKey = i .. "_" .. j
                
                -- 读取上一帧状态
                local lastTier = lastDistances[pairKey] or 0
                local wasLocked = lastDistances[pairKey .. "_locked"] or false
                local currentTier = 0
                
                local isLeaderDrifting = getSlipAngle(leader) > CONFIG.minDriftAngle
                
                -- 核心判定: Chaser 在飘 + Leader 在飘 + 距离近 + Chaser在后方
                if isChaserDrifting and isLeaderDrifting and isBehind then
                   if dist <= CONFIG.distPraise then
                      currentTier = 3 -- TIER 3: PRAISE
                   elseif dist <= CONFIG.distMock then
                      currentTier = 2 -- TIER 2: MOCK
                   elseif dist <= CONFIG.distProvoke then
                      currentTier = 1 -- TIER 1: PROVOKE
                   end
                end

                -- 预热计时器逻辑 (用于飘字锁定)
                if currentTier > 0 then
                    chaseTimers[pairKey] = (chaseTimers[pairKey] or 0) + dt
                else
                    chaseTimers[pairKey] = 0
                end
                
                local timer = chaseTimers[pairKey]
                local isLocked = timer > CONFIG.warmupTime

                -- 状态检测 & 触发特效 (仅逻辑，不涉及 UI)
                local targetCarIndex = j 
                
                -- A. 刚刚锁定！
                if isLocked and not wasLocked then
                    -- add3DMessage(targetCarIndex, "锁定目标!", 0) 
                end
                
                -- B. 跟丢了！
                if wasLocked and not isLocked then
                     if timer < 0.1 then
                         add3DMessage(targetCarIndex, getRandomMsg(MSG_POOL.LOST), 3)
                     end
                end

                -- C. 升级反馈 & 对话
                if isLocked then
                    if currentTier > lastTier then
                       -- Cooldown Check
                       local now = os.clock()
                       local lastTime = lastMessageTime[pairKey] or -9999
                       
                       if now - lastTime > CONFIG.messageCooldown then
                           lastMessageTime[pairKey] = now
                           -- 对话生成...
                           if math.random() > 0.0 then 
                              local msgTable = MSG_POOL["REAR_TIER" .. currentTier]
                              if msgTable then add3DMessage(j, getRandomMsg(msgTable), currentTier) end
                           end
                           if math.random() > 0.3 then 
                              local msgTable = MSG_POOL["FRONT_TIER" .. currentTier]
                              if msgTable then add3DMessage(i, getRandomMsg(msgTable), currentTier) end
                           end
                       end
                    end
                end

                lastDistances[pairKey] = currentTier
                lastDistances[pairKey .. "_locked"] = isLocked
                
                -- [MERGED] 玩家专属逻辑: 完美追走 & 进度条目标查找
                -- 如果当前 Chaser 是玩家，计算完美追走数据并寻找最佳目标
                if i == sim.focusedCar then
                    -- 完美追走计时 (Perfect Chase Stats)
                    local stats = perfectChaseStats[pairKey] or { activeTime = 0, graceTimer = 0 }
                    local realDt = ac.getDeltaT()
                    
                    if dist < CONFIG.distPraise then
                         -- Perfect Chase (1.0x)
                         stats.graceTimer = 0
                         stats.activeTime = stats.activeTime + realDt
                    elseif dist < CONFIG.distMock then
                         -- Normal Chase (0.2x) - Maintains combo, slow gain
                         stats.graceTimer = 0
                         stats.activeTime = stats.activeTime + (realDt * 0.2)
                    else
                         -- Lost Chase
                         stats.graceTimer = stats.graceTimer + realDt
                         -- Grace period 1.0s
                         if stats.graceTimer > 1.0 then stats.activeTime = 0 end
                    end
                    perfectChaseStats[pairKey] = stats
                    
                    -- 寻找最佳 UI 目标 (最近的有效目标)
                    -- 条件：都在漂移，且距离在显示范围内 (45m)，且在玩家前方
                    -- 注意: 这里复用 loop 中的 isChaserDrifting, isLeaderDrifting
                    -- 但需要额外的 dot check 确保在我们前方 (UI 显示用)
                    local playerLookDot = player.look:dot( (leader.position - chaser.position):normalize() )
                    
                    if isChaserDrifting and isLeaderDrifting and playerLookDot > 0.5 and rawDist < 45.0 then
                        -- 距离修正 (UI用)
                        if dist < minFrontDist then
                            minFrontDist = dist
                            frameBestTarget = {
                                index = j,
                                dist = dist,
                                stats = stats,
                                isLocked = isLocked
                            }
                        end
                    end
                end
            end
         end
       end
    end
  end
  
  -- 更新全局状态供 drawUI 使用
  if frameBestTarget then
      activeTarget = frameBestTarget
  else
      -- 如果这一帧没有目标，快速重置(或保留上一帧? 还是重置吧以免UI卡住)
      activeTarget = { index = -1, dist = 0, stats = nil }
  end
end

-- 2D UI 绘制 (包含 Face 表情包 和 距离进度条)
function script.drawUI(dt)
  if not CONFIG.enableFaces then return end

  local uiState = ac.getUI()
  local windowSize = uiState.windowSize
  
  -- [NEW] 绘制表情包 (2D Overlay)
  ui.beginTransparentWindow("FaceOverlay", vec2(0,0), windowSize)
  
  local sim = ac.getSim()
  local player = ac.getCar(sim.focusedCar)
  
  -- 1. 表情包逻辑 (Face Logic) -- 独立逻辑，保留遍历
  if player then
      for i = 0, sim.carsCount - 1 do
           local car = ac.getCar(i)
           if car and car.isConnected and i ~= sim.focusedCar then
               local dist = math.distance(car.position, player.position)
               if dist < 60 then
                   local faceUrl = FACES_CONFIG.A
                   if dist < 5.0 then faceUrl = FACES_CONFIG.C
                   elseif dist < 15.0 then faceUrl = FACES_CONFIG.B
                   end
                   
                   local headPos = car.position + vec3(0, 2.5, 0) 
                   local proj = render.projectPoint(headPos)
                   
                   if proj.x > -0.2 and proj.x < 1.2 and proj.y > -0.2 and proj.y < 1.2 then
                        local screenPos = vec2(proj.x * windowSize.x, proj.y * windowSize.y)
                        local scale = math.clamp(40 / math.max(1, dist), 0.5, 3.0) 
                        local baseSize = 45 
                        local sizePx = baseSize * scale
                        sizePx = math.clamp(sizePx, 25, 180) 
                        local size2D = vec2(sizePx, sizePx)
                        local pos2D = screenPos - size2D * 0.5
                        
                        local facePath = TextureManager:get(faceUrl)
                        if facePath then
                             local distAlpha = math.clamp(1 - (dist - 40)/20, 0, 1)
                             if distAlpha > 0.05 then
                                 local col = rgbm(1,1,1, distAlpha)
                                 ui.drawImage(facePath, pos2D, pos2D + size2D, col)
                                 local center = pos2D + size2D * 0.5
                                 local radius = sizePx * 0.6 
                                 ui.drawCircle(center, radius, col, 2.0)
                             end
                        end
                   end
               end
           end
      end
  end
  
  -- 2. 距离进度条逻辑 (使用 update 计算好的 activeTarget)
  if activeTarget.index ~= -1 and player then
      local targetCar = ac.getCar(activeTarget.index)
      if targetCar then
          local dist = activeTarget.dist
          local headPos = targetCar.position + vec3(0, 1.4, 0)
          local proj = render.projectPoint(headPos)
          
          if proj.x > -0.2 and proj.x < 1.2 and proj.y > -0.2 and proj.y < 1.2 then
              local screenPos = vec2(proj.x * windowSize.x, proj.y * windowSize.y)
              
              -- Bar Config
              local barWidth = 140
              local barHeight = 8
              local barPos = screenPos - vec2(barWidth / 2, 0)
              
              -- Progress
              local progress = 1.0 - math.clamp(dist / 45.0, 0, 1)

              -- Perfect Chase Timer
              local stats = activeTarget.stats
              local isPerfect = stats and (stats.activeTime >= 1.0) or false
              local activeTime = stats and stats.activeTime or 0

              -- Draw Bar
              local barColor = isPerfect and rgbm(1, 0.84, 0, 1) or rgbm(0, 1, 0, 0.9)
              
              ui.drawRectFilled(barPos, barPos + vec2(barWidth, barHeight), rgbm(0, 0, 0, 0.5), 2)
              local fillW = barWidth * progress
              if fillW > 2 then
                  ui.drawRectFilled(barPos, barPos + vec2(fillW, barHeight), barColor, 2)
              end
              
              -- Star Rating System (Replaces Timer)
              if activeTime > 0.0 then
                   local STAR_Count = 5
                   local TIME_Per_Star = 1.0
                   local CYCLE_Time = STAR_Count * TIME_Per_Star
                   
                   local cycle = math.floor(activeTime / CYCLE_Time)
                   local localTime = activeTime % CYCLE_Time
                   local activeStarIndex = math.floor(localTime / TIME_Per_Star) + 1 -- 1 to 5
                   local activeStarProgress = (localTime % TIME_Per_Star) / TIME_Per_Star
                   
                   -- Color Palette
                   local colors = {
                       rgbm(0.2, 0.2, 0.2, 0.5), -- Base (Gray)
                       rgbm(1, 0.84, 0, 1),      -- Lvl 1: Yellow
                       rgbm(1, 0.2, 0, 1),       -- Lvl 2: Red
                       rgbm(0.8, 0, 1, 1),       -- Lvl 3: Purple
                       rgbm(0, 1, 1, 1)          -- Lvl 4: Cyan
                   }
                   
                   local baseCol = colors[math.min(cycle + 1, #colors)]     -- Current Cycle Background
                   local fillCol = colors[math.min(cycle + 2, #colors)]     -- Filling Color
                   
                   -- If max level reached, just flash
                   if cycle >= (#colors - 2) then
                       baseCol = colors[#colors]
                       fillCol = rgbm(1, 1, 1, 1) -- Flash White
                   end

                   ui.pushFont(ui.Font.Title) -- Large stars
                   local starStr = "★"
                   local starSize = ui.measureText(starStr)
                   local spacing = 5
                   local totalWidth = (starSize.x + spacing) * STAR_Count
                   local startX = barPos.x + (barWidth - totalWidth) / 2
                   local startY = barPos.y - 45 -- Above bar
                   
                   for s = 1, STAR_Count do
                       local sPos = vec2(startX + (s-1) * (starSize.x + spacing), startY)
                       local col = baseCol
                       local scale = 1.0
                       
                       if s < activeStarIndex then
                           -- Already filled
                           col = fillCol
                       elseif s == activeStarIndex then
                           -- Currently filling (Pulse size + Lerp Color)
                           local t = activeStarProgress
                           -- Lerp color
                           col = vec4(
                               baseCol.r + (fillCol.r - baseCol.r) * t,
                               baseCol.g + (fillCol.g - baseCol.g) * t,
                               baseCol.b + (fillCol.b - baseCol.b) * t,
                               1 -- Alpha always 1 for active
                           )
                           -- Pulse size
                           scale = 1.0 + 0.3 * math.sin(t * 3.14)
                       else
                           -- Not yet reached
                           col = baseCol
                       end
                       
                       ui.setCursor(sPos)
                       -- Optional: Scale adjustment needs offset correction, simplified for now
                       -- Text scale via window font scale is global, tricky. 
                       -- Just use color lerp for smoothness.
                       ui.textColored(starStr, col)
                   end
                   ui.popFont()
              end
              

          end
      end
  end

  ui.endTransparentWindow()
end

-- 3D 绘制 (仅保留粒子效果)
-- 3D 绘制 (仅保留文字气泡)
function script.draw3D(dt)
  -- 保留 "Car Popups" (文字气泡)
  local sim = ac.getSim()
  local player = ac.getCar(sim.focusedCar)
  if not player then return end

  for i = 0, sim.carsCount - 1 do
    local popup = carPopups[i]
    if popup then
       local car = ac.getCar(i)
       if car then
         local dist = math.distance(player.position, car.position)
         local distAlpha = math.clamp(1 - (dist - 40)/20, 0, 1)
         
         if distAlpha > 0.05 then
            local alpha = math.min(1, CONFIG.messageLife - popup.age)
            if alpha > 0.05 then
                 -- Animation
                 local riseDuration = 2.0
                 local t_rise = math.min(1, popup.age / riseDuration) 
                 local currentHeight = 2.2 * t_rise
                 
                 -- Pop
                 local t_pop = math.min(1, popup.age * 2.0)
                 local popScale = 1 + 2.7 * math.pow(t_pop - 1, 3) + 1.7 * math.pow(t_pop - 1, 2)
                 if t_pop>=1 then popScale = 1 end
                 
                 -- Pos (Base 1.2m)
                 local textBasePos = car.position + vec3(0, 1.2, 0)
                 local currentDist = 2.0 * t_rise
                 local bubblePos = textBasePos + car.look * currentDist + vec3(0, currentHeight, 0)
                 
                 -- Render
                 local finalAlpha = alpha * distAlpha
                 render.debugText(bubblePos, popup.text, rgbm(1,1,1, finalAlpha), 3.0 * popScale)
            end
         end
       end
    end
  end
end
