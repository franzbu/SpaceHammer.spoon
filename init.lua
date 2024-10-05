local function scriptPath()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local Mellon = {}

Mellon.author = "Franz B. <csaa6335@gmail.com>"
Mellon.homepage = "https://github.com/franzbu/Mellon.spoon"
Mellon.winMSpaces = "MIT"
Mellon.name = "Mellon"
Mellon.version = "0.1"
Mellon.spoonPath = scriptPath()

local dragTypes = {
  move = 1,
  resize = 2,
}

local function tableToMap(table)
  local map = {}
  for _, v in pairs(table) do
    map[v] = true
  end
  return map
end

local function getWindowUnderMouse()
  --local _ = hs.application
  local my_pos = hs.geometry.new(hs.mouse.absolutePosition())
  local my_screen = hs.mouse.getCurrentScreen()
  return hs.fnutils.find(hs.window.orderedWindows(), function(w)
    return my_screen == w:screen() and my_pos:inside(w:frame())
  end)
end

local function buttonNameToEventType(name, optionName)
  if name == 'left' then
    return hs.eventtap.event.types.leftMouseDown
  end
  if name == 'right' then
    return hs.eventtap.event.types.rightMouseDown
  end
  error(optionName .. ': only "left" and "right" mouse button supported, got ' .. name)
end

