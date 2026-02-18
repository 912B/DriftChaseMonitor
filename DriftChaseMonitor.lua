-- DriftChaseMonitor.lua
-- REWRITE: 2026-01-31
-- STATUS: PRODUCTION READY

-- ============================================================================
-- 1. CONFIGURATION (配置层)
-- ============================================================================
local CONFIG = {
  -- 漂移阈值
  minSpeed = 20.0,       -- 最低速度 km/h
  minDriftAngle = 15.0,  -- 最小漂移角度
  driftGraceTime = 0.5,  -- 漂移中断容忍时间 (秒)
  
  -- 追走阈值
  maxAngleDiff = 30.0,   -- 最大角度差 (同步要求)
  maxDistance = 45.0,    -- 最大距离 (米)
  
  -- 区域判定 (米)
  distPraise = 3.0,      -- Tier 3 (贴脸)
  distNormal = 5.0,     -- Tier 2 (正常)
  distMock = 10.0,       -- Tier 1 (有距离但还没丢)
  distProvoke = 45.0,    -- Tier 0 (丢了，或者太远)
  
  -- 计时器
  warmupTime = 2.0,      -- 锁定目标前的预热时间 (秒)
  messageCooldown = 8.0, -- 聊天消息冷却时间 (秒)
  comboGrace = 2.0,      -- 连击/UI 保持的容忍时间 (秒)
}

local UI_CONFIG = {
  barWidth = 200,
  barHeight = 12,
  starSize = 20,
  pos = vec2(100, 100)
}

local COLORS = {
  White  = rgbm(0.5, 0.5, 0.5, 1), -- 0.5 防止HDR过曝

  Blue   = rgbm(0.2, 0.6, 1.0, 1),
  Green  = rgbm(0.2, 0.9, 0.4, 1),
  Gold   = rgbm(1.0, 0.8, 0.1, 1),
  Purple = rgbm(0.8, 0.3, 0.9, 1),
  Red    = rgbm(1.0, 0.2, 0.2, 1)
}

local GRA_CONF = {
  { threshold = 0,   key = "White",  color = COLORS.White,  name = "白" },
  { threshold = 5,   key = "Blue",   color = COLORS.Blue,   name = "蓝" },
  { threshold = 25,  key = "Green",  color = COLORS.Green,  name = "绿" },
  { threshold = 125, key = "Gold",   color = COLORS.Gold,   name = "金" },
  { threshold = 625, key = "Purple", color = COLORS.Purple, name = "紫" }
}

local MSGS = {
  LEADER_TO_CHASER = {
    -- 被贴脸 (神级压力)
    TIER3 = { 
        "别亲我屁股!", "负距离!", "变态啊!", 
        "要撞了要撞了!", "你没有刹车吗?", "太近了太近了!",
        "别摸我!", "报警了啊!", "你是长在我车上了吗?"
    },
    -- 被紧追 (优秀压力)
    TIER2 = { 
        "这就粘上了?", "跟紧点弟弟!", "想超车吗?", 
        "甩不掉?!", "有点东西!", "牛皮糖一样!",
        "咬得挺死啊!", "别眨眼!" 
    },
    -- 把后车甩远了 (嘲讽)
    TIER1 = { 
        "来追我呀!", "闻闻尾气!", "就这点本事?", 
        "后视镜里没人?", "我在散步你都跟不上?", "需要拖车吗?",
        "建议重开!", "看不见你咯!", "我在终点等你!"
    }
  },
  RESULTS = {
    FAIL = { "完全跟不住啊!", "这是在画龙吗?", "轮胎没热?", "像是酒驾..." },
    OK   = { "勉强跟住了!", "普通发挥!", "还可以更近!", "及格水平" },
    GOOD = { "我是你的影子!", "胶水做的车!", "窒息般的压迫感!", "完美的同步!" }
  },
  RESULTS_SUFFIX = {
       Green = { 
           "勉强跟住了!", "节奏还行!", "下次贴更近!", "普通发挥!", "稍微认真了一点!", "一般般吧!", "还可以更近!",
           "刚才节奏乱了...", "被假动作骗了!", "勉强能预判路线!", "差点被甩出节奏!", "这图太滑了!", "刚才手滑了一下!", "还没有进入状态!", "忽快忽慢的...", "完全没节奏...", "刚才网卡了..."
       },
       Gold = { 
           "这就叫贴贴!", "咬得死死的!", "节奏完美!", "别想逃出我的掌心!", "后视镜里全是我!", "这就叫追走!", "不仅快还稳!",
           "这路线谁跟得上？", "这是在画龙吗?", "这领跑太飘忽了!", "路线太诡异了!", "是在梦游吗？"
       },
       Purple = { 
           "我是你的影子!", "胶水做的车!", "完全同步!", "想甩掉我？没门!", "窒息般的压迫感!", "你的动作我都会!", "请叫我复制忍者!" 
       }
  }
}

