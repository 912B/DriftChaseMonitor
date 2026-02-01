-- Drift Chase Monitor v6.3
-- Server Script compatible


-- 配置
local CONFIG = {
  minDriftAngle = 10, -- 最小漂移角度
  minSpeed = 20,      -- 最小速度
  distPraise = 2,   -- TIER 3: 贴贴 (赞扬/阴阳)
  distNormal = 5.0,   -- Normal Chase Range (Accumulates slowly)
  distMock = 10.0,    -- TIER 2: 嘲讽 (Synced with Scoring Range)
  distProvoke = 40.0, -- TIER 1: 挑衅 (Scope for Danmaku Logic)
  
  maxAngleDiff = 35, -- [New] 最大角度差 (超过此值不积分) - Relaxed from 20 to 35 for better feel
  starDuration = 1.0, -- [New] 单颗星星所需时间 (秒) -> User requested harder, let's keep 1.0 logic first but multiplier controls it? 
  -- No, let's set base duration. User said "Too simple", slowing it down is good.
  -- Let's set it to 2.0s per star in logic.
  
  messageLife = 5.0,  -- 消息停留时间

  warmupTime = 2.0,   -- 预热时间 (秒)
  
  messageCooldown = 15.0, -- [New] 消息冷却时间 (秒) - 防止刷屏
  
  driftGraceTime = 0.5, -- [New] 漂移状态维持时间 (秒) - 解决折身时角度归零导致中断的问题
}



-- [New] Grade Colors (Global)
local GRADE_COLOR_NAMES = { "White", "Blue", "Green", "Gold", "Purple" }
local GRADE_DISPLAY_MAP = { White="白", Blue="蓝", Green="绿", Gold="金", Purple="紫" }
local GRADE_COLORS = {
    rgbm(1, 1, 1, 1),         -- Lvl 1: White
    rgbm(0, 0.6, 1, 1),       -- Lvl 2: Blue
    rgbm(0, 1, 0, 1),         -- Lvl 3: Green
    rgbm(1, 0.84, 0, 1),      -- Lvl 4: Gold
    rgbm(0.8, 0, 1, 1)        -- Lvl 5: Purple
}

-- [Helper] Get star color (includes gray base for empty stars)
local function getStarColor(index)
    if index == 0 then
        return rgbm(0.2, 0.2, 0.2, 0.5) -- Gray base
    else
        return GRADE_COLORS[index]
    end
end

-- [New] 弹幕配置 (Danmaku Config) - Adjusted for 3D World Space (Appears as HUD)
local DANMAKU_CONFIG = {
    -- World Units (Meters)
    depth = 8.0,      -- Distance in front of camera
    width = 12.0,     -- Virtual screen width (Meters) at depth
    height = 6.0,     -- Virtual screen height (Meters)
    
    speed = 0.25,      -- Meters per second (Limit max speed for readability)
    life = 60.0,      -- Extended life for very slow speed
    
    fontSize = 2.5,   -- Scale Factor for render.debugText (2.0 - 3.0 is large)
    lineHeight = 1.2, -- Vertical spacing in meters 
    maxLines = 5,     -- Fewer lines but bigger
    
    opacity = 1.0,    -- Opacity
}
local DANMAKU_POOL = {}

-- ... (Status Vars remain) ...

local function addDanmaku(text, color)
    -- Randomize line (Slot 0 to maxLines-1)
    local lineIdx = math.random(0, DANMAKU_CONFIG.maxLines - 1)
    
    -- Jitter speed
    local speed = DANMAKU_CONFIG.speed + math.random() * 1.0
    
    table.insert(DANMAKU_POOL, {
        text = text,
        -- Start at Right edge (+Width/2) with slight random delay offset
        x = (DANMAKU_CONFIG.width / 2) + math.random(0, 2), 
        -- Top-down layout: Start from top (+Height/2) and go down
        y = (DANMAKU_CONFIG.height / 3) - (lineIdx * DANMAKU_CONFIG.lineHeight), 
        speed = speed,
        color = color or rgbm(0.4, 0.4, 0.4, 1),
    })
end

