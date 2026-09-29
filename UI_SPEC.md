# Alchemist's Almanac UI

The main mod UI consists of a window with two tabs: a searchable Ingredients List, and an effect-based Shopping Planner. The almanac keybind opens this window (replacing the previous single-panel effect view).

## Ingredients List

The ingredients list primarily consists of a list of Ingredients and a search bar text field. The list shows a windowed view — mouse-wheel scrolling with page up/down buttons, since the engine's Lua UI has no native scrollbars — of all ingredients that have a case-insensitive substring match to the search bar in any of:

- Name
- Effect display names, including any parameters that affect the display name of the effect, like Strength or Fatigue

The list is sorted alphabetically by ingredient name. Ingredients should also be filtered to only discovered ingredients if Immersive Mode is on in the mod's settings.

Each ingredient row displays the following.

- Name
- Icon (the ingredient record's icon, `IngredientRecord.icon`)
- Effects (display names; compound — one entry per effect + attribute/skill combination)
- Number of discovered merchants that restock the ingredient (i.e., include it in their restocking supply). A merchant with the Ingredients service but no restocking supply of the item does not count.

## Shopping Planner

The shopping planner consists of a header, an effects list, and a merchant list.

The header has a toggle for Strict Mode. Strict Mode is off by default and session-only (not persisted).

### Effects List

A list of effects, one entry per compound effect (effect + attribute/skill combination), sorted and filterable by display name. In Immersive mode, this should only include effects present on discovered ingredients. Entries are selectable; multiple selections use AND semantics — each selected effect further filters the merchant list to only merchants that have at least one restocking ingredient with that effect, or at least two distinct restocking ingredients with that effect if Strict Mode is enabled. "Distinct" means distinct ingredient records: if two mods add their own versions of an ingredient with the same name, they count as two.

### Merchant List

A list of all discovered merchants, filtered by the effect selection (with no effects selected, all discovered merchants are shown). Each merchant displays:

- Actor Name
- Location Name — the last-known cell display name, captured when the merchant was encountered and updated on re-encounter
- List of ingredients they restock that match any selected effect (ingredient record names; with no selection, their full restocking supply)

The merchant list should be sortable and filterable by both Actor and Location names.

## Notes

- Effect display names are generated at runtime by splitting CamelCase RefIds into words (e.g. `WeaknessToFire` → "Weakness to Fire"), built from the effects present on ingredient records at init — so mod-added MGEFs get names without any static table. Unmapped attribute/skill targets fall back to showing the raw ID.
- The only icons used are ingredient record icons; effects are displayed as text.
- List data is refreshed when the window opens and on tab switch; it is not live-updated while the window stays open.
- "Restocking supply" means ingredients a merchant holds at a negative count in their inventory — what they sell and restock.
