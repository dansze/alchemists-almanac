# OpenMW Lua API — Full Overview (module details + mod best practices)

Companion to `openmw-lua-api-reference.md` (loading, registration, sandbox).
Sources: module definitions at `/nvme1/OMW/resources/lua_api/openmw`, online reference
(https://openmw.readthedocs.io/en/latest/reference/lua-scripting/api.html), and ~35 installed
mods under `/nvme1/OMW/momw-mods`.

## 1. Module inventory (`require('openmw.<module>')`)

### Core / player / inventory — most relevant to this project

- **`core`** — engine core. `GameObject` type (universal object handle:
  `getRefData()`, `getPosition()`, `sendEvent(name, params)`, `castSpell(...)`,
  `applyEffect(effectId, magnitude, duration, area)`).
  `core.executeConsoleCommand(cmd)` for console commands from Lua.
  `core.magic.EFFECT_TYPE.*` effect ID constants; `core.magic.effects.records[name]`.
- **`self`** — player access: `getActor()` → player GameObject, `getInventory()`,
  convenience item add/remove helpers. In a PLAYER script the global `self` IS the player actor.
- **`interfaces`** (`I`) — per-object interface methods + cross-mod interfaces.
  Inventory: `getItems()`, `add(item, count)`, `remove(item, count)`, `hasItem(id)`,
  `getItemCount(id)`. Also Actor, Cell, Container, MagicEffects, AnimationController.
- **`types`** — typed record accessors. `types.<RecordClass>.record(id)` → full ESM/ESP
  field table (actors, ingredients, potions, apparatus, ...). Stats:
  `types.NPC.stats.skills.alchemy(player)` → `{base, modifier, current}` (mutate in place).
  Inventory: `types.Player.inventory(p):find/:getAll/:moveInto`.
  Active effects: `types.Actor.activeEffects(actor):modify(delta, EFFECT_TYPE.X)`.

### World / cell

- **`world`** — `getCell()` → Cell object (name, id, interior/exterior, position),
  time-of-day get/set, weather. Also dynamic record creation:
  `core.magic.spells.createRecordDraft({...})` → `pcall(world.createRecord, draft)`;
  `world.createObject(id, count)`, `obj:moveInto(inv)`, `obj:teleport(cell, pos, rot)`.

### Messaging / UI

- **`ui`** — `showMessage(text, opts)`, `printToConsole(msg, ui.CONSOLE_COLOR.Info/Error)`,
  custom widgets via `ui.create({layer=..., type=ui.TYPE.Text, props={relativePosition=util.vector2(...), anchor=..., textColor=util.color.rgb(...)}})`
  → element with `:destroy()`. Blocking input: `I.UI.setMode("Jail")`; drive vanilla menus by
  sequencing `I.UI.setMode("ChargenName")` etc. with a ~0.01 s confirm timer checking
  `not I.UI.getMode()` before advancing.
- **`menu`** — `isMenuOpen(type?)`, `open(type)`, `close()` (`"inventory"`, `"magic"`, ...).
- **`markup`** — parses MW markup text (`{red}...{/}`, links) into styled segments.

### Timers / async

- **`async`** — the standard timer API:
  - `async:newSimulationTimer(seconds, fn)` (savable)
  - `async:newUnsavableSimulationTimer(seconds, fn)`
  - `async:registerTimerCallback(name, fn)` (named = savable)
  - `async:callback(fn)` wrapper for one-shots.
  For per-frame throttling use a manual accumulator (`if t >= 0.25 then ...`) in
  `onUpdate(dt)`, not many timers. `onUpdate` receives `dt == 0` while paused — usable as
  pause/resume detector.

### Supporting modules

| Module | Key exports |
|---|---|
| `util` | `vector2/3/4`, `color.rgb(r,g,b[,a])`, transforms/matrices |
| `debug` | logging/diagnostics |
| `input` | key/mouse state, key constants; `input.registerActionHandler(action, cb)` (action-based beats raw `onKeyPress` — text fields eat raw keys) |
| `storage` | persistent key/value across saves: `storage.playerSection("Name"):get/set/subscribe/asTable`; also global sections for cross-script coordination |
| `vfs` | read/write/list files in game VFS (e.g. loading recipe data shipped with the mod) |
| `nearby` | `getActors()`, `getObjects()`, raycasting (`RayCastingResult`, `COLLISION_TYPE`) |
| `content` | loaded plugins list/load order; `core.contentFiles.has('X.omwaddon')` for compat gates |
| `ambient` | `playSound(id, opts)`, `playSoundFile(path, opts)`, stop/isPlaying, `streamMusic`, `say(file, subtitle)` |
| `animation` | `PRIORITY`/`BLEND_MASK`/`BONE_GROUP`; `playQueued`, `playBlended`, `addGlow`, `addVfx`/`removeVfx` |
| `camera` | camera mode, FOV, `worldToViewportVector`/`viewportToWorldVector`, `getFocusRay()` (crosshair targeting) |
| `postprocessing` | `load(name)` → Shader with `enable/disable/setFloat/...` (glow overlays etc.) |

## 2. Script shape and events

Every script returns a table:

```lua
return {
    engineHandlers = { onInit, onActive, onLoad, onSave, onFrame, onUpdate,
                       onKeyPress, onMouseButtonPress, onConsoleCommand, ... },
    eventHandlers  = { MyEvent = fn, UiModeChanged = fn, ... },
    -- optional: interfaceName + interface (public API for other mods)
}
```

- File roles are conventional: `global.lua` (world access), `player.lua` (`self` = player),
  `npc.lua`/`creature.lua`, per-object scripts attached at runtime with
  `obj:addScript(path, {params})` / `:removeScript(path)`.
- Built-in engine events in use across the mod corpus: `onFrame`, `onUpdate(dt)`,
  `onLoad/onSave`, `onInit/onActive`, `UiModeChanged`, `onQuestUpdate`, `onConsume`,
  `onTeleported`, `onKeyPress`, `onConsoleCommand(mode, command, selectedObject)`.
- Load-time work goes in `onLoad`/`onInit` of the player script, guarded by
  `types.Player.isCharGenFinished(self)`.
- **Events**: player-local `self:sendEvent(name, data)`; global bus
  `core.sendGlobalEvent(name, data)` (the universal channel for player↔global↔object scripts
  and inter-mod signals).

## 3. Cross-mod interfaces (`I.<Name>`)

Publish by returning `{ interfaceName = "MyMod", interface = { fn = ... } }`; consume via
`interfaces.MyMod` **after a nil-check** (capability detection, degrade gracefully).
Notable built-in/installed ones seen in mods:

- `I.ItemUsage.addHandlerForType(types.Potion/types.Ingredient, fn)` — intercept item use;
  return `false` to block.
- `I.Combat.addOnHitHandler(fn)` — inspect/mutate `attackInfo.damage[key]`, `.successful`,
  `.sourceType`.
- `I.UI.setMode/getMode` — force vanilla UI windows.
- `interfaces.Settings.registerPage/registerGroup` — auto-generated in-game settings UI
  (renderers: `'number'`, `'checkbox'`; `argument = {min,max}`; `permanentStorage = true`).
- Third-party: `I.SkillFramework`, `I.InventoryExtender.registerTooltipModifier(name, fn)`
  (wrap in `pcall` — layout shapes drift), `interfaces.TPA_AlchemyRedone`
  (`registerPotionModifier('Name', fn)` — receives draft record + ingredient list, returns
  modified draft: magnitude/duration/value/weight).

## 4. Best practices observed in installed mods

- **Defensive, not exception-based**: `pcall` around optional `require`s and
  `world.createRecord`; universal `item:isValid()` / `item.count == 0` guards before use;
  compat gate at top of player script (`if not mCompat.check(...) then return end`);
  one-shot "warned" flags so missing-dependency warnings print once.
- **Save persistence**: `onSave = function() return data end` / `onLoad(data)` with
  defaults; version field + `upgradeOldState(oldState)` migration branches.
- **Settings**: modern pattern = a `store.lua` describing each setting (order, section,
  renderer, default) with `.get()/.set()` wrappers; hot paths cache via
  `section:asTable()` + `section:subscribe(async:callback(fn))`; clamp every read.
- **Throttling**: manual accumulators in `onUpdate` for periodic work (0.25 s tick etc.).
- **Feedback**: `ui.showMessage(text, {showInDialogue=false})` for lightweight notices;
  `ui.printToConsole(msg, ui.CONSOLE_COLOR.Info/Error)` for console output;
  custom popups via `ui.create({layer='Notification', ...})`, tracked in a stack with
  `expiresAt = core.getSimulationTime() + duration`, pruned in `onUpdate`, `:destroy()`d.
- **Deferred world mutations**: when acting from UI callbacks, queue the mutation and apply
  it next frame (InventoryExtender's delayed-job queue) — never mutate containers mid-callback.
- **Cross-script coordination without a server**: shared `storage.playerSection` keys with
  heartbeats + staleness check (Evasion family elects one popup manager this way).
- **Alchemy-specific reference impl**: SaneCustomPotions — registers an Alchemy Redone potion
  modifier, reads alchemy skill via `types.NPC.stats.skills.alchemy(player).modified` and
  apparatus quality via `types.Apparatus.record(id).quality`.

## 5. Typical wiring for this project (alchemy helper UI)

```
self (player actor)
 ├─ types.Player.inventory(self)          -- ingredients held, find/getAll/moveInto
 ├─ types.<Record>.record(id)             -- ingredient/potion effect data
 ├─ I.ItemUsage.addHandlerForType(...)    -- intercept potion/ingredient use if needed
 ├─ ui.create({layer='Notification', ...})-- custom panel/popups
 ├─ markup.parse                          -- styled text in widgets
 ├─ async:newSimulationTimer / accumulator in onUpdate  -- timers/polling
 ├─ storage.playerSection("AHSettings")   -- settings, persisted
 └─ core.executeConsoleCommand            -- debugging/testing
```

Context rules: game-state APIs need the player (gameplay) context; menu-context functions
only when operating from an inventory-screen widget. Each module function is tagged
`@context player|menu|local|...` in the doclua shims.
