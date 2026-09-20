--- The arm itself, as a real entity rather than a drawing of one, and one prototype per
--- tier because the tiers differ in colour, in how fast they swing and in what that costs.
---
--- Drawing an arm by hand means drawing an arm: a sprite stretched from the shoulder to
--- the claw, with no elbow, no shadow, and a texture that distorts as it reaches. An
--- inserter entity already knows how to swing, and the engine animates it properly. So
--- there is one of these per arm, moved to wherever its character is, aimed by setting its
--- drop position, and handed an item when there is something to deliver. Its own logic
--- does the rest.
---
--- It is not a thing in the world in any other sense: it collides with nothing, cannot be
--- selected, mined, blueprinted or seen on the map. placeable-off-grid is what lets it sit
--- exactly on a character rather than snapping to the tile they happen to be standing on.
---
--- It does run on power, at the base game's own prices for the inserter it borrows from,
--- and out in the open it is on no network to get any: control.lua tops its buffer up out
--- of the armour's batteries every tick and takes back whatever is left when the arm is put
--- away. That way the engine works out the bill -- a swing costs what a swing costs, and a
--- long reach costs more than a short one -- and an armour with nothing left in it stops
--- the arm where it stands.
---
--- Which is why the power goes through script at all, rather than the equipment feeding the
--- arm the way a grid feeds equipment. There is no engine path from a grid to an entity: a
--- grid powers equipment, and this is an inserter, because an inserter is the only thing in
--- the game that knows how to swing a hand on an elbow at a given speed and move something
--- at the end of it. The one precedent, a personal roboport powering robots, is a fixed
--- relationship between two prototype types rather than anything a mod can aim at an
--- inserter. Giving this a void energy source would do away with the script and with the
--- billing together, which is the half worth keeping.
---
--- "On no network" is only true outdoors, and that is worth writing down. An electric entity
--- joins whatever network covers the tile it stands on, and an arm rides on a character who
--- can walk into a supply area. Measured on 2.1.19, with a fourth tier arm reaching for a
--- ghost: standing in the open the arm reports no network at all, and standing inside a
--- powered area it reports one and draws 2017 J from it over sixty ticks, about 34 J a tick.
--- charge() only makes up the shortfall, so whatever the network gives is subtracted from
--- what the armour pays: building inside your own factory is part paid for by the factory,
--- to the tune of roughly one fiftieth of a reach.
---
--- Left alone rather than fixed. There is no flag for an electric energy source that refuses
--- to join a network, and the alternatives cost more than the leak: a void source loses the
--- billing, and emptying the buffer before refilling it each tick does not help, because the
--- engine has already spent that tick's network draw by the time script runs.
local tiers = require("lib.tiers")
local art = require("prototypes.art")

--- How much charge an arm carries: a couple of movements' worth, so a tick's draw never
--- empties it between one top up and the next, and little is tied up in the arm at any
--- moment or has to be handed back when it is put away.
local BUFFER_MOVEMENTS = 2

local arms = {}

for _, tier in ipairs(tiers.list) do
  table.insert(arms, {
    type = "inserter",
    name = tier.inserter,
    energy_source =
    {
      type = "electric",
      usage_priority = "secondary-input",
      buffer_capacity = (tier.movement * BUFFER_MOVEMENTS) .. "J",
      -- The arm is on no network on purpose: the armour feeds it. Say so, or the engine
      -- draws an unplugged warning over the character the whole time the arm is out.
      render_no_network_icon = false,
      render_no_power_icon = false,
      -- what the base game charges this same inserter to sit idle
      drain = tier.drain
    },
    energy_per_movement = tier.energy,
    energy_per_rotation = tier.energy,
    -- A claw that carries more than one has to be told so: without this the engine holds
    -- the hand to a single item however many are put in it. Inserter capacity research
    -- raises it from there, the same as it raises every other inserter in the factory --
    -- these are inserters, and a player who has paid for bigger hands should get them here
    -- too. Nothing is added on top of that, so an arm holds what the inserter it is made of
    -- holds. How many ghosts a journey works through is read back off the hand itself in
    -- control.lua, so the two can never disagree.
    bulk = tier.bulk,
    uses_inserter_stack_size_bonus = true,
    extension_speed = tier.extension,
    rotation_speed = tier.rotation,
    -- both ends are set from script every tick; these are only what it starts with
    pickup_position = { 0, 0 },
    insert_position = { 0, 1 },
    allow_custom_vectors = true,
    draw_held_item = true,
    -- No arrow. An inserter draws a marker showing which way it hands things over, and it
    -- is drawn on the character's own tile when the arm is worn: hovering the ghost it was
    -- reaching for showed a yellow line straight through them.
    draw_inserter_arrow = false,
    -- the base is deliberately nothing. An arm coming out of someone's back says what is
    -- happening; a platform strapped there as well only gets in the way of it.
    platform_picture =
    {
      sheet =
      {
        filename = "__core__/graphics/empty.png",
        priority = "extra-high",
        width = 1,
        height = 1
      }
    },
    hand_base_picture = art.hand(tier, "base"),
    hand_closed_picture = art.hand(tier, "closed"),
    hand_open_picture = art.hand(tier, "open"),
    hand_base_shadow = art.hand_shadow(tier, "base"),
    hand_closed_shadow = art.hand_shadow(tier, "closed"),
    hand_open_shadow = art.hand_shadow(tier, "open"),
    collision_box = { { -0.15, -0.15 }, { 0.15, 0.15 } },
    collision_mask = { layers = {} },
    -- No selection box at all rather than a small one. Hovering something an inserter is
    -- working with highlights the inserter as well, and a box round the middle of the
    -- character is not something the player should ever be shown. Being unselectable is
    -- not enough on its own: the highlight is drawn for the entity a hovered one is
    -- related to, whether it can be clicked or not.
    selectable_in_game = false,
    hidden = true,
    hidden_in_factoriopedia = true,
    flags =
    {
      -- Sixteen ways to face rather than four. Without this an inserter takes the four
      -- cardinals and truncates anything else -- ask for west by way of a fifteenth of a
      -- turn and it faces south -- and control.lua points an arm at what it is about to
      -- reach for by building it facing that way. Four leaves an eighth of a turn to swing
      -- through at worst, which hides behind the extension on a long reach and does not on
      -- a short one; sixteen leaves a thirty-second, which is nothing anywhere.
      --
      -- Measured on 2.1.19: with this flag all sixteen stick and the hand starts exactly on
      -- its bearing, 179/256 of a tile out, at every one of them. On its bearing and nothing
      -- else -- an arm built facing east starts its hand due east whether its pickup is set
      -- three tiles west, three north, or never set at all, and setting either end on the
      -- same tick does not move it. It is a flag about how a player builds a thing, and
      -- nobody builds these: they are hidden, not blueprintable, and made only by script.
      "building-direction-16-way",
      "not-on-map",
      "not-blueprintable",
      "not-deconstructable",
      "placeable-off-grid",
      "not-upgradable",
      "no-automated-item-removal",
      "no-automated-item-insertion"
    }
  })
end

data:extend(arms)
