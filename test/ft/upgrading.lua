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
  -- world.player puts a character back first: a test here takes one away, and everything
  -- after it wants one.
  player = world.player()
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

  -- what a construction robot does with the thing it took off. A whole swing and a whole
  -- swing back: the claw carries it now, so it arrives when the arm does rather than the
  -- moment the swap is made.
  it("hands the old belt back", function()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(world.DELIVERED + world.CYCLE, function()
      assert.are.equal(1, player.get_item_count(BELT),
        "the belt that came off went nowhere")
    end)
  end)

  it("carries the old belt home in the claw rather than teleporting it", function()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.count(player, FASTER), "the swap has not happened yet")
      assert.are.equal(0, player.get_item_count(BELT),
        "the old belt went straight to the pockets instead of into the claw")
      assert.are.equal(BELT, world.held(player), "the claw is not carrying the old belt")
      after_ticks(world.CYCLE, function()
        assert.are.equal(1, player.get_item_count(BELT),
          "the claw never handed the old belt over")
      end)
    end)
  end)

  it("carries one thing out when the trip is a swap", function()
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    world.to_upgrade(player, BELT, FASTER, -2, 0)
    after_ticks(12, function()
      assert.are.equal(4, player.get_item_count(FASTER),
        "the claw took more than one fast belt out for a swap")
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

  -- With the pockets full the engine puts what came off wherever it can reach -- the floor,
  -- or the lane of the belt that replaced it. The claw takes it instead and holds it until
  -- there is room, so it arrives where the player expects rather than underfoot.
  it("keeps the old belt in the claw when the pockets are full", function()
    world.fill_pockets(player)
    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(world.CYCLE, function()
      assert.are.equal(1, world.count(player, FASTER), "the swap never happened")
      assert.are.equal(BELT, world.held(player),
        "the belt that came off was lost rather than held")
    end)
  end)

  -- A robot marks everything it sheds so the network tidies up after it. Measured on
  -- 2.1.17: a robot downgrading a full steel chest marked all 1501 items it dropped, and
  -- the same swap made from script marked none of them.
  --
  -- A robot never reaches into anybody's pockets, so neither does this: what the
  -- replacement cannot hold is left on the ground whether the character has room for it or
  -- not. The engine will not hand it over at all without a player named, so the pockets are
  -- a moment's stop on the way and these tests are about it not being longer than that.
  describe("a swap that sheds what the replacement cannot hold", function()
    local DROPPED = 7

    local function full_chest_marked_down()
      local chest = player.surface.create_entity{
        name = "steel-chest",
        position = { world.ORIGIN.x + 2, world.ORIGIN.y },
        force = player.force,
      }
      for _ = 1, 48 do chest.insert{ name = "iron-plate", count = 100 } end
      chest.order_upgrade{ force = player.force,
        target = prototypes.entity["iron-chest"] }
      player.insert{ name = "iron-chest", count = 5 }
      return chest
    end

    local function on_the_floor()
      local total, marked, stranger = 0, 0, 0
      for _, item in pairs(player.surface.find_entities_filtered{
          position = world.ORIGIN, radius = 20, type = "item-entity" }) do
        if item.stack.valid_for_read then
          if item.stack.name == "copper-plate" then
            stranger = stranger + item.stack.count
            if item.to_be_deconstructed() then
              stranger = stranger - item.stack.count
            end
          else
            total = total + item.stack.count
            if item.to_be_deconstructed() then marked = marked + item.stack.count end
          end
        end
      end
      return total, marked, stranger
    end

    it("leaves it on the ground rather than in the character's pockets", function()
      full_chest_marked_down()
      after_ticks(A_BUILD, function()
        local total = on_the_floor()
        assert.are.equal(1600, total,
          "the plates the iron chest could not hold are not on the ground")
        assert.are.equal(0, player.get_item_count("iron-plate"),
          "the plates went into the character's pockets, which no robot would do")
      end)
    end)

    it("does it with the pockets full as well", function()
      full_chest_marked_down()
      world.fill_pockets(player)
      after_ticks(A_BUILD, function()
        local total = on_the_floor()
        assert.are.equal(1600, total, "the plates were lost rather than shed")
      end)
    end)

    -- The engine gives the chest that came off one of three fates depending on what room
    -- there is, and two of them are recoverable. Whichever it picked, there was one chest
    -- and there is one chest.
    --
    -- A wooden chest rather than an iron one: it holds a third of what the steel one did,
    -- so the shed is twice the size and reaches half again as far, which is what put the
    -- chest outside the search that looks for it and had a second one made in the claw.
    it("ends with exactly one of the chest that came off, however far it was thrown",
      function()
      local chest = player.surface.create_entity{
        name = "steel-chest",
        position = { world.ORIGIN.x + 2, world.ORIGIN.y },
        force = player.force,
      }
      for _ = 1, 48 do chest.insert{ name = "iron-plate", count = 100 } end
      chest.order_upgrade{ force = player.force,
        target = prototypes.entity["wooden-chest"] }
      player.insert{ name = "wooden-chest", count = 5 }
      world.fill_pockets(player)
      after_ticks(A_BUILD, function()
        local loose = 0
        for _, item in pairs(player.surface.find_entities_filtered{
            position = world.ORIGIN, radius = 40, type = "item-entity" }) do
          if item.stack.valid_for_read and item.stack.name == "steel-chest" then
            loose = loose + item.stack.count
          end
        end
        local held = world.held(player) == "steel-chest" and 1 or 0
        assert.are.equal(1, loose + held + player.get_item_count("steel-chest"),
          "the chest that came off was duplicated or lost")
        assert.are.equal(1, held, "the claw is not the one carrying it")
      end)
    end)

    it("marks the spill for deconstruction", function()
      full_chest_marked_down()
      after_ticks(A_BUILD, function()
        local total, marked = on_the_floor()
        assert.is_true(total > 0, "nothing was shed, so there is nothing to check")
        assert.are.equal(total, marked, "some of the spill was left lying there unmarked")
      end)
    end)

    it("leaves the player's own dropped items unmarked", function()
      player.surface.spill_item_stack{
        position = { world.ORIGIN.x + 1, world.ORIGIN.y + 1 },
        stack = { name = "copper-plate", count = DROPPED },
        enable_looted = false,
        force = player.force,
      }
      for _, item in pairs(player.surface.find_entities_filtered{
          position = world.ORIGIN, radius = 20, type = "item-entity" }) do
        if item.to_be_deconstructed() then item.cancel_deconstruction(player.force) end
      end
      full_chest_marked_down()
      after_ticks(A_BUILD, function()
        local _, _, stranger = on_the_floor()
        assert.are.equal(DROPPED, stranger,
          "the player's own copper plates were marked along with the spill")
      end)
    end)
  end)

  -- The pockets are made big enough to catch the whole swap and then put back, so what the
  -- engine handed over must leave no trace in them.
  --
  -- Slot by slot is not worth asserting, and not something any mod can promise: the game
  -- rearranges the character's pockets by itself between one tick and the next, with nobody
  -- touching them. Measured on 2.1.17 -- a stack set in slot 3 was in slot 1 a tick later.
  -- What has to hold is the contents: the same items, the same counts, nothing made and
  -- nothing lost.
  it("leaves the pockets holding exactly what they held", function()
    local pockets = player.get_inventory(defines.inventory.character_main)
    pockets.clear()
    pockets.insert{ name = BELT, count = 40 }      -- a part stack of what comes back
    pockets.insert{ name = "stone", count = 13 }   -- and one with nothing to do with it
    pockets.insert{ name = FASTER, count = 5 }     -- and the one that pays

    world.to_upgrade(player, BELT, FASTER, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.count(player, FASTER), "the swap has not happened yet")
      assert.are.equal(BELT, world.held(player), "the claw is not carrying the old belt")
      assert.are.equal(40, pockets.get_item_count(BELT),
        "the belt that came off was left in the pockets rather than taken to the claw")
      assert.are.equal(13, pockets.get_item_count("stone"),
        "a stack with nothing to do with the swap was disturbed")
      assert.are.equal(4, pockets.get_item_count(FASTER),
        "more than the one fast belt that paid for it was spent")
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
