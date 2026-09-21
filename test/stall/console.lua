--- The vanilla reproduction, as console commands.
---
--- Kept as strings so that the fixture which proves they work runs exactly the text that
--- gets handed to somebody, rather than a paraphrase of it that can drift away from it.
--- Paste each one into the game's console with `/c` in front. Base game prototypes only,
--- and nothing is cleared away first, because this is for a blank map.
---
--- Powered by an energy interface and a pole rather than by a burner inserter carrying coal.
--- Coal went in perfectly well when measured here, by all three of the ways there are to put
--- it in, and went in as nothing at all on the machine this was written for -- so the fuel
--- is taken out of the question rather than argued about.
---
--- No comments inside the command strings: a paste that loses its newlines turns the first
--- of them into a lid over everything after it.
---
--- `game.player or game.players[1]` because the first works in a console and the second in a
--- headless test, and both are true in the other's setting.
return {
  {
    name = "build",
    what = "Build the rig four tiles east of you.",
    code = [[
local p = game.player or game.players[1]
local s = p.surface
local at = { x = math.floor(p.position.x) + 4.5, y = math.floor(p.position.y) + 0.5 }
local arm = s.create_entity{ name = "inserter", position = at,
  direction = defines.direction.north, force = p.force }
local pole = s.create_entity{ name = "small-electric-pole", force = p.force,
  position = { at.x + 1, at.y } }
local supply = s.create_entity{ name = "electric-energy-interface", force = p.force,
  position = { at.x + 2, at.y } }
supply.power_production = 1000000
supply.electric_buffer_size = 10000000
supply.energy = 10000000
local pick, drop = arm.pickup_position, arm.drop_position
local from = s.create_entity{ name = "iron-chest", force = p.force,
  position = { math.floor(pick.x) + 0.5, math.floor(pick.y) + 0.5 } }
from.insert{ name = "transport-belt", count = 50 }
local front = s.create_entity{ name = "transport-belt", force = p.force,
  position = { math.floor(drop.x) + 0.5, math.floor(drop.y) + 0.5 },
  direction = defines.direction.east }
front.order_deconstruction(p.force)
p.print(string.format("built: chest of %d belts behind it, a belt in front of it marked for"
  .. " deconstruction, power %s. It will not move.",
  from.get_item_count("transport-belt"),
  (pole and supply) and "connected" or "MISSING"))
]],
  },
  {
    name = "toggle",
    what = "Take the deconstruction order off, or put it back. Off, it starts at once.",
    code = [[
local p = game.player or game.players[1]
local s = p.surface
local arm = s.find_entities_filtered{ name = "inserter", position = p.position,
  radius = 10 }[1]
if not arm then p.print("no inserter nearby") return end
local d = arm.drop_position
local front = s.find_entities_filtered{ position = { math.floor(d.x) + 0.5,
  math.floor(d.y) + 0.5 }, radius = 0.4 }[1]
if not front then p.print("nothing in front of it") return end
if front.to_be_deconstructed() then
  front.cancel_deconstruction(p.force)
  p.print("the mark is off, so the hand should start moving")
else
  front.order_deconstruction(p.force)
  p.print("the mark is back on, so the hand should stop")
end
]],
  },
  {
    name = "say",
    what = "Say what the inserter is doing, and where its two ends are.",
    code = [[
local p = game.player or game.players[1]
local s = p.surface
local arm = s.find_entities_filtered{ name = "inserter", position = p.position,
  radius = 10 }[1]
if not arm then p.print("no inserter nearby") return end
local names = {}
for name, value in pairs(defines.entity_status) do names[value] = name end
local d = arm.drop_position
local front = s.find_entities_filtered{ position = { math.floor(d.x) + 0.5,
  math.floor(d.y) + 0.5 }, radius = 0.4 }[1]
p.print(string.format("status %s | hand at %.2f,%.2f | pickup %.1f,%.1f | drop %.1f,%.1f"
  .. " | in front: %s", names[arm.status] or arm.status,
  arm.held_stack_position.x, arm.held_stack_position.y,
  arm.pickup_position.x, arm.pickup_position.y, d.x, d.y,
  front and (front.name .. (front.to_be_deconstructed() and ", marked" or ", not marked"))
    or "nothing"))
]],
  },
}