function Mellon:new(options)
  hs.window.animationDuration = 0
  options = options or {}

  modifier1 = options.modifier1 or { 'alt' } -- for mouse and potentially modifierSwitchWin_MS_All
  modifier2 = options.modifier2 or { 'ctrl' } -- for mouse and potentially modifierSwitchWin_App_Ref
  modifier1_2 = mergeModifiers(modifier1, modifier2) -- could be used for modSwitchSpace (or something else)
  modSwitchSpace =  { 'shift', 'ctrl', 'alt', 'cmd' } -- { 'ctrl', 'shift' }
  modifierReference = { 'ctrl', 'shift' } -- { 'alt', 'ctrl', 'shift' }
  modifierSwitchWin_MS_All = options.modifierSwitchWin_MS_All or options.modifier1
  modifierSwitchWin_App_Ref = options.modifierSwitchWin_App_Ref or options.modifier2

  margin = options.margin or 0.3
  m = margin * 100 / 2

  useResize = options.resize or false

  useMSpaces = options.useMSpaces or true
  ratioSpaces = options.ratioSpaces or 0.8
  amountSpaces = options. amountSpaces or 3
  currentSpace = options.startSpace or 2
  
  prevSpace = options.prevSpace or 'a'
  nextSpace = options.nextSpace or 's'
  moveWindowPrevSpace = options.moveWindowPrevSpace or 'd'
  moveWindowNextSpace = options.moveWindowNextSpace or 'f'
  moveWindowPrevSpaceSwitch = options.moveWindowPrevSpaceSwitch or 'q'
  moveWindowNextSpaceSwitch = options.moveWindowNextSpaceSwitch or 'w'

  local resizer = {
    disabledApps = tableToMap(options.disabledApps or {}),
    dragging = false,
    dragType = nil,
    moveStartMouseEvent = buttonNameToEventType('left', 'moveMouseButton'),
    resizeStartMouseEvent = buttonNameToEventType('right', 'resizeMouseButton'),
    targetWindow = nil,
  }

  setmetatable(resizer, self)
  self.__index = self

  resizer.clickHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseDown,
      hs.eventtap.event.types.rightMouseDown,
    },
    resizer:handleClick()
  )

  resizer.cancelHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseUp,
      hs.eventtap.event.types.rightMouseUp,
    },
    resizer:handleCancel()
  )

  resizer.dragHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseDragged,
      hs.eventtap.event.types.rightMouseDragged,
    },
    resizer:handleDrag()
  )

  --___________ mspaces ___________


  -- watchdogs
  filter = hs.window.filter --subscribe: when a new window (dis)appears, run refreshWindowsWS
  filter.default:subscribe(filter.windowNotOnScreen, function() refreshWinMSpaces() end)
  filter.default:subscribe(filter.windowOnScreen, function() refreshWinMSpaces() end)
  filter.default:subscribe(filter.windowFocused, function(w) refreshWinMSpaces(w) end)
  filter.default:subscribe(filter.windowMoved, function(w) correctXY(w) end)
  --?todo: also react to resizing (perhaps incl. subscription)

  -- 'subscribe', watchdog for modifier keys
  cycleModCounter = 0 
  local events = hs.eventtap.event.types
  local prevModifier = nil --{ "xyz" }
  cycleAll = false
  keyboardTracker = hs.eventtap.new({ events.flagsChanged }, function(e)
    local flagsKeyboardTracker = eventToArray(e:getFlags())
    -- since on modifier release the flag is 'nil', prevModifier is used
    if modifiersEqual(flagsKeyboardTracker, modifierSwitchWin_MS_All) or modifiersEqual(prevModifier, modifierSwitchWin_MS_All) then
      cycleModCounter = cycleModCounter + 1
      if cycleModCounter % 2 == 0 then -- only when released (and not when pressed)
        prevModifier = nil
        if cycleAll then
          hs.timer.doAfter(0.02, function()
            cycleModCounter = 0
            pos = getWinMSpacesPos(hs.window.focusedWindow())
            for i = 1, amountSpaces do
              if winMSpaces[pos].mspace[i] then
                goToSpace(i)
                break 
              end
            end
          end)
          cycleAll = false
        end

      end
    end
    prevModifier = flagsKeyboardTracker
  end)
  keyboardTracker:start()


  --cycle through all windows, regardless of which WS they are on
  ---[[ -- https://applehelpwriter.com/2018/01/14/how-to-add-a-window-switcher/
  switcher = hs.window.switcher.new()   -- default windowfilter: only visible windows, all Spaces
  switcher.ui.highlightColor = { 0.4, 0.4, 0.5, 0.8 }
  switcher.ui.thumbnailSize = 112
  switcher.ui.selectedThumbnailSize = 284
  switcher.ui.backgroundColor = { 0.3, 0.3, 0.3, 0.5 }
  switcher.ui.textSize = 14
  switcher.ui.showSelectedTitle = false
  hs.hotkey.bind(modifierSwitchWin_MS_All, "tab", function()
    cycleAll = true
    switcher:nextWindow ()   --nextWindow()
    --after release of modifierSwitchWin_MS_All, watchdog is called and does the rest
  end)
  hs.hotkey.bind("alt-shift", "tab", function()
    cycleAll = true
    switcher:previous()
  end)
  --]]


  -- cycle through windows of current WS, ?todo: last focus first
  local nextFMS = 1
  hs.hotkey.bind(modifierSwitchWin_MS_All, "escape", function()
    if nextFMS > #winMSpaces then nextFMS = 1 end
    while not winMSpaces[nextFMS].mspace[currentSpace] do
      if nextFMS == #winMSpaces then
        nextFMS = 1
      else
        nextFMS = nextFMS + 1
      end
    end
    winMSpaces[nextFMS].win:focus()
    nextFMS = nextFMS + 1
  end)


  --fb
  -- todo: cycle through windows of one app - in all mspaces
  hs.hotkey.bind(modifierSwitchWin_App_Ref, "tab", function()

  end)


  -- cycle through references of one window
  local nextFR = 1
  hs.hotkey.bind(modifierSwitchWin_App_Ref, "escape", function()
    pos = getWinMSpacesPos(hs.window.focusedWindow())

    nextFR = getNextSpaceNumber(currentSpace)
    while not winMSpaces[pos].mspace[nextFR] do
      if nextFR == amountSpaces then
        nextFR = 1
      else
        nextFR = nextFR + 1
      end
    end
    goToSpace(nextFR)
    winMSpaces[pos].win:focus()
  end)


  -- ___________ own spaces ___________

    -- menubar
  -- https://github.com/Hammerspoon/hammerspoon/issues/2878
  a = hs.menubar.new(true, "A"):setTitle("2")
  a:setTooltip("Mellon - Space")
  hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "o", function()
    a:setTitle(tostring('2'))
  end)


  --___________ own spaces ___________

  filter_all = hs.window.filter.new()
  winAll = filter_all:getWindows(hs.window.sortByFocused)
  -- ?todo: hs.window.allWindows()
  --winAll = hs.application.find("")

  --initialize winMSpaces
  winMSpaces = {}
  refreshWinMSpaces()




  -- fb:
  --_________ reference/dereference windows to/from mspaces, goto mspaces _________
  -- reference
  for i = 1, amountSpaces do
    hs.hotkey.bind(modifierReference, tostring(i), function()
      refWinMSpace(i)
    end)
  end
  -- de-reference
  hs.hotkey.bind(modifierReference, "0", function()
    derefWinMSpace()
  end)
  --]]

  -- goto mspaces directly
  for i = 1, amountSpaces do
    hs.hotkey.bind(modSwitchSpace, tostring(i), function()
      goToSpace(i)
    end)
  end


  --_________ switching spaces / moving windows _________
  hs.hotkey.bind(modSwitchSpace, prevSpace, function() -- previous space (incl. cycle)
    currentSpace = getPrevSpaceNumber(currentSpace)
    goToSpace(currentSpace)
  end)


  hs.hotkey.bind(modSwitchSpace, nextSpace, function() -- next space (incl. cycle)
    currentSpace = getNextSpaceNumber(currentSpace)
    goToSpace(currentSpace)
  end)


  hs.hotkey.bind(modSwitchSpace, moveWindowPrevSpace, function() -- move active window to previous space (incl. cycle)
    -- move window to prev space
    moveToSpace(getPrevSpaceNumber(currentSpace), currentSpace)
  end)


  hs.hotkey.bind(modSwitchSpace, moveWindowNextSpace, function() -- move active window to next space (incl. cycle)
    -- move window to next space
    moveToSpace(getNextSpaceNumber(currentSpace), currentSpace)
  end)


  hs.hotkey.bind(modSwitchSpace, moveWindowPrevSpaceSwitch, function() -- move active window to previous space and switch there (incl. cycle)
    -- move window to prev space and switch there
    moveToSpace(getPrevSpaceNumber(currentSpace), currentSpace)
    currentSpace = getPrevSpaceNumber(currentSpace)
    goToSpace(currentSpace)
  end)


  hs.hotkey.bind(modSwitchSpace, moveWindowNextSpaceSwitch, function() -- move active window to next space and switch there (incl. cycle)
    -- move window to next space and switch there
      moveToSpace(getNextSpaceNumber(currentSpace), currentSpace)
      currentSpace = getNextSpaceNumber(currentSpace)
      goToSpace(currentSpace)
    end)

  -- debug
  -- list all windows
  hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "m", function()
    print("_______winAll_________")
    for i, v in pairs(winAll) do
      print(i, v)
    end


    for i, v in pairs(winMSpaces) do
      print("_______winMSpaces_________")
      --print(i .. ": " .. "mspace " .. tostring(winMSpaces[i].mspace))
      print("id: " .. tostring(winMSpaces[i].win:application()))

      spaces = ""
      for j = 1, amountSpaces do
        spaces = spaces .. tostring(winMSpaces[i].mspace[j]) .. ", "
      end

      print("space: " .. spaces)
    end

    print("=====")
    print(hs.application.find("WhatsApp"))
  end)

  hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "n", function()
    refreshWinMSpaces()
  end)

  goToSpace(currentSpace) -- refresh

  resizer.clickHandler:start()

  return resizer
