--- An idle arm must not help itself to whatever its owner is standing on.
---
--- An inserter takes from whatever container sits at its pickup position, and an arm's claw
--- rests two tenths of a tile from where it is bolted on, which is on its owner. That is a
--- container often enough to matter: a vehicle with a hold of its own is one, and a
--- character can walk over a chest and stand on it.
---
--- Measured before this was prevented: a character standing on an iron chest of fifty belts
--- had one out of it and into the claw, and an arm bolted to a tank took one out of the
--- tank's own hold. What that costs by itself is a chest quietly emptied by somebody walking
--- across it. What it used to cost as well was the belt: the next job's load was written
--- straight over the hand, and that is the third of the three ways an item left the world.
---
--- The prevention is a box of the mod's own stood where the claw rests, with its bar down so
--- that nothing can go into it and there is therefore never anything to take out. See
--- keeper_at() in control.lua.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local BELT = "transport-belt"
local STOCK = 50
--- Long enough for an arm to finish its one job and stand idle for several seconds, which
--- is when it used to go looking.
local IDLING = 400

describe("an idle arm standing over something", function()
  local player

  local function scrub()
    for _, entity in ipairs(player.surface.find_entities_filtered{
          position = world.ORIGIN, radius = 60 }) do
      if entity.valid and entity.type ~= "character" then entity.destroy() end
    end
  end

  before_each(function()
    player = world.player()
    world.clear(player)
    scrub()
  end)

  after_each(function()
    if player.vehicle then world.unseat(player) end
    scrub()
    world.clear(player)
  end)

  ---Whether an arm with no job is holding anything, which is the whole question.
  ---@return boolean
  local function pilfering()
    local record = (storage.constructor_arms[player.index] or {})[1]
    local arm = record and record.entity
    return arm ~= nil and arm.valid and arm.held_stack.valid_for_read
      and record.job == nil
  end

  it("leaves alone a chest its owner is standing on", function()
    local surface = player.surface
    world.equipped_with(player, 1)
    player.insert{ name = BELT, count = 5 }
    -- one ghost, so the arm is grown and has been busy; after that it has nothing to do
    world.ghost(player, BELT, 1, 0)

    -- A chest collides with a character, so it goes down on the tile the character is
    -- already standing on rather than the character being moved onto it.
    local chest = surface.create_entity{ name = "iron-chest",
      position = { world.ORIGIN.x, world.ORIGIN.y - 1 }, force = player.force }
    assert(chest, "no chest was placed")
    chest.insert{ name = BELT, count = STOCK }

    local caught, emptiest = false, STOCK
    local began = game.tick
    world.once(function()
      if pilfering() then caught = true end
      emptiest = math.min(emptiest, chest.get_item_count(BELT))
      return game.tick - began > IDLING
    end, function()
      assert.is_false(caught, "an idle claw was holding something it was never given")
      assert.are.equal(STOCK, emptiest,
        ("the chest went down to %d of %d belts"):format(emptiest, STOCK))
      assert.are.equal(0, player.get_main_inventory().get_item_count(BELT)
        - (5 - 1), "belts appeared in the pockets that did not come from the ghost")
    end, "the run never ended", IDLING + 100)
  end)

  it("leaves alone the hold of the vehicle it is bolted to", function()
    local tank = world.vehicle(player, "tank")
    world.fit(tank, { tiers.by_level[4].name, "battery-equipment" }, true)
    tank.insert{ name = BELT, count = STOCK }
    world.ghost(player, BELT, 4, 0)

    local caught = false
    local began = game.tick
    world.once(function()
      if pilfering() then caught = true end
      return game.tick - began > IDLING
    end, function()
      assert.is_false(caught, "an idle claw was holding something it was never given")
      -- one belt is spent on the ghost and no more: anything else came out of the hold on
      -- its own account
      assert.are.equal(STOCK - 1, tank.get_item_count(BELT),
        ("the hold went from %d to %d where one ghost was built"):format(
          STOCK, tank.get_item_count(BELT)))
    end, "the run never ended", IDLING + 100)
  end)
end)
