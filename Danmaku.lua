-- Danmaku.lua
-- Independent Chat Danmaku Renderer
-- Created: 2026-02-03

local COLORS = {
  White  = rgbm(0.5, 0.5, 0.5, 1),
  Blue   = rgbm(0.2, 0.6, 1.0, 1),
  Green  = rgbm(0.2, 0.9, 0.4, 1),
  Gold   = rgbm(1.0, 0.8, 0.1, 1),
  Purple = rgbm(0.8, 0.3, 0.9, 1),
  Red    = rgbm(1.0, 0.2, 0.2, 1)
}

local State = {
  danmakuQueue = {}
}

local function AddDanmaku(text, color)
  -- Config inherited from DriftChaseMonitor optimization
  local DANMAKU_CONFIG = {
      depth = 8.0,      
      width = 12.0,     
      height = 6.0,     
      speed = 0.25,     
      fontSize = 3.5,   -- Optimized font size
      maxLines = 3,     
      lineHeight = 0.8  -- Optimized line spacing
  }
  
  local lineIdx = math.random(0, DANMAKU_CONFIG.maxLines - 1)
  local speed = DANMAKU_CONFIG.speed + math.random() * 1.0
  
  table.insert(State.danmakuQueue, {
      text = text, 
      color = color or COLORS.White,
      x = (DANMAKU_CONFIG.width / 2) + math.random(0, 2), 
      -- Optimized height (4.5m)
      y = 4.5 - (lineIdx * DANMAKU_CONFIG.lineHeight),
      speed = speed,
      life = 60.0,
      fontSize = DANMAKU_CONFIG.fontSize
  })
end

local function Render_Danmaku(dt)
  local safeDt = dt or ac.getDeltaT()
  local camPos = ac.getCameraPosition()
  local camLook = ac.getCameraForward()
  local camUp = ac.getCameraUp()
  local camSide = ac.getCameraSide() 
  
  local depth = 8.0 
  local width = 12.0
  local screenCenter = camPos + camLook * depth

  for i = #State.danmakuQueue, 1, -1 do
      local item = State.danmakuQueue[i]
      item.x = item.x - item.speed * safeDt
      local textPos = screenCenter + (camSide * item.x) + (camUp * item.y)
      
      render.debugText(textPos, item.text, item.color, item.fontSize or 3.5)
      
      if item.x < -(width / 2) - 5 then 
          table.remove(State.danmakuQueue, i)
      end
  end
end

function script.draw3D(dt)
  Render_Danmaku(dt)
end

ac.onChatMessage(function(msg, carIndex) 
   if not msg or #msg == 0 or msg:match("^%s*$") then return end

   -- Process system messages or player messages
   if carIndex == -1 then return end

   local car = ac.getCar(carIndex)
   local name = "Car " .. tostring(carIndex)
   
   if car then
       if type(car.driverName) == "string" then
           name = car.driverName
       elseif type(car.driverName) == "function" then
           local status, result = pcall(function() return car:driverName() end)
           if status then name = result else name = car.driverName(car) end
       end
   end
   
   local fullMsg = name .. ": " .. msg
   
   -- [ADDED] Color Parsing Logic
   -- Detect keywords to apply colors (compatible with DriftChaseMonitor output)
   local color = COLORS.White
   if msg:find("紫") or msg:find("Purple") then color = COLORS.Purple
   elseif msg:find("金") or msg:find("Gold") then color = COLORS.Gold
   elseif msg:find("绿") or msg:find("Green") then color = COLORS.Green
   elseif msg:find("蓝") or msg:find("Blue") then color = COLORS.Blue
   end

   AddDanmaku(fullMsg, color)
end)