end


function Mellon:stop()
  self.dragging = false
  self.dragType = nil

  for i = 1, #cv do -- delete canvases
    cv[i]:delete()
  end

  self.cancelHandler:stop()
  self.dragHandler:stop()
  self.clickHandler:start()
end


function Mellon:isResizing()
  return self.dragType == dragTypes.resize
end


function Mellon:isMoving()
  return self.dragType == dragTypes.move
end


sumdx = 0
sumdy = 0
function Mellon:handleDrag()
  return function(event)
    if not self.dragging then return nil end
    local currentSize = win:size() -- win:frame
    local current = win:topLeft()
      
    local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
    local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)

    if self:isMoving() then

      local point = win:topLeft()
      local frame = win:size() -- win:frame
      --win:move(hs.geometry.new(point.x + dx, point.y + dy, frame.w, frame.h), nil, false, 0)
      win:move({ dx, dy }, nil, false, 0)
      sumdy = sumdy + dy
      sumdx = sumdx + dx
      movedNotResized = true

      -- mspaces --
      moveLeftAS = false -- these two variables are also needed in case AeroSpace is deactivated
      moveRightAS = false
      if useMSpaces then
        if current.x + currentSize.w * ratioSpaces < 0 then -- left
          for i = 1, #cv do
            cv[ i ]:hide() 
          end
          moveLeftAS = true
        elseif current.x + currentSize.w > max.w + currentSize.w * ratioSpaces then -- right
          for i = 1, #cv do
            cv[ i ]:hide()
          end
          moveRightAS = true
        else
          for i = 1, #cv do
            cv[ i ]:show()
          end
          moveLeftAS = false
          moveRightAS = false
        end
      else
        ratioSpaces = 1 -- if 'useMSpaces' is disabled, enable automatic snapping and resizing beyond 'ratioSpaces', i.e., for dragging windows as far as possible (= 1)
      end

      return true
    elseif self:isResizing() and useResize then
      movedNotResized = false
      if mH <= -m and mV <= m and mV > -m then -- 9 o'clock
        win:move(hs.geometry.new(current.x + dx, current.y, currentSize.w - dx, currentSize.h), nil, false, 0)
      elseif mH <= -m and mV <= -m then -- 10:30
        if dy < 0 then -- prevent extension of downwards when cursor enters menubar
          if current.y > heightMB then
            win:move(hs.geometry.new(current.x + dx, current.y + dy, currentSize.w - dx, currentSize.h - dy), nil, false,
              0)
          end
        else
          win:move(hs.geometry.new(current.x + dx, current.y + dy, currentSize.w - dx, currentSize.h - dy), nil, false, 0)
        end
      elseif mH > -m and mH <= m and mV <= -m then -- 12 o'clock
        if dy < 0 then -- prevent extension of downwards when cursor enters menubar
          if current.y > heightMB then
            win:move(hs.geometry.new(current.x, current.y + dy, currentSize.w, currentSize.h - dy), nil, false, 0)
          end
        else
          win:move(hs.geometry.new(current.x, current.y + dy, currentSize.w, currentSize.h - dy), nil, false, 0)
        end
      elseif mH > m and mV <= -m then -- 1:30
        if dy < 0 then -- prevent extension of downwards when cursor enters menubar
          if current.y > heightMB then
            win:move(hs.geometry.new(current.x, current.y + dy, currentSize.w + dx, currentSize.h - dy), nil, false, 0)
          end
        else
          win:move(hs.geometry.new(current.x, current.y + dy, currentSize.w + dx, currentSize.h - dy), nil, false, 0)
        end
      elseif mH > m and mV > -m and mV <= m then -- 3 o'clock
        win:move(hs.geometry.new(current.x, current.y, currentSize.w + dx, currentSize.h), nil, false, 0)
      elseif mH > m and mV > m then -- 4:30
        win:move(hs.geometry.new(current.x, current.y, currentSize.w + dx, currentSize.h + dy), nil, false, 0)
      elseif mV > m and mH <= m and mH > -m then -- 6 o'clock
        win:move(hs.geometry.new(current.x, current.y, currentSize.w, currentSize.h + dy), nil, false, 0)
      elseif mH <= -m and mV > m then -- 7:30
        win:move(hs.geometry.new(current.x + dx, current.y, currentSize.w - dx, currentSize.h + dy), nil, false, 0)
      else -- middle -> moving (not resizing) window
        local point = win:topLeft()
        local frame = win:frame()
        win:move({ dx, dy }, nil, false, 0)
        movedNotResized = true
      end
      return true
    else
      return nil
    end
  end
end


function Mellon:handleCancel()
  return function()
    if not self.dragging then return end
    self:doMagic()
    self:stop()
  end
end


