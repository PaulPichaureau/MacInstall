--- reopen_windowless.lua
--
-- Quand on bascule vers une app avec Cmd+Tab et qu'elle n'a aucune fenêtre
-- visible, lui envoyer l'événement « reopen », comme le fait un clic sur son
-- icône dans le Dock. La plupart des apps répondent en ouvrant une nouvelle
-- fenêtre, ou en dé-minimisant une fenêtre existante.
--
-- Le reopen passe par `open -b <bundleID>` : aucune autorisation
-- « Automatisation » par app n'est nécessaire, contrairement à AppleScript.
--
-- Usage (dans init.lua) :
--   reopenWindowless = require("reopen_windowless")   -- variable GLOBALE, sinon le
--   reopenWindowless.start()                          -- garbage collector tue les watchers

local M = {}

M.config = {
  -- "cmdtab" : n'agit qu'après un Cmd+Tab.
  -- "any"    : agit sur toute activation (Dock, Spotlight, Raycast, clic…).
  trigger = "cmdtab",

  -- Délai (s) avant de compter les fenêtres. Laisse à macOS le temps de basculer
  -- de Space si l'app a ses fenêtres ailleurs ; trop court = fenêtres en double.
  delay = 0.4,

  -- Délai max (s) entre le relâchement de Cmd et l'activation pour considérer
  -- que celle-ci vient bien du Cmd+Tab.
  cmdTabWindow = 1.0,

  -- Délai min (s) entre deux reopen pour une même app (garde-fou anti-boucle).
  cooldown = 3,

  -- Apps jamais concernées (bundle IDs). Pour trouver un bundle ID :
  --   osascript -e 'id of app "Aperçu"'
  exclude = {
    ["com.apple.finder"] = true,             -- cliquer le bureau active le Finder
    ["org.hammerspoon.Hammerspoon"] = true,
  },

  -- "debug" pour voir chaque activation dans la console Hammerspoon.
  logLevel = "info",
}

local log = hs.logger.new("reopenWL", M.config.logLevel)
local watcherEvents = hs.application.watcher
local eventTypes = hs.eventtap.event.types
local TAB = hs.keycodes.map["tab"]

local state = {
  tabWithCmd = false, -- Tab pressé pendant que Cmd est tenu
  lastCmdTab = 0,     -- instant du relâchement de Cmd qui a clos un Cmd+Tab
  lastReopen = {},    -- bundleID -> instant du dernier reopen
  pending = {},       -- bundleID -> timer de vérification en attente
  running = false,
}

local function now()
  return hs.timer.secondsSinceEpoch()
end

-- Une fenêtre « compte » si elle n'est pas minimisée et qu'elle est une vraie
-- fenêtre (standard ou dialogue), pas une palette ou un élément invisible.
-- Une app qui n'a que des fenêtres minimisées reçoit donc un reopen : la
-- plupart des apps Cocoa y répondent en dé-minimisant, ce qui est le but.
local function hasUsableWindow(app)
  for _, w in ipairs(app:allWindows()) do
    if not w:isMinimized() then
      local sr = w:subrole()
      if sr == "AXStandardWindow" or sr == "AXDialog" or sr == "AXSystemDialog" then
        return true
      end
    end
  end
  return false
end

local function reopen(app, bundleID)
  local name = app:name() or bundleID
  local task = hs.task.new("/usr/bin/open", function(code, _, err)
    if code ~= 0 then
      log.w(string.format("échec du reopen de %s (%d) : %s", name, code, err or ""))
    end
  end, { "-b", bundleID })
  if task then
    task:start()
  end
end

local function check(app, bundleID)
  if not app:isRunning() or not app:isFrontmost() then
    return -- on est déjà passé à autre chose
  end
  if hasUsableWindow(app) then
    log.d("fenêtre présente, rien à faire : " .. (app:name() or bundleID))
    return
  end
  local t = now()
  local last = state.lastReopen[bundleID]
  if last and t - last < M.config.cooldown then
    log.d("cooldown, ignoré : " .. bundleID)
    return
  end
  state.lastReopen[bundleID] = t
  log.i("reopen → " .. (app:name() or bundleID))
  reopen(app, bundleID)
