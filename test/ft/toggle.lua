--- The toolbar button that switches a player's arms off.
---
--- What it is for is the times the equipment is in the way: ghosts laid down to think about
--- rather than to build, or items wanted for something else. Taking the equipment out of
--- the armour does the same thing and costs a trip through the inventory each way.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")
--- Skipped wholesale while the walking penalty is switched off, rather than deleted: the
--- switch is meant to be flipped back. See tiers.SLOWS.
local slowed_describe = tiers.SLOWS and describe or describe.skip
local slowed_it = tiers.SLOWS and it or it.skip

local BELT = "transport-belt"
local A_BUILD = world.BUILD_INTERVAL * 2
local TOGGLE = "constructor-equipment-toggle"

--- Long enough for a claw switched off part way through a reach to swing home. It is not
--- taken away where it stands: the hand retracts along the line it was working on, hands
--- over whatever it is holding and only then folds up, so everything a press does to the
--- pockets happens when the claw arrives rather than on the tick of the press.
local A_FOLD = 120

local player

--- Pressing the button, which has to be done by calling what the toolbar calls: the engine
--- will not let a script raise on_lua_shortcut, so there is no pretending to be the
--- toolbar. press() is control.lua's, and global for exactly this.

before_each(function()
  player = world.player()
  world.clear(player)
  storage.constructor_off = {}
  world.equipped(player)
  player.insert{ name = BELT, count = 5 }
end)

