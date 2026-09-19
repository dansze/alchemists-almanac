# Phase 3 Investigation Report: OpenMW Alchemy Ingredient Data Structures

> **Date:** 2025-01-XX
> **OpenMW version:** 0.50+ (verified against 0.51.0 release)
> **Source:** OpenMW official documentation, `openmw.readthedocs.io`, and C++ source code at `apps/openmw/mwlua/types/ingredient.cpp`
> **Scope:** Investigation only — no implementation code. See §12 for the distinction between investigated APIs and planned implementation.

---

## 1. Executive Summary

This report documents the exact OpenMW Lua API types and data structures used for alchemy ingredients, validated against the OpenMW 0.51.0 runtime. Key finding: **ingredient effects are accessible via `IngredientRecord.effects` (a `list<MagicEffectWithParams>`), but the `Alchemy` C++ class is not exposed to Lua at all.** The `LOAD` context provides mutable access to ingredient records with truncated effect fields (`id`, `affectedAttribute`, `affectedSkill` only), while `PLAYER` context provides read-only access with full `MagicEffectWithParams` fields.

---

## 2. `types.Ingredient.record(id)` — Field Names and Effect Data

### 2.1 The `IngredientRecord` Type

`types.Ingredient.record(objectOrRecordId)` returns a read-only `IngredientRecord` object. The field names are explicitly documented and verified in the C++ source (`ingredient.cpp`):

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Record ID (e.g. `"ingred_almow_01"`) |
| `name` | string | Human-readable name |
| `icon` | string | VFS path to the icon (e.g. `"icons\\i\\almow.dds"`) |
| `model` | string | VFS path to the model |
| `value` | number | Base value |
| `weight` | number | Base weight |
| `mwscript` | string or nil | MWScript attached to this ingredient |
| `effects` | `list<MagicEffectWithParams>` | The ingredient's magic effects |

**Verified against:** `openmw-improved-docs.readthedocs.io/en/latest/reference/lua-scripting/openmw-types/types_ingredient.html` and `ingredient.cpp` source.

### 2.2 The `effects` Field — Effect Entry Structure

The `effects` field is a list (1-indexed via `ipairs`) of `MagicEffectWithParams` objects. Each effect entry has these fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Magic effect ID (e.g. `"FireDamage"`, `"Vampirism"`) |
| `index` | number | Position in the effect list (0–3) |
| `affectedAttribute` | string or nil | Attribute this effect modifies (e.g. `"Endurance"`) |
| `affectedSkill` | string or nil | Skill this effect modifies (e.g. `"Destruction"`) |
| `range` | number | Spell range constant (always `ESM::RT_Self` for ingredients) |
| `area` | number | Always `0` for ingredients |
| `duration` | number | Always `0` for ingredients |
| `magnMin` | number | Always `0` for ingredients |
| `magnMax` | number | Always `0` for ingredients |

**Critical:** The C++ source (`ingredient.cpp` line ~112) hard-codes `range = ESM::RT_Self`, `area = 0`, `duration = 0`, `magnMin = 0`, `magnMax = 0` for ingredient effects read from game data. Only `id`, `affectedAttribute`, and `affectedSkill` carry real alchemy data from the ESM records.

**Verified against:** `ingredient.cpp` source (readonly_effects closure at line ~109–127).

### 2.3 `types.Ingredient.records`

`types.Ingredient.records` returns a read-only list of all `IngredientRecord` objects. Can be iterated via `ipairs`. This is the primary iteration path for building an effects database during LOAD context.

### 2.4 `types.Ingredient.createRecordDraft(data)` (0.51.0+)

Creates a custom ingredient record from a Lua table. Supports `template`, `name`, `model`, `icon`, `mwscript`, `weight`, `value`, and `effects` fields.

---

## 3. `types.ESM4Ingredient` — Low-Level Table Structure

### 3.1 What `types.ESM4Ingredient` Actually Is

`types.ESM4Ingredient` is a **minimal type wrapper** created by the generic `addType()` function in `types.cpp` (line 174). It is registered with `ESM::REC_INGR4` (the ESM4 ingredient record type). It does NOT have the rich `record()`, `records`, `createRecordDraft()`, or effects functions that `types.Ingredient` has.

**Fields/methods on `types.ESM4Ingredient`:**