function Mellon:doMagic() -- automatic positioning and adjustments, for example, prevent window from moving/resizing beyond screen boundaries
  if not self.targetWindow then return end

  modifierDM = eventToArray(hs.eventtap.checkKeyboardModifiers()) -- modifiers (still) pressed after releasing mouse button
  
  local frame = win:frame()
  local point = win:topLeft()
  -- 'max' should not be reintialized here because if there is another adjacent display with different resolution, windows are adjusted according to that resolution (as cursor gets moved there)
  -- local max = win:screen():frame() -- max.x = 0; max.y = 0; max.w = screen width; max.h = screen height without menu bar
  local xNew = point.x
  local yNew = point.y
  local wNew = frame.w
  local hNew = frame.h

  if not moveLeftAS and not moveRightAS then -- if moved to other workspace, no resizing/repositioning wanted/necessary
    if movedNotResized then
      -- window moved past left screen border
      if modifiersEqual(flags, modifier1) then
        gridX = 2
        gridY = 2
      elseif modifiersEqual(flags, modifier2) then --or modifiersEqual(flags, modifier1_2) then
        gridX = 3
        gridY = 3
      end

      if modifiersEqual(flags, modifier1) then
        if point.x < 0 and hs.mouse.getRelativePosition().y + sumdy < max.h + heightMB then -- left and not bottom
          if math.abs(point.x) < wNew / 10 then -- moved past border by 10 or less percent: move window as is back within boundaries of screen
            xNew = 0
          -- window moved past left screen border
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            for i = 1, gridY, 1 do
              -- middle third of left border
              if hs.mouse.getRelativePosition().y + sumdy > max.h / 3 and hs.mouse.getRelativePosition().y + sumdy < max.h * 2 / 3 then -- getRelativePosition() returns mouse coordinates where moving process starts, not ends, thus sumdx/sumdy make necessary adjustment
                xNew = 0
                yNew = heightMB
                wNew = max.w / 2
                hNew = max.h
              elseif hs.mouse.getRelativePosition().y + sumdy <= max.h / 3 then -- upper third
                xNew = 0
                yNew = heightMB
                wNew = max.w / 2
                hNew = max.h / 2
              else -- bottom third
                xNew = 0
                yNew = heightMB + max.h / 2
                wNew = max.w / 2
                hNew = max.h / 2
              end
            end
          end
        -- moved window past right screen border
        elseif point.x + frame.w > max.w and hs.mouse.getRelativePosition().y + sumdy < max.h + heightMB then -- right and not bottom
          if max.w - point.x > math.abs(max.w - point.x - wNew) * 9 then -- 9 times as much inside screen than outside = 10 percent outside; move window back within boundaries of screen (keep size)
            wNew = frame.w
            xNew = max.w - wNew
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            for i = 1, gridY, 1 do
              -- middle third of left border
              if hs.mouse.getRelativePosition().y + sumdy > max.h / 3 and hs.mouse.getRelativePosition().y + sumdy < max.h * 2 / 3 then
                xNew = max.w / 2
                yNew = heightMB
                wNew = max.w / 2
                hNew = max.h
              elseif hs.mouse.getRelativePosition().y + sumdy <= max.h / 3 then -- upper third
                xNew = max.w / 2
                yNew = heightMB
                wNew = max.w / 2
                hNew = max.h / 2
              else -- bottom third
                xNew = max.w / 2
                yNew = heightMB + max.h / 2
                wNew = max.w / 2
                hNew = max.h / 2
              end
            end
          end
        -- moved window below bottom of screen
        elseif point.y + hNew > maxWithMB.h and hs.mouse.getRelativePosition().x + sumdx < max.w and hs.mouse.getRelativePosition().x + sumdx > 0 then
          if max.h - point.y > math.abs(max.h - point.y - hNew) * 9 then -- and flags:containExactly(modifier1) then -- move window as is back within boundaries
            yNew = maxWithMB.h - hNew
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            for i = 1, gridX, 1 do
              if hs.mouse.getRelativePosition().x + sumdx > max.w / 3 and hs.mouse.getRelativePosition().x + sumdx < max.w * 2 / 3 then -- middle
                xNew = 0
                yNew = heightMB
                wNew = max.w
                hNew = max.h
                break
              elseif hs.mouse.getRelativePosition().x + sumdx <= max.w / 3 then -- left
                xNew = 0
                yNew = heightMB
                wNew = max.w / gridX
                hNew = max.h
                break
              else -- right
                xNew = max.w - max.w / gridX -- for gridX = 2 the same as max.w / 2
                yNew = heightMB
                wNew = max.w / gridX
                hNew = max.h
                break
              end
            end
          end
        end
      elseif modifiersEqual(flags, modifier2) and modifiersEqual(flags, modifierDM) then --todo: ?not necessary? -> and eventType == self.moveStartMouseEvent
        if point.x < 0 and hs.mouse.getRelativePosition().y + sumdy < max.h + heightMB then -- left and not bottom
          if math.abs(point.x) < wNew / 10 then -- moved past border by 10 or less percent: move window as is back within boundaries of screen
            xNew = 0
          -- window moved past left screen border
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            -- 3 standard areas
            if (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 2 and hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 3) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 4) then
              for i = 1, gridY, 1 do
                -- getRelativePosition() returns mouse coordinates where moving process starts, not ends, thus sumdx/sumdy make necessary adjustment             
                if hs.mouse.getRelativePosition().y + sumdy < max.h - (gridY - i) * max.h / gridY then 
                  xNew = 0
                  yNew = heightMB + (i - 1) * max.h / gridY
                  wNew = max.w / gridX
                  hNew = max.h / gridY
                  break
                end
              end
            -- first (upper) double area
            elseif (hs.mouse.getRelativePosition().y + sumdy > max.h / 5) and (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 2) then
              xNew = 0
              yNew = heightMB
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            else -- second (lower) double area
              xNew = 0
              yNew = heightMB + max.h / 5 * 2
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            end
          end
        -- moved window past right screen border
        elseif point.x + frame.w > max.w and hs.mouse.getRelativePosition().y + sumdy < max.h + heightMB then -- right and not bottom
          if max.w - point.x > math.abs(max.w - point.x - wNew) * 9 then  -- 9 times as much inside screen than outside = 10 percent outside; move window back within boundaries of screen (keep size)
            wNew = frame.w
            xNew = max.w - wNew
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            -- getRelativePosition() returns mouse coordinates where moving process starts, not ends, thus sumdx/sumdy make necessary adjustment                     
            if (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 2 and hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 3) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 4) then
              -- 3 standard areas
              for i = 1, gridY, 1 do
                if hs.mouse.getRelativePosition().y + sumdy < max.h - (gridY - i) * max.h / gridY then 
                  xNew = max.w - max.w / gridX
                  yNew = heightMB + (i - 1) * max.h / gridY
                  wNew = max.w / gridX
                  hNew = max.h / gridY
                  break
                end
              end
            -- first (upper) double area
            elseif (hs.mouse.getRelativePosition().y + sumdy > max.h / 5) and (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 2) then
              xNew = max.w - max.w / gridX
              yNew = heightMB
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            else -- second (lower) double area
              xNew = max.w - max.w / gridX
              yNew = heightMB + max.h / 5 * 2
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            end
          end
        -- moved window below bottom of screen
        elseif point.y + hNew > maxWithMB.h and hs.mouse.getRelativePosition().x + sumdx < max.w and hs.mouse.getRelativePosition().x + sumdx > 0 then
          if max.h - point.y > math.abs(max.h - point.y - hNew) * 9 then -- and flags:containExactly(modifier1) then -- move window as is back within boundaries
            yNew = maxWithMB.h - hNew
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            if (hs.mouse.getRelativePosition().x + sumdx <= max.w / 5) or (hs.mouse.getRelativePosition().x + sumdx > max.w / 5 * 2 and hs.mouse.getRelativePosition().x + sumdx <= max.w / 5 * 3) or (hs.mouse.getRelativePosition().x + sumdx > max.w / 5 * 4) then
              -- 3 standard areas
              for i = 1, gridX, 1 do
                if hs.mouse.getRelativePosition().x + sumdx < max.w - (gridX - i) * max.w / gridX then 
                  xNew = (i - 1) * max.w / gridX 
                  yNew = heightMB + (i - 1) * gridX
                  wNew = max.w / gridX
                  hNew = max.h
                  break
                end
              end
            -- first (left) double width
            elseif (hs.mouse.getRelativePosition().x + sumdx > max.w / 5) and (hs.mouse.getRelativePosition().x + sumdx <= max.w / 5 * 2) then
              xNew = 0
              yNew = heightMB
              wNew = max.w / gridX * 2
              hNew = max.h
            else -- second (right) double width
              xNew = max.w - max.w / gridX * 2
              yNew = heightMB
              wNew = max.w / gridX * 2
              hNew = max.h
            end
          end
        end
      -- if dragged beyond left/right screen border, window snaps to middle column
      --elseif modifiersEqual(flags, modifier1_2) then --todo: ?not necessary? -> and eventType == self.moveStartMouseEvent
      elseif modifiersEqual(flags, modifier2) and #modifierDM == 0 then --todo: ?not necessary? -> and eventType == self.moveStartMouseEvent
        if point.x < 0 and hs.mouse.getRelativePosition().y + sumdy < max.h + heightMB then -- left and not bottom
          if math.abs(point.x) < wNew / 10 then -- moved past border by 10 or less percent: move window as is back within boundaries of screen
            xNew = 0
          -- window moved past left screen border
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            -- 3 standard areas
            if (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 2 and hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 3) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 4) then
              for i = 1, gridY, 1 do
                -- getRelativePosition() returns mouse coordinates where moving process starts, not ends, thus sumdx/sumdy make necessary adjustment             
                if hs.mouse.getRelativePosition().y + sumdy < max.h - (gridY - i) * max.h / gridY then 
                  xNew = max.w / gridX
                  yNew = heightMB + (i - 1) * max.h / gridY
                  wNew = max.w / gridX
                  hNew = max.h / gridY
                  break
                end
              end
            -- first (upper) double area
            elseif (hs.mouse.getRelativePosition().y + sumdy > max.h / 5) and (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 2) then
              xNew = max.w / gridX
              yNew = heightMB
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            else -- second (lower) double area
              xNew = max.w / gridX
              yNew = heightMB + max.h / 5 * 2
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            end
          end
        -- moved window past right screen border
        elseif point.x + frame.w > max.w and hs.mouse.getRelativePosition().y + sumdy < max.h + heightMB then -- right and not bottom
          if max.w - point.x > math.abs(max.w - point.x - wNew) * 9 then  -- 9 times as much inside screen than outside = 10 percent outside; move window back within boundaries of screen (keep size)
            wNew = frame.w
            xNew = max.w - wNew
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            -- getRelativePosition() returns mouse coordinates where moving process starts, not ends, thus sumdx/sumdy make necessary adjustment                     
            if (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 2 and hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 3) or (hs.mouse.getRelativePosition().y + sumdy > max.h / 5 * 4) then
              -- 3 standard areas
              for i = 1, gridY, 1 do
                if hs.mouse.getRelativePosition().y + sumdy < max.h - (gridY - i) * max.h / gridY then 
                  xNew = max.w / gridX
                  yNew = heightMB + (i - 1) * max.h / gridY
                  wNew = max.w / gridX
                  hNew = max.h / gridY
                  break
                end
              end
            -- first (upper) double area
            elseif (hs.mouse.getRelativePosition().y + sumdy > max.h / 5) and (hs.mouse.getRelativePosition().y + sumdy <= max.h / 5 * 2) then
              xNew = max.w / gridX
              yNew = heightMB
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            else -- second (lower) double area
              xNew = max.w / gridX
              yNew = heightMB + max.h / 5 * 2
              wNew = max.w / gridX
              hNew = max.h / gridY * 2
            end
          end
        -- moved window below bottom of screen
        elseif point.y + hNew > maxWithMB.h and hs.mouse.getRelativePosition().x + sumdx < max.w and hs.mouse.getRelativePosition().x + sumdx > 0 then
          if max.h - point.y > math.abs(max.h - point.y - hNew) * 9 then -- and flags:containExactly(modifier1) then -- move window as is back within boundaries
            yNew = maxWithMB.h - hNew
          elseif eventType == self.moveStartMouseEvent then -- automatically resize and position window within grid, but only with left mouse button
            if (hs.mouse.getRelativePosition().x + sumdx <= max.w / 5) or (hs.mouse.getRelativePosition().x + sumdx > max.w / 5 * 2 and hs.mouse.getRelativePosition().x + sumdx <= max.w / 5 * 3) or (hs.mouse.getRelativePosition().x + sumdx > max.w / 5 * 4) then
              -- 3 standard areas
              for i = 1, gridX, 1 do
                if hs.mouse.getRelativePosition().x + sumdx < max.w - (gridX - i) * max.w / gridX then 
                  xNew = (i - 1) * max.w / gridX 
                  yNew = heightMB + (i - 1) * gridX
                  wNew = max.w / gridX
                  hNew = max.h
                  break
                end
              end
            -- first (left) double width
            elseif (hs.mouse.getRelativePosition().x + sumdx > max.w / 5) and (hs.mouse.getRelativePosition().x + sumdx <= max.w / 5 * 2) then
              xNew = 0
              yNew = heightMB
              wNew = max.w / gridX * 2
              hNew = max.h
            else -- second (right) double width
              xNew = max.w - max.w / gridX * 2
              yNew = heightMB
              wNew = max.w / gridX * 2
              hNew = max.h
            end
          end
        end
      end
    else -- if window has been resized (and not moved)
      if point.x < 0 then -- window resized past left screen border
        wNew = frame.w + point.x
        xNew = 0
      elseif point.x + frame.w > max.w then -- window resized past right screen border
        wNew = max.w - point.x
        xNew = max.w - wNew
      end
      if point.y < heightMB then -- if window has been resized past beginning of menu bar, height of window is corrected accordingly
        hNew = frame.h + point.y - heightMB
        yNew = heightMB
      end
    end
    self.targetWindow:move(hs.geometry.new(xNew, yNew, wNew, hNew), nil, false, 0)
  
  -- mspaces
  elseif useMSpaces and movedNotResized then
    if moveLeftAS then
     moveToSpace(getPrevSpaceNumber(currentSpace), currentSpace)
      hs.timer.doAfter(0.1, function()
        goToSpace(currentSpace) -- refresh (otherwise window still visible in former mspace)
      end)
      if modifiersEqual(modifierDM, flags) then -- if modifier is still pressed, switch to where window has been moved
      
        hs.timer.doAfter(0.02, function()
          currentSpace = getPrevSpaceNumber(currentSpace)
          goToSpace(currentSpace)
        end)
      end
    elseif moveRightAS then
      moveToSpace(getNextSpaceNumber(currentSpace), currentSpace)
      hs.timer.doAfter(0.1, function()
        goToSpace(currentSpace) -- refresh (otherwise window still visible in former mspace)
      end)
      if modifiersEqual(modifierDM, flags) then
        hs.timer.doAfter(0.02, function()
          currentSpace = getNextSpaceNumber(currentSpace)
          goToSpace(currentSpace)
        end)
      end
    end
    -- position window in middle of new workspace
    xNew = max.w / 2 - wNew / 2
    yNew = max.h / 2 - hNew / 2
    self.targetWindow:move(hs.geometry.new(xNew, yNew, wNew, hNew), nil, false, 0)
  end
  sumdx = 0
  sumdy = 0
