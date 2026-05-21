<img width="640" height="298" alt="image" src="https://github.com/user-attachments/assets/88ea7e68-b432-4e43-8559-3d57ae29706b" />

<img width="628" height="644" alt="image" src="https://github.com/user-attachments/assets/dd1bde3e-13eb-4716-aa42-eed21f9722f1" />

```
Savory Deviate Delight
Noggenfogger Elixir
Drums of the Wild
Drums of Forgotten Kings
Drums of Speed
Lesser Flask of Toughness
Flask of Endless Rage
Scroll of Strength VIII
Runescroll of Fortitude
Stormchops
Fish Feast
Swiftness Potion

Flask of Pure Mojo
Flask of the Frost Wyrm
```



# BlackrockAssist

World of Warcraft **3.3.5a** (WotLK) addon that highlights UI frames under the mouse and shows identifiers you can use in Lua/macros.

## Install

The folder layout **must** be:

```
World of Warcraft/Interface/AddOns/BlackrockAssist/BlackrockAssist.toc
World of Warcraft/Interface/AddOns/BlackrockAssist/BlackrockAssist.xml
World of Warcraft/Interface/AddOns/BlackrockAssist/Core.lua
```

From this repo (WSL/Linux):

```bash
chmod +x copy-to-game.sh
# Edit wow-path.local.sh once (see below), then:
./copy-to-game.sh
```

**WoW path (WSL vs Windows):**

| Windows | WSL |
|---------|-----|
| `C:\D_Drive\Games\World of Warcraft - WOTLK 3.3.5a` | `/mnt/c/D_Drive/Games/World of Warcraft - WOTLK 3.3.5a` |

- `/mnt/c` = your **C:** drive  
- `/mnt/d` = your **D:** drive (only if Windows has a D: drive)  
- A folder named `D_Drive` on **C:** is just a normal folder → use `/mnt/c/D_Drive/...`, **not** `/mnt/d/`

Copy `wow-path.local.sh` and set `WOW_DIR` to your install. The default in `copy-to-game.sh` matches `BG_HealerMark` (`C:\D_Drive\Games\...`).

**Important:** The `.toc` file name must match the folder name (`BlackrockAssist.toc` inside `BlackrockAssist/`). Do not put the `.toc` directly under `AddOns/`.

### Addon not in the list?

1. **Character select screen** — In WotLK 3.3.5a, addons are managed on the **login / character select** screen via the **AddOns** button (bottom-left). There is no full addon list in the in-game Esc menu like retail.
2. **Correct WoW folder** — Copy into the install you actually launch (see `wow-path.local.sh`). Do not use `/mnt/d/...` unless WoW really lives on Windows drive D:.
3. **Load out of date AddOns** — On the character select AddOns window, check **Load out of date AddOns** if your client build does not match `30300`.
4. **After copying** — Exit the game completely and start it again (or `/reload` if already in world after enabling).

Enable **BlackrockAssist** on the character select screen, then `/reload`.

## Usage

| Command | Action |
|--------|--------|
| `/ba` | Toggle inspector on/off |
| `/ba on` / `/ba off` | Force state |
| `/ba click FrameName` | Fire `Click()` or `OnClick` on a global frame (e.g. `TradeFrameCloseButton`) |
| `/ba help` | Show commands |

**Default:** inspector is **ON** when you log in (saved in `BlackrockAssistDB`).

Hover any UI window, panel, or button:

- Edges glow (cyan ADD blend border)
- A label above the frame shows its **global name** (e.g. `CharacterFrameCloseButton`) or a stable anonymous ref `BA_Frame_N`
- A second line shows type, parent, and a Lua reference snippet

### Referencing frames in Lua

**Named frame:**

```lua
_G["CharacterFrameCloseButton"]:Click()
-- or
CharacterFrameCloseButton:Click()
```

**Anonymous frame** (no `GetName()`): hover it once to assign `BA_Frame_3`, then:

```lua
BA:GetFrame("BA_Frame_3"):Click()
```

**Child with ID** (parent has a name): label shows `id:4 (parent SomeFrame)` — locate via parent APIs or use a named child instead.

### Macros

Only **named** global frames work in secure macro `/click` syntax, for example:

```
/click TradeFrameCloseButton
```

Use `/ba click TradeFrameCloseButton` from chat for quick testing outside combat when the frame allows it.

## Notes

- Uses `GetMouseFocus()` — the deepest mouse-enabled frame under the cursor.
- Secure/action buttons may not be clickable from addons in combat; highlighting still works.
- Anonymous refs are session-only (not saved across reload).