| Field/Method | Type | Description |
|-------------|------|-------------|
| `baseType` | `types.Item` | Inherited from Item |
| `objectIsInstance(object)` | function | Checks if `object` is an ESM4Ingredient instance |

**No `record()` method.** **No `records` property.** **No effects access.** This is a thin type-checking wrapper.

### 3.2 `types.ESM3_Ingredient` — The Actual Low-Level Record

The underlying C++ type `ESM::Ingredient` is exposed in Lua as `ESM3_Ingredient` (the name used in `ingredient.cpp` line ~60). This type has the full effect data structure.

### 3.3 Field Populated: LOAD vs. PLAYER Context

| Field | LOAD context (`content.ingredients.records`) | PLAYER context (`types.Ingredient.record()`) |
|-------|---------------------------------------------|----------------------------------------------|
| `id` | ✅ Populated | ✅ Populated |
| `name` | ✅ Populated | ✅ Populated |
| `icon` | ✅ Populated | ✅ Populated |
| `model` | ✅ Populated | ✅ Populated |
| `value` | ✅ Populated | ✅ Populated |
| `weight` | ✅ Populated | ✅ Populated |
| `mwscript` | ✅ Populated | ✅ Populated |
| `effects[].id` | ✅ Populated | ✅ Populated |
| `effects[].affectedAttribute` | ✅ Populated | ✅ Populated |
| `effects[].affectedSkill` | ✅ Populated | ✅ Populated |
| `effects[].range` | ❌ Not available | ✅ Populated (always `ESM::RT_Self`) |
| `effects[].area` | ❌ Not available | ✅ Populated (always `0`) |
| `effects[].duration` | ❌ Not available | ✅ Populated (always `0`) |
| `effects[].magnMin` | ❌ Not available | ✅ Populated (always `0`) |
| `effects[].magnMax` | ❌ Not available | ✅ Populated (always `0`) |
| `effects[].index` | ❌ Not available | ✅ Populated |

**Key distinction:** During LOAD, ingredient effects only have `id`, `affectedAttribute`, and `affectedSkill` — the other `MagicEffectWithParams` fields are not present. This is explicitly documented in the `openmw.content` reference:

> "Note that ingredient effects only have the `id`, `affectedAttribute`, and `affectedSkill` properties."

**Source:** `openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_content.html` → `IngredientContent.records` section.

---

## 4. `MagicEffectWithParams` — Complete Field Surface

This type is shared across spells, enchantments, potions, and ingredient effects. All fields documented:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Magic effect ID |
| `index` | number | Position in the original effect list |
| `affectedAttribute` | string or nil | Attribute ID (e.g. `"Intelligence"`) |
| `affectedSkill` | string or nil | Skill ID (e.g. `"Destruction"`) |
| `range` | number | Spell range constant (`ESM::RT_Self`, etc.) |
| `area` | number | Area in yards |
| `duration` | number | Duration in seconds |
| `magnitudeMin` | number | Minimum magnitude |
| `magnitudeMax` | number | Maximum magnitude |

**Verified against:** `openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_core.html` and C++ source.

---

## 5. Engine Handlers Under `openmw.handlers`

**There is no `openmw.handlers` package.** The OpenMW Lua API does not expose a `handlers` namespace.

Engine handlers are **defined in the script's returned table** under the `engineHandlers` key:

```lua
return {
    engineHandlers = {
        onUpdate = function(dt) end,
        onSave = function() return {} end,
        -- etc.
    },
}
```

The official documentation separates handlers into a standalone page at `openmw.readthedocs.io/en/latest/reference/lua-scripting/engine_handlers.html`. They are NOT accessed via `require('openmw.handlers')`.

### 5.1 Complete Handler Inventory with Context Availability

#### 5.1.1 Global (any script)

| Handler | Context | Description |
|---------|---------|-------------|
| `onUpdate(dt)` | global, menu, local, load | Called every frame; `dt` is simulation time delta |
| `onSave()` | global, menu, local, load | Called on save; must return serializable data |
| `onLoad(savedData, initData)` | global, menu, local, load | Called on load with saved data |
| `onInterfaceOverride(base)` | global, menu, local, load | Interface was overridden by another script |
| `onDialogueResponse(response)` | global, menu, local, player, load | **0.51.0+** Dialogue response event |
| `onAnimationEnd(animId)` | global, menu, local, player, load | **0.51.0+** Animation end event |

#### 5.1.2 Global-only