end


function Mellon:handleClick()
  return function(event)
    if self.dragging then return true end
    flags = eventToArray(event:getFlags())
    eventType = event:getType()

    -- enable active modifiers (modifier1, modifier2, modSwitchSpace, modifier4)
    isMoving = false
    isResizing = false
    if eventType == self.moveStartMouseEvent then
      if modifiersEqual(flags, modifier1) then
        isMoving = true
      elseif modifier2 ~= nil and modifiersEqual(flags, modifier2) then
        isMoving = true
      elseif modSwitchSpace ~= nil and modifiersEqual(flags, modSwitchSpace) then
        isMoving = true
      elseif modifier4 ~= nil and modifiersEqual(flags, modifier4) then
        isMoving = true
     --elseif modifier1_2 ~= nil and modifiersEqual(flags, modifier1_2) then
      --  isMoving = true
      end
    elseif eventType == self.resizeStartMouseEvent then
      if modifiersEqual(flags, modifier1) then
        isResizing = true
      elseif modifier2 ~= nil and modifiersEqual(flags, modifier2) then
        isResizing = true
      elseif modSwitchSpace ~= nil and modifiersEqual(flags, modSwitchSpace) then
        isResizing = true
      elseif modifier4 ~= nil and modifiersEqual(flags, modifier4) then
        isResizing = true
      --elseif modifier1_2 ~= nil and modifiersEqual(flags, modifier1_2) then
      --  isResizing = true
      end
    end

    if isMoving or isResizing then
      local currentWindow = getWindowUnderMouse()
      if #self.disabledApps >= 1 then
        if self.disabledApps[currentWindow:application():name()] then
          return nil
        end
      end

      self.dragging = true
      self.targetWindow = currentWindow
      
      if isMoving then
        self.dragType = dragTypes.move
      else
        self.dragType = dragTypes.resize
      end
    
      ---[[
      -- prevent error when clicking on screen (and not window) with pressed modifier(s)
      if type(getWindowUnderMouse()) == "nil" then
        self.cancelHandler:start()
        self.dragHandler:stop()
        self.clickHandler:stop()
        -- Prevent selection
        return true
      end
      --]]

      win = getWindowUnderMouse():focus() --todo (?done? ->experimental): error if clicked on screen (and not window)
      local point = win:topLeft()
      local frame = win:frame()
      max = win:screen():frame() -- max.x = 0; max.y = 0; max.w = screen width; max.h = screen height
      maxWithMB = win:screen():fullFrame()
      heightMB = maxWithMB.h - max.h   -- height menu bar
      local xNew = point.x
      local yNew = point.y
      local wNew = frame.w
      local hNew = frame.h

      local mousePos = hs.mouse.absolutePosition()
      local mx = wNew + xNew - mousePos.x -- distance between right border of window and cursor
      local dmah = wNew / 2 - mx -- absolute delta: mid window - cursor
      mH = dmah * 100 / wNew -- delta from mid window: -50(left border of window) to 50 (left border)

      local my = hNew + yNew - mousePos.y
      local dmav = hNew / 2 - my
      mV = dmav * 100 / hNew -- delta from mid window in %: from -50(=top border of window) to 50 (bottom border)

      -- show canvases for visually supporting automatic window positioning and resizing
      local thickness = 20 -- thickness of bar
      cv = {} -- canvases need to be reset
      if eventType == self.moveStartMouseEvent and modifiersEqual(flags, modifier1) then
        createCanvas(1, 0, max.h / 3, thickness, max.h / 3)
        createCanvas(2, max.w / 3, heightMB + max.h - thickness, max.w / 3, thickness)
        createCanvas(3, max.w - thickness, max.h / 3, thickness, max.h / 3)
      elseif eventType == self.moveStartMouseEvent and (modifiersEqual(flags, modifier2)) then -- or modifiersEqual(flags, modifier1_2)) then
        createCanvas(1, 0, max.h / 5, thickness, max.h / 5)
        createCanvas(2, 0, max.h / 5 * 3, thickness, max.h / 5)
        createCanvas(3, max.w / 5, heightMB + max.h - thickness, max.w / 5, thickness)
        createCanvas(4, max.w / 5 * 3, heightMB + max.h - thickness, max.w / 5, thickness)
        createCanvas(5, max.w - thickness, max.h / 5, thickness, max.h / 5)
        createCanvas(6, max.w - thickness, max.h / 5 * 3, thickness, max.h / 5)
      end

      self.cancelHandler:start()
      self.dragHandler:start()
      self.clickHandler:stop()

      -- Prevent selection
      return true
    else
      return nil
    end
  end
