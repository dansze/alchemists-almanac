# `reloadlua` Limitation — LOAD-Context Scripts

## Problem

The `reloadlua` console command reloads GLOBAL, MENU, LOCAL, and PLAYER context
scripts, but **does not re-execute LOAD-context scripts**. This is a hard
limitation of OpenMW 0.50+ (introduced as a known behavior boundary in 0.51.0
when the LOAD context was added).

**Consequence:** A full game restart is required to reload LOAD-context scripts
after any source change.

## Why It Matters for the Effect Database

The effect database in `scripts/alchemy-helper/load-db.lua` is built entirely
inside the LOAD-context handler (after `content.ingredients.records` is populated
by the engine). The `queryEffects` function is registered on
`interfaces.AlchemyHelper` during this build.

When a user runs `reloadlua`:

1. The LOAD-context script is **not re-executed**.
2. `interfaces.AlchemyHelper.queryEffects` may be **`nil`** (uninitialized) if
   the current PLAYER context started before a LOAD event completed.
3. Any PLAYER-context caller that invokes `queryEffects` without checking will
   get a runtime error.

## Guard Pattern for PLAYER-Context Callers

All callers that invoke `queryEffects` from PLAYER context (or any context that
can be active when `reloadlua` has fired) **must check for `nil`** before
calling:

```lua
local interfaces = require('openmw.interfaces')

local helper = interfaces.AlchemyHelper
if not helper or not helper.queryEffects then
    -- LOAD has not fired yet, or reloadlua was called without a full restart.
    -- Defer the query until the main menu (when LOAD fires).
    return nil, 'AlchemyHelper not yet initialized — wait for LOAD to complete'
end

local result = helper.queryEffects({'fireDamage', 'frostDamage'})
-- result['fireDamage'] = { ingredients = {...}, sharedIngredient = ..., pairs = {...}, ... }
```

## Safe Pattern Summary

| Situation | Action |
|-----------|--------|
| Main menu (before game load) | LOAD fires; `queryEffects` is available |
| During gameplay after game load | `queryEffects` is available (built once at start) |
| After `reloadlua` in-game | `queryEffects` is **uninitialized** — check for `nil` |
| After `reloadlua` + game reload | `queryEffects` is available again (LOAD fires on next game load) |
| Script source changed + `reloadlua` | **Full restart required** to pick up changes to `load-db.lua` |

## Recommendation

Always wrap `queryEffects` calls in a nil-guard. Defer queries to a
main-menu handler or an `onUpdate` check that retries once `queryEffects` is
available. Do not assume the effect database exists at script-load time in
PLAYER context.