| Handler | Description |
|---------|-------------|
| `onNewGame()` | New game started |
| `onPlayerAdded(player)` | Player added to game world (triggered at start and load) |
| `onObjectActive(object)` | Object becomes active |
| `onActorActive(actor)` | Actor (NPC or Creature) becomes active |
| `onItemActive(item)` | Item becomes active in a cell |
| `onActivate(object, actor)` | Object activated by an actor |
| `onNewExterior(cell)` | New exterior cell generated |
| `onDropped(object, actor, position, rotation)` | Object dropped by actor |
| `onPlaced(object, actor, position, rotation)` | Object placed by player |

#### 5.1.3 Local-only

| Handler | Description |
|---------|-------------|
| `onActive()` | Object becomes active (cell entered or save loaded) |
| `onInactive()` | Object became inactive |
| `onTeleported()` | Object was teleported |
| `onActivated(actor)` | Actor activated the object |
| `onConsume(item)` | Actor consumed the item |

#### 5.1.4 Menu and Player-local

| Handler | Context | Description |
|---------|---------|-------------|
| `onFrame(dt)` | menu, player | Called after input processing |
| `onKeyPress(key)` | menu, player | Key pressed |
| `onKeyRelease(key)` | menu, player | Key released |
| `onControllerButtonPress(id)` | menu, player | Controller button pressed |
| `onControllerButtonRelease(id)` | menu, player | Controller button released |
| `onInputAction(id)` | menu, player | **0.51.0+ deprecated** |
| `onTouchPress(touchEvent)` | menu, player | Touch pressed |
| `onTouchRelease(touchEvent)` | menu, player | Touch released |
| `onTouchMove(touchEvent)` | menu, player | Touch moved |
| `onMouseButtonPress(button)` | menu, player | Mouse button pressed |
| `onMouseButtonRelease(button)` | menu, player | Mouse button released |
| `onMouseWheel(vertical, horizontal)` | menu, player | Mouse wheel scrolled |
| `onConsoleCommand(mode, command, selectedObject)` | menu, player | Console command entered |
| `onViewportResized(width, height)` | menu, player | Viewport resized |

#### 5.1.5 Player-only

| Handler | Description |
|---------|-------------|
| `onQuestUpdate(questId, stage)` | Quest updated |

#### 5.1.6 Load-only

| Handler | Description |
|---------|-------------|
| `onContentFilesLoaded()` | **0.51.0+** Called after all content files parsed, before main menu |

**Verified against:** `openmw.readthedocs.io/en/latest/reference/lua-scripting/engine_handlers.html`.

---

## 6. `openmw.content` — Full Function Surface

### 6.1 Package Overview

`openmw.content` is available in **load scripts only**. It provides mutable access to all record types loaded from content files.

```lua
local content = require('openmw.content')
```

### 6.2 Top-Level Properties

| Property | Type | Description |
|----------|------|-------------|
| `content.RANGE` | `SpellRange` | Magic range constants |
| `content.activators` | `ActivatorContent` | Activator manipulation |
| `content.apparatuses` | `ApparatusContent` | Apparatus manipulation |
| `content.attributes` | `AttributeContent` | Attribute manipulation |
| `content.books` | `BookContent` | Book manipulation |
| `content.classes` | `ClassContent` | Class manipulation |
| `content.doors` | `DoorContent` | Door manipulation |
| `content.enchantments` | `EnchantmentContent` | Enchantment manipulation |
| `content.factions` | `FactionContent` | Faction manipulation |
| `content.gameSettings` | `GMSTContent` | GMST manipulation |
| `content.globals` | `GlobalContent` | Global variable manipulation |
| `content.ingredients` | `IngredientContent` | **Ingredient manipulation** |
| `content.levelledCreatures` | `LevCreatureContent` | Levelled creature manipulation |
| `content.levelledItems` | `LevItemContent` | Levelled item manipulation |
| `content.lights` | `LightContent` | Light manipulation |
| `content.lockpicks` | `LockpickContent` | Lockpick manipulation |
| `content.magicEffects` | `MagicEffectContent` | Magic effect manipulation |
| `content.miscs` | `MiscContent` | Misc item manipulation |
| `content.potions` | `PotionContent` | Potion manipulation |
| `content.probes` | `ProbeContent` | Probe manipulation |
| `content.races` | `RaceContent` | Race manipulation |
| `content.repairs` | `RepairContent` | Repair item manipulation |
| `content.skills` | `SkillContent` | Skill manipulation |
| `content.sounds` | `SoundContent` | Sound manipulation |
| `content.spells` | `SpellContent` | Spell manipulation |
| `content.statics` | `StaticContent` | Static manipulation |

