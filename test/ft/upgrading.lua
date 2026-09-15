--- What the equipment does about an upgrade planner.
---
--- An upgrade order is not a ghost, which is the whole reason the arms used to ignore one.
--- The belt stays exactly where it was and the planner hangs an order on it, so a search
--- for ghosts comes back empty however much work is standing in front of the character.
--- None of the tests next door would have caught that.
local world = require("test.ft.world")

--- Comfortably more than one swing, so a test is not at the mercy of which tick of the
--- cycle it started on.
local A_BUILD = world.BUILD_INTERVAL * 2

local BELT = "transport-belt"
local FASTER = "fast-transport-belt"

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
    player.insert{ name = FASTER, count = 5 }
  end)

  it("upgrades a belt that is within reach", function()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, FASTER), "the belt was never upgraded")
      assert.are.equal(0, world.count(player, BELT), "the old belt is still standing there")
    end)
  end)

  it("pays for it with the better belt out of the inventory", function()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(4, player.get_item_count(FASTER),
        "one fast belt should have gone, out of five")
    end)
  end)

  -- what a construction robot does with the thing it took off
  it("hands the old belt back", function()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, player.get_item_count(BELT),
        "the belt that came off went nowhere")
    end)
  end)

  it("keeps what was on the belt", function()
    local belt = world.to_upgrade(player, BELT, FASTER, 2, 0)
    belt.get_transport_line(1).insert_at(0.25, { name = "iron-plate" })
    belt.get_transport_line(2).insert_at(0.25, { name = "copper-plate" })
    after_ticks(A_BUILD, function()
      local upgraded = player.surface.find_entities_filtered{ name = FASTER }[1]
      assert.is_not_nil(upgraded, "the belt was never upgraded")
      assert.are.equal(2, upgraded.get_item_count(),
        "the two plates on the old belt did not survive the swap")
    end)
  end)

  it("keeps which end of a pair an underground belt is", function()
    local under = player.surface.create_entity{
      name = "underground-belt",
      position = { world.ORIGIN.x + 2, world.ORIGIN.y },
      direction = defines.direction.east,
      type = "output",
      force = player.force,
    }
    under.order_upgrade{ force = player.force,
      target = prototypes.entity["fast-underground-belt"] }
    player.insert{ name = "fast-underground-belt", count = 5 }
    after_ticks(A_BUILD, function()
      local upgraded =
        player.surface.find_entities_filtered{ name = "fast-underground-belt" }[1]
      assert.is_not_nil(upgraded, "the underground belt was never upgraded")
      assert.are.equal("output", upgraded.belt_to_ground_type,
        "the replacement came back as the wrong end of the pair")
    end)
  end)

  it("leaves one out of reach alone", function()
    world.to_upgrade(player, BELT, FASTER, world.BUILD_RANGE + 6, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, FASTER), "it reached further than its range")
      assert.are.equal(1, world.count(player, BELT), "the belt went somewhere")
    end)
  end)

  it("leaves it alone with nothing to pay for it with", function()
    player.get_inventory(defines.inventory.character_main).clear()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT),
        "it upgraded a belt the character could not pay for")
      assert.are.equal(0, world.count(player, FASTER), "a fast belt came out of nowhere")
    end)
  end)

  -- The engine destroys what comes off when there is nowhere to put it, rather than
  -- refusing, so the room has to be asked for before the swap is made.
  it("leaves it alone when there is nowhere to put the old belt", function()
    world.fill_pockets(player)
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT),
        "the belt was swapped with nowhere for the old one to go")
      assert.are.equal(5, player.get_item_count(FASTER),
        "the fast belt was spent on an upgrade that could not happen")
    end)
  end)

  it("stops when the order is called off mid reach", function()
    local belt = world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(12, function()
      assert.are.equal(4, player.get_item_count(FASTER),
        "the arm should have taken a fast belt out of the pockets to carry")
      belt.cancel_upgrade(player.force)
      after_ticks(world.CYCLE, function()
        assert.are.equal(1, world.count(player, BELT), "the belt was upgraded anyway")
        assert.are.equal(5, player.get_item_count(FASTER),
          "the fast belt the claw was carrying was not handed back")
      end)
    end)
  end)

  it("still builds ghosts", function()
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.ghosts(player), "the ghost is still standing there")
      assert.are.equal(1, world.count(player, BELT), "the ghost was never built")
    end)
  end)
end)
