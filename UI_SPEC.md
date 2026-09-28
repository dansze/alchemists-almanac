# Alchemist's Almanac UI
The main mod UI consists of a window with two tabs: a searchable Ingredients List, and an effect-based Shopping Planner.

## Ingredients List

The ingredients list primarily consists of a list of Ingredients and a search bar text field. The ingredients list should show a scrollable view of all ingredients that have a substring match to the search bar with in any of its:

- Name
- Effect Names, including any parameters that would affect the display name of the effect like Strength or Fatigue

Ingredients should also be filtered to only discovered ingredients if Immersive Mode is on in the mod's settings.

Each ingredient display should include the following.

- Name
- Icon
- Effects (including effect icon)
- Number of discovered merchants that restock the ingredient.

## Shopping Planner

The shopping planner consists of a header, an effects list, and a merchant list.

The header should have a toggle for a Strict Mode.

The first is a list of effects, sorted and filterable by name. In Immersive mode, this should only include effects from discovered ingredients. These effects should be selectable. Each selected effect should filter the list of merchants to only include those who have at least one restocking ingredient with that effect, or at least two such ingredients if Strict Mode is enabled.

The second list shows a list of all discovered merchants, as filtered by the effect selection. They should display the following information:

- Actor Name
- Location Name (the cell they can be found in)
- List of ingredients they sell that match selected effects

The merchant list should be sortable and filterable by both Actor and Location names.