end

local function onAppEvent(name, event, app)
  if event ~= watcherEvents.activated or not app then
    return
  end
  if app:kind() ~= 1 then
    return -- app sans icône dans le Dock (barre de menus, agent) : on n'y touche pas
  end
  local bundleID = app:bundleID()
  if not bundleID or M.config.exclude[bundleID] then
    return
  end
  if M.config.trigger == "cmdtab" then
    -- Deux cas : Cmd vient d'être relâché après un Cmd+Tab (sélection au
    -- clavier), ou le sélecteur est encore ouvert, Cmd tenu (clic sur une icône).
    local switcherOpen = state.tabWithCmd
    local justReleased = now() - state.lastCmdTab <= M.config.cmdTabWindow
    if not (switcherOpen or justReleased) then
      log.d("pas un Cmd+Tab, ignoré : " .. (name or bundleID))
      return
    end
    -- Un Cmd+Tab ne déclenche qu'une seule vérification : on efface les deux
    -- marqueurs pour que le relâchement de Cmd qui suit un clic ne compte pas.
    state.lastCmdTab = 0
    state.tabWithCmd = false
  end
  if state.pending[bundleID] then
    state.pending[bundleID]:stop()
  end
  state.pending[bundleID] = hs.timer.doAfter(M.config.delay, function()
    state.pending[bundleID] = nil
    check(app, bundleID)
  end)
end

-- Détection du Cmd+Tab : on note qu'un Tab a été pressé avec Cmd, puis on
-- horodate le relâchement de Cmd (c'est à ce moment que macOS active l'app).
-- L'eventtap est en écoute seule : il ne bloque ni ne modifie aucun événement.
local function onKeyEvent(e)
  local etype = e:getType()
  if etype == eventTypes.keyDown then
    if e:getKeyCode() == TAB and e:getFlags().cmd then
      state.tabWithCmd = true
    end
  elseif etype == eventTypes.flagsChanged then
    if not e:getFlags().cmd then
      if state.tabWithCmd then
        state.lastCmdTab = now()
      end
      state.tabWithCmd = false
    end
  end
  return false
end

function M.start()
  if state.running then
    return M
  end
  log.setLogLevel(M.config.logLevel)

  state.appWatcher = hs.application.watcher.new(onAppEvent)
  state.appWatcher:start()

  if M.config.trigger == "cmdtab" then
    state.keyTap = hs.eventtap.new({ eventTypes.keyDown, eventTypes.flagsChanged }, onKeyEvent)
    state.keyTap:start()
    -- macOS désactive parfois les eventtaps (lenteur, veille) : on le relance.
    state.watchdog = hs.timer.doEvery(5, function()
      if state.keyTap and not state.keyTap:isEnabled() then
        log.w("eventtap désactivé par le système, redémarrage")
        state.keyTap:start()
      end
    end)
  end

  state.running = true
  log.i("démarré (déclencheur : " .. M.config.trigger .. ")")
  return M
end

function M.stop()
  for _, key in ipairs({ "appWatcher", "keyTap", "watchdog" }) do
    if state[key] then
      state[key]:stop()
      state[key] = nil
    end
  end
  for bundleID, timer in pairs(state.pending) do
    timer:stop()
    state.pending[bundleID] = nil
  end
  state.running = false
  log.i("arrêté")
  return M
end

function M.toggle()
  if state.running then
    M.stop()
    hs.alert.show("Reopen fenêtres : désactivé")
  else
    M.start()
    hs.alert.show("Reopen fenêtres : activé")
  end
  return M
end

function M.isRunning()
  return state.running
end

return M
