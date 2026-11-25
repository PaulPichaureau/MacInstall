-- Configuration Hammerspoon (~/.hammerspoon/init.lua)

-- Rouvrir une fenêtre quand Cmd+Tab amène une app qui n'en a plus.
-- Variable globale obligatoire : une variable locale serait collectée par le
-- garbage collector et les watchers s'arrêteraient sans prévenir.
reopenWindowless = require("reopen_windowless")

-- Réglages à ajuster selon l'usage (valeurs par défaut dans reopen_windowless.lua) :
-- reopenWindowless.config.trigger = "any"     -- agir aussi via Dock, Spotlight, clic…
-- reopenWindowless.config.delay = 0.6         -- si des fenêtres apparaissent en double
-- reopenWindowless.config.logLevel = "debug"  -- tracer chaque activation dans la console
-- reopenWindowless.config.exclude["com.apple.Preview"] = true
-- reopenWindowless.config.exclude["com.apple.TextEdit"] = true

reopenWindowless.start()

-- Ctrl+Alt+Cmd+W : activer / désactiver à la volée.
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "W", reopenWindowless.toggle)

-- Recharger automatiquement la config quand un fichier .lua change.
configWatcher = hs.pathwatcher.new(hs.configdir, function(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()

hs.alert.show("Config Hammerspoon chargée")
