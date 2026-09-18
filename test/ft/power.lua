--- What the arm costs to run.
---
--- The arm is a real electric inserter with nothing to plug into, so control.lua feeds it
--- out of its own equipment every tick and lets the engine decide the price. That is worth
--- testing rather than assuming, because the cost is no longer a number the mod picks: it
--- falls out of how far and how often the thing actually moves.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

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

describe("the arm's power", function()
  local grid

  before_each(function()
    grid = world.equipped(player)
    player.insert{ name = BELT, count = 20 }
  end)

  ---Everything the grid is holding, across all of its equipment.
  local function stored()
    local total = 0
    for _, piece in pairs(grid.equipment) do total = total + piece.energy end
    return total
  end

  -- The old flat charge was taken at the moment of delivery, so an abandoned reach was
  -- free. The engine bills for movement as it happens, which is what a real inserter does.
  it("is spent on the way out, not only on arrival", function()
    world.ghost(player, BELT, 2, 0)
    local before = stored()
    after_ticks(15, function()
      assert.are.equal(1, world.ghosts(player),
        "it delivered sooner than expected, so this proves nothing")
      assert.is_true(stored() < before,
        "nothing was spent while the arm was still on its way out")
    end)
  end)

  it("costs more to reach further", function()
    -- The two measurements have to start from the same place. An arm that is already out
    -- has swung itself into position and paid for it; one that is not has that swing still
    -- to come. So the second ghost does not go down until the first arm has been put away
    -- again, and each window is one cycle long from nothing.
    local SETTLED = world.CYCLE + 150
    local near, before
    world.ghost(player, BELT, 1, 0)
    before = stored()
    after_ticks(world.CYCLE, function()
      near = before - stored()
      assert.are.equal(0, world.ghosts(player), "the near ghost was never built")
    end)
    after_ticks(SETTLED, function()
      assert.is_nil(world.arm(player), "the arm never went away, so this is not a fair test")
      world.ghost(player, BELT, world.BUILD_RANGE, 0)
      before = stored()
    end)
    after_ticks(SETTLED + world.CYCLE, function()
      local far = before - stored()
      assert.are.equal(0, world.ghosts(player), "the far ghost was never built")
      assert.is_true(far > near,
        "reaching " .. world.BUILD_RANGE .. " tiles cost " .. far
        .. "J, no more than the " .. near .. "J it cost to reach one tile")
    end)
  end)

  --- What matters is that the charge is not thrown away, which is conservation rather than
  --- a rise in any one place: the armour keeps the equipment's own buffer topped up, so
  --- what comes out of the arm mostly has to go somewhere else in the grid.
  it("is not thrown away when the arm is put away", function()
    world.ghost(player, BELT, 2, 0)
    local before
    after_ticks(world.CYCLE, function()
      local arm = world.arm(player)
      assert.is_not_nil(arm, "the arm was already put away")
      assert.is_true(arm.energy > 1000, "the arm was holding almost nothing to give back")
      before = stored() + arm.energy
    end)
    -- long enough for the idle second to run out and the arm to go
    after_ticks(world.CYCLE + 90, function()
      assert.is_nil(world.arm(player), "the arm is still out")
      -- It spends while it works and drains while it waits out its idle second, so this
      -- is not exact. The allowance is wider than it was: the engine finishes the swing
      -- onto the box rather than the mod cutting it short, so the journey home costs more,
      -- Traced tick by tick, the arm's remaining buffer does come back in full -- the grid
      -- rose by 6869J as the arm went, against 6889J in its buffer.
      assert.is_true(stored() > before - 10000,
        ("%.0fJ was in the grid and the arm together, and only %.0fJ came back")
          :format(before, stored()))
    end)
  end)

  it("is not burnt by an idle character", function()
    local before = stored()
    after_ticks(A_BUILD * 4, function()
      -- the arm never comes out with nothing to build, so nothing should be spent
      assert.is_true(stored() > before - 100,
        "standing about with nothing to build cost " .. (before - stored()) .. "J")
    end)
  end)
end)

