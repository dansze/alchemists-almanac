# Alchemist's Almanac

Alchemist's Almanac is an OpenMW lua mod that acts as a general reference for alchemy ingredients and the merchants that sell them. The mod provides a filterable list of ingredients present in the game, as well as a way to find places to buy them. Optionally, this information can be limited to only ingredients or merchants the player has already encountered.

## Motivation

Modded merchants and ingredients are often poorly documented, if at all. Additionally, many modern mods change things via scripts for compatibility reasons, making it impossible to keep track of the result with external tools alone. This mod aims to mitigate this by providing an in game reference based on the real time state of records.

## Functionality

The mod should present an interface that can be opened with a configurable key. This interface has the following tabs:

- Ingredient List: A searchable list of ingredients in the game
- Shopping Planner: A utility for finding ingredient vendors

The mod also keeps track of the following information:

- A cache of Ingredient records indexed by effect
- A cache of NPC records that both sell Ingredients and have a restocking supply of them
- A list of encountered Ingredients
- A list of encountered Ingredient merchants

### Configuration Options

The mod provides the following configuration options using OpenMW's standard mod configuration mechanisms:

- Immersive Mode: The Ingredient List and Shopping Planner only show ingredients and merchants the player has encountered

### Ingredient List

The first tab is a filterable list of all ingredient records in the game. Each ingredient entry should display the following information:

- Name
- Inventory Icon
- Effects
- Weight
- Value
- Number of merchants encountered who restock this ingredient

This list of ingredients should be filterable and sortable by:

- Name
- Effect
- Weight
- Value
- Number of merchants encountered who restock this ingredient

Name and Value should be filterable by substring match, using the display name for effects. Weight and Value should be filterable by numeric value.

### Shopping Planner

The second tab has two parts. The left side has a searchable list of effects that exist on ingredients. This list can by filtered by effect name, and effects in this list can be selected. There is also a clear selection button.

The right side shows a list of merchants that sell ingredients with the effects selected in the left panel, as well as a list of those ingredients they sell. This list can be filtered by:

- Minimum number of matching ingredients per effect
- Total number of matching ingredients sold
- Location substring

This list can also be sorted by:

- Number of matching ingredients sold
- Location

### Ingredients Cache

When first opening the UI for the mod, it should populate a cache of ingrendients indexed by their effect. Ingredients with more than one effect should be in the tables of each of their effects.

Rebuilding this cache should be triggerable from the mod options.

Additionally, each time the player opens an inventory, each ingredient in that inventory should be added to a list of ingredients the player has seen. Ingredients should also be added to that list when they enter the player's inventory.

### Merchant Cache

When first opening the shopping planner, the mod should populate a cache of merchants with restocking ingredients. That is, this cache should contain every NPC or Creature record that has both Barter and Ingredients in its services offered, and has a negative amount of an ingredient in its inventory.

Rebuilding this cache should be triggerable from the mod options.

Additionally, each time the player chances cells, the list of active actors should be checked for any of the above merchants, and if any are found they should be marked as seen.