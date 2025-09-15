# SmithsReach (KCD2)
Auto-pull blacksmithing materials from your stash when you open the forge, and return leftovers when you leave. Detects crafted outputs via a lightweight heartbeat so you don’t have to click anything extra.

> **Status:** Gameplay is stable. Core is slim; console debug lives in `Debug.lua`.

---

## ✨ Features
- **Auto-pull on open:** Clones only whitelisted smithing mats from stash → player, respecting caps per kind, per item, and total.
- **Heartbeat craft detect:** Watches inventory deltas; ignores tools (tongs/hammer) so only real outputs count.
- **Auto-reconcile on close:** Debits used materials from stash and removes leftover clones from player.
- **Configurable FX & logs:** Optional toasts and verbose logs for troubleshooting.
- **Debug console suite:** Commands to inspect stash/player, diff counts, and discover unknown mat IDs.

---

## 📦 Install
1. Drop the `scripts/SmithsReach/` folder into your mod directory.
2. Ensure your `init.lua` (or equivalent) loads **in this order**:
   ```lua
   Script.ReloadScript("scripts/SmithsReach/Config.lua")
   Script.ReloadScript("scripts/SmithsReach/CraftingMats.lua")
   Script.ReloadScript("scripts/SmithsReach/Stash.lua")
   Script.ReloadScript("scripts/SmithsReach/Core.lua")
   Script.ReloadScript("scripts/SmithsReach/Debug.lua")
