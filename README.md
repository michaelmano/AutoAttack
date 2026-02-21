# AutoAttack

A lightweight World of Warcraft addon for **Turtle WoW** (1.12 client) that automatically starts auto-attack so you never stand still doing nothing.

Compatible with **SuperWoW**, **VanillaFixes**, and **nampower**.

---

## Features

- **Auto-attack on ability use** — press any ability even with no rage/energy/mana and auto-attack starts immediately, just like having `/startattack` at the top of every macro.
- **Retaliate when hit** — if a mob attacks you while you have no target, the game auto-focuses it and this addon immediately starts attacking back. Can be toggled on/off.
- **Mandokir/Ohgan suppression (ZG)** — in Zul'Gurub, if you or anyone in your raid targets Ohgan or Bloodlord Mandokir, auto-attack is suppressed so you don't accidentally break the encounter. It re-enables automatically once nobody is targeting them.
- **Debug mode** — prints detailed output to chat so you can see exactly what the addon is doing and why.
- **Persistent settings** — all settings are saved between sessions via `SavedVariables`.

---

## Installation

### Option A — Git clone
```bash
cd "path/to/wow/Interface/AddOns"
git clone https://github.com/michaelmano/AutoAttack.git
```

### Option B — Download ZIP
1. Click **Code → Download ZIP** on the GitHub repository page.
2. Extract the ZIP — this will produce a folder called `AutoAttack-master`.
3. Rename it to `AutoAttack` (remove the `-master` suffix).
4. Move the `AutoAttack` folder into:
   ```
   path/to/wow/Interface/AddOns/
   ```
5. Launch the game and enable **AutoAttack** in your addon list at the character select screen.

---

## Commands

| Command | Description |
|---|---|
| `/aa` | Toggle addon on/off |
| `/aa on` | Enable the addon |
| `/aa off` | Disable the addon |
| `/aa retaliate` | Toggle retaliate on/off |
| `/aa retaliate on` | Enable retaliate |
| `/aa retaliate off` | Disable retaliate |
| `/aa debug` | Toggle debug output on/off |
| `/aa debug on` | Enable debug output |
| `/aa debug off` | Disable debug output |
| `/aa status` | Show all current settings and session state |

---

## How It Works

### Auto-attack on ability use
Hooks every action bar button. When you press one, `SlashCmdList["STARTATTACK"]` is called — the same internal handler as `/startattack` in a macro. This is one-way only and will never toggle auto-attack off.

As a secondary fallback, the `SPELLCAST_FAILED` and `UI_ERROR_MESSAGE` events are also listened to, catching any ability failure that the button hook might miss.

### Retaliate when hit
Listens to `PLAYER_REGEN_DISABLED` (entering combat) and `PLAYER_TARGET_CHANGED` (game auto-focused your attacker). Either event triggers an immediate attack on the current target if it's hostile.

The retaliate setting only controls these passive triggers. Manual button presses and spell failures always start auto-attack regardless of the retaliate setting — because you deliberately pressed something.

### Mandokir/Ohgan suppression
Only active inside Zul'Gurub (`GetZoneText() == "Zul'Gurub"`). When **you** target Ohgan or Bloodlord Mandokir, a raid scan begins polling every 0.5 seconds checking every `raidXtarget` for those units. While any raid member is targeting either of them, auto-attack is suppressed. The poll stops automatically once everyone has stopped targeting them and normal behaviour resumes.

The scan **only runs while polling is active** — there is no `OnUpdate` overhead anywhere else in the world or before you personally target a watched unit.

### Debug mode
When enabled with `/aa debug`, every event and decision is printed to chat in grey — what fired, what was blocked, why, and what target was attacked. Useful for diagnosing unexpected behaviour. The setting persists across sessions so you can enable it before logging in if needed.

---

## ZG Suppression Flow

```
You target Ohgan or Mandokir
        ↓
Polling starts (0.5s interval)
        ↓
Any raid member targeting them? → YES → Suppressed (auto-attack blocked)
        ↓
All raid members stop targeting  → Suppression lifted, polling stops
```

---

## Troubleshooting

**Auto-attack isn't starting**
- Type `/aa status` and confirm it shows `ON`.
- Make sure you have a hostile, living target selected.
- Enable debug with `/aa debug` and check the chat output to see what is blocking it.

**Retaliate isn't working**
- Type `/aa status` and confirm `Retaliate` shows `ON`.
- Retaliate only fires when you enter combat passively (a mob hits you). If you initiated combat yourself it won't trigger — use an ability or button instead.

**ZG suppression isn't triggering**
- Type `/aa status` inside ZG and check the `Zone:` field. It should show `Zul'Gurub` exactly. If it shows something different, open `AutoAttack.lua` and update the `ZG_ZONE` value at the top of the file to match.

**Suppression won't lift**
- Type `/aa status` and check `Polling` and `Suppressed`. If polling stopped but suppressed is still `yes`, relog — this shouldn't happen normally.