local function updateAndDrawDanmaku(dt)
    -- [Fix] Fallback if dt is nil
    dt = dt or ac.getDeltaT()
    
    -- 1. Get Camera Basis (World Space)
    local camPos = ac.getCameraPosition()
    local camLook = ac.getCameraForward()
    local camUp = ac.getCameraUp()
    local camSide = ac.getCameraSide() -- Right vector
    
    -- Calculate Center of Virtual Screen
    -- Center = CamPos + Look * Depth
    local screenCenter = camPos + camLook * DANMAKU_CONFIG.depth
    
    for i = #DANMAKU_POOL, 1, -1 do
        local item = DANMAKU_POOL[i]
        
        -- Update Pos (Move Left: decrease x)
        item.x = item.x - item.speed * dt
        
        -- Calculate 3D World Position for this text
        -- Use standard basis: Right * x + Up * y
        local textPos = screenCenter + (camSide * item.x) + (camUp * item.y)
        
        -- Draw directly in 3D (No UI loop needed)
        render.debugText(textPos, item.text, item.color, DANMAKU_CONFIG.fontSize)
        
        -- Cleanup if off-screen (Left edge is -Width/2)
        if item.x < -(DANMAKU_CONFIG.width / 2) - 5 then 
            table.remove(DANMAKU_POOL, i)
        end
    end
end
local lastMessageTime = {} -- [New] 记录上一次消息触发时间 {pairKey -> time}
local perfectChaseStats = {} -- [New] 完美追走统计 {activeTime, graceTimer}
local driftTimers = {} -- [New] 漂移断开计时器 (Grace Logic)

-- (Face Assets Removed)
local lastDistances = {}
local chaseTimers = {} 

-- [New] Overhead Messages System
local overheadMessages = {} -- Key: carIndex, Value: { text, color, age, duration }

local function addOverheadMessage(carIndex, text, color)
    overheadMessages[carIndex] = {
        text = text,
        color = color,
        age = 0,
        duration = CONFIG.messageLife
    }
end

local function updateAndDrawOverhead(dt)
    dt = dt or ac.getDeltaT()
    local sim = ac.getSim()
    local camPos = ac.getCameraPosition()
    
    for carIndex, msg in pairs(overheadMessages) do
        msg.age = msg.age + dt
        if msg.age > msg.duration then
            overheadMessages[carIndex] = nil
        else
            local car = ac.getCar(carIndex)
            if car then
                -- Position: Above Car + slight bobbing or rise?
                -- Just static overhead for readability
                local headPos = car.position + vec3(0, 1.8, 0) 
                
                -- Fade out
                local alpha = 1.0
                if msg.age > (msg.duration - 1.0) then
                    alpha = (msg.duration - msg.age)
                end
                
                -- Scale by distance? render.debugText handles perspective, 
                -- but we might want it slightly larger.
                local dist = (headPos - camPos):length()
                local scale = math.clamp(50.0 / dist, 1.0, 3.0) 
                -- Logic: close = 1.0, far = 3.0? No, debugText shrinks with distance.
                -- We want to counteract shrinking slightly or just let it be?
                -- render.debugText(pos, text, color, scale)
                -- Standard scale 1.0 is fine for debugText usually.
                
                msg.color.mult = alpha -- Apply fade
                
                render.debugText(headPos, msg.text, msg.color, 1.2)
            end
        end
    end
