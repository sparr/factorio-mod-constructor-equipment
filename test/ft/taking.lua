--- What the equipment does about a deconstruction planner.
---
--- The mirror of building: the claw goes out empty and comes home loaded. A thing holding
--- something is emptied a stack a trip and taken up only once it is empty, which is what a
--- robot does with it: measured on 2.1.17, fifty of them took a full steel chest away in
--- hundred plate mouthfuls over a minute and the chest itself went last.
local world = require("test.ft.world")

local A_BUILD = world.BUILD_INTERVAL * 2
local BELT = "transport-belt"

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

---Something standing in the arena with a deconstruction order on it.
local function doomed(name, dx, dy)
  local thing = player.surface.create_entity{
    name = name,
    position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy },
    direction = defines.direction.east,
    force = player.force,
  }
  assert(thing, "could not place a " .. name)
  thing.order_deconstruction(player.force)
  assert(thing.to_be_deconstructed(), name .. " would not take the order")
  return thing
end

describe("a thing marked for deconstruction", function()
  before_each(function()
    world.equipped(player)
    player.get_inventory(defines.inventory.character_main).clear()
  end)

  it("is taken up and handed to the character", function()
    doomed(BELT, 2, 0)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, world.count(player, BELT), "the belt is still standing there")
      assert.are.equal(1, player.get_item_count(BELT), "the belt never arrived")
    end)
  end)

  it("costs nothing to set off after", function()
    doomed(BELT, 2, 0)
    after_ticks(12, function()
      assert.are.equal(0, player.get_item_count(BELT),
        "something was taken out of the pockets for a fetch")
    end)
  end)

  it("comes home in the claw rather than teleporting", function()
    doomed(BELT, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(0, world.count(player, BELT), "the belt has not been taken up yet")
      assert.are.equal(BELT, world.held(player), "the claw is not carrying it")
      assert.are.equal(0, player.get_item_count(BELT), "it went straight to the pockets")
    end)
  end)

  it("leaves one out of reach alone", function()
    doomed(BELT, world.BUILD_RANGE + 6, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "it reached further than its range")
    end)
  end)

  it("leaves an unmarked thing standing", function()
    local belt = doomed(BELT, 2, 0)
    belt.cancel_deconstruction(player.force)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "something nobody marked was taken up")
      assert.are.equal(0, player.get_item_count(BELT), "and it was handed over")
    end)
  end)

  it("stops when the order is called off mid reach", function()
    local belt = doomed(BELT, 2, 0)
    after_ticks(12, function()
      belt.cancel_deconstruction(player.force)
      after_ticks(world.CYCLE, function()
        assert.are.equal(1, world.count(player, BELT), "it was taken up anyway")
      end)
    end)
  end)

  describe("a chest with something in it", function()
    it("is emptied a load at a time before the chest itself goes", function()
      local chest = doomed("steel-chest", 2, 0)
      chest.insert{ name = "iron-plate", count = 250 }
      after_ticks(world.CYCLE * 2, function()
        assert.is_true(chest.valid, "the chest went before it was empty")
        assert.is_true(player.get_item_count("iron-plate") > 0,
          "no plates were brought back")
        assert.is_true(chest.get_inventory(defines.inventory.chest).get_item_count() < 250,
          "the chest is as full as it was")
      end)
    end)

    -- Three, not three hundred. A claw carries what its inserter carries, which is one
    -- thing for the first tier before any capacity research, so emptying a chest is as many
    -- trips as it has things in it. That is the same bargain the building side makes.
    it("goes last, once it is empty", function()
      local chest = doomed("steel-chest", 2, 0)
      chest.insert{ name = "iron-plate", count = 3 }
      after_ticks(world.CYCLE * 8, function()
        assert.are.equal(0, world.count(player, "steel-chest"), "the chest is still standing")
        assert.are.equal(3, player.get_item_count("iron-plate"), "the plates went astray")
        assert.are.equal(1, player.get_item_count("steel-chest"), "the chest never arrived")
      end)
    end)

    it("brings back no more in one trip than the claw can hold", function()
      local chest = doomed("steel-chest", 2, 0)
      chest.insert{ name = "iron-plate", count = 50 }
      after_ticks(world.DELIVERED, function()
        assert.is_true(player.get_item_count("iron-plate") <= 1,
          "a first tier claw came home with more than it can hold")
        assert.is_true(chest.valid and
          chest.get_inventory(defines.inventory.chest).get_item_count() >= 49,
          "more than a clawful left the chest")
      end)
    end)
  end)

  it("takes up a tile marked for removal", function()
    local at = { world.ORIGIN.x + 2, world.ORIGIN.y }
    player.surface.set_tiles{ { name = "concrete", position = at } }
    local tile = player.surface.get_tile(at[1], at[2])
    tile.order_deconstruction(player.force)
    assert.are.equal(1, player.surface.count_entities_filtered{
      type = "deconstructible-tile-proxy" }, "the tile was never marked")
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, player.surface.count_entities_filtered{
        type = "deconstructible-tile-proxy" }, "the tile is still marked")
      assert.are.equal(1, player.get_item_count("concrete"), "the concrete never arrived")
    end)
  end)
