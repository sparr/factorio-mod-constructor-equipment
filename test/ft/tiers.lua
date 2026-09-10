--- What a better tier actually buys: a longer reach, a faster clock, and its own arm.
---
--- The prototypes are checked in test/ft/equipping.lua and the numbers in
--- test/spec/tiers_spec.lua. This is here for the part neither of those can see, which is
--- whether control.lua gives a given arm the reach and the clock of its own tier rather
--- than the first tier's for everything.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local BELT = "transport-belt"

--- Two tiles out and one across is 2.24 tiles: past what the first tier will reach and
--- comfortably inside what the second will.
local BEYOND_FIRST = { 2, 1 }

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("the first tier", function()
  it("leaves alone what it cannot reach", function()
    world.equip(player, { tiers.list[1].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, BEYOND_FIRST[1], BEYOND_FIRST[2])
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.ghosts(player),
        "the first tier built something 2.24 tiles off, which is past its two")
    end)
  end)
end)

describe("the second tier", function()
  before_each(function()
    world.equip(player, { tiers.list[2].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = 20 }
  end)

  it("reaches what the first tier cannot", function()
    world.ghost(player, BELT, BEYOND_FIRST[1], BEYOND_FIRST[2])
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, world.ghosts(player),
        "the second tier did not reach 2.24 tiles, which is inside its three")
      assert.are.equal(1, world.count(player, BELT))
    end)
  end)

  it("swings its own arm rather than the first tier's", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      local arms = world.arms(player)
      assert.are.equal(1, #arms, "there should be one arm")
      assert.are.equal(tiers.list[2].inserter, arms[1].name,
        "the second tier is swinging " .. arms[1].name)
    end)
  end)

  it("still leaves alone what even it cannot reach", function()
    -- two tiles out and three across is 3.61, past the second tier's three
    world.ghost(player, BELT, 2, 3)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.ghosts(player),
        "the second tier built something 3.6 tiles off, which is past its three")
    end)
  end)
end)