end 

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
    "这种距离要怀孕了!", "甚至想帮你推车!", "您是NPC吗?", "这屁股我收下了!",
    "还没断奶吗?", "回家喝奶去吧!", "这种水平也敢领跑?", "是不是在梦游?"
  },
  -- TIER 2: 嘲讽 (3-10m) - 施压
  FRONT_TIER2 = { 
    "开太慢了!", "在散步?", "给点力啊!", "算了，你自己跑吧", "这速度认真的?",
    "杂鱼杂鱼", "我闭着眼都能追!", "路太宽了吗?", "甚至想按喇叭!",
    "奶奶买菜都比你快!", "您在热身吗?", "倒车都能追!", "你知道油门在哪吗？",
    "轮椅都比你快!", "驾照是买的吗?", "前面是红灯吗?", "是不是没加油?"
  },
  -- TIER 1: 挑衅 (10-40m) - 远距离
  FRONT_TIER1 = { 
    "快点啊!", "前面有人吗?", "要推头了?", "能不能行?", "我来了!", 
    "小心屁股!", "就在你后面!", "追上来了!", "有种你等我!",
    "前面是安全车吗?", "我要开始认真了!", "准备好被超车了吗?", "别以为能跑掉!"
  },
  
  -- (B) 前车视角 (Leader -> Chaser)
  -- TIER 3: 贴贴 (<3m) - 惊恐/阴阳
  REAR_TIER3 = { 
    "别亲我屁股!", "杂鱼杂鱼!", "你没有刹车吗?", "太近了喂!", "想同归于尽?", 
    "负距离!", "车漆要蹭掉了!", "真爱粉!", "胶水做的?",
    "甚至想上我的车?", "在此地不要走动!", "这就是你的极限?", "想看我底盘?",
    "想当我的挂件吗?", "别爱我没结果!", "是不是想碰瓷?", "保持社交距离!"
  },
  -- TIER 2: 嘲讽 (3-10m) - 嘲笑
  REAR_TIER2 = { 
    "这就粘上了?", "通过考核!", "想超车吗?", "跟紧点弟弟!", "杂鱼杂鱼!",
    "不仅快还稳!", "这种距离也没谁了!", "你是牛皮糖吗?", "甚至想给你颁奖!",
    "还不赖嘛!", "稍微有点意思!", "别跟丢了哦!", "吃我尾气吧!", "只能看到尾灯吗?"
  },
  -- TIER 1: 挑衅 (10-40m) - 勾引
  REAR_TIER1 = { 
    "来追我呀!", "闻闻尾气!", "就这点本事?", "靠近点!", "太慢了!", 
    "这就虚了?", "甚至看不到灯!", "油门踩进油箱里!", "我在前面!",
    "看得到我尾灯算我输!", "需要导航吗?", "不仅慢还菜!", "是不是迷路了?", "我在终点等你!"
  },
  
  -- LOST (通用)
  LOST = { 
    "迷路了?", "人呢?", "驾照买的?", "我在终点等你", "回家练练吧!",
    "完全跟不住!", "这就放弃了?", "甚至看不到尾灯...", "慢得像蜗牛!",
    "甚至以为你掉线了!", "打个车过来吧!", "回家练练吧!", "是不是睡着了?",
    "完全是两个世界的车!", "甚至连影子都看不到了!", "再练个十年吧!"
  }
}