end


-- function for creating canvases at screen border
function createCanvas(n, x, y, w, h)
  cv[n] = hs.canvas.new(hs.geometry.rect(x, y, w, h))
  cv[n]:insertElement(
    {
      action = 'fill',
      type = 'rectangle',
      fillColor = { red = 1, green = 0, blue = 0, alpha = 0.5 },
      roundedRectRadii = { xRadius = 5.0, yRadius = 5.0 },
    },
    1
  )
  cv[n]:show()
end


 -- event looks like this: {'alt' 'true'}; function turns table into an 'array' so
 -- it can be compared to the other arrays (modifier1, modifier2,...)
function eventToArray(a) -- maybe extend to work with more than one modifier at at time
  k = 1
  b = {}
  for i,_ in pairs(a) do
    if i == "cmd" or i == "alt" or i == "ctrl" or i == "shift" then -- or i == "fn" then
      b[k] = i
      k = k + 1
    end
  end
  return b
end


function modifiersEqual(a, b)
  if #a ~= #b then 
    return false
  end 
  table.sort(a)
  table.sort(b)
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end


function mergeModifiers(m1, m2)
  m1_2 = {} -- merge modifier1 and modifier2:
  k = 1
  for i = 1, #m1 do
    m1_2[k] = m1[i]
    k = k + 1
  end
  for i = 1, #m2 do
    ap = false -- already present
    for j = 1, #m1_2 do -- avoid double entries
      if m1_2[j] == m2[i] then
        ap = true
        break
      end
    end
    if not ap then
      m1_2[k] = m2[i]
      k = k + 1
    end
  end
  return m1_2