after_each(function()
  storage.constructor_off = {}
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("the constructor equipment toggle", function()
  it("starts switched on", function()
    assert.is_true(player.is_shortcut_toggled(TOGGLE),
      "the button starts out looking as though the equipment were off")
  end)

  it("stops the equipment building once it is pressed", function()
    press(player)
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built with the equipment switched off")
      assert.are.equal(1, world.ghosts(player), "the ghost was taken")
    end)
  end)

  it("shows itself pressed in", function()
    press(player)
    assert.is_false(player.is_shortcut_toggled(TOGGLE),
      "the button does not show that the equipment is off")
    press(player)
    assert.is_true(player.is_shortcut_toggled(TOGGLE),
      "the button does not show that the equipment is back on")
  end)

  it("takes the arms away rather than leaving them out", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      assert.are.equal(1, #world.arms(player), "there was no arm out to take away")
      press(player)
      after_ticks(A_FOLD, function()
        assert.are.equal(0, #world.arms(player), "the arm is still on the character's back")
      end)
    end)
  end)

  -- The other half of the same thing: it is gone by the end, it is not gone at once, and
  -- what it does in between is come back.
  it("brings a claw home rather than taking it away where it stands", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      press(player)
      after_ticks(1, function()
        local arm = world.arms(player)[1]
        assert.is_truthy(arm, "the arm vanished mid reach instead of swinging home first")
        local out = reach.distance(player.position, arm.held_stack_position)
        -- A short look. A first tier hand a dozen ticks into a two tile reach is most of
        -- the way home again within thirty, and an arm that has arrived has been put away.
        after_ticks(6, function()
          local still = world.arms(player)[1]
          assert.is_truthy(still, "the arm was taken away before it could get home")
          assert.is_true(reach.distance(player.position, still.held_stack_position) < out,
            "the claw is no nearer home than it was when the button was pressed")
        end)
      end)
    end)
  end)

  -- Coming home is not the same as getting there. An ordinary reach is called home as soon
  -- as the hand is within HOME of the rest point, which is early on purpose so the next
  -- reach can start sooner. Nothing follows a fold, and being early there is visible:
  -- measured, the button took the arm away with the claw still 0.63 of a tile out and the
  -- belt still in it, so the item winked out in mid air and the claw jumped the rest of the
  -- way to where it is drawn being stowed.
  it("brings the claw all the way in before it folds away", function()
    world.ghost(player, BELT, 2, 0)
    local last_out, last_held
    after_ticks(20, function()
      press(player)
      for n = 21, 200 do
        after_ticks(n, function()
          local arm = world.arms(player)[1]
          if arm and arm.valid then
            last_out = reach.distance(arm.position, arm.held_stack_position)
            last_held = arm.held_stack.valid_for_read
          end
        end)
      end
    end)
    after_ticks(210, function()
      assert.is_nil(world.arms(player)[1], "the arm never folded away")
      assert.is_not_nil(last_out, "the arm was never seen after the button was pressed")
      -- A hand will not retract inside a minimum extension of its own, and where that
      -- leaves it is the tier's business rather than the mod's: measured at 0.19 on a first
      -- tier arm folding from a two tile reach. What is asked is that it got there.
      assert.is_true(last_out < 0.3,
        ("the claw was %.2f tiles out when the arm was taken away"):format(last_out))
      assert.is_false(last_held,
        "the claw was still holding the belt on the last tick it was seen")
    end)
  end)

  -- Pressing it off lifts the arm out of its owner's list and leaves it folding on its own,
  -- so pressing it on again straight away built a second one beside it -- and took a second
  -- belt out of the pockets for it -- while the first was still swinging in. There is one
  -- piece of equipment, so there should never be two arms.
  it("does not deploy a second arm while the first is still coming home", function()
    world.ghost(player, BELT, 2, 0)
    local most, took = 0, nil
    after_ticks(14, function()
      took = player.get_item_count(BELT)
      press(player)
      after_ticks(6, function()
        press(player)
        for n = 1, 60 do
          after_ticks(n, function()
            most = math.max(most, #world.arms(player))
          end)
        end
      end)
    end)
    after_ticks(A_FOLD, function()
      assert.are.equal(1, most,
        ("%d arms were out at once for one piece of equipment"):format(most))
      assert.is_true(player.get_item_count(BELT) >= took,
        "a second belt was taken out of the pockets for a second arm")
    end)
  end)

  --- The same again with the claw a good deal further out, which is where it went wrong.
  --- A folding arm was not fed, so it retracted on whatever was left in its buffer and
  --- stopped dead when that ran out -- measured, a fourth tier claw carrying a belt halted
  --- 0.98 tiles from its own base with twenty megajoules in the battery beside it. The
  --- pockets did get their belt back, but only when the swing limit gave up on the arm five
  --- seconds later, which is a long time to stand there holding somebody's belt.
  ---
  --- So this presses late enough for the hand to be three tiles out, and asks for the belt
  --- inside a fold rather than inside a swing limit.
  it("gives it back promptly from a claw that is a long way out", function()
    world.equip(player, { "constructor-equipment-4", "battery-equipment" }, true,
      "power-armor")
    world.ghost(player, BELT, 4, 0)
    after_ticks(25, function()
      assert.are.equal(4, player.get_item_count(BELT),
        "the arm should be carrying a belt by now")
      local arm = world.arm(player)
      assert.is_not_nil(arm, "there should be an arm out")
      assert.is_true(reach.distance(arm.position, arm.held_stack_position) > 2,
        "the claw should be well out by now")
      press(player)
      after_ticks(A_FOLD, function()
        assert.are.equal(5, player.get_item_count(BELT),
          "the belt was not handed back inside a fold")
        assert.is_nil(world.arm(player), "the arm was still hanging about")
      end)
    end)
  end)

  it("gives back what a claw was carrying when it is pressed mid reach", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      assert.are.equal(4, player.get_item_count(BELT),
        "the arm should have taken a belt out of the pockets to carry")
      press(player)
      after_ticks(A_FOLD, function()
        assert.are.equal(5, player.get_item_count(BELT),
          "the belt the claw was carrying was not handed back")
      end)
    end)
  end)

  -- The pockets an arm was paid out of can be full by the time it comes home, and a
  -- vehicle's hold can be the wrong shape entirely. Inserting and clearing regardless quietly
  -- destroyed whatever would not fit, which the button made easy to do by accident.
  it("puts on the floor what full pockets will not take back", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      assert.are.equal(4, player.get_item_count(BELT),
        "the arm should have taken a belt out of the pockets to carry")
      -- Filled now rather than at the start, so that the arm had a belt to pick up and the
      -- pockets have no room for it by the time it is handed back. The belts left behind go
      -- first: a part full stack of the very thing being handed back has room in it, and an
      -- inventory with no empty slot is not a full one while that stack is there.
      player.get_main_inventory().remove{ name = BELT, count = 100 }
      world.fill_pockets(player)
      local before = player.get_item_count(BELT)
      press(player)
      after_ticks(A_FOLD, function()
        local loose = 0
        for _, item in pairs(player.surface.find_entities_filtered{
            position = player.position, radius = 10, type = "item-entity" }) do
          if item.stack.valid_for_read and item.stack.name == BELT then
            loose = loose + item.stack.count
          end
        end
        assert.are.equal(before + 1, player.get_item_count(BELT) + loose,
          "the belt the claw was carrying was destroyed rather than handed back or dropped")
      end)
    end)
  end)

  slowed_it("hands the speed back at once rather than waiting for the sticker to run out", function()
    world.several(player, BELT, 4)
    after_ticks(world.DELIVERED, function()
      assert.is_not_nil(world.slowed_by(player), "the character was never slowed")
      press(player)
      after_ticks(2, function()
        assert.is_nil(world.slowed_by(player),
          "the character is still slowed by arms that are switched off")
      end)
    end)
  end)

  it("builds again once it is pressed a second time", function()
    press(player)
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built while switched off")
      press(player)
      after_ticks(A_BUILD, function()
        assert.are.equal(1, world.count(player, BELT), "it did not start again when switched on")
      end)
    end)
  end)

  it("switches off a vehicle's arms as readily as an armour's", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    -- the vehicle's own hold, which is what its arms spend
    tank.insert{ name = BELT, count = 5 }
    press(player)
    -- out to the tank's right, which is where its lone arm is mounted and the only place it
    -- could build: world.vehicle puts the tank down facing east, so its right is southward
    world.ghost(player, BELT, 0, 2.4)
    -- an arm on a hull reaches from the hull's edge, so it wants longer than one on a back
    after_ticks(A_BUILD * 4, function()
      assert.are.equal(0, world.count(player, BELT),
        "the vehicle built with the equipment switched off")
      assert.are.equal(0, #world.arms(player), "the vehicle has an arm out all the same")
      world.unseat(player)
    end)
  end)

  it("is remembered rather than read off the button", function()
    press(player)
    -- the button is the display; what decides is the entry the save keeps
    assert.is_true(storage.constructor_off[player.index] or false,
      "nothing was written down about the player switching off")
    press(player)
    assert.is_nil(storage.constructor_off[player.index],
      "switching back on left the player written down as off")
  end)
end)

describe("switching off while the box has something in it", function()
  local player

  before_each(function()
    player = world.player()
    world.clear(player)
    storage.constructor_off = {}
    world.equipped(player)
  end)

  after_each(function()
    player = world.player()
    world.clear(player)
    storage.constructor_off = {}
  end)

  -- The box is taken away with the arm, and what it was holding is not the box's: it was
  -- thrown away with it, because catcher_away says what was left in it and nobody was
  -- listening. A fetch is where it shows -- the claw is handed its load through the box and
  -- carries it home -- rather than a delivery, where the box holds something for about a
  -- tick before the ghost it is standing on consumes it.
  it("keeps what a fetch had been handed", function()
    local belt = player.surface.create_entity{ name = "transport-belt",
      position = { world.ORIGIN.x + 2, world.ORIGIN.y }, force = player.force }
    belt.order_deconstruction(player.force)
    player.get_inventory(defines.inventory.character_main).clear()
    after_ticks(world.DELIVERED, function()
      press(player)
      after_ticks(A_FOLD, function()
        assert.are.equal(1, player.get_item_count("transport-belt"),
          "what the claw had been given went with the box")
      end)
    end)
  end)
end)