end)

describe("several things marked at once", function()
  before_each(function()
    player = world.player()
    world.clear(player)
    world.equipped(player)
    player.get_inventory(defines.inventory.character_main).clear()
  end)

  -- The order find_entities_filtered hands things back in walks the map's own index, which
  -- had a claw crossing a patch in bands rather than working outward from itself.
  it("goes for the nearest first", function()
    local near = player.surface.create_entity{ name = "transport-belt",
      position = { world.ORIGIN.x + 1, world.ORIGIN.y }, force = player.force }
    local far = player.surface.create_entity{ name = "transport-belt",
      position = { world.ORIGIN.x + 2, world.ORIGIN.y }, force = player.force }
    -- marked far first, so index order and distance order disagree
    far.order_deconstruction(player.force)
    near.order_deconstruction(player.force)
    after_ticks(world.DELIVERED, function()
      assert.is_false(near.valid, "it went for the far one first")
      assert.is_true(far.valid, "both went at once")
    end)
  end)
end)

-- A claw takes what it went to and nothing else, however much room is left in its hand. An
-- arm that picks up what it did not travel to is not doing anything a player can watch, and
-- a version of this that gathered everything marked inside the arm's whole range made a yard
-- of shed plates wink out at once while the claw sat over one of them.
--
-- Filling up still happens where filling up means more out of the one thing the claw is
-- standing at: a chest goes a clawful at a time, which is tested further up.
describe("a claw with room left in its hand", function()
  local BULK = "constructor-equipment-4"

  before_each(function()
    player = world.player()
    world.clear(player)
    for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1",
                          "inserter-capacity-bonus-2" } do
      local technology = player.force.technologies[name]
      if technology then technology.researched = true end
    end
    world.equip(player, { BULK, "battery-mk2-equipment" }, true)
    player.get_inventory(defines.inventory.character_main).clear()
  end)

  after_each(function()
    for _, name in pairs{ "inserter-capacity-bonus-1", "inserter-capacity-bonus-2" } do
      local technology = player.force.technologies[name]
      if technology then technology.researched = false end
    end
  end)

  it("leaves the rest of the patch for another trip", function()
    local at = { world.ORIGIN.x + 3, world.ORIGIN.y }
    local tiles = {}
    for dx = 0, 1 do
      for dy = -1, 0 do
        tiles[#tiles + 1] = { name = "concrete", position = { at[1] + dx, at[2] + dy } }
      end
    end
    player.surface.set_tiles(tiles)
    for _, tile in pairs(tiles) do
      player.surface.get_tile(tile.position[1], tile.position[2])
        .order_deconstruction(player.force)
    end
    assert.are.equal(4, player.surface.count_entities_filtered{
      type = "deconstructible-tile-proxy" }, "the tiles were not all marked")

    -- One trip, and the claw has room for four. Three of the patch are still standing,
    -- within a tile and a half of the one it took, and it did not reach for any of them.
    after_ticks(world.CYCLE, function()
      assert.are.equal(1, player.get_item_count("concrete"),
        "the claw took tiles it had not travelled to")
      assert.are.equal(3, player.surface.count_entities_filtered{
        type = "deconstructible-tile-proxy" }, "more of the patch went than the claw went to")
    end)
  end)

  -- Every one of them is its own journey now, which is slower and is what an arm does.
  it("comes back for the rest of the patch until it is gone", function()
    local at = { world.ORIGIN.x + 3, world.ORIGIN.y }
    local tiles = {}
    for dx = 0, 1 do
      for dy = -1, 0 do
        tiles[#tiles + 1] = { name = "concrete", position = { at[1] + dx, at[2] + dy } }
      end
    end
    player.surface.set_tiles(tiles)
    for _, tile in pairs(tiles) do
      player.surface.get_tile(tile.position[1], tile.position[2])
        .order_deconstruction(player.force)
    end
    after_ticks(world.CYCLE * 8, function()
      assert.are.equal(0, player.surface.count_entities_filtered{
        type = "deconstructible-tile-proxy" }, "some of the patch is still marked")
      assert.are.equal(4, player.get_item_count("concrete"),
        "the whole patch did not come home")
    end)
  end)

  -- A trip each, since they are in two places. They both come home, which is the part worth
  -- keeping: what is decided here is how many journeys it takes, not whether it gets done.
  it("takes one from either side of its owner, a trip each", function()
    for _, dx in pairs{ 3, -3 } do
      local belt = player.surface.create_entity{ name = "transport-belt",
        position = { world.ORIGIN.x + dx, world.ORIGIN.y }, force = player.force }
      belt.order_deconstruction(player.force)
    end
    after_ticks(world.CYCLE * 4, function()
      assert.are.equal(0, world.count(player, "transport-belt"),
        "one of them is still standing after both trips")
      assert.are.equal(2, player.get_item_count("transport-belt"),
        "both should have come home")
    end)
  end)

end)

-- The walk round reported the arm emptying the chest it had just built, and the obvious
-- mechanism is that a claw fetches things off the floor by pointing an inserter at them:
-- aim one where a chest stands and it ought to take from the chest. Measured, it does not.
-- The heap comes up off the floor and the chest is not touched, at the middle of its tile
-- and at the edge of it alike, so this is here to keep that true rather than to guard
-- against the thing it was written to catch.
describe("something marked for taking up with a chest standing over it", function()
  local function chest_over_a_heap(offset)
    local at = { world.ORIGIN.x + 2, world.ORIGIN.y }
    local chest = player.surface.create_entity{
      name = "iron-chest", position = at, force = player.force }
    chest.insert{ name = "iron-plate", count = 100 }
    local heap = player.surface.create_entity{
      name = "item-on-ground",
      position = { at[1] + offset, at[2] },
      stack = { name = "copper-plate", count = 1 },
    }
    if heap then heap.order_deconstruction(player.force) end
    world.equip(player, { "constructor-equipment-4", "battery-mk2-equipment" }, true)
    return chest, heap
  end

  it("takes a heap off the chest's middle without touching the chest", function()
    local chest = chest_over_a_heap(0)
    after_ticks(A_BUILD * 4, function()
      assert.are.equal(1, player.get_item_count("copper-plate"),
        "the heap on the chest's tile was never picked up at all")
      assert.are.equal(100, chest.get_item_count("iron-plate"),
        "the arm emptied the chest instead of picking up what was on its tile")
    end)
  end)

  -- A container's collision box is smaller than the tile it stands on, so a heap can sit
  -- clear of the box and still be on the tile the inserter would aim at.
  it("takes one at the edge of its tile without touching the chest", function()
    local chest = chest_over_a_heap(0.45)
    after_ticks(A_BUILD * 4, function()
      assert.are.equal(1, player.get_item_count("copper-plate"),
        "the heap on the chest's tile was never picked up at all")
      assert.are.equal(100, chest.get_item_count("iron-plate"),
        "the arm emptied the chest instead of picking up what was on its tile")
    end)
  end)
end)

-- How fast a claw clears a yard, as a floor.
--
-- The number is what it is because every one of these is its own journey. Measured on this
-- scatter as the rule changed: 27 of forty in 360 ticks when a claw arriving at one thing
-- swept up everything marked inside the arm's whole range, 19 when that was cut to a tile
-- and a half of where it stood, and 8 now that it takes only what it travelled to. The last
-- of those is the honest one, and the two before it were the mod moving things it had not
-- gone to.
--
-- The order the claw goes in is decided by swing time rather than distance, because an
-- inserter turns and extends at once and on the long arms the turn is the slower of the
-- two. That arithmetic is unit tested in reach_spec; this is only a floor, so that a change
-- which halves the rate is noticed.
describe("a claw with a yardful of things to pick up", function()
  local LAID = 40
  local RUN = 360
  -- Comfortably under the 8 it measures at, so drift does not fail it and a collapse does.
  local ENOUGH = 6

  it("clears most of it inside a few hundred ticks", function()
    world.equip(player, { "constructor-equipment-4", "fission-reactor-equipment",
                          "battery-mk2-equipment" }, true)
    for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1" } do
      player.force.technologies[name].researched = true
    end
    -- Every angle and every reach, which is the shape a shed leaves on the floor. Thirteen
    -- is coprime with forty, so the angles do not fall into spokes.
    local laid = 0
    for step = 0, LAID - 1 do
      local angle = step * 2 * math.pi / 13
      local radius = 1.2 + (step % 5) * 0.7
      local thing = player.surface.create_entity{
        name = "item-on-ground",
        position = { world.ORIGIN.x + math.cos(angle) * radius,
                     world.ORIGIN.y + math.sin(angle) * radius },
        stack = { name = BELT, count = 1 },
      }
      if thing then
        thing.order_deconstruction(player.force)
        laid = laid + 1
      end
    end
    assert.are.equal(LAID, laid, "the scatter did not go down")
    after_ticks(RUN, function()
      local left = #player.surface.find_entities_filtered{
        position = world.ORIGIN, radius = 20, type = "item-entity" }
      assert.is_true(laid - left >= ENOUGH,
        ("only %d of %d were taken up in %d ticks, where 8 is what it measures at"):
          format(laid - left, laid, RUN))
    end)
  end)

  after_each(function()
    for _, name in pairs{ "inserter-capacity-bonus-1", "bulk-inserter" } do
      local technology = player.force.technologies[name]
      if technology then technology.researched = false end
    end
  end)
end)
