--- The inserter itself, as a real entity rather than a drawing of one.
---
--- Drawing an arm by hand means drawing an arm: a sprite stretched from the shoulder to
--- the claw, with no elbow, no shadow, and a texture that distorts as it reaches. An
--- inserter entity already knows how to swing, and the engine animates it properly. So
--- there is one of these per character, moved to wherever they are, aimed by setting its
--- drop position, and handed an item when there is something to deliver. Its own logic
--- does the rest.
---
--- It is not a thing in the world in any other sense: it collides with nothing, cannot be
--- selected, mined, blueprinted or seen on the map, and runs on no power so it never waits
--- for any. placeable-off-grid is what lets it sit exactly on a character rather than
--- snapping to the tile they happen to be standing on.
local HAND = "__base__/graphics/entity/long-handed-inserter/"

--- How fast the hand moves, in tiles per tick, and how fast it turns. Quicker than a real
--- long handed inserter, because this one is meant to keep up with someone walking.
local EXTENSION_SPEED = 0.15
local ROTATION_SPEED = 0.05

---The base game's own hand graphics. The arm and the claw are different sizes, so the
---size goes with the picture rather than being guessed from it.
local function hand(picture, width, height, shadow)
  return {
    filename = HAND .. picture,
    priority = "extra-high",
    width = width,
    height = height,
    scale = 0.5,
    draw_as_shadow = shadow or nil
  }
end

local ARM = { "long-handed-inserter-hand-base.png", 32, 136 }
local CLOSED = { "long-handed-inserter-hand-closed.png", 72, 164 }
local OPEN = { "long-handed-inserter-hand-open.png", 72, 164 }

data:extend(
{
  {
    type = "inserter",
    name = "constructor-equipment-inserter",
    -- runs on nothing: the equipment's own batteries are what actually pay for a build,
    -- and an inserter waiting for power would just stand there with its arm out
    energy_source = { type = "void" },
    energy_per_movement = "1J",
    energy_per_rotation = "1J",
    extension_speed = EXTENSION_SPEED,
    rotation_speed = ROTATION_SPEED,
    -- both ends are set from script every tick; these are only what it starts with
    pickup_position = { 0, 0 },
    insert_position = { 0, 1 },
    allow_custom_vectors = true,
    draw_held_item = true,
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
    hand_base_picture = hand(ARM[1], ARM[2], ARM[3]),
    hand_closed_picture = hand(CLOSED[1], CLOSED[2], CLOSED[3]),
    hand_open_picture = hand(OPEN[1], OPEN[2], OPEN[3]),
    hand_base_shadow = hand(ARM[1], ARM[2], ARM[3], true),
    hand_closed_shadow = hand(CLOSED[1], CLOSED[2], CLOSED[3], true),
    hand_open_shadow = hand(OPEN[1], OPEN[2], OPEN[3], true),
    collision_box = { { -0.15, -0.15 }, { 0.15, 0.15 } },
    collision_mask = { layers = {} },
    selection_box = { { -0.2, -0.2 }, { 0.2, 0.2 } },
    selectable_in_game = false,
    hidden = true,
    hidden_in_factoriopedia = true,
    flags =
    {
      "not-on-map",
      "not-blueprintable",
      "not-deconstructable",
      "placeable-off-grid",
      "not-upgradable",
      "no-automated-item-removal",
      "no-automated-item-insertion"
    }
  }
})
