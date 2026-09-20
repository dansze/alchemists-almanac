---
id: TASK_AUTO_0001
state: in_progress
phase: done
created_at: 2026-09-19T18:10:16.370Z
updated_at: 2026-09-20T04:53:20.669Z
title: Implement mod as described in TODO.md
---

## feature prompt

Implement mod as described in TODO.md

## clarifications

Q1: Which UI approach should be chosen for post-MVP Phase 5: built-in MWUI interface (Morrowind-style templates), raw openmw.ui (custom overlay), or openmw_aux.ui (UI utilities)? This is explicitly flagged as an open decision (Phase 5.1) and fundamentally forks the Phase 5 task structure—MWUI requires template setup and interface override work, openmw.ui requires building panel/controls from scratch, and openmw_aux.ui reuses existing abstractions, each producing a different task set and dependency ordering.
A1: use openmw_aux.ui utilities layered on openmw.ui primitives, since the API reference notes openmw_aux.ui is a Lua-implemented convenience layer with no additional capabilities beyond the basic API but more ergonomic—this gives a pragmatic middle ground that avoids the complexity of MWUI template manipulation while providing reusable UI helpers for the alchemy panel. (accepted recommendation)
Q2: How should the mod detect that the vanilla alchemy menu is open and retrieve the currently selected ingredient IDs for display in the UI panel? This is the bottleneck for Phase 5.2/5.3 — the panel cannot show meaningful data without ingredient selection input, and Section 3.4 explicitly states Alchemy::getEffects() is not exposed to Lua. The chosen detection mechanism determines whether Phase 5 needs a dedicated "menu-state detector" task (polling, MWUI introspection, camera/actor-state inference, or magic-effect monitoring) and fundamentally changes whether the UI can be auto-responsive or must be manual/on-demand.
A2: Use a **hybrid approach** — detect the alchemy menu via MWUI introspection or the `onActivated()` event at alchemy labs (whichever proves feasible during Phase 5.1 investigation), but for retrieving ingredient IDs, rely on the **on-demand keybind (Phase 5.3) triggering a lookup against the pre-built effect database from Phase 3**, since Section 3.4 explicitly blocks querying the alchemy menu's selected ingredients and no C++ `Alchemy` binding exists. (auto-resolved — already settled by the spec)
Q3: Should the effect database be fully rebuilt at LOAD time (Phase 4) and only player discoveries persisted to saves (via onSave()/onLoad()), or should the entire database — including discovered recipes and preferences — be serialized via onSave()/onLoad() and reconstructed on onLoad() to avoid the LOAD-context rebuild?
A3: Fully rebuild at LOAD time, only persist player discoveries (discovered recipes) and preferences via onSave()/onLoad(). (auto-resolved — already settled by the spec)
Q4: How do recipes become "discovered" — automatically when the player successfully brews a potion, or manually when the player marks a recipe via the UI panel? This forks whether Phase 5 needs interactive UI controls (a "lock this recipe" button on the panel) and whether Phase 6 needs an event hook into the potion-creation lifecycle (which, since Alchemy::create() is not exposed to Lua, may require investigating whether onObjectAdded() on the player inventory detects newly brewed potions, or whether the openmw.records package's findPotion/createPotion — gap O5 — provides a higher-level hook).
A4: Automatic discovery when the player successfully brews a potion, detected via `onObjectAdded()` on the player inventory. Phase 6.4 of the TODO explicitly references `onObjectAdded()` for this purpose and states "New ingredient combinations encountered during play are added to the discovered list." (auto-resolved — already settled by the spec)

## tasks

- [x] P01 TASK_0003 a1  Create directory structure, `.omwscripts` manifest, and mod registration documentation — establish foundational scaffolding —
- [x] P02 TASK_0004 a3  Verify script loads and runs in OpenMW 0.50+, document Lua 5.1 sandbox constraints, and document serialization limits for `onSave()`/`onLoad()` — ensure execution baseline and compliance —
- [x] P03 TASK_0005 a2  Investigate `types.Ingredient.record()` effect field names, low-level `ESM4Ingredient` mappings, complete engine handlers, and `openmw.content` LOAD capabilities — verify via console and validate against known Morrowind data —
- [x] P04 TASK_0006 a1  Build ingredient → effects, effects → shared ingredients, and pair/triple → potion effects lookup tables, plus recipe reverse lookup and effect ID name mapping — replicate internal C++ alchemy logic in Lua —
- [x] P05 TASK_0007 a2  Create LOAD-context script to build effect database during content load, register it via `interfaces.AlchemyHelper.queryEffects(ids)`, and document `reloadlua` limitations to handle uninitialized DB in PLAYER contexts — ensure DB is ready before scripts start — [decisions: fully rebuild at LOAD time, only persist player discoveries (discovered recipes) and preferences via onSave()/onLoad()] —
- [ ] P06  Create alchemy effects UI panel using openmw_aux.ui utilities layered on openmw.ui primitives — ensure pragmatic middle-ground API without MWUI template complexity — [decisions: use openmw_aux.ui utilities layered on openmw.ui primitives] —
- [ ] P07  Detect alchemy menu via MWUI introspection or `onActivated()` at alchemy labs and add key binding to trigger on-demand ingredient lookup against pre-built database — auto-responsive detection not required; rely on manual trigger for data — [decisions: detect the alchemy menu via MWUI introspection or the `onActivated()` event at alchemy labs (whichever proves feasible during Phase 5.1 investigation), but for retrieving ingredient IDs, rely on the **on-demand keybind (Phase 5.3) triggering a lookup against the pre-built effect database from Phase 3**] —
- [ ] P08  Handle UI panel positioning relative to alchemy menu/screen corner and make theme/style configurable via plain Lua table — avoid custom metatables in config —
- [ ] P09  Design save schema, implement `onSave()` and `onLoad()` handlers with version migration, and wire up automatic recipe discovery via `onObjectAdded()` on player inventory — persist only discoveries/preferences to save files — [decisions: fully rebuild at LOAD time, only persist player discoveries (discovered recipes) and preferences via onSave()/onLoad() — automatic discovery when the player successfully brews a potion, detected via `onObjectAdded()` on the player inventory] —
- [ ] P10  Guard all record lookups and database queries with `pcall`, handle missing ingredients/ESP unloads, duplicate selections, uninitialized databases, and batch startup table builds to avoid >1s freezes — ensure graceful degradation and performance —

