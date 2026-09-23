--- What the equipment does about an upgrade planner.
---
--- An upgrade order is not a ghost, which is the whole reason the arms used to ignore one.
--- The belt stays exactly where it was and the planner hangs an order on it, so a search
--- for ghosts comes back empty however much work is standing in front of the character.
--- None of the tests next door would have caught that.
local world = require("test.ft.world")

--- Comfortably more than one swing, so a test is not at the mercy of which tick of the
--- check cycle it started on. Built on the swing rather than on world.BUILD_INTERVAL, which
--- is a leftover from when the mod capped its own build rate and has nothing to do with how
--- long a reach takes: two of those intervals is sixty ticks, and a first tier arm reaching
--- the edge of its two tiles wants up to sixty three.
local A_BUILD = world.DELIVERED

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

  -- A pair is one thing in two hulls. The base game upgrades an end at a time and turns the
  -- tunnel out doing it: measured on 2.1.17, a robot put the eight items that were in there
  -- on the floor and its network collected them afterwards. Nothing lost, but the line is
  -- short of what was travelling in it, and somebody has to tidy up.
  describe("an underground pair", function()
    local UNDER = "underground-belt"
    local FASTER_UNDER = "fast-underground-belt"

    -- One of these turns capacity research on to give the claw a hand that holds two. It
    -- goes off again afterwards: a force is shared by every test that runs after this one,
    -- and a bigger hand quietly changes what they are measuring.
    after_each(function()
      for _, name in pairs{ "inserter-capacity-bonus-1", "bulk-inserter" } do
        local technology = player.force.technologies[name]
        if technology then technology.researched = false end
      end
    end)

    ---A pair with both ends marked, the near one within reach and the far one not.
    local function pair(cargo)
      local surface, force = player.surface, player.force
      local near = surface.create_entity{ name = UNDER, direction = defines.direction.east,
        position = { world.ORIGIN.x + 2, world.ORIGIN.y }, type = "input", force = force }
      local far = surface.create_entity{ name = UNDER, direction = defines.direction.east,
        position = { world.ORIGIN.x + 6, world.ORIGIN.y }, type = "output", force = force }
      assert(near and far, "could not lay the pair down")
      assert.are.equal(far.unit_number, near.underground_belt_neighbour.unit_number,
        "the two ends did not pair up")
      for line = 3, 4 do
        for spot = 0.2, 1.4, 0.6 do
          near.get_transport_line(line).insert_at(spot, { name = cargo })
        end
      end
      near.order_upgrade{ force = force, target = prototypes.entity[FASTER_UNDER] }
      far.order_upgrade{ force = force, target = prototypes.entity[FASTER_UNDER] }
      return near, far
    end

    ---Where the two old ends are while the claw is on its way home: in its hand, or set
    ---aside against the job, or neither.
    local function in_flight()
      local claw, owed = 0, 0
      for _, record in pairs(storage.constructor_arms[player.index] or {}) do
        local arm = record.entity
        if arm and arm.valid and arm.held_stack.valid_for_read
            and arm.held_stack.name == UNDER then
          claw = claw + arm.held_stack.count
        end
        local job = record.job
        if job and job.owed and job.owed.name == UNDER then owed = owed + job.owed.count end
      end
      return claw, owed
    end

    -- The claw first, always. Travelling with the job is what a hand too small to hold the
    -- pair falls back on, not the way a pair is carried.
    it("carries both ends in the claw when the hand can hold them", function()
      for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1" } do
        player.force.technologies[name].researched = true
      end
      player.get_inventory(defines.inventory.character_armor).clear()
      world.equip(player, { "constructor-equipment-4", "battery-mk2-equipment" }, true)
      pair("iron-plate")
      player.insert{ name = FASTER_UNDER, count = 5 }
      -- Watched rather than sampled. The claw holds both ends for about ten ticks on its
      -- way home, and exactly when that falls moves with the check tick, so a single look
      -- is a coin toss dressed up as a measurement.
      local most, owed_ever = 0, 0
      script.on_nth_tick(1, function()
        local claw, owed = in_flight()
        most = math.max(most, claw)
        owed_ever = math.max(owed_ever, owed)
      end)
      after_ticks(world.CYCLE * 2, function()
        script.on_nth_tick(1, nil)
        assert.are.equal(2, most,
          ("the claw carried at most %d of the pair, and %d travelled with the job"):format(
            most, owed_ever))
        assert.are.equal(0, owed_ever, "the job carried what the hand had room for")
      end)
    end)

    -- A claw that holds one thing can carry one of the two ends home, and the other used to
    -- go on the floor marked, so the arm came back out for something it had been standing
    -- over. A pair is one of the two things the box is for: it rides home in that, and is
    -- handed over when the claw gets there.
    it("brings both ends home in one trip on a hand that holds one", function()
      -- No capacity research: the claw holds a single thing, which is the case this is about.
      for _, name in pairs{ "inserter-capacity-bonus-1", "bulk-inserter" } do
        local technology = player.force.technologies[name]
        if technology then technology.researched = false end
      end
      pair("iron-plate")
      player.insert{ name = FASTER_UNDER, count = 5 }
      -- Long enough for the claw to get home, which is where what the job owes is settled.
      after_ticks(A_BUILD * 2, function()
        assert.are.equal(2, player.get_item_count(UNDER),
          "both old ends should be in the pockets after the one trip")
        local loose = 0
        for _, item in pairs(player.surface.find_entities_filtered{
            position = world.ORIGIN, radius = 20, type = "item-entity" }) do
          if item.stack.valid_for_read and item.stack.name == UNDER then
            loose = loose + item.stack.count
          end
        end
        assert.are.equal(0, loose, "an end was shed on the floor for a second journey")
      end)
    end)

    it("goes up as one job, both ends, from the end within reach", function()
      pair("iron-plate")
      player.insert{ name = FASTER_UNDER, count = 5 }
      after_ticks(A_BUILD, function()
        assert.are.equal(2, world.count(player, FASTER_UNDER),
          "the far end was left joined to a faster near one")
        assert.are.equal(0, world.count(player, UNDER), "an old end is still standing")
      end)
    end)

    it("costs two, one for each end", function()
      pair("iron-plate")
      player.insert{ name = FASTER_UNDER, count = 5 }
      after_ticks(A_BUILD, function()
        assert.are.equal(3, player.get_item_count(FASTER_UNDER),
          "a pair should cost two of the five")
      end)
    end)

    it("is left alone when only one is carried", function()
      pair("iron-plate")
      player.insert{ name = FASTER_UNDER, count = 1 }
      after_ticks(A_BUILD, function()
        assert.are.equal(2, world.count(player, UNDER), "half a pair was paid for")
        assert.are.equal(1, player.get_item_count(FASTER_UNDER), "something was spent")
      end)
    end)

    -- what the base game throws away
    -- Both ends are the same item and come off together, so a hand with room takes both.
    -- Shedding the second put an underground belt on the lane of the belt that had just
    -- replaced it, riding away down the line.
    it("brings both old ends home rather than shedding one", function()
      pair("iron-plate")
      for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1" } do
        local technology = player.force.technologies[name]
        if technology then technology.researched = true end
      end
      -- the armour the fixture put on in before_each has to come off, or the new one goes
      -- into the pockets and the arm on the character's back is still the first tier's
      player.get_inventory(defines.inventory.character_armor).clear()
      world.equip(player, { "constructor-equipment-4", "battery-mk2-equipment" }, true)
      player.insert{ name = FASTER_UNDER, count = 5 }
      after_ticks(world.CYCLE * 2, function()
        assert.are.equal(2, world.count(player, FASTER_UNDER), "the pair was not upgraded")
        assert.are.equal(2, player.get_item_count(UNDER),
          "both old ends should have come home")
        local loose = 0
        for _, item in pairs(player.surface.find_entities_filtered{
            position = world.ORIGIN, radius = 20, type = "item-entity" }) do
          if item.stack.valid_for_read and item.stack.name == UNDER then
            loose = loose + item.stack.count
          end
        end
        assert.are.equal(0, loose, "an old end was left lying about")
      end)
    end)

    it("keeps what was in the tunnel", function()
      local near = pair("iron-plate")
      local before = near.get_item_count()
      assert.is_true(before > 0, "the tunnel was empty to begin with")
      player.insert{ name = FASTER_UNDER, count = 5 }
      after_ticks(A_BUILD, function()
        local ends = player.surface.find_entities_filtered{ name = FASTER_UNDER }
        assert.are.equal(2, #ends, "the pair was not upgraded")
        local held = 0
        for _, one in pairs(ends) do held = held + one.get_item_count() end
        assert.are.equal(before, held, "the tunnel's cargo was lost in the swap")
      end)
    end)

    -- The cargo counted everywhere rather than only in the tunnel. Both can be right at
    -- once: for a while the swap laid every item back on the line and put a copy of it on
    -- the floor as well, because force_insert_at answers nil whether it worked or not and
    -- the answer was read as a refusal. The tunnel kept its load and the ground grew one
    -- iron plate per tunnel line beside it, which the test above cannot see.
    it("leaves no more iron plates than it found", function()
      local near = pair("iron-plate")
      local before = near.get_item_count()
      assert.is_true(before > 0, "the tunnel was empty to begin with")
      local pocketed = player.get_item_count("iron-plate")
      player.insert{ name = FASTER_UNDER, count = 5 }
      after_ticks(A_BUILD, function()
        local ends = player.surface.find_entities_filtered{ name = FASTER_UNDER }
        assert.are.equal(2, #ends, "the pair was not upgraded")
        local held = 0
        for _, one in pairs(ends) do held = held + one.get_item_count() end
        local loose = 0
        for _, item in pairs(player.surface.find_entities_filtered{
            position = world.ORIGIN, radius = 20, type = "item-entity" }) do
          if item.stack.valid_for_read and item.stack.name == "iron-plate" then
            loose = loose + item.stack.count
          end
        end
        assert.are.equal(0, loose,
          ("the swap left %d iron plates on the ground"):format(loose))
        assert.are.equal(before + pocketed,
          held + loose + player.get_item_count("iron-plate"),
          "the swap did not end with as many iron plates as it began with")
      end)
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
    -- On the way home rather than after it. Spending a belt on the swap empties the stack
    -- it came from, which frees the slot the old one then goes into, so the pockets are only
    -- full while the claw is carrying -- which is the whole of what this is about.
    after_ticks(world.DELIVERED, function()
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

    -- The claw goes back for the shed, because the shed is marked and marked things are
    -- work like any other. What it must not go on to is the chest it has just put down: that
    -- is the player's, nobody marked it, and emptying it would undo the swap a plate at a
    -- time.
    it("does not go on to empty the chest it just built", function()
      full_chest_marked_down()
      after_ticks(world.CYCLE * 12, function()
        local standing = player.surface.find_entities_filtered{ name = "iron-chest",
          position = { world.ORIGIN.x + 2, world.ORIGIN.y }, radius = 0.6 }[1]
        assert.is_not_nil(standing, "the chest the swap put down is gone")
        local inside = standing.get_inventory(defines.inventory.chest)
        assert.are.equal(3200, inside.get_item_count("iron-plate"),
          ("the new chest is down to %d of the 3200 it took")
            :format(inside.get_item_count("iron-plate")))
        assert.is_false(standing.to_be_deconstructed(),
          "something marked the chest the swap put down")
      end)
    end)

    it("leaves it on the ground rather than in the character's pockets", function()
      full_chest_marked_down()
      -- The tick they are shed, rather than a tick the swap ought to have happened by. The
      -- shed is marked, so it is work like any other and the claw comes straight back for
      -- it: what this has is a window between the swap and the first plate going home, and
      -- where in the run that window falls moves with how fast an arm swings.
      world.once(function() return on_the_floor() > 0 end, function()
        local total = on_the_floor()
        assert.are.equal(1600, total,
          "the plates the iron chest could not hold are not on the ground")
        assert.are.equal(0, player.get_item_count("iron-plate"),
          "the plates went into the character's pockets, which no robot would do")
      end, "nothing was ever shed onto the ground", world.CYCLE * 2)
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

    -- A claw fetches something off the floor by pointing an inserter at it, and an
    -- inserter aimed at a tile a chest stands on takes from the chest. The shed lands on
    -- the tile the replacement was just put down on, so without moving it the arm spent
    -- its time emptying the chest it had built, which is what the walk round saw.
    it("does not leave the shed underneath the chest that replaced it", function()
      full_chest_marked_down()
      after_ticks(A_BUILD, function()
        local chest = player.surface.find_entities_filtered{
          position = { world.ORIGIN.x + 2, world.ORIGIN.y }, name = "iron-chest" }[1]
        assert.is_truthy(chest, "the chest was never swapped, so there is nothing to check")
        local under = 0
        for _, item in pairs(player.surface.find_entities_filtered{
            area = chest.bounding_box, type = "item-entity" }) do
          if item.stack.valid_for_read then under = under + item.stack.count end
        end
        assert.are.equal(0, under, "part of the shed is out of reach on the chest's tile")
      end)
    end)

    it("leaves what the replacement is holding alone", function()
      full_chest_marked_down()
      after_ticks(A_BUILD * 6, function()
        local chest = player.surface.find_entities_filtered{
          position = { world.ORIGIN.x + 2, world.ORIGIN.y }, name = "iron-chest" }[1]
        assert.is_truthy(chest, "the chest was never swapped, so there is nothing to check")
        assert.are.equal(3200, chest.get_item_count("iron-plate"),
          "the arm has been emptying the chest it just built")
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

  -- The quality a piece of work asks for is the quality it has to be paid in. Putting a
  -- legendary belt down for a normal one would be minting the difference, and the hole was
  -- open on both paths before this.
  --
  -- Through ghosts rather than upgrade orders, because an order cannot be given a quality
  -- from script: order_upgrade takes a quality and hands back normal regardless. The gate
  -- and the paying are the same code either way.
  describe("work that asks for a better quality", function()
    local BETTER = "uncommon"

    local function quality_ghost()
      return player.surface.create_entity{
        name = "entity-ghost",
        inner_name = BELT,
        quality = BETTER,
        position = { world.ORIGIN.x + 2, world.ORIGIN.y },
        force = player.force,
      }
    end

    before_each(function()
      player.get_inventory(defines.inventory.character_main).clear()
    end)

    it("is left alone when only the plain item is carried", function()
      player.insert{ name = BELT, count = 5 }
      local ghost = quality_ghost()
      assert.are.equal(BETTER, ghost.quality.name, "the ghost did not keep its quality")
      after_ticks(A_BUILD, function()
        assert.are.equal(1, world.ghosts(player),
          "a plain belt paid for a better one")
        assert.are.equal(5, player.get_item_count(BELT), "something was spent anyway")
      end)
    end)

    it("is built with the better item, and spends that one", function()
      local pockets = player.get_inventory(defines.inventory.character_main)
      player.insert{ name = BELT, count = 5 }
      player.insert{ name = BELT, quality = BETTER, count = 2 }
      quality_ghost()
      after_ticks(A_BUILD, function()
        assert.are.equal(0, world.ghosts(player), "the ghost was never built")
        local made = player.surface.find_entities_filtered{ name = BELT }[1]
        assert.is_not_nil(made, "nothing was built")
        assert.are.equal(BETTER, made.quality.name,
          "what went up is not the quality that was asked for")
        assert.are.equal(5, pockets.get_item_count{ name = BELT, quality = "normal" },
          "a plain belt was spent on a better one")
        assert.are.equal(1, pockets.get_item_count{ name = BELT, quality = BETTER },
          "the better belt was not the one spent")
      end)
    end)
  end)

  -- Nothing about a swap wants the player's own pockets any more -- a porter of the mod's
  -- own catches what comes off -- so a driver with no character upgrades like anybody else.
  -- They are not exotic: the map editor and the opening cutscene both make one.
  it("upgrades for a driver with no character", function()
    local tank = player.surface.create_entity{
      name = "tank", position = world.ORIGIN, force = player.force,
      direction = defines.direction.east }
    assert(tank, "could not put the tank down")
    tank.insert{ name = "coal", count = 10 }
    world.fitted(tank)
    tank.insert{ name = FASTER, count = 5 }

    -- The character goes before anybody takes the wheel. Destroying it while seated puts
    -- the player out of the vehicle, and a player out of a vehicle with no character is
    -- wearing nothing at all.
    player.character.destroy()
    assert.is_nil(player.character, "the character did not actually go away")
    tank.set_driver(player)
    assert.is_true(player.driving, "a player with no character could not take the wheel")

    -- Beside the hull, not in front of it: a vehicle's arms are mounted along its sides and
    -- reach from where they are bolted.
    local box = tank.prototype.selection_box
    local away = (box.right_bottom.x - box.left_top.x) / 2 + 1.5
    local turns = tank.orientation * 2 * math.pi
    world.to_upgrade(player, BELT, FASTER,
      math.cos(turns) * away, math.sin(turns) * away)

    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, FASTER), "the belt was never upgraded")
      assert.are.equal(0, world.count(player, BELT), "the old belt is still standing there")
      assert.are.equal(4, tank.get_item_count(FASTER),
        "the vehicle's own hold should have paid for it")
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
