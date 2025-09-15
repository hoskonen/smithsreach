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

## 🧪 Debug utilities (quick ref)

> Debug lives in `Debug.lua`. It doesn’t change gameplay; it just prints info to the log/console.

### General
| Command | What it does |
|---|---|
| `smithsreach_ping` | Smoke test (`[SmithsReach] pong`). |
| `smithsreach_config_dump` | Show effective config summary. |
| `smithsreach_mats_where` | Counts for **whitelisted** mats in stash vs player. |
| `smithsreach_scan_unmatched` | Print paste-ready `bsmt_*` entries missing from `CraftingMats.lua`. |
| `smithsreach_find <substr>` | Find stash items by UI/DB name substring. |

### Stash
| Command | What it does |
|---|---|
| `smithsreach_stash_methods` | Probe `stash.inventory` API (GetInventoryTable, CreateItem, Dump…). |
| `smithsreach_stash_names` | List first N stash items with UI/DB names. |
| `smithsreach_stash_summary` | Group stash by class with names. |
| `smithsreach_stash_raw` | Dump raw `GetInventoryTable` entry types. |
| `smithsreach_stash_dump` | Call `stash.inventory:Dump()` if available. |

### Player / Inventory
| Command | What it does |
|---|---|
| `smithsreach_item_dump <wuid>` | Dump `ItemManager:GetItem(wuid)` fields. |
| `smithsreach_inv_methods` | Probe `player.inventory` API. |
| `smithsreach_inv_dump` | Call `player.inventory:Dump()` if available. |
| `smithsreach_inv_summary` | Group player inventory by class with names. |
| `smithsreach_diff_stash_pl` | Diff stash vs player class counts. |
| `smithsreach_pull_one` | Clone first stash item → player (sanity test). |

### Gameplay hooks (live in Core)
| Command | What it does |
|---|---|
| `smithsreach_hook_smithery` | Wrap smithery use to auto-start session. |
| `smithsreach_hook_minigame` | Attach minigame end listeners (best-effort). |
| `smithsreach_craft_end` | Manually force close/reconcile (test). |
| `smithsreach_hook_psh_end` | Wrap PSH minigame end. |

> Tip: if a command is “unknown,” ensure your init loads in this order:  
> `Config.lua → CraftingMats.lua → Stash.lua → Core.lua → Debug.lua`