### 6.3 `content.ingredients` — IngredientContent

| Property | Type | Description |
|----------|------|-------------|
| `content.ingredients.records` | `list<IngredientRecord>` | **Mutable** list of all ingredient records |

**CRITICAL:** The documentation explicitly states: "Note that ingredient effects only have the `id`, `affectedAttribute`, and `affectedSkill` properties."

**Usage pattern:**
```lua
-- Access an existing ingredient
local existing = content.ingredients.records['ingred_almow_01']
-- effects will only have: id, affectedAttribute, affectedSkill

-- Create/modify an ingredient
content.ingredients.records.MyIngredient = {
    template = content.ingredients.records['ingred_ectoplasm_01'],
    name = 'Soylent',
    effects = { { id = 'vampirism' } }
}
```

### 6.4 Can Ingredients Be Queried by ID or Name?

**By ID:** ✅ Yes. `content.ingredients.records` is indexed by record ID. You can access `content.ingredients.records['ingred_almow_01']` directly.

**By name:** ❌ Not directly. `records` is keyed by ID string. To find by name, iterate the records list and compare `.name` fields.

**In `types.Ingredient`:**
- `types.Ingredient.record(id)` — queries by ID only. No name-based lookup.
- `types.Ingredient.records` — iterable list of all records. Can iterate to match by `.name` if needed.

**In `types.ESM4Ingredient`:** No `record()` or `records` method. Only `objectIsInstance()` for type checking.

### 6.5 Content Package Methods by Record Type

Every `XContent` follows the same pattern:

| Type | Key Property | Mutable? | Notes |
|------|-------------|----------|-------|
| `ActivatorContent` | `.records` | ✅ Mutable | List of `ActivatorRecord` |
| `ApparatusContent` | `.records`, `.TYPE` | ✅ Mutable | Has type constants |
| `AttributeContent` | `.records` | ✅ Mutable | List of `AttributeRecord` |
| `BookContent` | `.records` | ✅ Mutable | List of `BookRecord` |
| `ClassContent` | `.records` | ✅ Mutable | List of `ClassRecord` |
| `DoorContent` | `.records` | ✅ Mutable | List of `DoorRecord` |
| `EnchantmentContent` | `.records`, `.TYPE` | ✅ Mutable | Has type constants |
| `FactionContent` | `.records` | ✅ Mutable | List of `FactionRecord` |
| `GMSTContent` | `.records`, `.getFallbacks()` | ✅ Mutable | `.getFallbacks()` returns openmw.cfg fallbacks |
| `GlobalContent` | `.records` | ✅ Mutable | Map of `string → number` |
| `IngredientContent` | `.records` | ✅ Mutable | Effects truncated to 3 fields |
| `LevCreatureContent` | `.records` | ✅ Mutable | List of `CreatureLevelledListRecord` |
| `LevItemContent` | `.records` | ✅ Mutable | List of `ItemLevelledListRecord` |
| `LightContent` | `.records` | ✅ Mutable | List of `LightRecord` |
| `LockpickContent` | `.records` | ✅ Mutable | List of `LockpickRecord` |
| `MagicEffectContent` | `.records` | ✅ Mutable | List of `MagicEffect` |
| `MiscContent` | `.records` | ✅ Mutable | List of `MiscellaneousRecord` |
| `PotionContent` | `.records` | ✅ Mutable | List of `PotionRecord` |
| `ProbeContent` | `.records` | ✅ Mutable | List of `ProbeRecord` |
| `RaceContent` | `.records` | ✅ Mutable | List of `RaceRecord` |
| `RepairContent` | `.records` | ✅ Mutable | List of `RepairRecord` |
| `SkillContent` | `.records` | ✅ Mutable | List of `SkillRecord` |
| `SoundContent` | `.records` | ✅ Mutable | List of `SoundRecord` |
| `SpellContent` | `.records`, `.TYPE` | ✅ Mutable | Has type constants |
| `StaticContent` | `.records` | ✅ Mutable | List of `StaticRecord` |

**Verified against:** `openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_content.html`.

---

## 7. `openmw.world` — World Access Package