-- 随机获取文本
local function getRandomMsg(pool)
  return pool[math.random(#pool)]
end

-- [New] 添加 3D 飘字 -> 改为发送到 3D 弹幕 (Redirect to Danmaku)
local function add3DMessage(carIndex, text, mood)
  -- [Fix] Reduce brightness Drastically to avoid "Glow/Bloom"
  -- Night Mode Safe: Values around 0.3 - 0.4
  local col = rgbm(0.4, 0.4, 0.4, 1)
  if mood == 2 then col = rgbm(0.4, 0.3, 0, 1) -- Gold (Dimmed)
  elseif mood == 1 then col = rgbm(0, 0.4, 0.4, 1) -- Cyan (Dimmed)
  elseif mood == 3 then col = rgbm(0.4, 0.15, 0.15, 1) -- Red (Dimmed)
  elseif mood == 4 then col = rgbm(0, 0.4, 0, 1)   -- Green (Chat - Dimmed)
  end
  
  -- Append Driver Name if possible
  local car = ac.getCar(carIndex)
  local name = "Car " .. carIndex
  
  if car then
      -- [New] Distance Filter: Only show danmaku if car is within interaction range (Provoke Range)
      -- This avoids spam from distant battles.
      local sim = ac.getSim()
      local focusPos = ac.getCar(sim.focusedCar).position
      if math.distance(car.position, focusPos) > CONFIG.distProvoke then return end

      -- [Fix] Manual Depth Check because render.projectPoint returns vec2
      local headPos = car.position + vec3(0, 1.0, 0) -- [Restore] Define headPos first
      local camPos = ac.getCameraPosition()
      local camForward = ac.getCameraForward()
      local toTarget = headPos - camPos
      local distanceInFront = toTarget:dot(camForward)
      local isInFront = distanceInFront > 0.5 -- At least 0.5m in front
      
      -- For overhead, we still probably want to avoid generating if totally behind, 
      -- but strictly "onScreen" check is less critical since render.debugText handles clipping.
      -- Keeping the logic to prevent spam processing for invisible cars is good.
      if not isInFront then return end

      -- Note: Removed name prefix as position identifies the car
  end
  
  -- [Visual] Overhead Message (Taunt)
  addOverheadMessage(carIndex, text, col)
end

-- 活跃的追踪目标 (用于 UI 显示)
local activeTarget = {
    index = -1,
    dist = 0,
    stats = nil
}

-- Helper: Get Chase Grade (Color, Stars) from Time
local function getChaseGrade(seconds)
    local CYCLE_Time = 5.0
    local cycle = math.floor(seconds / CYCLE_Time)
    
    local colorIdx = math.clamp(cycle + 1, 1, #GRADE_COLOR_NAMES)
    local colorKey = GRADE_COLOR_NAMES[colorIdx]
    
    -- Stars (0-4 per cycle)
    local cycleStars = math.floor(seconds % 5)

    -- Return standardized grade object
    return {
        key = colorKey,
        name = GRADE_DISPLAY_MAP[colorKey] or "白",
        color = GRADE_COLORS[colorIdx],
        stars = cycleStars,
        cycle = cycle,
        totalStars = math.floor(seconds)
    }
end

-- [New] Report Score Helper
local function reportScore(scoreTime, realTime, leaderIndex)
   -- [Refined] Only report Blue Star or above (> 5s score time)
   if scoreTime < 5.0 then return end
   
   -- Security Check: 
   -- 1. Spectator: Don't send chat if I am just watching.
   -- 2. Replay: Don't send chat in replay.
   local sim = ac.getSim()
   local focusCar = ac.getCar(sim.focusedCar)
   
   -- [Fix] carIndex might be missing. Use isRemote (true for network cars) to detect spectator mode.
   -- If car is remote, it's not us -> return.
   if not focusCar or focusCar.isRemote then return end

   -- [New] Sarcastic Comments for Results (Player Boasting/Excuses) -> [Refined] Tsuiso Style (Sync & Proximity)
   local RESULT_COMMENTS = {
       White = { "完全跟不住啊!", "这是在画龙吗?", "刚才网卡了...", "被套圈了...", "这领跑太飘忽了!", "轮胎没热!", "差点睡着了..." },
       Blue = { "刚才节奏乱了...", "距离感失灵了!", "勉强能看到尾灯!", "差点被甩掉!", "这图太滑了!", "刚才手滑了一下!", "还没有进入状态!" },
       Green = { "勉强跟住了!", "节奏还行!", "下次贴更近!", "普通发挥!", "稍微认真了一点!", "一般般吧!", "还可以更近!" },
       Gold = { "这就叫贴贴!", "咬得死死的!", "节奏完美!", "别想逃出我的掌心!", "后视镜里全是我!", "这就叫追走!", "不仅快还稳!" },
       Purple = { "我是你的影子!", "胶水做的车!", "完全同步!", "想甩掉我？没门!", "窒息般的压迫感!", "你的动作我都会!", "请叫我复制忍者!" }
   }

   -- Calc Logic (Sync with Draw)
   local grade = getChaseGrade(scoreTime)
   
   -- [New] Pick random sarcastic comment
   local comments = RESULT_COMMENTS[grade.key] or RESULT_COMMENTS.White
   local comment = comments[math.random(#comments)]
   
   -- Build Message
   -- [Refined] Only show Score Time (积分总时长)
   -- [Refined] Only show Score Time (积分总时长)
   local msg = string.format("追走结算: %s色 %d 星 (积分:%.1fs) | %s", grade.name, grade.stars, scoreTime, comment)
   
   -- [Security] Protected call - some servers may block ac.sendChatMessage
   local success, err = pcall(function()
       ac.sendChatMessage(msg)
   end)
   if not success then
       ac.log("DriftChase: Failed to send chat message (server may have disabled it): " .. tostring(err))
   end
   
   -- [New] Display Result on Leader's Roof (Overhead)
   if leaderIndex then
       -- Short format for overhead: "[*] 5 Stars (Purple) | Nice!"
       local shortMsg = string.format("[*] %d 星 (%s) | %s", grade.stars, grade.name, comment)
       addOverheadMessage(leaderIndex, shortMsg, grade.color)
   end
end

-- [New] Scoring Helper Function
-- Encapsulates Geometric Difficulty & Distance Logic
local function calculateScoreGain(currentActiveTime, dist, realDt)
    -- Levels based on 5-second intervals (5 stars per level if base is 1s)
    local currentLevel = math.floor(currentActiveTime / 5)
    
    -- Geometric Penalty: 5^Level
    -- Level 0 (0-5s):   1.0
    -- Level 1 (5-10s):  0.2   (1/5)
    -- Level 2 (10-15s): 0.04  (1/25)
    -- Level 3 (15-20s): 0.008 (1/125)
    local levelPenalty = 1.0 / math.pow(5.0, currentLevel)
    
    local scoreGain = 0
    
    if dist < CONFIG.distPraise then
        -- Perfect Zone (<3.5m): Base 1.0 (1s real = 1s score)
        scoreGain = realDt * 1.0 * levelPenalty
    elseif dist < CONFIG.distNormal then
        -- Normal Zone (3.5-10m): Base 0.2 (5s real = 1s score)
        scoreGain = realDt * 0.2 * levelPenalty
    end
    
    return scoreGain
end

-- 主更新逻辑 (Global Loop)
function script.update(dt)
  local realDt = ac.getDeltaT() -- [Fix] Define realDt for global use
  local updatedStats = {} -- [Fix] Track focused car stats updates for cleanup
  -- 2. 更新 3D 粒子 (已移除)
  
  -- 3. 更新 3D 飘字 (已重定向到弹幕，此处移除)


  -- 4. 全局漂移追走检测 (N * N)
  local sim = ac.getSim()
  local player = ac.getCar(sim.focusedCar)
  
  -- [New] 预计算所有车辆的漂移状态 (处理 Hysteresis)
  local driftStates = {}
  for i = 0, sim.carsCount - 1 do
      local car = ac.getCar(i)
      if car and car.isConnected then
          local slip = getSlipAngle(car)
          local isRawDrifting = slip > CONFIG.minDriftAngle and car.speedKmh > CONFIG.minSpeed
          
          if isRawDrifting then
              driftTimers[i] = 0
          else
              driftTimers[i] = (driftTimers[i] or 0) + realDt
          end
          
          -- 只要 grace timer 在允许范围内，就认为还在漂移 (即使 switch 中)
          driftStates[i] = driftTimers[i] < CONFIG.driftGraceTime
      else
          driftStates[i] = false
      end
  end

  -- 重置本帧最佳目标
  local frameBestTarget = nil
  local minFrontDist = 99999
  
  -- 遍历所有可能的追击者 (Chaser)
  for i = 0, sim.carsCount - 1 do 
    local chaser = ac.getCar(i)
    if chaser and chaser.isConnected then
       -- 检查 Chaser 状态
       local chaserSlip = getSlipAngle(chaser) -- (Still needed for angleDiff)
       local isChaserDrifting = driftStates[i]
       
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
                
                -- Use cached drift state
                local isLeaderDrifting = driftStates[j]
                
                -- [Fix] Speed Check: 
                -- Must be moving faster than minSpeed (20km/h) to count as chase
                -- Avoids parked cars triggering "Good Chase"
                local chaserSpeed = chaser.velocity:length() * 3.6
                local leaderSpeed = leader.velocity:length() * 3.6
                local isMovingFastEnough = (chaserSpeed > CONFIG.minSpeed) and (leaderSpeed > CONFIG.minSpeed)
                
                -- [Fix] Calculate Angle Info HERE so it is available for both blocks
                local leaderSlip = getSlipAngle(leader)
                local angleDiff = math.abs(chaserSlip - leaderSlip)
                local isAngleGood = angleDiff < CONFIG.maxAngleDiff
                
                if isChaserDrifting and isLeaderDrifting and isBehind and isMovingFastEnough then
                       -- [New] 角度一致性检查
                       -- 必须动作同步才能得分 (防止瞎蹭)
                       
                       -- 基础得分为 0
                       local scoreGain = 0
                       
                       if isAngleGood then
                           if dist < CONFIG.distPraise then
                              -- Perfect Zone: 0.2x points (1 star = 5 seconds)
                              currentTier = 3
                              scoreGain = realDt * 0.2 
                           elseif dist < CONFIG.distNormal then
                              -- Normal Zone: 0.04x points (1 star = 25 seconds)
                              currentTier = 2 
                              scoreGain = realDt * 0.04
                           elseif dist < CONFIG.distMock then
                               currentTier = 2
                           elseif dist <= CONFIG.distProvoke then
                               currentTier = 1
                           end
                       else
                           -- 角度差太大，不得分 (但如果在范围内，维持Tier状态用于显示?)
                           -- 暂时降级处理
                           if dist < CONFIG.distMock then currentTier = 2 end
                       end
                       
                       -- 更新 Stats (Global)
                       -- 注意: 这里复用了 update loop 里的 stats 更新
                       -- 但 Stats 是在下面 "if i == focusedCar" 专属块里更新的
                       -- 所以这里只负责 Tier 更新 (用于 3D 文字)
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
                -- A. 刚刚锁定！
                -- (已注释)

                -- B. 跟丢了！
                if wasLocked and not isLocked then
                     -- only trigger if we actually had a lock for a bit
                     if timer < 0.1 then
                         add3DMessage(j, getRandomMsg(MSG_POOL.LOST), 3)
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
                           -- 70% 概率触发前车嘲讽
                           if math.random() > 0.3 then 
                              local msgTable = MSG_POOL["REAR_TIER" .. currentTier]
                              -- add3DMessage(TargetCarIndex, Text, Mood)
                              if msgTable then add3DMessage(j, getRandomMsg(msgTable), currentTier) end
                           end
                           -- 30% 概率触发后车心里话 (Optional, 也可以都触发)
                           if math.random() > 0.7 then 
                               -- Front Tier messages are for chaser
                              local msgTable = MSG_POOL["FRONT_TIER" .. currentTier]
                               -- add3DMessage(ChaserIndex, Text, Mood)
                              if msgTable then add3DMessage(i, getRandomMsg(msgTable), currentTier) end
                           end
                       end
                    end
                end

                lastDistances[pairKey] = currentTier
                lastDistances[pairKey .. "_locked"] = isLocked
                
                -- [MERGED] 玩家专属逻辑: 完美追走
                if i == sim.focusedCar then
                    local stats = perfectChaseStats[pairKey] or { activeTime = 0, realTime = 0, graceTimer = 0 }
                    -- [Fix] Reset display flag each frame so it doesn't stick
                    stats.isDisplayed = false
                    
                    if isAngleGood then
                        -- Calculate Score using Helper
                        local gain = calculateScoreGain(stats.activeTime, dist, realDt)
                        
                        if gain > 0 then
                             -- Scoring (Praise or Normal)
                             stats.graceTimer = 0
                             stats.activeTime = stats.activeTime + gain
                             stats.realTime = stats.realTime + realDt
                        elseif dist < CONFIG.distMock then
                             -- In Mock Range (5m - 10m): No Score, but MAINTAIN chase
                             -- Same behavior as "Bad Angle" in range -> Pause Decay
                             stats.graceTimer = 0
                             stats.realTime = stats.realTime + realDt
                        else
                             -- Lost Chase (Dist > Mock)
                             stats.graceTimer = stats.graceTimer + realDt
                             if stats.graceTimer > 1.0 then 
                                 reportScore(stats.activeTime, stats.realTime, j) -- [New] Report with Leader Index
                                 stats.activeTime = 0 
                                 stats.realTime = 0
                             end
                        end

                    else
                         -- Bad Angle (角度不对)
                         if dist < CONFIG.distMock then
                             -- [New] Range OK (Wide) but Angle Bad -> PAUSE
                             -- 只要在 20m 内 (可视范围)，角度不对只暂停，不断连
                             stats.graceTimer = 0
                         else
                             -- Range Bad -> DECAY (Lost Chase)
                             stats.graceTimer = stats.graceTimer + realDt
                             if stats.graceTimer > 1.0 then 
                                 reportScore(stats.activeTime, stats.realTime, j) -- [New] Report with Leader Index
                                 stats.activeTime = 0 
                                 stats.realTime = 0
                             end
                         end
                    end
                    perfectChaseStats[pairKey] = stats
                    updatedStats[pairKey] = true -- [Fix] Mark as active
                    
                    -- ... Best Target Logic check angle too?
                    -- Best Target logic relies on "isChaserDrifting and isLeaderDrifting".
                    -- Use the raw values for finding target, let the bar color/progress reflect the strictness.
                    -- But if angle is bad, bar shouldn't grow.
                    -- The stats update above handles growth.
                    -- ...

                    
                    -- 寻找最佳 UI 目标 (最近的有效目标)
                    -- 条件：都在漂移，且距离在显示范围内 (45m)，且在玩家前方
                    -- 注意: 这里复用 loop 中的 isChaserDrifting, isLeaderDrifting
                    -- 但需要额外的 dot check 确保在我们前方 (UI 显示用)
                    local playerLookDot = player.look:dot( (leader.position - chaser.position):normalize() )
                    
                    -- [Fix] 放宽视野判定 (View Cone)
                    -- 原来的 > 0.5 (60度) 太严苛，大角度漂移时车头没对准前车会导致 UI 丢失
                    -- 改为 > -0.2 (约 100度)，支持 Reverse Entry
                    if isChaserDrifting and isLeaderDrifting and playerLookDot > -0.2 and rawDist < 45.0 then
                        -- [Fix] 目标锁定粘滞 (Hysteresis)
                        -- 为了防止目标乱跳，现在的目标会有 3.0m 的"虚拟距离优势"
                        -- 也就是说，新目标必须比当前目标近 3.0m 以上才能抢走焦点
                        local effectiveDist = dist
                        if activeTarget and activeTarget.index == j then
                            effectiveDist = dist - 3.0
                        end

                        -- 距离修正 (UI用)
                        if effectiveDist < minFrontDist then
                            minFrontDist = effectiveDist
                            frameBestTarget = {
                                index = j,
                                dist = dist,
                                stats = stats,
                                isLocked = isLocked
                            }
                            -- [Removed] Don't set here, only set FINAL winner
                        end
                    end
                end
            end
         end
       end
    end
  end
  
  -- [Fix] Finalize UI Target Flag
  if frameBestTarget then
      frameBestTarget.stats.isDisplayed = true
  end
  
  -- [Fix] Cleanup Stale Stats (Frozen Chase Bug)
  -- If we didn't update the stats this frame (e.g. stopped drifting/parked), decay them immediately.
  for k, stats in pairs(perfectChaseStats) do
      if not updatedStats[k] then
          stats.graceTimer = stats.graceTimer + realDt
          if stats.graceTimer > 1.0 then 
               -- Report if valid score exists
               -- Report if valid score exists
               -- Report if valid score exists AND it was shown on UI
               if stats.activeTime > 0 and stats.isDisplayed then
                   -- Parse Leader Index from Key "chaser_leader"
                   local _, _, _, leaderIdxStr = string.find(k, "(%d+)_(%d+)")
                   local leaderIdx = tonumber(leaderIdxStr)
                   reportScore(stats.activeTime, stats.realTime, leaderIdx)
               end
               -- Remove from list
               perfectChaseStats[k] = nil
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
  -- 2D UI 绘制 (仅保留距离进度条)
  local uiState = ac.getUI()
  local windowSize = uiState.windowSize
  
  ui.beginTransparentWindow("DriftOverlay", vec2(0,0), windowSize)
  
  local sim = ac.getSim()
  local player = ac.getCar(sim.focusedCar)
  
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
              local barColor = rgbm(0, 1, 0, 0.9) -- Default Green (> Normal)
              
              if dist < CONFIG.distPraise then
                  barColor = rgbm(0.8, 0, 1, 1) -- Perfect: Purple
              elseif dist < CONFIG.distNormal then
                  barColor = rgbm(1, 0.84, 0, 1) -- Normal: Gold
              end
              
              ui.drawRectFilled(barPos, barPos + vec2(barWidth, barHeight), rgbm(0, 0, 0, 0.5), 2)
              local fillW = barWidth * progress
              if fillW > 2 then
                  ui.drawRectFilled(barPos, barPos + vec2(fillW, barHeight), barColor, 2)
              end
              
              -- Star Rating System (Replaces Timer)
              if activeTime > 0.0 then
                    -- Use Helper for consistent logic
                    local grade = getChaseGrade(activeTime)
                    local STAR_Count = 5
                    
                    -- Determine Colors based on grade.cycle
                    local cycle = grade.cycle
                    local baseCol = getStarColor(math.min(cycle + 1, #GRADE_COLORS))  -- Current Cycle Background
                    local fillCol = getStarColor(math.min(cycle + 2, #GRADE_COLORS))  -- Filling Color
                    
                    -- If max level reached
                    if cycle >= (#GRADE_COLORS - 1) then
                        baseCol = GRADE_COLORS[#GRADE_COLORS]
                        fillCol = rgbm(1, 1, 1, 1) -- Flash White
                    end
                    
                    -- Calc partial progress for current star
                    local localTime = activeTime % 1.0 -- Assuming 1.0s per star
                    -- Note: grade.stars is 0-4 (completed stars).
                    -- So we are filling star index (grade.stars + 1).
                    local activeStarIndex = grade.stars + 1 
                    local activeStarProgress = localTime / 1.0

                   ui.pushFont(ui.Font.Title) -- Large stars
                   local starStr = "★"
                   local starSize = ui.measureText(starStr)
                   local spacing = 5
                   local totalWidth = (starSize.x + spacing) * STAR_Count
                   local startX = barPos.x + (barWidth - totalWidth) / 2
                   local startY = barPos.y - 45 -- Above bar
                   
                   for s = 1, STAR_Count do
                       local sPos = vec2(startX + (s-1) * (starSize.x + spacing), startY)
                       
                       if s < activeStarIndex then
                           -- Fully filled
                           ui.setCursor(sPos)
                           ui.textColored(starStr, fillCol)
                       elseif s > activeStarIndex then
                           -- Empty (Base Color)
                           ui.setCursor(sPos)
                           ui.textColored(starStr, baseCol)
                       else
                           -- Currently filling (Progressive Cut)
                           -- 1. Draw Base
                           ui.setCursor(sPos)
                           ui.textColored(starStr, baseCol)
                           
                           -- 2. Draw Fill Clipped
                           local t = activeStarProgress
                           local clipMin = sPos
                           local clipMax = sPos + vec2(starSize.x * t, starSize.y)
                           
                           ui.pushClipRect(clipMin, clipMax, true)
                           ui.setCursor(sPos)
                           ui.textColored(starStr, fillCol)
                           ui.popClipRect()
                       end
                   end
                   ui.popFont()
              end
              

          end
      end
  end

  ui.endTransparentWindow()
end

-- 3D 绘制 (仅保留 Danmaku HUD)
function script.draw3D(dt)
  -- [New] 3D Danmaku (HUD)
  updateAndDrawDanmaku(dt)
  
  -- [New] 3D Overhead (Taunts)
  updateAndDrawOverhead(dt)
end



-- [New] 聊天消息接入 (Chat Integration)
ac.onChatMessage(function(msg, senderName, carIndex)
    -- 1. 参数归一化 (Normalize Arguments)
    -- 情况 A: (msg, carIndex) -> senderName 是 index, carIndex 是 nil
    if type(senderName) == "number" then
        carIndex = senderName
        senderName = nil
    end
    
    -- [Fix] Ignore System Messages (Index < 0 are System/Server KeepAlives) and Empty Messages
    -- The "Driver -1" bubbles are caused by rendering these system packets.
    -- We must filter them out to only show real player chat.
    if (carIndex and carIndex < 0) or (not msg or msg == "") or (not carIndex and not senderName) then 
        return 
    end

    -- 情况 B: carIndex 依然为空，尝试用 senderName 字符串反查 (如果 senderName 是名字)
    local senderCar = nil
    if (not carIndex or carIndex == -1) and type(senderName) == "string" then
        local sim = ac.getSim()
        for i = 0, sim.carsCount - 1 do
            local c = ac.getCar(i)
            if c and c.driverName == senderName then
                carIndex = i
                break
            end
        end
    end

    -- 2. 获取车辆对象 (Get Car Object)
    if carIndex and carIndex >= 0 then
        senderCar = ac.getCar(carIndex)
    end
    
    
    -- [New] Check if sender is the focused player
    local sim = ac.getSim()
    local isSelf = (carIndex == sim.focusedCar)
    
    -- [New] 触发全屏弹幕 (Global Danmaku)
    local danmakuColor = isSelf and rgbm(0.5, 0.35, 0, 1) or rgbm(0.4, 0.4, 0.4, 1)
    
    -- 3. 构造显示名称 (Priority: Car.driverName > senderName > "Unknown")
    local finalName = senderName
    if senderCar then
        -- [Fix] Robust Name Fetching (handle function vs string vs nil)
        local rawName = senderCar.driverName
        if type(rawName) == "function" then
            finalName = rawName(senderCar) -- Try method call style or just function
        elseif type(rawName) == "string" then
            finalName = rawName
        end
    end
    
    -- Normalize to string
    if type(finalName) ~= "string" then
        finalName = tostring(finalName)
    end
    
    -- Filter out "nil" string
    if finalName == "nil" then finalName = "Driver " .. (carIndex or "?") end
    
    local displayText = msg
    if finalName then 
        -- [Visual] Icons for different message types
        if msg:find("追走结算") then
             displayText = finalName .. " [*] " .. msg
        else
             displayText = finalName .. " > " .. msg 
        end
    end
    
    addDanmaku(displayText, danmakuColor)

end)
