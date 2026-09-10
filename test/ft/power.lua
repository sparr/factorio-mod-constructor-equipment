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
      -- onto the box rather than the mod cutting it short, so the journey home costs more.
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