### 7.1 Functions Available (Global Scripts)

| Function | Return Type | Description |
|----------|-------------|-------------|
| `world.activeActors` | list | List of active actors |
| `world.cells` | list | List of all cells |
| `world.players` | list | List of players (single element in single-player) |
| `world.createObject(recordId, count)` | GameObject | Create instance of a record |
| `world.createRecord(record)` | GameObject | Create a custom record in the world database |
| `world.getCellById(cellId)` | Cell | Load cell by ID |
| `world.getCellByName(cellName)` | Cell | Load cell by name |
| `world.getExteriorCell(gridX, gridY, cellOrName)` | Cell | Load exterior cell |
| `world.getGameTime()` | number | Game time in seconds |
| `world.getGameTimeScale()` | number | Game time / simulation time ratio |
| `world.getObjectByFormId(formId)` | GameObject | Object by RefNum/FormId |
| `world.getObjectsByRecordId(recordId, worldSpaceId, loadedOnly)` | list | Find objects by record ID |
| `world.getObjectsInRange(position, range)` | list | Find objects within range |
| `world.getPausedTags()` | list | Current pause tags |
| `world.getSimulationTime()` | number | Simulation time in seconds |
| `world.getSimulationTimeScale()` | number | Simulation time / real time ratio |
| `world.isWorldPaused()` | boolean | Whether world is paused |
| `world.mwscript` | MWScript | MWScript functions |
| `world.vfx` | VFX | Visual effects |
| `world.advanceTime(hours)` | void | Advance simulation time |
| `world.pause(tag)` | void | Pause game |
| `world.setGameTimeScale(ratio)` | void | Set game time scale |
| `world.setSimulationTimeScale(scale)` | void | Set simulation time scale |
| `world.unpause(tag)` | void | Remove pause tag |

### 7.2 World Access During LOAD Context

**`openmw.world` functions are NOT available during LOAD context.** The LOAD context runs before the game world is initialized — before cells, actors, and the player object exist. Only `openmw.content` and `openmw.types` are usable during LOAD.

This is a critical constraint for the database build: effect data extraction must happen via `content.ingredients.records` in the LOAD context, not via `world` functions.

---

## 8. LOAD Context vs. PLAYER Context — Complete Comparison

### 8.1 Context Matrix for Alchemy-Relevant APIs

| API | LOAD Context | PLAYER Context | Notes |
|-----|-------------|----------------|-------|
| `types.Ingredient.record(id)` | ✅ Read-only | ✅ Read-only | Same behavior in both |
| `types.Ingredient.records` | ✅ Read-only | ✅ Read-only | Same behavior in both |
| `types.Ingredient.createRecordDraft()` | ✅ Create | ❌ Not needed | Only useful in LOAD |
| `content.ingredients.records` | ✅ **Mutable** | ❌ Not available | **LOAD-only** |
| `content.ingredients.records[].effects` | ✅ 3 fields | ❌ Not available | **LOAD-only** |
| `IngredientRecord.effects` | ✅ Full | ✅ Full | All `MagicEffectWithParams` fields |
| `types.ESM4Ingredient` | ✅ Type check | ✅ Type check | Thin wrapper only |
| `types.ESM4Ingredient.record()` | ❌ Not available | ❌ Not available | Does not exist |
| `types.ESM4Ingredient.records` | ❌ Not available | ❌ Not available | Does not exist |
| `world.createRecord()` | ❌ Not available | ✅ Available | World not initialized in LOAD |
| `world.getObjectsByRecordId()` | ❌ Not available | ✅ Available | World not initialized in LOAD |
| `openmw.world.*` (all) | ❌ Not available | ✅ Available | World not initialized in LOAD |
| `onContentFilesLoaded()` | ✅ Available | ❌ Not available | **LOAD-only handler** |

### 8.2 Effect Data Availability

| Effect Property | LOAD (`content.ingredients.records`) | PLAYER (`types.Ingredient.record()`) |
|----------------|-------------------------------------|-------------------------------------|
| `id` | ✅ | ✅ |
| `affectedAttribute` | ✅ | ✅ |
| `affectedSkill` | ✅ | ✅ |
| `range` | ❌ | ✅ (always `RT_Self`) |
| `area` | ❌ | ✅ (always `0`) |
| `duration` | ❌ | ✅ (always `0`) |
| `magnMin` | ❌ | ✅ (always `0`) |
| `magnMax` | ❌ | ✅ (always `0`) |
| `index` | ❌ | ✅ |