-- ============================================================================
-- 2. STATE MANAGEMENT (状态层)
-- ============================================================================
local State = {
  driftTimers = {},
  isDrifting = {}, 
  chaseStats = {}, 
  activeTarget = nil, 
  danmakuQueue = {},
  overheadQueue = {},
}

-- ============================================================================
-- 3. UTILITIES (工具层)
-- ============================================================================
local function getSlipAngle(car)
  local v = car.velocity
  if v:length() < 1 then return 0 end
  local fwd = car.look
  local vDir = v:clone():normalize()
  local dot = math.clamp(fwd:dot(vDir), -1, 1)
  return math.deg(math.acos(dot))
end

local function getRandom(pool)
  return pool[math.random(#pool)]
end

-- ============================================================================
-- 4. LOGIC MODULES (逻辑模块层)
-- ============================================================================

local function Logic_UpdateDrift(sim, realDt)
  for i = 0, sim.carsCount - 1 do
    local car = ac.getCar(i)
    if car and car.isConnected then
      local slip = getSlipAngle(car)
      local isRaw = slip > CONFIG.minDriftAngle and car.speedKmh > CONFIG.minSpeed
      if isRaw then State.driftTimers[i] = 0 else State.driftTimers[i] = (State.driftTimers[i] or 0) + realDt end
      State.isDrifting[i] = State.driftTimers[i] < CONFIG.driftGraceTime
    else
      State.isDrifting[i] = false
    end
  end
end

-- 交互模块
local function Logic_TriggerChat(chaserIdx, leaderIdx, tier, isChaser)
    -- 目前仅支持前车嘲讽后车
    if isChaser then return end

    local msgTable = MSGS.LEADER_TO_CHASER["TIER" .. tier]
    if not msgTable then return end
    
    local text = getRandom(msgTable)
    -- 嘲讽文字显示在发出嘲讽的车（前车，即 leader）头顶
    local targetIdx = leaderIdx
    local color = COLORS.White -- 所有消息使用纯白

    
    table.insert(State.overheadQueue, {
        carIndex = targetIdx, text = text, color = color, life = 5.0, offset = vec3(0, 1.5, 0)
    })
end


-- 辅助函数：将世界坐标转换为相对车辆的局部坐标
local function Math_WorldToLocal(refCar, targetPos)
  local diff = targetPos - refCar.position
  local fwd = refCar.look
  local up = refCar.up or vec3(0, 1, 0) -- 防御性编程
  local side = refCar.side 
  
  if not side then
      -- 如果没有 side 属性，手动计算
       side = fwd:cross(up):normalize()
  end
  
  -- 投影到局部轴
  -- Local Z (纵向) = Diff dot Forward (前方为正)
  -- Local X (横向) = Diff dot Side
  -- Local Y (垂直) = Diff dot Up
  
  local z = diff:dot(fwd)
  local x = diff:dot(side)
  local y = diff:dot(up)
  
  return vec3(x, y, z)
end

-- 检测辅助函数
local function Logic_IsChaseValid(chaser, leader, i, j)
      -- 1. 漂移检查 (基础门槛)
      if not (State.isDrifting[i] and State.isDrifting[j]) then return false, "未漂移" end
      
      -- 计算相对位置 (手动计算，替代 crashing 的 worldToLocal)
      local relPos = Math_WorldToLocal(leader, chaser.position)
      local longDist = -relPos.z -- 正值为后方距离 (注意：通常 Forward 是 +Z，但在 3D 数学中 worldToLocal 的 Z 轴定义可能不同，
                                 -- 这里我们根据原始逻辑：longDist 正值为后方。
                                 -- 如果 relPos.z 是前方距离 (前为正)，那么后方就是负数。
                                 -- 原始代码这里用了 -relPos.z，说明原始 worldToLocal 返回的是 +Z 为前。
                                 -- 所以如果我们 chaser 在 leader 后方，relPos.z 应该是负数 (例如 -10)，取反变成 +10。
                                 -- 我们的 Math_WorldToLocal 计算的是 "在前方多少米"。
                                 -- 比如 Chaser 在 Leader 后方 10米。 chaser = leader - 10*fwd. 
                                 -- diff = -10*fwd. diff:dot(fwd) = -10. 
                                 -- 所以 relPos.z 是 -10. longDist = -(-10) = 10. 正确。

      local latDist = math.abs(relPos.x) -- 横向距离
      
      -- A. 追走判定 (正后方)
      -- 在后方 2m 到 45m 之间，且横向偏差不过大
      local isBehind = longDist > 2.0 and longDist < CONFIG.maxDistance and latDist < 10.0
      
      -- B. 并排判定 (贴门/Side-by-Side)
      -- 允许稍微超车 (longDist > -2.0) 到 后方 5m 内，横向距离必须很近 (< 4.5m)
      local isSideBySide = longDist > -2.0 and longDist < 5.0 and latDist < 4.5
      
      if not (isBehind or isSideBySide) then return false, "位置无效" end
      
      -- 3. 同步检查 (角度)
      local cSlip = getSlipAngle(chaser)
      local lSlip = getSlipAngle(leader)
      local angleDiff = math.abs(cSlip - lSlip)
      
      -- [REMOVED] 移除硬性角度检查，超过 30度 不再视为断开，而是由 Tier 计算决定得分
      -- if angleDiff >= CONFIG.maxAngleDiff then return false, "角度不同步" end
      
      return true, "OK", angleDiff
end

-- Tier 计算辅助函数 (包含角度质量)
local function Logic_CalculateTier(dist, angleDiff)
      -- Tier 3 (神级): 极近距离 (< 3.5m) 且 角度完美 (< 10deg)
      -- 完美追走: 1秒 5分
      if dist < CONFIG.distPraise and angleDiff < 10.0 then return 3, 5.0 end 
      
      -- Tier 2 (优秀): 近距离 (< 10m)
      -- 普通追走: 1秒 1分 (只要距离够近，角度差大也算普通追走，不给完美分而已)
      if dist < CONFIG.distNormal then return 2, 1.0 end 
      
      -- Tier 1 (有效): 只要在范围内算有效
      -- 勉强跟住: 不加分，只算维持连接
      if dist < CONFIG.distMock then return 1, 0.0 end
      
      return 1, 0.0 -- 距离太远，或者是 provike 区域
end


-- 结束追走并结算
local function Logic_FinishChase(key, stats, leaderName)
    local score = math.floor(stats.chaseScore)
    if stats.chaseScore < 2.0 then return end -- 时间太短不结算
    

    
    -- 优化：绿色星星 (25分) 以上才发送消息，避免低分刷屏
    if score < 25 then return end

    -- 计算星级颜色 (与 Render_StarRating 逻辑一致)
    local starsStr = ""
    local colorName = "白"
    local colorKey = "White"
    
    if score >= 625 then
        colorName = "紫"
        colorKey = "Purple"
        starsStr = "★★★★★" -- 简化显示，不像渲染那样精细计算多颗星
    elseif score >= 125 then
        colorName = "金"
        colorKey = "Gold"
        starsStr = "★★★★"
    elseif score >= 25 then
        colorName = "绿"
        colorKey = "Green"
        starsStr = "★★★"
    elseif score >= 5 then
        colorName = "蓝"
        colorKey = "Blue"
        starsStr = "★★"
    else
        colorName = "白"
        colorKey = "White"
        starsStr = "★"
    end
    
    -- 仅仅发送聊天消息 (Chat Message)
    -- 格式: [追走结算] 齐驰上树 (Car 0) -> 52分 (绿星 ★★★) 阴阳怪气后缀
    local suffix = ""
    if MSGS.RESULTS_SUFFIX and MSGS.RESULTS_SUFFIX[colorKey] then
        suffix = getRandom(MSGS.RESULTS_SUFFIX[colorKey])
    end
    

    -- [FIX] 防止观众端重复发送消息 (仅允许本地车手发送)
    local sim = ac.getSim()
    local car = ac.getCar(sim.focusedCar)
    if not car or not car.isLocal then return end

    local msg = string.format("追走结束! 获得: %d分 (%s色 %s) %s", score, colorName, starsStr, suffix)
    ac.sendChatMessage(msg)
end

-- 仅处理选定的目标
local function Logic_ProcessChase(i, j, chaser, leader, dt, realDt, sim)
  local key = i .. "_" .. j
  local stats = State.chaseStats[key] or { 
      chaseScore=0, realTime=0, graceTimer=0, 
      lastTier=0, lockTimer=0, isLocked=false, lastMsgTime=-9999 
  }
  
  local rawDist = math.distance(chaser.position, leader.position)
  local dist = math.max(0, rawDist - 2.0)
  
  -- 1. 核心判定：验证漂移状态与相对位置（追走或并排）
  local isValid, reason, angleDiff = Logic_IsChaseValid(chaser, leader, i, j)
  
  -- 2. 动态评分：结合距离与角度同步率计算 Tier 等级
  local currentTier = 0
  local scoreGain = 0
  
  if isValid then
      currentTier, scoreGain = Logic_CalculateTier(dist, angleDiff)
      scoreGain = scoreGain * realDt
  end
  
  -- 3. 状态维护：管理锁定时间与连击容错 (Grace Timer)
  if currentTier > 0 then
      stats.graceTimer = 0 -- 重置衰减
      stats.chaseScore = stats.chaseScore + scoreGain
      stats.realTime = stats.realTime + realDt
      stats.lockTimer = stats.lockTimer + dt
  else
      stats.lockTimer = 0
      stats.graceTimer = stats.graceTimer + realDt
  end
  
  -- 判断是否断开
  -- 判断是否断开
  if stats.graceTimer > CONFIG.comboGrace then
       -- 结算并重置
       if stats.chaseScore > 0 then
           local leaderName = ac.getCar(j).driverName
           Logic_FinishChase(key, stats, leaderName)
           stats.chaseScore = 0
       end
       stats.isLocked = false
  else
       -- [FIXED] 只要有分数积累 (chaseScore > 0)，就强制保持锁定，直到 Grace 超时
       -- [MODIFIED] 零分不锁定：如果还没开始得分 (chaseScore == 0)，则始终不锁定 (isLocked = false)
       -- 这允许 Logic_SelectTarget 继续寻找更近/更好的目标，直到我们真正开始拿分为止。
       if stats.chaseScore > 0 then
           stats.isLocked = true
       else
           stats.isLocked = false
       end
  end
  
  -- E. 交互 (聊天)
  if currentTier > 0 then
     local now = os.clock()
     if now - stats.lastMsgTime > CONFIG.messageCooldown then
         stats.lastMsgTime = now
         
         -- 只触发前车嘲讽后车
         Logic_TriggerChat(i, j, currentTier, false)
     end
  end
  
  stats.lastTier = currentTier
  
  State.chaseStats[key] = stats
  return { index = j, dist = dist, stats = stats }
end

-- 纯目标选择 (带滞后锁定)
local function Logic_SelectTarget(sim, player)
  local bestIdx = -1
  local minDist = 99999
  
  for j = 0, sim.carsCount - 1 do
      if j ~= sim.focusedCar then
          local car = ac.getCar(j)
          if car and car.isConnected then
              local dist = math.distance(player.position, car.position)
              
              -- 简单过滤: 距离范围 + 前方视野/漂移状态
              -- 如果正在漂移，优先选择漂移车
              local isDrift = State.isDrifting[j]
              local scoreDist = dist
              
              -- Hysteresis: 粘性锁定
              if State.activeTarget and State.activeTarget.index == j then
                  scoreDist = scoreDist - 10.0
              end
              
              -- 稍微偏向正在漂移的目标 (-5m)
              if isDrift then
                  scoreDist = scoreDist - 5.0
              end
              
              if scoreDist < CONFIG.maxDistance and scoreDist < minDist then
                  -- 视野检查: 必须在前方 (大致)
                  local dir = (car.position - player.position):normalize()
                  if player.look:dot(dir) > 0.2 then -- +/- 80 degrees
                       minDist = scoreDist
                       bestIdx = j
                  end
              end
          end
      end
  end
  return bestIdx
end



-- ============================================================================
-- 5. RENDER MODULES (渲染模块层)
-- ============================================================================

local function Render_StarRating(car, chaseScore)
    if not car then return end
    
    local score = math.floor(chaseScore)
    local tierIdx = 1 -- 默认白
    local stars = 0
    
    -- 进阶逻辑 (5进制): 
    -- 0-4: 白
    -- 5: 进阶蓝 (显示为 1颗蓝)
    
    if score >= 625 then
        tierIdx = 5
        stars = math.min(5, math.floor(score / 625)) 
    elseif score >= 125 then
        tierIdx = 4
        stars = math.floor(score / 125)
    elseif score >= 25 then
        tierIdx = 3
        stars = math.floor(score / 25)
    elseif score >= 5 then
        tierIdx = 2
        stars = math.floor(score / 5)
    else
        tierIdx = 1
        stars = score
    end
    
    -- 限制最大5颗星
    stars = math.clamp(stars, 0, 5) 
    
    local conf = GRA_CONF[tierIdx]
    -- 5个槽位
    local starStr = string.rep("★", stars) .. string.rep("☆", 5 - stars)
    
    -- 组合显示: 星星 + 分数 (整数)
    local fullText = starStr .. " " .. string.format("%d", score)
    
    -- 2.8m 高度 (避开名牌)
    render.debugText(car.position + vec3(0, 2.8, 0), fullText, conf.color, 1.5)
end

local function Render_Overhead(dt)
  -- 防御性编程: 如果 dt 为空，尝试获取真实帧时间
  local safeDt = dt or ac.getDeltaT()

  -- 1. 消息
  for i = #State.overheadQueue, 1, -1 do
      local item = State.overheadQueue[i]
      local maxLife = 5.0 -- 增加到 5.0s- safeDt
      -- 更新剩余寿命
      item.life = item.life - safeDt
      
      if item.life <= 0 then
          table.remove(State.overheadQueue, i)
      else
          local car = ac.getCar(item.carIndex)
          if car then
              local elapsed = maxLife - item.life
              
              -- 动画阶段:
              -- 1. 快速出现 + 飘升 (0 ~ 1.2s)
              -- 2. 悬停 + 缓慢飘动 (1.2s ~ 4.0s)
              -- 3. 消失 (4.0s ~ 5.0s)
              
              local FLOAT_TIME = 1.2
              
              -- 1. 字体大小 (快速变大后保持)
              local tSize = math.min(elapsed, FLOAT_TIME) / FLOAT_TIME
              local currentSize = 1.2 + (tSize * 1.5) -- 1.2 -> 2.7 (for 1080p)
              
              -- 2. 位移计算 (往屏幕中心漂)
              -- 如果车在屏幕右侧，文字往左飘；如果在左侧，往右飘。
              local camPos = ac.getCameraPosition()
              local camSide = ac.getCameraSide()
              local toCar = car.position - camPos
              local sideDot = toCar:dot(camSide)
              
              -- 确定漂移方向: 总是反向于它偏离屏幕中心的方向
              local driftDir = vec3(0,0,0)
              if sideDot > 0 then
                  driftDir = -camSide -- 在右边，往左
              else
                  driftDir = camSide  -- 在左边，往右
              end
              
              local upDir = vec3(0, 1, 0)
              
              -- 阶段1偏移: 向中心 2m, 向上 1.5m
              local p1_t = math.min(elapsed, FLOAT_TIME) / FLOAT_TIME
              local easeP1 = p1_t * (2 - p1_t) 
              local offset1 = (driftDir * (easeP1 * 2.0)) + (upDir * (easeP1 * 1.5))
              
              -- 阶段2偏移: 缓慢继续 (从 1.2s 开始)
              local offset2 = vec3(0,0,0)
              if elapsed > FLOAT_TIME then
                  local hoverT = elapsed - FLOAT_TIME
                  -- 极慢漂移
                  offset2 = (driftDir * (hoverT * 0.2)) + (upDir * (hoverT * 0.1))
              end
              
              local pos = car.position + item.offset + offset1 + offset2
              
              -- 3. 透明度 (最后 1.0秒 淡出)
              local alpha = 1.0
              if item.life < 1.0 then
                  alpha = item.life / 1.0
              end
              
              local col = item.color:clone()
              col.mult = alpha
              
              render.debugText(pos, item.text, col, currentSize)
          end
      end
  end
  
  -- 2. 星级评分 (静态显示)
  if State.activeTarget and State.activeTarget.index ~= -1 then
      local t = State.activeTarget
      local car = ac.getCar(t.index)
      Render_StarRating(car, t.stats.chaseScore)
  end
  

end





-- ============================================================================
-- 6. MAIN LOOP (主循环)
-- ============================================================================


function script.update(dt)
  local realDt = ac.getDeltaT()
  local sim = ac.getSim()
  
  Logic_UpdateDrift(sim, realDt)
  
  local player = ac.getCar(sim.focusedCar)
  
  -- 1. 目标选择逻辑 (修改版)
  -- 默认没有目标
  local targetIdx = -1
  
  -- 检查当前是否有锁定的目标
  if State.activeTarget and State.activeTarget.index ~= -1 and State.activeTarget.stats.isLocked then
      -- 如果已锁定，强制保持当前目标，跳过搜索
      targetIdx = State.activeTarget.index
  else
      -- 未锁定，寻找最佳目标
      targetIdx = Logic_SelectTarget(sim, player)
  end
  
  local activeData = nil
  
  -- 2. 判定追走 (Process)
  if targetIdx ~= -1 then
      local leader = ac.getCar(targetIdx)
      -- 确保目标仍存在且连接
      if leader and leader.isConnected then
          activeData = Logic_ProcessChase(sim.focusedCar, targetIdx, player, leader, dt or realDt, realDt, sim)
      else
          -- [OPTIMIZED] 目标断开结算逻辑
          -- 缓存上一帧的目标状态
          local prevTarget = State.activeTarget 
          
          -- 检查是否是我们正在追的目标且有分数
          if prevTarget and prevTarget.index == targetIdx and prevTarget.stats.chaseScore > 0 then
             local leaderName = (leader and leader.driverName) or "Unknown"
             -- [CORRECTED KEY] 使用 sim.focusedCar (chaser) .. "_" .. targetIdx (leader) 以匹配 Logic_ProcessChase
             Logic_FinishChase(sim.focusedCar .. "_" .. targetIdx, prevTarget.stats, leaderName)
             -- [FIX] Reset stats immediately to prevent stale state if re-acquired
             prevTarget.stats.chaseScore = 0
             prevTarget.stats.isLocked = false
          end
          
          -- 目标断开，强制清除
          targetIdx = -1 
      end
  end
  
  State.activeTarget = activeData or { index = -1, dist=0, stats={} }
end

function script.draw3D(dt)
  local safeDt = dt or ac.getDeltaT()
  Render_Overhead(safeDt)
end


