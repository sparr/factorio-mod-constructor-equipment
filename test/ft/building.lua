--- What the equipment does, and what it declines to do.
local world = require("test.ft.world")

--- Comfortably more than one build interval, so a test is not at the mercy of which tick
--- of the cycle it started on.
local A_BUILD = world.BUILD_INTERVAL * 2

local BELT = "transport-belt"

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("a character wearing the equipment", function()
  before_each(function()
    world.equipped(player)
    player.insert{ name = BELT, count = 5 }
  end)

  it("builds a ghost that is within reach", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "the belt was never built")
      assert.are.equal(0, world.ghosts(player), "the ghost is still standing there")
    end)
  end)

  it("pays for it with one item out of the inventory", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(4, player.get_item_count(BELT),
        "one belt should have gone, out of five")
    end)
  end)

  it("pays for it out of the batteries", function()
    local grid = player.character.grid
    local before = grid.available_in_batteries
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.is_true(grid.available_in_batteries < before,
        "building cost nothing: batteries went from " .. before .. " to "
        .. grid.available_in_batteries)
    end)
  end)

  -- the trade the mod offers: it builds for you, and you walk slowly while it does
  it("slows the character down while it is working", function()
    world.ghost(player, BELT, 2, 0)
    world.ghost(player, BELT, 3, 0)
    after_ticks(5, function()
      assert.is_true(player.character_running_speed_modifier < 0,
        "the character was not slowed while building")
    end)
  end)

  it("gives the speed back once there is nothing left to build", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD * 3, function()
      assert.are.equal(0, world.ghosts(player), "something is still waiting to be built")
      assert.are.equal(0, player.character_running_speed_modifier,
        "the character is still slowed with nothing left to build")
    end)
  end)

  it("leaves a ghost that is out of reach alone", function()
    world.ghost(player, BELT, world.BUILD_RANGE + 6, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "a ghost well out of range was built")
      assert.are.equal(1, world.ghosts(player))
    end)
  end)

  it("builds one at a time rather than all at once", function()
    for i = 1, 4 do world.ghost(player, BELT, i - 3, 2) end
    -- one interval's worth of ticks should be one belt, not four
    after_ticks(world.BUILD_INTERVAL - 5, function()
      assert.are.equal(1, world.count(player, BELT),
        "the whole row went up in one interval, so the build rate is not being kept")
    end)
  end)
end)

describe("a character who cannot build", function()
  it("does nothing without the equipment", function()
    world.equip(player, { "battery-equipment" }, true)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built without the equipment")
      assert.are.equal(5, player.get_item_count(BELT))
    end)
  end)

  it("does nothing with flat batteries", function()
    world.equip(player, { "constructor-equipment", "battery-equipment" }, false)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built with no power")
    end)
  end)

  it("does nothing without the item to build with", function()
    world.equipped(player)
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT),
        "it built a belt the character was not carrying")
      assert.are.equal(1, world.ghosts(player))
    end)
  end)

  it("is not slowed down when it cannot build", function()
    world.equipped(player)
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, player.character_running_speed_modifier,
        "the character was slowed for a build that never happened")
    end)
  end)
end)

--- The build loop revives nearby_ghosts[1] rather than the ghost it matched an item for.
--- With one kind of ghost about that is invisible. With two, it takes the item for the
--- one it can build and puts up the one it cannot, which is how you end up holding a
--- chest and looking at a belt.
---
--- Skipped rather than failing: 2.1.1 is the tier that writes the tests and 2.1.2 is the
--- tier that fixes what they find. Turn it into `it` when it is fixed.
describe("with more than one kind of ghost in reach", function()
  test.skip("builds the one it has the item for", function()
    world.equipped(player)
    -- a chest ghost first in the list, a belt second, and only belts in the pocket
    world.ghost(player, "wooden-chest", -2, 0)
    world.ghost(player, BELT, 2, 0)
    player.insert{ name = BELT, count = 5 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "the belt it could build is missing")
      assert.are.equal(0, world.count(player, "wooden-chest"),
        "it built a chest the character was not carrying")
    end)
  end)
end)