end


function isIncludedWinAll(id) -- check whether window id is included in table
  local a = false
  for i,v in pairs(winAll) do
    if tostring(id) == tostring(winAll[i]:id()) then
      a = true
    end
  end
  return a
end


function isIncludedWinMSpaces(w) -- check whether window id is included in table
  local a = false
  for i,v in pairs(winAll) do
    if w:id() == winMSpaces[i].win:id() then
      return i
    end
  end
  return 0
end


function copyTable(a)
  b = {}
  for i,v in pairs(a) do
    b[i] = v
  end
  return b
end



--spaces
function getPrevSpaceNumber(cS)
  if cS == 1 then
    return amountSpaces
  else
    return cS - 1
  end
end


function getNextSpaceNumber(cS)
  if cS == amountSpaces then
    return 1
  else
    return cS + 1
  end
end


function goToSpace(target)
  local win = winAll[1]
  local max = win:screen():frame() -- max.x = 0; max.y = 0; max.w = screen width; max.h = screen height

  for i,v in pairs(winMSpaces) do
    if winMSpaces[i].mspace[target] == true then
      winMSpaces[i].win:setFrame(winMSpaces[i].frame[target]) -- 'unhide' window
    else
      winMSpaces[i].win:setTopLeft(hs.geometry.point(max.w - 1, max.h))
    end
  end
  a:setTitle(tostring(target)) -- menubar
  currentSpace = target