--- Same ghosts, same time, one tier apart. Run one after the other in a single test so
--- both halves are measured against the same clock.
describe("a better tier", function()
  --- Long enough for the difference between two hand speeds to add up to whole builds, and
  --- topped up so neither run can finish early and flatter the slower arm.
  local WINDOW = world.CYCLE * 3
  local STOCK = 60

  --- Counted as items spent, not as belts standing: topping the ghosts up clears whatever
  --- was built on those spots, so the belts on the ground are no record of anything.
  local function spent()
    return STOCK - player.get_item_count(BELT)
  end

  local function keep_stocked(from, to)
    for n = from, to, 20 do
      after_ticks(n, function()
        if world.ghosts(player) < 6 then world.top_up(player, BELT, 12) end
      end)
    end
  end

  local function start_tier(level)
    world.equip(player, { tiers.list[level].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = STOCK }
    world.several(player, BELT, 12)
  end

  it("builds more in the same time", function()
    local first
    start_tier(1)
    keep_stocked(20, WINDOW)
    after_ticks(WINDOW, function()
      first = spent()
      world.clear(player)
      player = world.player()
      start_tier(2)
    end)
    keep_stocked(WINDOW + 20, WINDOW * 2)
    after_ticks(WINDOW * 2 + 10, function()
      local second = spent()
      assert.is_true(first > 0, "the first tier built nothing, so this proves nothing")
      assert.is_true(second > first,
        ("the second tier built %d where the first built %d"):format(second, first))
    end)
  end)
end)

--- Tiers mix, and they disagree about the penalty. The heaviest lands: a good arm does not
--- excuse the old one working beside it.
---
--- Measured as the lowest speed reached while there was still something to build, rather
--- than at a fixed tick. A pair of arms clears ten ghosts in well under two seconds and a
--- fast one clears them quicker still, so any fixed sample is a race against the run
--- ending and the character recovering.
--- Not a correctness check: control.lua cannot rely on this, and does not.
---
--- The mod looks at the hand once a tick, so a window narrower than a tick of travel is a
--- band the hand can step over. That much can be worked out from the tier's numbers. What
--- cannot is the last step: the engine does not creep up on its target and stop, it jumps
--- whatever gap is left in a single tick to land exactly on it, measured at 0.44 tiles for
--- the third tier against a sustained 0.25. So no window computed from extension and
--- rotation is safe, and salvage in control.lua is what actually closes the hole.
---
--- What this is for is the shape of the swing. A tier whose hand crosses half a tile in a
--- tick is one whose turn looks instantaneous against an extension that crawls, which is
--- what the fourth tier did at the base game's rotation speed on a five tile arm.
describe("how far a hand moves in a tick", function()
  local SETTLE = 150

  local function measure(level, done)
    world.equip(player, { tiers.list[level].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = 40 }
    -- out at the very edge, where a turn carries the hand furthest
    world.ghost(player, BELT, tiers.list[level].range, 0)
    world.ghost(player, BELT, -tiers.list[level].range, 0)

    local worst, last, last_arm = 0, nil, nil
    local function sample()
      local arm = world.arms(player)[1]
      if not (arm and arm.valid) then last, last_arm = nil, nil return end
      local at = arm.held_stack_position
      -- only between two looks at the same arm: a new arm starts wherever it starts, and
      -- that jump is not the hand moving
      if last and last_arm == arm.unit_number then
        worst = math.max(worst, reach.distance(last, at))
      end
      last, last_arm = { x = at.x, y = at.y }, arm.unit_number
    end
    for n = 1, SETTLE do after_ticks(n, sample) end
    after_ticks(SETTLE + 1, function() done(worst) end)
  end

  for level = 1, #tiers.list do
    it(("keeps tier %d's hand under half a tile a tick"):format(level), function()
      measure(level, function(worst)
        assert.is_true(worst > 0, "the hand never moved, so this measured nothing")
        assert.is_true(worst < 0.5,
          ("tier %d moved its hand %.3f tiles in a tick"):format(level, worst))
      end)
    end)
  end
end)

describe("tiers worn together", function()
  local function lowest_while_working(pairs_of)
    world.equip(player, pairs_of, true, "power-armor")
    player.insert{ name = BELT, count = 60 }
    world.several(player, BELT, 12)
  end

  local function watch(full, seen)
    for n = 10, 200, 5 do
      after_ticks(n, function()
        -- keep the run alive, so the slowdown is never measured against a run that ended
        if world.ghosts(player) < 6 then world.top_up(player, BELT, 12) end
        seen.lowest = math.min(seen.lowest, world.share_of(player, full))
        local level = world.slowed_level(player)
        if level then seen.levels[level] = true end
      end)
    end
  end

  it("costs whatever the worse of a slowing tier and a free one costs", function()
    local full = player.character_running_speed
    local seen = { lowest = 1, levels = {} }
    lowest_while_working{ tiers.list[1].name, tiers.list[3].name, "battery-equipment" }
    watch(full, seen)
    after_ticks(210, function()
      assert.is_true(math.abs(seen.lowest - tiers.list[1].slowdown) < 0.02,
        ("the slowest they walked was %.4f, not the first tier's %.4f")
          :format(seen.lowest, tiers.list[1].slowdown))
      assert.is_true(seen.levels[1], "the first tier's slowdown was never applied")
    end)
  end)

  -- Both of these ask for a penalty, and they disagree about how much. The first tier's is
  -- the heavier, so that is the one that should land. Two tiers where only one asks for
  -- anything cannot tell the difference, because the other is never a candidate.
  it("takes the heavier of two penalties, not the lighter", function()
    local full = player.character_running_speed
    local seen = { lowest = 1, levels = {} }
    lowest_while_working{ tiers.list[1].name, tiers.list[2].name, "battery-equipment" }
    watch(full, seen)
    after_ticks(210, function()
      assert.is_true(math.abs(seen.lowest - tiers.list[1].slowdown) < 0.02,
        ("the slowest they walked was %.4f: the first tier asks %.4f and the second %.4f")
          :format(seen.lowest, tiers.list[1].slowdown, tiers.list[2].slowdown))
      assert.is_true(seen.levels[1], "the heavier of the two was never applied")
      assert.is_false(seen.levels[2] or false,
        "the lighter of the two was applied while the heavier arm was working")
    end)
  end)

  -- two sets at once would be two prototypes, which the engine multiplies together: the
  -- character would end up slower than either arm asks for
  it("never puts two of the mod's slowdowns on at once", function()
    lowest_while_working{ tiers.list[1].name, tiers.list[2].name, "battery-equipment" }
    local most = 0
    for n = 10, 200, 5 do
      after_ticks(n, function()
        if world.ghosts(player) < 6 then world.top_up(player, BELT, 12) end
        most = math.max(most, #world.mod_stickers(player))
      end)
    end
    after_ticks(210, function()
      assert.is_true(most > 0, "it was never slowed at all, so this proves nothing")
      assert.are.equal(1, most, "there were " .. most .. " of the mod's slowdowns at once")
    end)
  end)
end)

--- The ramp into the slowdown runs once per run of building, and then the flat sticker
--- holds the character there.
---
--- It used to be swapped in by watching how much life the ramp sticker had left, which
--- only worked while something looked every tick. A run of building is not continuous --
--- an arm that gets home before its clock is due waits a few ticks -- and a ramp that ran
--- out in one of those gaps was replaced by a second ramp rather than by the flat sticker.
--- The character eased towards a speed they never actually reached, over and over.
describe("easing into the slowdown", function()
  --- Close ghosts, so the arm finishes early and waits: that is what makes the gaps.
  local CLOSE = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 },
                  { 1, -1 }, { -1, -1 }, { 2, 0 }, { -2, 0 } }

  local function close_ghosts()
    for _, spot in pairs(CLOSE) do world.ghost(player, BELT, spot[1], spot[2]) end
  end

  it("settles at the speed the tier asks for rather than easing forever", function()
    local full = player.character_running_speed
    world.equip(player, { tiers.list[1].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = 40 }
    close_ghosts()
    local highest, sampled = 0, 0
    -- from well after the ramp should have finished, to the end of the run
    for n = world.RAMP_TICKS + 30, 200, 5 do
      after_ticks(n, function()
        if world.ghosts(player) > 0 then
          sampled = sampled + 1
          highest = math.max(highest, world.share_of(player, full))
        end
      end)
    end
    after_ticks(210, function()
      assert.is_true(sampled > 10, "the run was too short to sample: " .. sampled)
      assert.is_true(highest < tiers.list[1].slowdown + 0.01,
        ("the character got back up to %.4f of full speed mid-run, so the ramp restarted")
          :format(highest))
    end)
  end)

  it("ramps in again for the next run, having stopped between them", function()
    local full = player.character_running_speed
    world.equip(player, { tiers.list[1].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = 40 }
    world.ghost(player, BELT, 2, 0)
    -- one ghost, then a long pause with nothing to do, then another
    after_ticks(world.CYCLE + 150, function()
      assert.is_nil(world.slowed_level(player), "it never came back up to speed")
      assert.are.equal(full, player.character_running_speed)
      world.ghost(player, BELT, -2, 0)
    end)
    after_ticks(world.CYCLE + 165, function()
      local level, which = world.slowed_level(player)
      assert.are.equal(1, level, "the second run did not slow the character")
      assert.are.equal("slowing", which,
        "the second run went straight to the flat slowdown instead of easing in")
    end)
  end)

  -- The old handover watched the ramp's remaining life and swapped in the flat sticker
  -- once it was nearly out. That worked, given something looks every tick, but it stepped:
  -- the ramp was cut short a fifth of the way from the end, so the character dropped the
  -- rest of the way in one tick instead of easing there. Letting the ramp expire on its
  -- own is seamless, because it ends at exactly the speed the flat sticker holds.
  it("lets the ramp run its whole life rather than cutting it short", function()
    world.equip(player, { tiers.list[1].name, "battery-equipment" }, true)
    player.insert{ name = BELT, count = 40 }
    close_ghosts()
    local lowest = math.huge
    for n = 30, 90 do
      after_ticks(n, function()
        local ramp = world.slowdown(player, tiers.list[1].stickers.slowing)
        if ramp then lowest = math.min(lowest, ramp.time_to_live) end
      end)
    end
    after_ticks(100, function()
      assert.is_true(lowest < math.huge, "the ramp was never seen at all")
      assert.is_true(lowest <= 5,
        ("the ramp was thrown away with %d ticks still to run"):format(lowest))
    end)
  end)
end)

--- What an armour must be holding before an arm will set off, which is a couple of that
--- arm's own reaches. A fourth tier swing costs sixteen times a first tier one, so the same
--- charge that is plenty for one is nowhere near enough for the other.
describe("the charge an arm wants before setting off", function()
  --- Over the first tier's reserve and under the fourth tier's, wherever those two sit.
  local BETWEEN = (tiers.list[1].reserve + tiers.list[#tiers.list].reserve) / 2

  local function charged_to(level, joules)
    local grid = world.equip(player, { tiers.list[level].name, "battery-equipment" }, true)
    for _, equipment in pairs(grid.equipment) do equipment.energy = 0 end
    for _, equipment in pairs(grid.equipment) do
      if equipment.name == "battery-equipment" then equipment.energy = joules end
    end
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    return grid
  end

  it("is little enough that the first tier sets off on it", function()
    assert.is_true(tiers.list[1].reserve < BETWEEN,
      "the first tier wants more than this test offers")
    charged_to(1, BETWEEN)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "the first tier would not build on " .. BETWEEN .. "J")
    end)
  end)

  it("is not enough for the fourth tier to set off on", function()
    assert.is_true(tiers.list[4].reserve > BETWEEN,
      "the fourth tier wants less than this test offers")
    charged_to(4, BETWEEN)
    after_ticks(world.CYCLE * 2, function()
      assert.is_nil(world.arm(player),
        "a fourth tier arm reached out on a charge that could not pay for the swing")
      assert.are.equal(1, world.ghosts(player), "it built anyway")
      assert.are.equal(0, world.count(player, BELT))
    end)
  end)

  it("lets the fourth tier set off once there is enough", function()
    charged_to(4, tiers.list[4].reserve * 3)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "the fourth tier would not build on three reaches' worth")
    end)
  end)
end)

--- Putting several things down for one journey out, rather than going home between each.
---
--- Not the last tier's alone, and not free: an arm holds exactly what the inserter it is
--- made of holds, which is one of anything until inserter capacity research starts raising
--- it. What the last tier has is a bulk claw, so the research takes it much further -- to
--- twelve where a plain one reaches three.
describe("putting several down for each journey", function()
  local STOCK = 40
  local ALL = 7

  local function research(upto)
    for n = 1, ALL do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = n <= upto end
    end
  end

  local function wearing(level)
    world.equip(player, { tiers.list[level].name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = STOCK }
  end

  local function spread(level)
    local r = tiers.list[level].range
    for _, d in ipairs{ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r },
                        { r - 1, 1 }, { -(r - 1), 1 }, { r - 1, -1 }, { -(r - 1), -1 } } do
      world.ghost(player, BELT, d[1], d[2])
    end
  end

  local function fresh()
    return { built = 0, most_queued = 0, mid_journey = 0, left = 0 }
  end

  ---How much the claw was queued with, and how many it put down inside a single journey.
  ---Counted as things actually spent, not as the queue counting down: the queue shortens
  ---whether or not the delivery that follows it happens.
  local function watch(seen, from, to)
    for n = from, to do
      after_ticks(n, function()
        local job = world.job(player)
        if job then
          local left = job.left or 1
          if seen.started == job.started then
            if left < seen.left and job.going == "out" then
              seen.mid_journey = seen.mid_journey + 1
            end
          else
            seen.most_queued = math.max(seen.most_queued, left)
          end
          seen.started, seen.left = job.started, left
        else
          seen.started, seen.left = nil, nil
        end
        seen.built = STOCK - player.get_item_count(BELT)
      end)
    end
  end

  after_each(function()
    research(0)
  end)

  for _, level in ipairs{ 1, 4 } do
    it("tier " .. level .. " does not, with no capacity research", function()
      research(0)
      wearing(level)
      spread(level)
      local seen = fresh()
      watch(seen, 2, 240)
      after_ticks(250, function()
        assert.is_true(seen.built > 0, "tier " .. level .. " built nothing")
        assert.are.equal(1, seen.most_queued,
          "tier " .. level .. " queued " .. seen.most_queued .. " with nothing researched")
        assert.are.equal(0, seen.mid_journey,
          "tier " .. level .. " put one down part way through a journey")
      end)
    end)

    it("tier " .. level .. " does, once the research is in", function()
      research(ALL)
      wearing(level)
      spread(level)
      local seen = fresh()
      watch(seen, 2, 300)
      after_ticks(310, function()
        assert.is_true(seen.most_queued > 1,
          "tier " .. level .. " still queued only " .. seen.most_queued)
        assert.is_true(seen.mid_journey > 0,
          "tier " .. level .. " never put one down part way through a journey")
      end)
    end)
  end

  it("takes a bulk claw much further than a plain one", function()
    research(ALL)
    local plain = 1 + player.force.inserter_stack_size_bonus
    local bulk = tiers.BULK_BASE + player.force.bulk_inserter_capacity_bonus
    assert.is_true(bulk > plain, "the research does not separate the two claws at all")
    wearing(4)
    spread(4)
    local seen = fresh()
    watch(seen, 2, 300)
    after_ticks(310, function()
      assert.is_true(seen.most_queued > plain,
        ("the last tier queued %d, no more than a plain claw's %d")
          :format(seen.most_queued, plain))
    end)
  end)
end)

--- Inserter capacity research raises what every inserter in the factory carries. These are
--- inserters, so it raises what they carry too, and no tier is given anything on top of
--- that: an arm holds what the inserter it is made of holds, and stops there.
describe("following the inserter capacity research", function()
  local ALL = 7

  local function research(upto)
    for n = 1, ALL do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = n <= upto end
    end
  end

  ---What a base game inserter's claw actually takes, measured the same way ours is: fill it
  ---and see what stuck. This reads one below the stack size the wiki lists for a bulk
  ---inserter -- the wiki's twelve is eleven here -- so it is the measure to compare against
  ---rather than the documented figure, since it is also the ceiling the mod runs into.
  local function vanilla_claw(name)
    local it = player.surface.create_entity{ name = name,
      position = { world.ORIGIN.x + 8, world.ORIGIN.y }, force = player.force }
    it.held_stack.set_stack{ name = BELT, count = 60 }
    local held = it.held_stack.valid_for_read and it.held_stack.count or 0
    it.held_stack.clear()
    it.destroy()
    return held
  end

  local function longest_queue(level, ticks)
    world.equip(player, { tiers.list[level].name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = 40 }
    world.several(player, BELT, 12)
    local most = { n = 0 }
    for n = 2, ticks do
      after_ticks(n, function()
        local job = world.job(player)
        if job then most.n = math.max(most.n, job.left or 1) end
      end)
    end
    return most
  end

  after_each(function()
    research(0)
  end)

  it("is what the research raises", function()
    research(2)
    assert.is_true(player.force.inserter_stack_size_bonus > 0,
      "researching it did not raise the force's inserter stack size")
    assert.is_true(player.force.bulk_inserter_capacity_bonus > 0,
      "researching it did not raise the force's bulk inserter capacity")
  end)

  it("gives a plain claw what a plain inserter gets", function()
    research(ALL)
    local theirs = vanilla_claw("inserter")
    local most = longest_queue(1, 120)
    after_ticks(130, function()
      assert.are.equal(theirs, most.n,
        ("the first tier holds %d where a plain inserter holds %d"):format(most.n, theirs))
    end)
  end)

  it("gives a bulk claw what a bulk inserter gets", function()
    research(ALL)
    local theirs = vanilla_claw("bulk-inserter")
    local most = longest_queue(4, 120)
    after_ticks(130, function()
      assert.are.equal(theirs, most.n,
        ("the last tier holds %d where a bulk inserter holds %d"):format(most.n, theirs))
    end)
  end)

  -- No tier gets a head start of its own on top of the research. One did, and it took the
  -- last tier three past what a bulk inserter can hold.
  it("gives no tier anything on top of that", function()
    research(0)
    local theirs = vanilla_claw("bulk-inserter")
    local most = longest_queue(4, 120)
    after_ticks(130, function()
      assert.are.equal(theirs, most.n,
        ("the last tier queued %d with no research done, where a bulk inserter holds %d")
          :format(most.n, theirs))
    end)
  end)
end)

--- What a base game bulk inserter actually carries, which is what lib.tiers.BULK_BASE is
--- set from and what the last tier is capped at.
---
--- Worth a test of its own because the documentation disagrees. Both the wiki and the base
--- game's own comments in technology.lua give a bulk inserter two to twelve: bonus-1 is
--- annotated "result of 3" and bonus-7 "result of 12". Measured in 2.1.17 it is one to
--- eleven. The annotations look to be left over from 1.1, where the stack inserter this
--- replaced did start at two. If a later version makes the documentation true, this fails
--- and the cap wants moving with it.
describe("what a base game bulk inserter carries", function()
  local ALL = 7

  local function research(upto)
    for n = 1, ALL do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = n <= upto end
    end
  end

  ---Runs a powered inserter between two chests and reports the most it ever held.
  local function most_carried(name, ticks, report)
    local force, surface = player.force, player.surface
    local o = { x = world.ORIGIN.x + 12, y = world.ORIGIN.y + 12 }
    for _, e in pairs(surface.find_entities_filtered{ position = o, radius = 8 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
    local function at(dx, dy) return { x = o.x + dx, y = o.y + dy } end
    surface.create_entity{ name = "steel-chest", position = at(0, 0), force = force }
      .insert{ name = BELT, count = 800 }
    surface.create_entity{ name = "steel-chest", position = at(2, 0), force = force }
    local arm = surface.create_entity{ name = name, position = at(1, 0), force = force,
      direction = defines.direction.west }
    surface.create_entity{ name = "small-electric-pole", position = at(1, 1), force = force }
    -- an inserter with no network never swings, and writing energy to it does not help:
    -- a vanilla inserter has no buffer of its own to write to
    local power = surface.create_entity{ name = "electric-energy-interface",
      position = at(1, 2), force = force }
    power.power_production = 5000000
    power.electric_buffer_size = 5000000
    power.energy = 5000000
    for n = 2, ticks do
      after_ticks(n, function()
        if arm.valid and arm.held_stack.valid_for_read then
          report.most = math.max(report.most, arm.held_stack.count)
        end
      end)
    end
  end

  after_each(function()
    research(0)
  end)

  for _, upto in ipairs{ 0, 2, ALL } do
    it("is one plus the capacity bonus, with " .. upto .. " researched", function()
      research(upto)
      local report = { most = 0 }
      local wanted = 1 + player.force.bulk_inserter_capacity_bonus
      most_carried("bulk-inserter", 300, report)
      after_ticks(310, function()
        assert.are.equal(wanted, report.most,
          ("a bulk inserter carried %d with a bonus of %d"):format(
            report.most, player.force.bulk_inserter_capacity_bonus))
      end)
    end)
  end

  it("is what the mod caps its own bulk claw at", function()
    research(ALL)
    local report = { most = 0 }
    most_carried("bulk-inserter", 300, report)
    after_ticks(310, function()
      assert.are.equal(
        tiers.BULK_BASE + player.force.bulk_inserter_capacity_bonus, report.most,
        "lib.tiers.BULK_BASE no longer matches what a bulk inserter carries")
    end)
  end)
end)

--- Running out of charge partway through a journey.
---
--- Setting off wants a full buffer, so an arm always starts with enough for a reach. A
--- journey with a queue can outlast that: the claw hops from ghost to ghost, and if the
--- armour cannot keep up it would otherwise turn to a fresh one, run dry somewhere out at
--- the end of its own arm, and stand there until the swing limit gave up on it.
describe("an arm that runs low mid journey", function()
  local ALL = 7

  local function research(upto)
    for n = 1, ALL do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = n <= upto end
    end
  end

  after_each(function()
    research(0)
  end)

  ---Empty everything the armour has, so nothing can refill anything.
  local function drain(grid)
    for _, piece in pairs(grid.equipment) do piece.energy = 0 end
  end

  it("comes home rather than turning to the next one", function()
    research(ALL)
    local grid = world.equip(player,
      { tiers.list[4].name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = 40 }
    world.several(player, BELT, 12)
    local queued, went_home = nil, false
    after_ticks(12, function()
      local job = world.job(player)
      assert.is_not_nil(job, "nothing was reaching, so this proves nothing")
      queued = job.left or 1
      assert.is_true(queued > 1, "it only queued " .. queued .. ", so there is nothing to cut short")
      drain(grid)
    end)
    for n = 14, 90 do
      after_ticks(n, function()
        drain(grid)
        local job = world.job(player)
        if job and job.going == "back" then went_home = true end
      end)
    end
    after_ticks(100, function()
      assert.is_true(went_home,
        "it never started for home after the armour ran dry")
    end)
  end)

  it("does not strand itself at full stretch", function()
    research(ALL)
    local grid = world.equip(player,
      { tiers.list[4].name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = 40 }
    world.several(player, BELT, 12)
    after_ticks(12, function() drain(grid) end)
    for n = 14, 200 do
      after_ticks(n, function() drain(grid) end)
    end
    after_ticks(210, function()
      local arm = world.arm(player)
      assert.is_nil(arm,
        "the arm is still out with a dry armour rather than having been put away")
      assert.is_nil(world.job(player), "it is still on a journey it cannot pay for")
    end)
  end)
end)

--- The threshold for carrying on is one reach's worth, and the worst hop has to fit inside
--- it. Swinging from due east to due west is half a circle at full stretch, which is a
--- longer path than the reach itself, so it is worth knowing that it is nowhere near as
--- expensive as it sounds: what a journey costs is almost all extending and retracting.
describe("what a hop costs against what carrying on asks for", function()
  local ALL = 7

  local function research(on)
    player.force.technologies["bulk-inserter"].researched = on
    for n = 1, ALL do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = on end
    end
  end

  after_each(function()
    research(false)
  end)

  it("leaves room for a half turn at full stretch", function()
    research(true)
    local tier = tiers.list[4]
    local grid = world.equip(player, { tier.name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = 40 }
    local function stored()
      local total = 0
      for _, piece in pairs(grid.equipment) do total = total + piece.energy end
      return total
    end
    -- due east and due west, the longest way round there is
    world.ghost(player, BELT, tier.range, 0)
    world.ghost(player, BELT, -tier.range, 0)
    local before
    after_ticks(4, function() before = stored() end)
    after_ticks(300, function()
      -- counted as belts standing, not as items missing from the pockets: the claw is
      -- loaded out of the pockets before it sets off now, so what has gone from them says
      -- what was picked up rather than what was delivered
      local built = #player.surface.find_entities_filtered{ name = BELT,
        position = world.ORIGIN, radius = tier.range + 2 }
      local spent = before - stored()
      assert.are.equal(2, built, "both ghosts should have gone up in one journey")
      -- Two reaches' worth covers both deliveries and the journey home, with room over.
      --
      -- It used to be one and a bit. The saving a carrying claw buys is smaller than it
      -- was: the mod used to count a delivery done three tenths of a tile short and cut
      -- the swing off, and the engine now takes the hand the whole way onto the box. Two
      -- deliveries half a turn apart measure about 1.85 reaches. Still a saving over two
      -- separate journeys, which would be two full reaches out and two home.
      assert.is_true(spent < tier.reach_energy * 2.0,
        ("two deliveries half a turn apart cost %.0fJ against a reach's %.0fJ")
          :format(spent, tier.reach_energy))
    end)
  end)
end)

--- A round of several is only as long as what is in the claw. The two came apart in the
--- sandbox: a fourth tier arm loaded with two solar panels put one down, found its hand
--- empty, and carried on to the next ghost anyway, because deliver() consulted the counter
--- and not the claw. The arm then stood at full stretch over a ghost holding nothing,
--- which is what a player sees as a delivery that never arrived.
describe("a round with less in the claw than the count says", function()
  -- Capacity research is a force wide setting, so a test that turns it on and walks away
  -- leaves every test after it with claws that carry more than they expect. Seven of them
  -- failed that way before this was put back.
  after_each(function()
    for n = 1, 7 do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = false end
    end
  end)

    it("ends the round instead of reaching on empty handed", function()
    for n = 1, 7 do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = true end
    end
    world.equip(player, { tiers.list[4].name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = 40 }
    local r = tiers.list[4].range
    for _, d in ipairs{ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r },
                        { r - 1, 1 }, { -(r - 1), 1 }, { r - 1, -1 } } do
      world.ghost(player, BELT, d[1], d[2])
    end

    -- Catch it loaded for a round of more than one and take all but one away: the state
    -- the sandbox arrived at on its own, without waiting for it to happen again.
    local trimmed, stranded, most = false, false, 0
    for n = 5, 240 do
      after_ticks(n, function()
        local arm = world.arms(player)[1]
        if not (arm and arm.valid) then return end
        local job = world.job(player)
        if arm.held_stack.valid_for_read then
          most = math.max(most, arm.held_stack.count)
        end
        if not trimmed then
          if arm.held_stack.valid_for_read and arm.held_stack.count > 1 then
            arm.held_stack.count = 1
            trimmed = true
          end
          return
        end
        -- from here on, an arm on its way out with nothing in the claw is the fault
        if job and job.going == "out" and not arm.held_stack.valid_for_read then
          stranded = true
        end
      end)
    end

    after_ticks(260, function()
      assert.is_true(trimmed,
        ("the arm never took a round of more than one; most in the claw was %d"):format(most))
      assert.is_false(stranded,
        "the arm carried on to another ghost with an empty claw")
    end)
  end)
end)
