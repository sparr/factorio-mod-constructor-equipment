--- A chest downgraded onto a heap of its own contents, which is where 20 was seen.
---
--- The showroom's bay: a steel chest two tiles from the mark holding 4800 iron plates,
--- ordered up to an iron chest. The smaller one takes 3200 and the other 1600 go on the
--- floor marked, the way a construction robot leaves what it cannot carry, and the arms
--- carry them away a clawful at a time over the next half minute.
---
--- What is measured is the one thing a ring of marked belts could never show. Those rings
--- were marked by the test, so every item on the ground had a marker by construction; here
--- the mod puts them there itself and then works them, and what is hunted is an item that
--- ends up lying on the ground with **no** marker on it -- which is an item nothing will
--- ever come back for, and which a player sees as litter appearing beside them.
---
--- Asked every tick rather than at the end, because the fault lasted one tick and left one
--- plate. The engine is asked for unmarked item entities directly, which costs nothing
--- until the moment being hunted: for the whole of a clean run the answer is none.
---
--- Run at two distances, because the report was of items reached for from about three and a
--- half tiles and dropped about four from the character, and where the heap lies decides
--- both. Swept over chests two, three and four tiles off and counting every pickup by how
--- far out its target was, the fault showed up once per run and in the bucket the heap put
--- the work in: on a pickup 1.29 out with the chest at two, on one 3.82 out with it at four,
--- landing 1.77 and 3.42 from the character. So it is the reported fault and not a
--- lookalike. One event a run is too few to call the rate, which the note put at one in
--- twenty at that distance and which measured here as one in forty odd in the bucket it fell
--- in; what is not in doubt is that with the ends moved together it is none at all, over a
--- thousand pickups across the three distances.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local PLATE = "iron-plate"
local HELD = 4800
local ROUND_RESEARCH = { "bulk-inserter", "inserter-capacity-bonus-1",
                         "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" }
--- Long enough for the arms to have worked a fair share of the heap, and long enough for
--- either layout to have gone wrong. The whole heap takes a good deal longer; what this has
--- to cover is enough crossings for one of them to go astray, and the further heap takes
--- until about tick 2600 to do it where the near one goes at 150.
local RUN = 3000
--- Everything within this of the character is the arms' doing. Wide enough to take in the
--- heap and the rest point both.
local NEAR = 14

describe("a chest downgraded onto a heap", function()
  local player

  local function scrub()
    for _, thing in ipairs(player.surface.find_entities_filtered{
          position = world.ORIGIN, radius = 60 }) do
      if thing.valid and thing.type ~= "character" then thing.destroy() end
    end
    world.clear(player)
  end

  before_each(function()
    player = world.player()
    world.clear(player)
    scrub()
    for _, name in ipairs(ROUND_RESEARCH) do
      local technology = player.force.technologies[name]
      if technology then technology.researched = true end
    end
  end)

  after_each(function()
    for _, name in ipairs(ROUND_RESEARCH) do
      local technology = player.force.technologies[name]
      if technology then technology.researched = false end
    end
    player.get_inventory(defines.inventory.character_armor).clear()
    scrub()
  end)

  -- Two tiles is the showroom's own bay; four is where the report put the work, and is the
  -- one that reaches far enough for a claw to be crossing at three and a half tiles out.
  for _, away in ipairs{ 2, 4 } do
  it(("leaves nothing lying about without a marker, a chest %d tiles off"):format(away),
      function()
    world.equip(player, { tiers.by_level[4].name, "fission-reactor-equipment",
      "battery-mk2-equipment" }, true, "power-armor")
    player.insert{ name = "iron-chest", count = 10 }

    local chest = player.surface.create_entity{ name = "steel-chest",
      position = { world.ORIGIN.x + away, world.ORIGIN.y }, force = player.force }
    assert.is_not_nil(chest, "the arena would not take a steel chest")
    chest.insert{ name = PLATE, count = HELD }
    chest.order_upgrade{ force = player.force,
      target = prototypes.entity["iron-chest"] }

    local began, stray, shed_at = game.tick, nil, nil
    world.once(function()
      local at = player.character and player.character.position or world.ORIGIN
      local loose = player.surface.find_entities_filtered{ position = at, radius = NEAR,
        type = "item-entity", to_be_deconstructed = false }
      if #loose > 0 and not stray then
        local item = loose[1]
        stray = {
          tick = game.tick - began,
          count = item.stack.valid_for_read and item.stack.count or 0,
          name = item.stack.valid_for_read and item.stack.name or "?",
          far = math.sqrt((item.position.x - at.x) ^ 2 + (item.position.y - at.y) ^ 2),
          how_many = #loose,
        }
      end
      if not shed_at and player.surface.count_entities_filtered{ position = at,
            radius = NEAR, type = "item-entity" } > 0 then
        shed_at = game.tick - began
      end
      return stray ~= nil or game.tick - began > RUN
    end, function()
      -- Everything the chest held, wherever it has got to, so that a run which loses an
      -- item somewhere else entirely cannot pass by leaving nothing on the floor.
      local carried = player.get_main_inventory().get_item_count(PLATE)
      local standing, marked = 0, 0
      for _, box in ipairs(player.surface.find_entities_filtered{
            position = world.ORIGIN, radius = 60, type = "container" }) do
        local inside = box.valid and box.get_inventory(defines.inventory.chest)
        if inside then standing = standing + inside.get_item_count(PLATE) end
      end
      for _, item in ipairs(player.surface.find_entities_filtered{
            position = world.ORIGIN, radius = 60, type = "item-entity" }) do
        if item.valid and item.stack.valid_for_read and item.stack.name == PLATE then
          marked = marked + item.stack.count
        end
      end
      local claws = 0
      for _, record in pairs(storage.constructor_arms[player.index] or {}) do
        local arm = record.entity
        if arm and arm.valid and arm.held_stack.valid_for_read
            and arm.held_stack.name == PLATE then
          claws = claws + arm.held_stack.count
        end
      end
      log(("SPILL | shed by tick %s | after %d ticks: %d carried, %d in containers, %d on"
        .. " the ground, %d in claws, %d of %d accounted for"):format(tostring(shed_at),
        game.tick - began, carried, standing, marked, claws,
        carried + standing + marked + claws, HELD))
      if stray then
        log(("SPILL | STRAY: %d %s on tick %d, %.2f tiles from the player, %d of them")
          :format(stray.count, stray.name, stray.tick, stray.far, stray.how_many))
      end
      assert.is_not_nil(shed_at, "nothing was ever shed, so the bay did not run")
      assert.is_nil(stray, stray and
        ("%d %s ended up on the ground with no deconstruct marker on it, on tick %d, %.2f"
          .. " tiles from the player"):format(stray.count, stray.name, stray.tick,
          stray.far) or "")
      -- Nothing made and nothing lost on the way, which is the other half of the question:
      -- an item quietly destroyed leaves the floor just as clean as one carried home.
      assert.are.equal(HELD, carried + standing + marked + claws,
        "the chest's plates do not add up")
    end, "the downgrade never finished", RUN + 200)
  end)
  end
end)