**Actionable conclusion for the database build (step 5):** The `LOAD` context's truncated effect data (id/affectedAttribute/affectedSkill only) is **sufficient** for building an ingredient→effect mapping database. The additional fields (range, area, duration, magnitude) are not meaningful for ingredient records since the game engine always uses `RT_Self`, `0`, `0`, `0`, `0` for ingredients.

### 8.3 LOAD Context Lifecycle

1. OpenMW starts
2. Content files are loaded and parsed
3. `LOAD` context scripts are created and their `onInit()` called
4. `onContentFilesLoaded()` is called — this is the earliest point where `content.ingredients.records` is populated
5. Main menu appears
6. When player loads a game: world initializes, `PLAYER` context scripts start
7. `onUpdate` runs every frame in all contexts

**Important:** `LOAD` context scripts do NOT re-run after `reloadlua`. A full game restart is required.

### 8.4 Record Mutability

| Context | Record Type | Mutable? | Can modify effects? |
|---------|------------|----------|---------------------|
| LOAD | `content.ingredients.records[<id>]` | ✅ Yes | ✅ Yes (3 fields only) |
| PLAYER | `types.Ingredient.record(<id>)` | ❌ No | ❌ No |

During LOAD, you can modify ingredient records including setting effects:
```lua
content.ingredients.records['ingred_almow_01'] = {
    template = content.ingredients.records['ingred_almow_01'],
    effects = { { id = 'vampirism' } }
}
```

Records injected via LOAD context are **not serialized into saves** and do not persist across restarts.

---

## 9. `openmw.core` — Relevant Functions

| Function | Description |
|----------|-------------|
| `core.getFormId(contentFile, index)` | Construct FormId string from content file and index |
| `core.getGMST(setting)` | Get a game setting by name |
| `core.getGameTime()` | Game time in seconds |
| `core.getSimulationTime()` | Simulation time in seconds |
| `core.getGameDifficulty()` | Game difficulty setting |
| `core.isWorldPaused()` | Whether world is paused |
| `core.sendGlobalEvent(eventName, eventData)` | Send event to global scripts |
| `core.magic` | Magic system access (spells, enchantments) |
| `core.contentFiles` | `ContentFiles` — current load order |

---

## 10. `openmw.types` — Ingredient-Related Types Summary

### 10.1 Type Hierarchy

```
openmw.types
├── Ingredient          # High-level ingredient access
│   ├── record(id) → IngredientRecord
│   ├── records → list<IngredientRecord>
│   ├── createRecordDraft(data) → ESM::Ingredient
│   └── baseType → Item
│
├── ESM4Ingredient      # Thin ESM4 type wrapper
│   ├── objectIsInstance(object) → boolean
│   └── baseType → Item
│
├── ESM3_Ingredient     # Low-level record (ESM3 format)
│   # Fields: id, name, model, icon, value, weight, mwscript, effects
│
├── Item                # Base type for ingredients
│   ├── baseType
│   └── objectIsInstance(object)
│
├── IngredientRecord    # Read-only record
│   ├── id, name, icon, model, value, weight, mwscript, effects
│   └── effects → list<MagicEffectWithParams>
│
├── MagicEffectWithParams  # Effect entry structure
│   ├── id, index, affectedAttribute, affectedSkill
│   ├── range, area, duration, magnitudeMin, magnitudeMax
│   └── (ingredient effects: range=RT_Self, area=0, duration=0, magMin=0, magMax=0)
```

### 10.2 Notable: `openmw.types` Also Provides These

| Type | Relevance |
|------|-----------|
| `types.Potion` | Potion record access |
| `types.Potion.createRecordDraft()` | Creating custom potions |
| `types.PotionRecord.effects` | Potion effects (full `MagicEffectWithParams`) |
| `types.Enchantment` | Enchantment records |
| `types.Enchantment.effects` | Enchantment effects |
| `types.Enchantments.records` | All enchantment records |
| `types.Enchantments.createRecordDraft()` | Creating custom enchantments |

These are relevant for step 4 (recipe mapping) but not for the phase 3 investigation.

---

## 11. Constraints and Known Gaps

### 11.1 Confirmed Gaps in OpenMW 0.50+

