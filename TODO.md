# TODO — openmw/alchemy-helper

> **Source of truth:** `docs/openmw-lua-api-reference.md` (the de facto specification; original SPEC.md is irrecoverably lost). Every task traces back to a Section reference in that document.

## Critical Architectural Constraint

OpenMW does **not** expose `MWMechanics::Alchemy` to Lua (GitLab issue [#7277](https://gitlab.com/OpenMW/openmw/-/issues/7277)). There is **no `openmw.alchemy` package**. Methods `Alchemy::getEffects()`, `Alchemy::getRecipe()`, `Alchemy::listEffects()`, `Alchemy::create()` are internal C++ methods with no Lua binding. The alchemy-helper must use the record-inspection workaround described in Section 3.3.5.

---

## MVP Boundary

**MVP = Phases 1–3.** After Phase 3 the mod can inspect ingredient effects and build a local alchemy database at LOAD time. Everything beyond Phase 3 (UI, alchemy menu assistance, persistence, error handling) is post-MVP / version-gated.

---

## Phase 1 — Scaffolding

### 1.1 Create directory structure and `.omwscripts` manifest
- **Done when:** `alchemy-helper/alchemy-helper.omwscripts` exists with at least one `GLOBAL:` line pointing to the main script; `scripts/alchemy-helper/init.lua` exists as a minimal `return { engineHandlers = { onUpdate = function() end } }` stub.
- **Source:** Section 1.2 (`.omwscripts` format), Section 1.4 (directory structure), Section 1.5 (minimal valid script).

### 1.2 Register mod in `openmw.cfg`
- **Done when:** A documented registration snippet (`data=...` or `content=...`) is written to `README.md` or a `docs/registration.md`; no `.omwaddon` file is used (Section 1.2 explicitly states `.omwaddon` is not implemented in 0.50/0.51).
- **Source:** Section 1.3 (`openmw.cfg` registration).

### 1.3 Verify script loads and runs in OpenMW 0.50+
- **Done when:** The mod loads via `openmw.cfg`, `reloadlua` in-game succeeds without error, and a log line (e.g., `print('alchemy-helper loaded')`) appears in the console.
- **Source:** Section 1.8 (hot reloading), Section 1.2.

### 1.4 Document serialization constraints for `onSave()`/`onLoad()`
- **Done when:** `docs/serialization.md` (or inline task notes) enumerate the serializable and non-serializable types; no task in later phases stores functions, custom metatables, or circular references.
- **Source:** Section 3.6 (serialization constraints).

### 1.5 Document Lua 5.1 constraints and allowed extensions
- **Done when:** `docs/lua-constraints.md` or inline notes list: Lua 5.1 base, allowed extensions (Lua 5.2 `goto`, `__pairs`, Lua 5.3 utf8), prohibited features (no DLLs, no `.luac`, no `math.randomseed`).
- **Source:** Section 1.7 (sandbox restrictions).

---

## Phase 2 — Record-Inspection Investigation (prerequisites)

> **These tasks are prerequisites** for all downstream functionality. The effect database cannot be built without knowing the actual field names and API available.

### 2.1 Investigate `types.Ingredient.record(id)` effect field names
- **Done when:** A definitive list of field names on the table returned by `types.Ingredient.record(id)` is documented, specifically the fields that hold the 1–4 effect IDs per ingredient. Verification method: call `types.Ingredient.record('ingredient_test_id')` in `lua player` console and print the table keys, or inspect `resources/lua_api` shipped with OpenMW.
- **Source:** Section 3.3.5 ("The exact field names depend on the openmw.types implementation. Check types.ESM4Ingredient.record() for low-level access if needed.").
- **Gap note:** The API reference explicitly states this is **not documented**.

### 2.2 Investigate `types.ESM4Ingredient.record(id)` low-level record fields
- **Done when:** A definitive mapping of ESM4Ingredient fields (e.g., `effects`, `effectIds`, `spells`) to the OpenMW Lua binding is documented. Verification: `lua player` console → `local r = require('openmw.types').ESM4Ingredient.record('slaughterfish_egg'); for k,v in pairs(r) do print(k, type(v)) end`.
- **Source:** Section 2.7 (ESM4 record types — `types.ESM4Ingredient`), Section 3.3.5.
- **Gap note:** Section 4.4 explicitly lists "the exact fields available on `types.Ingredient.record()` for effect data enumeration" as **not documented**.

### 2.3 Map all ingredients in a known ESP to their effect IDs
- **Done when:** A Lua script (runnable via `lua global` or `lua player`) iterates `types.Ingredient.records` for one known master file (e.g., `Morrowind.esm`), prints each ingredient's ID alongside its effect IDs, and the output matches known Morrowind alchemy data. This validates the field names found in 2.1 and 2.2.
- **Source:** Section 2.7 (`types.Ingredient.records` iterator), Section 3.3.5.

### 2.4 Investigate the complete list of engine handlers
- **Done when:** The "Engine handlers reference" page (`reference/lua-scripting/engine_handlers.html` per Section 1.2 footnote) is fetched and compared against the Section 2.12 table; any missing handlers are catalogued. Key handlers for alchemy: `onActivated()`, `onObjectAdded()`, `onObjectRemoved()`.
- **Source:** Section 2.12 ("This table is not exhaustive. The complete list ... referenced as a separate page that may be incomplete").
- **Gap note:** Section 4.4 explicitly lists "the complete list of engine handlers" as **not documented** beyond Section 2.12.

### 2.5 Investigate `openmw.world.createObject(recordId, count)` behavior for ingredients/potions
- **Done when:** Verified whether `world.createObject()` on an ingredient record ID creates a usable inventory item with known properties (weight, value). Confirmed whether `moveInto()` works.
- **Source:** Section 2.7 (`openmw.world` table), Section 3.3.4.

### 2.6 Investigate `openmw.content` package capabilities in LOAD context
- **Done when:** Documented what `openmw.content` provides (record querying, modification) in the LOAD context. Determined if `openmw.content` can list loaded records, filter by record type, or access record data for building the effect database.
- **Source:** Section 2.2 (`openmw.content` — "Content manipulation (load context only)"), Section 3.5 (LOAD context added in 0.51.0), Section 3.4.
- **Gap note:** Section 4.4 lists "the `LOAD` context record API" as **not documented** beyond a high-level description.

---

## Phase 3 — Effect Data Model (MVP core)

> These tasks are the MVP core. After Phase 3 completes, the mod has a functional in-memory effect database built at LOAD time.

### 3.1 Build ingredient → effects lookup table in GLOBAL context
- **Done when:** A GLOBAL script populates a `local ingredientEffects = {}` table where `ingredientEffects[ingredientId]` returns an array of effect ID strings. Populated by iterating `types.Ingredient.records` and extracting effect IDs using the field names verified in Phase 2. Verification: running `lua global` and calling the lookup function for a known ingredient returns the correct effect IDs.
- **Source:** Section 3.3.5 (workaround approach: inspect ingredient records), Section 2.7 (`types.Ingredient.records`), Section 2.2 (GLOBAL context).

### 3.2 Build effects → shared ingredients lookup table
- **Done when:** A `local effectToIngredients = {}` table is populated such that `effectToIngredients[effectId]` returns the list of ingredient IDs that share that effect. This is the direct analogue of `Alchemy::listEffects()` (the method that "lists effects shared by at least two ingredients" — Section 3.2). Verification: for a known effect present in ≥2 Morrowind ingredients, the table returns all those ingredient IDs.
- **Source:** Section 3.2 (`Alchemy::listEffects()` description), Section 3.3.5.

### 3.3 Build ingredient pair → potion effects lookup table
- **Done when:** A `local pairEffects = {}` table maps pairs of ingredient IDs (as a canonical sorted key) to the intersection of their effect IDs. This replicates `Alchemy::getEffects()` (which returns the effects of the current ingredient combination). Verification: for two known ingredients that share an effect, `pairEffects[{id1, id2}]` returns that effect.
- **Source:** Section 3.2 (`Alchemy::getEffects()` / `Alchemy::getRecipe()` not exposed), Section 3.3.5.

### 3.4 Build ingredient triple → potion effects lookup table
- **Done when:** A `local tripleEffects = {}` table maps triples of ingredient IDs to the intersection of all three ingredients' effects. This replicates the 3-ingredient potion slot behavior. Verification: for three known ingredients that share an effect, `tripleEffects[{id1, id2, id3}]` returns that effect.
- **Source:** Section 3.2 (`Alchemy::create()` described as "creates a potion from current ingredient state"), Section 3.5 (4-ingredient slot implied by alchemy mechanics).

### 3.5 Build recipe → ingredient list reverse lookup (potion name lookup)
- **Done when:** A `local knownRecipes = {}` table maps combinations of ingredients (canonical key) to a list of existing potion record IDs that could be brewed from them. Populated from `types.Potion.records` (Section 3.3.2). Verification: a known Morrowind potion recipe returns the expected potion record IDs.
- **Source:** Section 3.3.2 (`openmw.types.Potion`), Section 3.2 (`Alchemy::getRecipe()` — not exposed, must be reverse-engineered from existing potions).

### 3.6 Verify effect ID ↔ effect name mapping
- **Done when:** A mapping table or function exists to convert effect IDs (e.g., numeric or string identifiers like `"restore health"`) to human-readable names. Verification: a known effect ID from any ingredient returns the correct name string. May require cross-referencing with `resources/lua_api` LDT files (Section 4.1).
- **Source:** Section 3.3.5 (effect IDs on ingredient records), Section 4.1 (IDE support via `resources/lua_api`).

### 3.7 MVP integration test
- **Done when:** A single GLOBAL script loads, builds all lookup tables (3.1–3.6) from `types.Ingredient.records` and `types.Potion.records`, and responds to queries from `lua global` console:
  - `query_shared_effects('ingredient1', 'ingredient2')` returns correct effect(s).
  - `query_ingredients_by_effect('effect_id')` returns correct list.
  - `query_recipes('ingredient1', 'ingredient2')` returns correct potion IDs.
- **Source:** Section 1.9 (Lua console), Sections 2.7–3.3 (API packages), Section 2.7 (`openmw.core` — `core.getFormId`, `core.sendGlobalEvent`).

---

## Phase 4 — LOAD-Context Integration (requires 0.51.0+)

> **Version-gated:** Requires OpenMW 0.51.0+ for the `LOAD` context.

### 4.1 Create LOAD-context script to build effect database during content load
- **Done when:** An `.omwscripts` entry with the `LOAD` flag (`LOAD: scripts/alchemy-helper/load-db.lua`) registers a LOAD-context script. The script populates the effect database (Phases 3.1–3.4) using `openmw.content` or `types.Ingredient.records` during the LOAD phase, so the database is ready before PLAYER scripts start.
- **Source:** Section 1.2 (`LOAD` flag, new in 0.51.0), Section 1.6 (LOAD context: "runs once after all content files are loaded"), Section 2.2 (`openmw.content` — load context only).

### 4.2 Hook ingredient/potion record events in LOAD context
- **Done when:** Custom magic effect and ingredient records injected in LOAD context (Section 3.5) are detected and integrated into the effect database. The script handles custom ingredients added at load time.
- **Source:** Section 3.5 (custom ingredients, custom magic effects in LOAD context), Section 2.12 (`onInit()` for local/player scripts).

### 4.3 Register the effect database in a script interface
- **Done when:** The LOAD script (or a GLOBAL script that reads the LOAD-built database) exposes an interface `AlchemyHelper` via `interfaceName` and `interface` (Section 2.8) with a function `queryEffects(ingredientIds)` that returns shared effects. Other scripts (PLAYER, MENU) can call it via `interfaces.AlchemyHelper.queryEffects(ids)` (Section 2.8).
- **Source:** Section 2.8 (script interfaces), Section 1.5 (returned table structure).

### 4.4 Handle `reloadlua` limitation for LOAD context
- **Done when:** The mod's startup documentation explicitly states: after `reloadlua`, the LOAD-context database is NOT rebuilt; a full game restart is required. The PLAYER script must handle the case where the database is uninitialized after `reloadlua` by either waiting for the next restart or deferring UI until the database is ready.
- **Source:** Section 1.8 ("The `load` context scripts do not re-run after `reloadlua`; a full restart is required.").

### 4.5 Ensure LOAD-injected records are not serialized into saves
- **Done when:** Verified that any custom records or state created during LOAD do not appear in save games (per Section 1.6: "records injected via this context are not serialized into saves"). No save-related task depends on LOAD-context state.
- **Source:** Section 1.6 (LOAD context description), Section 3.6 (serialization constraints).

---

## Phase 5 — UI Layer (post-MVP)

### 5.1 Determine UI approach: MWUI interface vs. openmw.ui vs. openmw_aux.ui
- **Done when:** A documented decision is made:
  - Option A: Use `MWUI` interface (Section 2.9) to interact with Morrowind-style UI templates.
  - Option B: Use `openmw.ui` package (Section 2.5) to build a custom overlay.
  - Option C: Use `openmw_aux.ui` (Section 2.6) for UI utilities.
  - Implementation choice (not spec requirement) — the API reference does not pin module-to-mount mappings.
- **Source:** Section 2.5 (`openmw.ui` — player context), Section 2.9 (`MWUI` — menu/player), Section 2.6 (`openmw_aux.ui`).

### 5.2 Create UI panel to display alchemy effects
- **Done when:** A UI panel (positioned near the alchemy menu or as an overlay) displays the shared effects for currently selected ingredients. Verified: panel renders and shows correct data for known ingredient pairs.
- **Source:** Section 2.5 (`openmw.ui`), Section 2.9 (`Controls` interface — player context).

### 5.3 Add key binding to toggle UI panel
- **Done when:** A player-context engine handler `onKeyPress(key)` (Section 2.12) toggles the UI panel visibility. Default key: a documented binding (e.g., `L` or `F`). Verified: pressing the key shows/hides the panel.
- **Source:** Section 2.12 (`onKeyPress(key)` — player context), Section 2.5 (player packages including `openmw.input` for input handling).

### 5.4 Handle UI panel positioning and resizing
- **Done when:** Panel repositions itself relative to the alchemy menu (when visible) or the player screen corner (when alchemy menu is closed). Verified: panel does not obscure critical UI elements.
- **Source:** Section 2.5 (`openmw.ui`), Section 2.7 (`util.vector3` for positioning).

### 5.5 Add UI theme/style customization
- **Done when:** Panel appearance (colors, font, size) is configurable via a plain Lua table or `openmw.cfg`-based config. No custom metatables in config (per serialization constraints, Section 3.6).
- **Source:** Section 2.9 (`Settings` interface — global/menu/player), Section 3.6 (serialization constraints).

---

## Phase 6 — Alchemy Menu Assistance (post-MVP)

### 6.1 Detect when player enters/exits alchemy menu
- **Done when:** The mod detects alchemy menu state. Investigation target: use `onActivated()` (Section 2.12), `MWUI` interface events (Section 2.9), or check for the presence of the alchemy menu window via `openmw.ui`. The API reference does not document a specific "alchemy menu opened" event.
- **Source:** Section 2.9 (`MWUI` — Morrowind-style UI templates), Section 2.10 (event system), Section 2.12 (`onActivated()`).

### 6.2 Identify currently selected ingredients in the alchemy window
- **Done when:** The mod knows which ingredients the player has placed in alchemy slots. Investigation target: the API reference does not expose the alchemy menu's ingredient state (Section 3.4: "cannot query the currently selected ingredients in the alchemy window"). Possible approach: monitor `onObjectAdded()` and `onObjectRemoved()` events (Section 2.12) on the player actor to infer ingredient selections, or inspect world state.
- **Source:** Section 3.4 (cannot interfere with vanilla alchemy menu), Section 2.12 (`onObjectAdded()`, `onObjectRemoved()`).
- **Gap note:** This is an undocumented interaction path — the exact mechanism is an implementation choice.

### 6.3 Display predicted potion effects in real time
- **Done when:** As the player selects ingredients (detected via 6.2), the UI panel (Phase 5) updates to show the predicted potion effects (from Phase 3 lookup tables). Verified: selecting two ingredients shows their shared effects; selecting three shows the triple intersection.
- **Source:** Section 3.3.5 (ingredient effects), Phase 3 lookup tables, Section 2.10 (event system for live updates).

### 6.4 Suggest recipe names
- **Done when:** The mod displays a suggested potion name based on the current ingredient combination, similar to `Alchemy::getPotionName()` (Section 3.2). Since `Alchemy::getPotionName()` is not exposed (Section 3.2), implement a Lua-side heuristic: use the "X and Y Potion" naming pattern from existing recipe data.
- **Source:** Section 3.2 (`Alchemy::getPotionName()` — internal C++ only), Section 3.3.2 (`types.Potion.records` for name patterns).

### 6.5 Highlight known recipes
- **Done when:** The mod visually indicates when a selected ingredient combination matches a known recipe from `types.Potion.records` (Section 3.3.2). Verified: selecting the exact ingredients for a known Morrowind potion triggers a highlight.
- **Source:** Section 3.3.2 (`types.Potion.records`), Section 3.5 (recipe data from potions).

---

## Phase 7 — Persistence (post-MVP)

### 7.1 Design save data schema for discovered recipes
- **Done when:** A documented schema (plain Lua table, no functions/metatables) for persistent alchemy data: e.g., `{ discovered = { {'ingredient1', 'ingredient2'}, ... }, preferences = { keybind = 'L' } }`. Schema must comply with serialization constraints (Section 3.6).
- **Source:** Section 3.6 (serialization constraints: only `nil`, numbers, strings, game objects, `util.vector3`, plain tables).

### 7.2 Implement `onSave()` handler
- **Done when:** `onSave()` (Section 2.12, all contexts) returns the serializable save data. Verification: save game, check that the returned table is valid (no functions, no circular refs, no custom metatables). Use `pcall` to guard against errors (Section 1.7 allows `pcall`).
- **Source:** Section 2.12 (`onSave()` — all contexts), Section 3.6 (serialization constraints).

### 7.3 Implement `onLoad()` handler
- **Done when:** `onLoad(data)` (Section 2.12) reconstructs the alchemy database state from the save data. Verification: save game, continue playing, reload save, verify data matches what was saved. Handle `data == nil` (new game) gracefully.
- **Source:** Section 2.12 (`onLoad()` — all contexts), Section 3.6.

### 7.4 Implement recipe discovery persistence
- **Done when:** Player-discovered recipes are saved via `onSave()` and restored via `onLoad()`. New ingredient combinations encountered during play are added to the discovered list.
- **Source:** Section 2.12 (`onObjectAdded()` event), Section 2.10 (event system), Section 3.6 (only serializable types).

### 7.5 Handle save/load versioning
- **Done when:** Save data includes a version field (e.g., `version = 1`). `onLoad()` checks the version and either loads, migrates, or ignores incompatible data.
- **Source:** Section 2.12 (`onSave`/`onLoad` lifecycle), Section 3.6.

---

## Phase 8 — Error Handling and Edge Cases (post-MVP)

### 8.1 Guard all `types.Ingredient.record(id)` and `types.Potion.record(id)` calls
- **Done when:** Every call to `types.Ingredient.record(id)` or `types.Potion.record(id)` checks for a `nil` return and handles it gracefully. Verified: calling with an invalid ID returns `nil` and does not crash.
- **Source:** Section 2.7 (type constructors), Section 1.7 (`pcall`, `error` are allowed).

### 8.2 Guard database lookups with `pcall`
- **Done when:** All Lua-side database queries (`query_shared_effects`, etc.) are wrapped in `pcall` to catch and log errors without crashing the game. Error messages are printed via `print()` or `error()` (Section 1.7).
- **Source:** Section 1.7 (allowed basic functions: `pcall`, `error`, `print`).

### 8.3 Handle missing ingredients (e.g., ESP not loaded)
- **Done when:** If an ingredient from the effect database is not available (ESP not loaded), the database lookup returns an empty table or a sentinel value instead of crashing. Verified: disable an ESP containing known ingredients and verify the mod degrades gracefully.
- **Source:** Section 2.7 (`types.Ingredient.record(id)` returns nil for missing records).

### 8.4 Handle effects with no matching ingredients
- **Done when:** Effect queries for effects that appear in only one ingredient (i.e., not shared) return an empty list without errors. Verified: query an effect present in exactly one ingredient.
- **Source:** Section 3.2 (`Alchemy::listEffects()` only lists effects shared by ≥2 ingredients).

### 8.5 Handle duplicate ingredient selection
- **Done when:** If the player selects the same ingredient twice (or three times), the effect database returns the intersection of the ingredient's effects with themselves (which is the full set) rather than an error. Verified: select the same ingredient in two slots and confirm correct output.
- **Source:** Section 3.3.5 (ingredient effects), Phase 3 lookup tables.

### 8.6 Handle uninitialized database in PLAYER/MENU contexts
- **Done when:** If a PLAYER or MENU script calls `interfaces.AlchemyHelper.queryEffects()` before the database is ready (e.g., before LOAD context completes, or after `reloadlua` without restart), the call returns a clear error or nil instead of crashing. The interface's `onInterfaceOverride()` handler (Section 2.12) manages initialization state.
- **Source:** Section 2.12 (`onInterfaceOverride(base)` — all contexts), Section 1.8 (reloadlua limitation for LOAD context).

### 8.7 Handle performance impact of full table builds on startup
- **Done when:** The effect database build time is measured and documented. If iterating all ingredients takes >1 second, the build is deferred to `onUpdate()` (Section 2.12) chunks or `async:newSimulationTimer` (Section 2.11). Verified: startup time with the mod loaded is within an acceptable threshold.
- **Source:** Section 2.12 (`onUpdate(dt)` — called every frame), Section 2.11 (timers in `openmw.async`).

### 8.8 Handle mod uninstall / data removal gracefully
- **Done when:** If the mod's data is removed while the game is running, the script handles subsequent API calls gracefully (no Lua errors from missing require). Verified: remove mod from `openmw.cfg` and reload — game continues without Lua errors.
- **Source:** Section 1.8 (reloadlua), Section 2.1 (packages cannot be overloaded).

---

## Open Investigation Items

These items are documented gaps in the API reference that must be resolved before their downstream tasks can be fully implemented:

| # | Gap | Impact | Source |
|---|-----|--------|--------|
| O1 | Exact field names on `types.Ingredient.record()` for effect IDs | Blocks all effect lookup tables (Phase 3) | Section 3.3.5, Section 4.4 |
| O2 | Exact field names on `types.ESM4Ingredient.record()` | Alternative low-level access path if needed | Section 2.7, Section 3.3.5 |
| O3 | Complete engine handlers list | May reveal undocumented handlers useful for alchemy menu detection | Section 2.12, Section 4.4 |
| O4 | `openmw.content` package API in LOAD context | Determines whether content manipulation in LOAD is more powerful than `types.Ingredient.records` | Section 2.2, Section 4.4 |
| O5 | `openmw.records` package status | Status unclear for 0.50+; could provide higher-level record APIs (Section 3.4 mentions `openmw.records.createPotion`/`findPotion`) | Section 3.4, Section 4.4, MR !2859 |
| O6 | Alchemy menu detection mechanism | API reference explicitly says the mod cannot query alchemy menu state (Section 3.4) — requires investigation | Section 3.4 |
| O7 | `openmw.ui` API specifics | Panel creation, rendering, and event handling details not in this reference | Section 2.5 |
