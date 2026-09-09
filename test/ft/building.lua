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
    local full = player.character_running_speed
    world.ghost(player, BELT, 2, 0)
    world.ghost(player, BELT, 3, 0)
    after_ticks(world.DELIVERED, function()
      assert.is_not_nil(world.slowed_by(player), "no slowdown sticker was applied")
      assert.is_true(player.character_running_speed < full,
        "the character is not actually walking any slower")
    end)
  end)

  it("gives the speed back once there is nothing left to build", function()
    local full = player.character_running_speed
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.SLOWDOWN_TICKS + A_BUILD, function()
      assert.are.equal(0, world.ghosts(player), "something is still waiting to be built")
      assert.is_nil(world.slowed_by(player), "the slowdown outlived the building")
      assert.are.equal(full, player.character_running_speed,
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
    -- a single swing's worth of time should be one belt, not the whole row: the arm has to
    -- go out and come back before the next one starts
    after_ticks(world.CYCLE, function()
      assert.are.equal(1, world.count(player, BELT),
        "the whole row went up at once, so the arm is not being waited for")
    end)
    after_ticks(world.CYCLE * 2 + 10, function()
      assert.is_true(world.count(player, BELT) >= 2,
        "it never got to the second one")
      assert.is_true(world.count(player, BELT) < 4,
        "the row went up faster than one swing each")
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
      assert.is_nil(world.slowed_by(player),
        "the character was slowed for a build that never happened")
    end)
  end)
end)

--- The build loop used to revive nearby_ghosts[1] rather than the ghost it had matched an
--- item for. With one kind of ghost about that is invisible. With two it took the item for
--- the one it could build and put up the one it could not, so you ended up a belt lighter
--- and looking at a chest.
describe("with more than one kind of ghost in reach", function()
  before_each(function()
    world.equipped(player)
  end)

  it("builds the one it has the item for", function()
    -- a chest ghost and a belt ghost, and only belts in the pocket
    world.ghost(player, "wooden-chest", -2, 0)
    world.ghost(player, BELT, 2, 0)
    player.insert{ name = BELT, count = 5 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "the belt it could build is missing")
      assert.are.equal(0, world.count(player, "wooden-chest"),
        "it built a chest the character was not carrying")
    end)
  end)

  it("leaves the one it cannot pay for standing", function()
    world.ghost(player, "wooden-chest", -2, 0)
    world.ghost(player, BELT, 2, 0)
    player.insert{ name = BELT, count = 5 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.ghosts(player), "the chest ghost should still be waiting")
      assert.are.equal(4, player.get_item_count(BELT), "exactly one belt should have gone")
    end)
  end)
end)

--- A half diagonal rail takes two rails and a curved one takes three. The mod used to
--- build either for anyone holding a single rail, and take only that rail off them.
describe("a ghost that takes more than one item", function()
  local RAIL_GHOST = "half-diagonal-rail"

  before_each(function()
    world.equipped(player)
  end)

  it("is left alone when the character has too few", function()
    world.ghost(player, RAIL_GHOST, 2, 0)
    player.insert{ name = "rail", count = 1 }
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, RAIL_GHOST),
        "a rail that takes two was built with one")
      assert.are.equal(1, player.get_item_count("rail"), "the rail should not have gone")
    end)
  end)

  it("is built when the character has enough", function()
    world.ghost(player, RAIL_GHOST, 2, 0)
    player.insert{ name = "rail", count = 10 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, RAIL_GHOST), "the rail was never built")
    end)
  end)

  it("costs as many items as it takes", function()
    world.ghost(player, RAIL_GHOST, 2, 0)
    player.insert{ name = "rail", count = 10 }
    after_ticks(A_BUILD, function()
      assert.are.equal(8, player.get_item_count("rail"),
        "a half diagonal rail takes two rails, so eight of ten should be left")
    end)
  end)
end)
