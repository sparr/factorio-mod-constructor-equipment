--- A quality arm, which is one the engine swings faster.
---
--- Nothing about a tier's reach or its price changes with quality. What changes is the pair
--- of speeds the hand moves at: the engine scales an inserter's extension and rotation by one
--- plus three tenths of the quality level, and charges proportionally more power for it.
--- Measured on the fourth tier's prototype: 0.1 and 0.0068 at normal, 0.25 and 0.017 at
--- legendary, with the draw going 2136 W to 5340 W.
---
--- So a quality piece in the grid has to make a quality arm, and lib/reach.lua has to be
--- working from the same pair the entity is -- a model reading the table while the engine
--- reads the prototype is a model that thinks the hand is somewhere it is not, by a factor of
--- two and a half at legendary. Both halves are what this checks.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local LEVEL = 4

describe("an arm made of quality equipment", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
    world.clear(player)
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function()
    player.get_inventory(defines.inventory.character_armor).clear()
    scrub()
  end)

  ---Every quality the game ships, worst first, skipping the placeholder.
  local function qualities()
    local found = {}
    for name, quality in pairs(prototypes.quality) do
      if name ~= "quality-unknown" then
        found[#found + 1] = { name = name, level = quality.level }
      end
    end
    table.sort(found, function(one, other) return one.level < other.level end)
    return found
  end

  for _, want in ipairs{ "normal", "rare", "legendary" } do
    it(("a %s piece makes a %s arm"):format(want, want), function()
      local tier = tiers.by_level[LEVEL]
      world.equip(player, { { tier.name, want }, "battery-mk2-equipment" }, true,
        "power-armor")
      -- Something to build and something to build it with, which is what brings an arm out.
      player.insert{ name = "transport-belt", count = 10 }
      world.ghost(player, "transport-belt", 2, 0)
      local arm
      world.once(function()
        local record = (storage.constructor_arms[player.index] or {})[1]
        arm = record and record.entity
        return arm ~= nil and arm.valid
      end, function()
        assert.are.equal(want, arm.quality.name,
          ("the piece was %s and the arm came out %s"):format(want, arm.quality.name))
      end, "no arm was ever made", 200)
    end)
  end

  it("PROBE: what each quality is worth, in ticks", function()
    local tier = tiers.by_level[LEVEL]
    local proto = prototypes.entity[tier.inserter]
    for _, quality in ipairs(qualities()) do
      local extension = proto.get_inserter_extension_speed(quality.name)
      local rotation = proto.get_inserter_rotation_speed(quality.name)
      log(("QUALITY | %-10s L%d | engine %.4f / %.5f | one flight out %.1f ticks | half a"
        .. " turn %.1f | %.0f W"):format(quality.name, quality.level, extension, rotation,
        reach.full_swing{ range = tier.range, extension = extension },
        reach.any_way{ rotation = rotation },
        proto.get_max_energy_usage(quality.name) * 60))
    end
  end)

  --- The whole of it end to end, which is the only thing that catches a model fitted to one
  --- pair of speeds while the entity swings at another: a claw aimed by arithmetic that
  --- thinks it is slow arrives somewhere its target no longer is.
  it("delivers sooner the better it is", function()
    local tier = tiers.by_level[LEVEL]
    -- One after another rather than side by side: world.once() registers a handler and
    -- returns, so a loop of them would set every run going on the same tick and time them
    -- all against the same ghost.
    local order = { "normal", "legendary" }
    local took = {}
    local function run(index)
      local want = order[index]
      if not want then
        log(("QUALITY | normal %d ticks, legendary %d"):format(took.normal,
          took.legendary))
        assert.is_true(took.normal < 400, "the normal arm never built it")
        assert.is_true(took.legendary < took.normal,
          ("legendary took %d ticks against normal's %d"):format(took.legendary,
            took.normal))
        return
      end
      player.get_inventory(defines.inventory.character_armor).clear()
      scrub()
      world.equip(player, { { tier.name, want }, "battery-mk2-equipment" }, true,
        "power-armor")
      player.insert{ name = "transport-belt", count = 10 }
      -- Behind the character and at nearly full stretch, so the swing is the whole of the
      -- wait: a half turn to make and the reach to cover, which is what quality shortens.
      world.ghost(player, "transport-belt", -4, 0)
      local began = game.tick
      world.once(function()
        return world.ghosts(player) == 0 or game.tick - began > 400
      end, function()
        took[want] = game.tick - began
        run(index + 1)
      end, ("the %s arm never built it"):format(want), 500)
    end
    run(1)
  end)

  it("swings faster the better it is", function()
    local tier = tiers.by_level[LEVEL]
    local proto = prototypes.entity[tier.inserter]
    local last
    for _, quality in ipairs(qualities()) do
      local extension = proto.get_inserter_extension_speed(quality.name)
      local rotation = proto.get_inserter_rotation_speed(quality.name)
      local swing = reach.full_swing{ range = tier.range, extension = extension }
      local turn = reach.any_way{ rotation = rotation }
      if last then
        assert.is_true(swing < last.swing,
          ("%s reaches out in %.1f ticks against %s's %.1f"):format(quality.name, swing,
            last.name, last.swing))
        assert.is_true(turn < last.turn,
          ("%s turns in %.1f ticks against %s's %.1f"):format(quality.name, turn,
            last.name, last.turn))
      end
      last = { name = quality.name, swing = swing, turn = turn }
    end
    assert.is_not_nil(last, "no qualities were found at all")
  end)
end)