end


function moveToSpace(target, origin)
  local fwin = hs.window.focusedWindow()
  max = fwin:screen():frame()
  fwin:setTopLeft(hs.geometry.point(max.w - 1, max.h))

  winMSpaces[getWinMSpacesPos(fwin)].mspace[target] = true
  winMSpaces[getWinMSpacesPos(fwin)].mspace[origin] = false

  -- always keep frame of MSpase of origin
  winMSpaces[getWinMSpacesPos(fwin)].frame[target] = winMSpaces[getWinMSpacesPos(fwin)].frame[origin]
  

end


function refreshWinMSpaces(w)
  print("_____refreshWinMSpaces_____")
  filter_all = hs.window.filter.new()
  winAll = filter_all:getWindows(hs.window.sortByFocused)
  --winAll = hs.application.find("")

  print("___#winAll_____" .. #winAll)
  print("winMSpaces length: " .. #winMSpaces)

  if #winMSpaces == 0 then   -- at first start
  --if #winMSpaces < #winAll then   -- at first start
    print("_______winMSpaces populated_________")
    for i, v in pairs(winAll) do
      print(i, v)
    end

    for i = 1, #winAll do
      winMSpaces[i] = {}
      winMSpaces[i].win = winAll[i]
      winMSpaces[i].mspace = {}
      winMSpaces[i].frame = {}

      for k = 1, amountSpaces do
        if k == currentSpace then
          winMSpaces[i].mspace[k] = true
          winMSpaces[i].frame[k] = winAll[i]:frame()
        else
          winMSpaces[i].mspace[k] = false
          winMSpaces[i].frame[k] = winAll[i]:frame()
        end
      end

    end

  end


  -- delete closed or minimized windows
  for i = 1, #winMSpaces do
    --print("___#winMSpaces_____" .. #winMSpaces)
    --print("________j: " .. winMSpaces[j].win:id())
    if not isIncludedWinAll(winMSpaces[i].win:id()) then
      --print("___not present______")
      table.remove(winMSpaces, i)  
      break -- ?todo: if more windows are closed at once, loop should restart
    else
      --print("___present______")
    end
    --print("____winspaces length: " .. #winMSpaces)

  end


  -- add missing windows
  for i = 1, #winAll do
    local there = false
    for j = 1, #winMSpaces do
      if winAll[i]:id() == winMSpaces[j].win:id() then
        there = true
      end
    end
    if not there then
      print("______adding window________")
      table.insert(winMSpaces, {})
      winMSpaces[#winMSpaces].win = winAll[i]

      winMSpaces[#winMSpaces].mspace = {}
      winMSpaces[#winMSpaces].frame = {}

      for k = 1, amountSpaces do
        if k == currentSpace then
          winMSpaces[#winMSpaces].mspace[k] = true
          winMSpaces[#winMSpaces].frame[k] = winAll[i]:frame()
        else
          winMSpaces[#winMSpaces].mspace[k] = false
          winMSpaces[#winMSpaces].frame[k] = winAll[i]:frame()
        end
      end

    end
  end


  function correctXY(w)
    -- subscribed filter for some reason takes a couple of seconds to trigger method
    --print("___correctXY_______")
    local max = w:screen():frame() 

    -- todo: find better way of detecting whether window has been moved manually or 'hidden' rather than 'fwin:topLeft().x < max.w - 100'
    if w:topLeft().x < max.w - 2 then   -- prevents subscriber-method to refresh coordinates of window that has just been 'hidden'
       winMSpaces[getWinMSpacesPos(w)].frame[currentSpace] = w:frame()
    end

  end


  function getWinMSpacesPos(w)
    for i = 1, #winMSpaces do
      if w:id() == winMSpaces[i].win:id() then
        return i
      end
    end
    return 0
  end

end

function refWinMSpace(target) -- add 'copy' of window on current mspace to target mspace
  local fwin = hs.window.focusedWindow()
  max = fwin:screen():frame()

  winMSpaces[getWinMSpacesPos(fwin)].mspace[target] = true

  -- keep frame of MSpase of origin
  winMSpaces[getWinMSpacesPos(fwin)].frame[target] = winMSpaces[getWinMSpacesPos(fwin)].frame[currentSpace]
end


function derefWinMSpace()
  local fwin = hs.window.focusedWindow()
  max = fwin:screen():frame()

  winMSpaces[getWinMSpacesPos(fwin)].mspace[currentSpace] = false

  -- in case all 'mspace' are 'false', close window
  local all_false = true
  for i = 1, #winMSpaces[getWinMSpacesPos(fwin)].mspace do
    if winMSpaces[getWinMSpacesPos(fwin)].mspace[i] then
      all_false = false
    end
  end
  if all_false then
    fwin:minimize()
  end

  goToSpace(currentSpace) -- refresh


end

return Mellon