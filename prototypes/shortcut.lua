--- The toolbar button that turns a player's arms off, and the key binding beside it.
---
--- The base game has two of these already, for the personal roboport and the exoskeleton,
--- and they are there for the same reason this one is: equipment worn for one job gets in
--- the way of another. A roboport rebuilds what you are trying to clear; an arm here builds
--- the ghosts you laid down to think about, spends the items you were saving, and slows you
--- down while it does it. Taking the equipment out of the armour is the alternative, and
--- putting it back costs a trip through the inventory every time.
---
--- Off is one player's own, not a force's and not a game's: the button sits in one player's
--- toolbar and the entry control.lua keeps is theirs alone, so switching off in a
--- multiplayer game leaves everybody else's arms working.
local tiers = require("lib.tiers")
local art = require("prototypes.art")

--- One name for the three things that have to agree: the button, the key binding it names,
--- and what control.lua listens for.
local TOGGLE = "constructor-equipment-toggle"

data:extend{
  {
    type = "shortcut",
    name = TOGGLE,
    --- Among the toggles rather than among the tools, which is where the two it is a cousin
    --- of live: c[toggles]-a is the roboport and -b the exoskeleton.
    order = "c[toggles]-c[constructor-equipment]",
    --- Nothing the engine knows how to do, so the engine passes the click to script.
    action = "lua",
    --- Without this the button cannot be shown pressed in, and a toggle that does not look
    --- like one is worse than no button at all.
    toggleable = true,
    associated_control_input = TOGGLE,
    --- No button until there is something for it to switch off. The first tier's technology
    --- is named after the equipment it unlocks, as every tier's is.
    technology_to_unlock = tiers.list[1].name,
    localised_name = {"shortcut-name." .. TOGGLE},
    icons = art.icons(tiers.list[1], 64),
    small_icons = art.icons(tiers.list[1], 64),
  },
  {
    type = "custom-input",
    name = TOGGLE,
    --- Bound to nothing. Every combination worth having is already taken by the base game
    --- or by whatever the player has put there themselves, and a mod that helps itself to
    --- one is a mod that has to be unbound before it can be played with. It is listed in
    --- the controls menu for anybody who wants it on a key.
    key_sequence = "",
    --- Nothing else would be listening for a key the player chose for this, but a toggle
    --- that swallowed a key it shares would be a nuisance to find.
    consuming = "none",
  },
}