describe("an armour with almost nothing left in it", function()
  it("will not start a reach it cannot finish", function()
    local grid = world.equipped(player)
    player.insert{ name = BELT, count = 5 }
    for _, piece in pairs(grid.equipment) do piece.energy = 0 end
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      -- Not built is not enough to ask: an arm that set off and ran out of charge halfway
      -- has not built anything either, and leaving one stopped in mid air holding a belt is
      -- the thing the reserve exists to prevent. So what is asked is whether it reached out
      -- at all.
      assert.is_nil(world.arm(player),
        "it reached out on a charge that could not have paid for the swing")
      assert.are.equal(1, world.ghosts(player))
      assert.are.equal(0, world.count(player, BELT))
    end)
  end)
end)

-- A character standing among ghosts with nothing happening has no way of telling a flat
-- armour from a broken mod. The game already marks every machine short of power, so this
-- borrows that. It goes on the wearer because in this state there is usually no arm: an
-- armour that cannot raise a full buffer never sends one out.
describe("work in reach and no charge to go for it", function()
  local function marks()
    local seen = 0
    for _, drawn in pairs(rendering.get_all_objects("constructor-equipment")) do
      local ok, sprite = pcall(function() return drawn.sprite end)
      if ok and sprite == "utility/electricity_icon" then seen = seen + 1 end
    end
    return seen
  end

  -- A mark from the test before this one outlives world.clear on purpose: it has a life of
  -- its own precisely so that an armour taken off leaves nothing hanging about, and nobody
  -- is left to take it down the instant the armour goes. Half a second of that is by design
  -- and is somebody else's test, so it is cleared here rather than waited out.
  before_each(function()
    for _, drawn in pairs(rendering.get_all_objects("constructor-equipment")) do
      local ok, sprite = pcall(function() return drawn.sprite end)
      if ok and sprite == "utility/electricity_icon" and drawn.valid then drawn.destroy() end
    end
  end)

  ---Watch every tick and say whether the mark was ever up, and whether it was always up.
  local function watch(ticks, whenever)
    local ever, always = false, true
    script.on_nth_tick(1, function()
      if marks() > 0 then ever = true else always = false end
    end)
    after_ticks(ticks, function()
      script.on_nth_tick(1, nil)
      whenever(ever, always)
    end)
  end

  it("marks a flat armour that has something to build", function()
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { "constructor-equipment" }, false)
    player.insert{ name = BELT, count = 20 }
    world.ghost(player, BELT, 2, 0)
    watch(120, function(ever)
      assert.is_true(ever, "a flat armour with a ghost in reach said nothing about why")
    end)
  end)

  -- The complaint this replaced: the mark went up while running past a row of belts on a
  -- full battery, because it was reading each arm's own status and an idle arm reports
  -- itself short. Measured over six hundred ticks of that, the mod's own answer never once
  -- says it is waiting.
  it("says nothing while a charged armour is working", function()
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { "constructor-equipment", "battery-equipment" }, true)
    player.insert{ name = BELT, count = 100 }
    for i = 0, 8 do world.ghost(player, BELT, 2, i - 4) end
    watch(300, function(ever)
      assert.is_false(ever, "a working arm on a full battery was marked as short of power")
    end)
  end)

  it("takes it down once the armour is charged again", function()
    player.get_inventory(defines.inventory.character_armor).clear()
    local grid = world.equip(player, { "constructor-equipment", "battery-equipment" }, false)
    player.insert{ name = BELT, count = 20 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(40, function()
      assert.is_true(marks() > 0, "the flat armour was never marked")
      for _, piece in pairs(grid.equipment) do piece.energy = piece.max_energy end
      after_ticks(60, function()
        assert.are.equal(0, marks(), "the mark stayed up after the armour was charged")
      end)
    end)
  end)

  it("leaves none behind when the armour comes off", function()
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { "constructor-equipment" }, false)
    player.insert{ name = BELT, count = 20 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(40, function()
      assert.is_true(marks() > 0, "the flat armour was never marked")
      player.get_inventory(defines.inventory.character_armor).clear()
      after_ticks(60, function()
        assert.are.equal(0, marks(), "a mark outlived the armour it belonged to")
      end)
    end)
  end)
end)