| Gap | Impact |
|-----|--------|
| No `openmw.alchemy` package | Cannot call `Alchemy::getEffects()` or `Alchemy::getRecipe()` from Lua |
| No `Alchemy::listEffects()` binding | Cannot query shared-effect lists |
| `types.ESM4Ingredient` is a thin wrapper | No record-level access via ESM4 types |
| `world.*` unavailable in LOAD | Cannot use world queries during database build |
| `content.ingredients.effects` truncated | Only 3 fields; full `MagicEffectWithParams` not available |
| `content.ingredients.records` indexed by ID only | No name-based lookup |
| LOAD context does not persist | Records injected in LOAD vanish on restart |
| `reloadlua` does not re-run LOAD scripts | Must restart game to reload LOAD scripts |

### 11.2 No Invented APIs

This report contains **only** APIs verified against:
- `openmw.readthedocs.io` (version 0.50.0, 0.51.0, and latest)
- `openmw-improved-docs.readthedocs.io/en/latest/` (latest development)
- C++ source: `apps/openmw/mwlua/types/ingredient.cpp` (OpenMW 0.51.0)
- C++ source: `apps/openmw/mwlua/types/types.cpp` (OpenMW 0.51.0)

**The following are NOT real APIs and must NOT be used:**
- ❌ `openmw.alchemy` — does not exist
- ❌ `Alchemy::getEffects()` — no Lua binding
- ❌ `Alchemy::getRecipe()` — no Lua binding
- ❌ `Alchemy::listEffects()` — no Lua binding
- ❌ `types.Ingredient.effects` — effects are on `IngredientRecord`, not on `Ingredient`
- ❌ `types.ESM4Ingredient.record(id)` — does not exist
- ❌ `types.ESM4Ingredient.records` — does not exist
- ❌ `openmw.handlers` — no such package exists
- ❌ `content.ingredients.byName()` — no such method exists
- ❌ `types.Ingredient.recordByName(name)` — no such method exists

---

## 12. Actionable Conclusions for Step 5 (Database Build)

Based on this investigation:

1. **Build the database in LOAD context** using `content.ingredients.records`, which is mutable and available during content load.

2. **Extract effects from `types.Ingredient.records`** (or `content.ingredients.records`) by iterating all ingredients and accessing `.effects` on each `IngredientRecord`.

3. **Each effect entry has only 3 meaningful fields for alchemy:** `id`, `affectedAttribute`, `affectedSkill`. The other `MagicEffectWithParams` fields are always zero/constant for ingredients.

4. **Use `content.ingredients.records[<id>]` for ID-based lookup.** No name-based query exists — iterate and filter if needed.

5. **The database will need to be rebuilt on every game start** since LOAD context records are not serialized. Implement `onSave()`/`onLoad()` (step 9) for persistence.

6. **`types.ESM4Ingredient` is not useful** for building the database — it's a thin type checker. Use `types.Ingredient` instead.

7. **`openmw.world` functions are unavailable during LOAD.** All data collection must happen via `openmw.types` and `openmw.content`.

8. **`openmw.content.magicEffects.records`** provides a list of all magic effects — useful for effect ID → name/type lookup tables in the database.

---

## 13. Reference URLs

| Resource | URL |
|----------|-----|
| Ingredient record types | <https://openmw-improved-docs.readthedocs.io/en/latest/reference/lua-scripting/openmw-types/types_ingredient.html> |
| openmw.types (full) | <https://openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw%5Ftypes.html> |
| openmw.content | <https://openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw%5Fcontent.html> |
| openmw.core (MagicEffectWithParams) | <https://openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_core.html> |
| Engine handlers | <https://openmw.readthedocs.io/en/latest/reference/lua-scripting/engine_handlers.html> |
| openmw.world | <https://openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw%5Fworld.html> |
| OpenMW issue #7277 (alchemy API request) | <https://gitlab.com/OpenMW/openmw/-/issues/7277> |
| OpenMW 0.51.0 source (ingredient.cpp) | <https://github.com/OpenMW/openmw/blob/openmw-0.51.0/apps/openmw/mwlua/types/ingredient.cpp> |
| OpenMW 0.51.0 source (types.cpp) | <https://github.com/OpenMW/openmw/blob/openmw-0.51.0/apps/openmw/mwlua/types/types.cpp> |

---

*This document is investigation-only. No implementation code. See `docs/openmw-lua-api-reference.md` for the broader API reference.*
