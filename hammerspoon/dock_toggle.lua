--- dock_toggle.lua
--
-- Un clic sur l'icône du Dock de l'app déjà au premier plan la masque (ou
-- réduit ses fenêtres), au lieu de ne rien faire. Le clic suivant la ramène,
-- comme d'habitude.
--
-- Tenir une touche de modification (Cmd, Option, Ctrl, Maj) pendant le clic
-- rend au Dock son comportement normal, par exemple pour déplacer l'icône.
--
-- Usage (dans init.lua) :
--   dockToggle = require("dock_toggle")   -- variable GLOBALE, comme pour reopen_windowless
--   dockToggle.start()

local M = {}

M.config = {
  -- "hide"     : masque l'app (Cmd+H). Instantané, toutes les fenêtres
  --              reviennent d'un coup au clic suivant ou au Cmd+Tab.
  -- "minimize" : réduit chaque fenêtre dans le Dock ; le clic suivant les
  --              ramène toutes.
  action = "hide",

  -- Distance (pixels) au bord de l'écran sous laquelle on cherche le Dock.
  -- Évite d'interroger l'interface à chaque clic ailleurs sur l'écran.
  edgeMargin = 150,

  -- Apps jamais concernées (bundle IDs).
  exclude = {},

  logLevel = "info",
}

local log = hs.logger.new("dockToggle", M.config.logLevel)
local eventTypes = hs.eventtap.event.types

local state = { swallowUntilUp = false, running = false }

local function visibleWindows(app)
  local wins = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and not w:isMinimized() then
      wins[#wins + 1] = w
    end
  end
  return wins
end

local function minimizedWindows(app)
  local wins = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and w:isMinimized() then
      wins[#wins + 1] = w
    end
  end
  return wins
end

-- Le clic est-il assez près d'un bord bas, gauche ou droit pour viser le Dock ?
local function nearDockEdge(p)
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then
      local m = M.config.edgeMargin
      return (f.y + f.h - p.y) < m or (p.x - f.x) < m or (f.x + f.w - p.x) < m
    end
  end
  return false
end

-- Ramène une URL de fichier ("file:///Applications/iA%20Writer.app/") à un chemin.
local function urlToPath(v)
  if type(v) == "table" then
    v = v.filePath or v.url
  end
  if type(v) ~= "string" then
    return nil
  end
  v = v:gsub("^file://", ""):gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return (v:gsub("/$", ""))
end

-- L'élément sous le pointeur est-il l'icône Dock de cette app ?
local function isDockIconOf(el, app)
  if not el or el:attributeValue("AXSubrole") ~= "AXApplicationDockItem" then
    return false
  end
  local itemPath = urlToPath(el:attributeValue("AXURL"))
  local appPath = app:path()
  if itemPath and appPath then
    return itemPath == appPath:gsub("/$", "")
  end
  return el:attributeValue("AXTitle") == app:name()
end

local function act(app)
  local name = app:name() or "?"
  if M.config.action == "minimize" then
    for _, w in ipairs(visibleWindows(app)) do
      w:minimize()
    end
    log.i("réduit → " .. name)
  else
    app:hide()
    log.i("masqué → " .. name)
  end
end

local function restoreMinimized(app, wins)
  for _, w in ipairs(wins) do
    w:unminimize()
  end
  log.i("restauré → " .. (app:name() or "?"))
end

local function onMouse(e)
  local etype = e:getType()

  -- Une fois le mouseDown avalé, on avale aussi la suite du même clic, pour
  -- que le Dock ne reçoive pas un mouseUp orphelin qui réactiverait l'app.
  if etype ~= eventTypes.leftMouseDown then
    if state.swallowUntilUp then
      if etype == eventTypes.leftMouseUp then
        state.swallowUntilUp = false
      end
      return true
    end
    return false
  end

  local flags = e:getFlags()
  if flags.cmd or flags.alt or flags.ctrl or flags.shift then
    return false
  end
  local p = e:location()
  if not nearDockEdge(p) then
    return false
  end
  local app = hs.application.frontmostApplication()
  if not app or M.config.exclude[app:bundleID() or ""] then
    return false
  end
  local el = hs.axuielement.systemElementAtPosition(p.x, p.y)
  if not isDockIconOf(el, app) then
    return false
  end

  if #visibleWindows(app) > 0 then
    state.swallowUntilUp = true
    hs.timer.doAfter(0, function() act(app) end)
    return true
  end

  -- Mode « minimize » : le clic suivant ramène toutes les fenêtres, alors que
  -- le Dock n'en restaurerait qu'une seule.
  if M.config.action == "minimize" then
    local mins = minimizedWindows(app)
    if #mins > 0 then
      state.swallowUntilUp = true
      hs.timer.doAfter(0, function() restoreMinimized(app, mins) end)
      return true
    end
  end

  return false -- aucune fenêtre : on laisse le Dock rouvrir l'app normalement
end

function M.start()
  if state.running then
    return M
  end
  log.setLogLevel(M.config.logLevel)
  state.tap = hs.eventtap.new({
    eventTypes.leftMouseDown, eventTypes.leftMouseDragged, eventTypes.leftMouseUp,
  }, onMouse)
  state.tap:start()
  state.watchdog = hs.timer.doEvery(5, function()
    if state.tap and not state.tap:isEnabled() then
      log.w("eventtap désactivé par le système, redémarrage")
      state.swallowUntilUp = false
      state.tap:start()
    end
  end)
  state.running = true
  log.i("démarré (action : " .. M.config.action .. ")")
  return M
end

function M.stop()
  for _, key in ipairs({ "tap", "watchdog" }) do
    if state[key] then
      state[key]:stop()
      state[key] = nil
    end
  end
  state.swallowUntilUp = false
  state.running = false
  log.i("arrêté")
  return M
end

function M.toggle()
  if state.running then
    M.stop()
    hs.alert.show("Clic Dock pour masquer : désactivé")
  else
    M.start()
    hs.alert.show("Clic Dock pour masquer : activé")
  end
  return M
end

function M.isRunning()
  return state.running
end

return M
