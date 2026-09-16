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
