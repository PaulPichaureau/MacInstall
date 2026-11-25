# Hammerspoon : rouvrir les fenêtres au Cmd+Tab

`reopen_windowless.lua` corrige un comportement de macOS : Cmd+Tab active une app sans rouvrir sa fenêtre si on l'avait fermée. Le module détecte le Cmd+Tab et, si l'app arrivée au premier plan n'a aucune fenêtre visible, lui envoie l'événement « reopen », comme un clic sur son icône dans le Dock. Une fenêtre s'ouvre alors, ou une fenêtre minimisée revient.

Pour installer Hammerspoon, lance `brew install --cask hammerspoon` et ouvre l'app une première fois. Dans Réglages Système > Confidentialité et sécurité > Accessibilité, autorise Hammerspoon. Si macOS demande aussi « Surveillance de l'entrée », accepte : c'est ce qui permet de voir le Cmd+Tab passer. Dans les préférences de Hammerspoon, coche « Launch Hammerspoon at login ».

Pour mettre la config en place sans config existante, remplace `~/.hammerspoon` par un lien vers ce dossier, ce qui garde la config versionnée dans le repo :

```sh
mv ~/.hammerspoon ~/.hammerspoon.bak 2>/dev/null
ln -s "$HOME/chemin/vers/MacInstall/hammerspoon" ~/.hammerspoon
```

Si tu as déjà un `init.lua`, copie `reopen_windowless.lua` dans `~/.hammerspoon/` et ajoute les lignes `reopenWindowless = require("reopen_windowless")` et `reopenWindowless.start()` à ton `init.lua`.

Pour l'utiliser au quotidien, Ctrl+Alt+Cmd+W active ou désactive le module. Les réglages (déclencheur, délai, exclusions, niveau de log) se changent dans `init.lua` ; la config se recharge toute seule à l'enregistrement. Pour comprendre un comportement inattendu, passe `logLevel` à `"debug"` et ouvre la console Hammerspoon (icône de barre de menus > Console).

Il y a quelques limites connues. Le Finder est exclu par défaut, sinon chaque clic sur le bureau ouvrirait une fenêtre. Si une app a ses fenêtres sur un autre Space et que tu obtiens une fenêtre en double, augmente `delay`. Le réglage macOS « Lors du changement d'application, basculer vers un Space avec des fenêtres ouvertes » (Réglages Système > Bureau et Dock) doit rester activé. Les apps qui ignorent le reopen ne réagiront pas : le module n'y peut rien.

# Clic sur l'icône du Dock pour masquer

`dock_toggle.lua` change le clic sur l'icône Dock de l'app déjà au premier plan : au lieu de ne rien faire, il la masque (comme Cmd+H), et le clic suivant la ramène. Avec `dockToggle.config.action = "minimize"` dans `init.lua`, il réduit plutôt les fenêtres dans le Dock, et le clic suivant les restaure toutes. Tenir une touche de modification pendant le clic rend au Dock son comportement normal, ce qui sert notamment à déplacer l'icône de l'app active. Ctrl+Alt+Cmd+D active ou désactive le module.
