--- With the box as both the claw's drop and its source, does the claw put its load down?
--- And once it arrives, how near does the hand get? Temporary.
local world = require("test.ft.world")
local reach = require("lib.reach")

local player

before_each(function() player = world.player() world.clear(player) end)
after_each(function() player = world.player() world.clear(player) end)

describe("MEASURE the box as both drop and source", function()
  for _, wait in ipairs{ 90, 200, 400 } do
    it(("held for %d ticks"):format(wait), function()
      for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1",
                            "inserter-capacity-bonus-2" } do
        player.force.technologies[name].researched = true
      end
      local arm = player.surface.create_entity{ name = "constructor-equipment-4-inserter",
        position = { world.ORIGIN.x, world.ORIGIN.y }, force = player.force }
      arm.destructible = false
      local source = player.surface.create_entity{ name = "electric-energy-interface",
        position = { world.ORIGIN.x, world.ORIGIN.y - 4 }, force = player.force }
      if source then source.power_production = 1000000 end
      player.surface.create_entity{ name = "substation",
        position = { world.ORIGIN.x - 2, world.ORIGIN.y - 3 }, force = player.force }

      local near = { world.ORIGIN.x + 2, world.ORIGIN.y }
      local far = { world.ORIGIN.x - 4, world.ORIGIN.y }
      local home = { world.ORIGIN.x, world.ORIGIN.y + 3 }
      local one = player.surface.create_entity{ name = "steel-chest", position = near,
        force = player.force }
      local two = player.surface.create_entity{ name = "steel-chest", position = far,
        force = player.force }
      one.insert{ name = "iron-plate", count = 1 }
      arm.pickup_position = near
      arm.drop_position = home
      after_ticks(35, function()
        local held = arm.held_stack.valid_for_read and arm.held_stack.count or 0
        arm.pickup_position = far
        arm.drop_position = far
        after_ticks(wait, function()
          assert.are.equal(-1, held,
            ("MEASURE %4d: set off holding %d, now %.2f from the box, holding %d, box %d, floor %d"):
            format(wait, held,
              reach.distance(arm.held_stack_position, { x = far[1], y = far[2] }),
              arm.held_stack.valid_for_read and arm.held_stack.count or 0,
              two.get_item_count("iron-plate"),
              #player.surface.find_entities_filtered{ position = world.ORIGIN, radius = 8,
                type = "item-entity" }))
        end)
      end)
    end)
  end
end)
