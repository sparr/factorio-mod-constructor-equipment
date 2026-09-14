--- The toolbar button that switches a player's arms off.
---
--- What it is for is the times the equipment is in the way: ghosts laid down to think about
--- rather than to build, or items wanted for something else. Taking the equipment out of
--- the armour does the same thing and costs a trip through the inventory each way.
local world = require("test.ft.world")

local BELT = "transport-belt"
local A_BUILD = world.BUILD_INTERVAL * 2
local TOGGLE = "constructor-equipment-toggle"

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
      after_ticks(2, function()
        assert.are.equal(0, #world.arms(player), "the arm is still on the character's back")
      end)
    end)
  end)

  it("gives back what a claw was carrying when it is pressed mid reach", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      assert.are.equal(4, player.get_item_count(BELT),
        "the arm should have taken a belt out of the pockets to carry")
      press(player)
      after_ticks(2, function()
        assert.are.equal(5, player.get_item_count(BELT),
          "the belt the claw was carrying was not handed back")
      end)
    end)
  end)

  it("hands the speed back at once rather than waiting for the sticker to run out", function()
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
