# 🏥 Hospital Check-In System
### QBCore · ox_target · FiveM

---

## Features

- **ox_target third-eye** on a check-in point (desk, sign, NPC — your choice)
- Assigns player to **one of 6 hospital beds** dynamically (first-come, first-served)
- **Revives the player completely** — health, armour, hunger, thirst, stress all restored
- **NLR (New Life Rule) notification** pops up on screen after revival reminding the player they must not remember the last 15 minutes
- Server-side **bed occupancy tracking** — beds auto-free after 30 seconds (configurable)
- Player **disconnect safety** — bed is freed if the occupying player drops
- Admin command `/clearbeds` to manually reset all beds

---

## Installation

1. Drop the `hospital_checkin` folder into your **`resources/`** directory.
2. Add `ensure hospital_checkin` to your **`server.cfg`**.
3. Make sure **`qb-core`** and **`ox_target`** are both started *before* this resource.

```
ensure qb-core
ensure ox_target
ensure hospital_checkin
```

---

## Configuration

All configurable values live at the top of `client.lua` inside the `Config` table:

| Key | Default | Description |
|-----|---------|-------------|
| `CheckInCoords` | `vector3(340.36, -1397.2, 32.51)` | World position of the ox_target third-eye sphere |
| `BedSpawns[1–6]` | Sandy Shores hospital area | `vector4(x, y, z, heading)` for each bed |
| `BlackoutDuration` | `3000` (ms) | How long the screen fades to black on check-in |
| `ReviveAnimation` | Tourist idle | Animation played while the player wakes up |

### Changing the Check-In Location

Replace `Config.CheckInCoords` with your hospital's desk coordinates. Use `GetEntityCoords(PlayerPedId())` in-game or a coords script to get exact values.

### Adjusting Bed Positions

Edit each entry in `Config.BedSpawns`. The `w` component of each `vector4` is the **heading** (direction the player faces when placed in bed). Beds should face away from the wall or toward a nurse station.

### Auto-Release Timer

In `server.lua`, find:
```lua
SetTimeout(30000, function()
```
Change `30000` (30 seconds) to however long you want a bed held before it auto-frees. If you want players to manually leave beds, remove this block and add a second ox_target zone on each bed for a "Leave Bed" option.

---

## NLR Notification

After revival, two notifications fire:

1. **DrawText** overlay (upper-left, persistent until dismissed) — styled with colour codes
2. **QBCore Notify** toast — visible for 8 seconds

If you prefer **ox_lib** notifications, replace the `Notify()` helper in `client.lua`:

```lua
local function Notify(msg, type, duration)
    lib.notify({ title = 'Hospital', description = msg, type = type, duration = duration })
end
```

---

## Dependencies

- [qb-core](https://github.com/qbcore-framework/qb-core)
- [ox_target](https://github.com/overextended/ox_target)

---

## Admin Commands

| Command | Permission | Description |
|---------|-----------|-------------|
| `/clearbeds` | `admin` | Resets all bed occupancy immediately |

---

## File Structure

```
hospital_checkin/
├── fxmanifest.lua   — Resource manifest
├── client.lua       — ox_target zone, teleport, animation, NLR notify
├── server.lua       — Bed state, revive callback, stat restore, drop handler
└── README.md        — This file
```
