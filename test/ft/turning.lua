--- Arms that set off for a ghost at full speed and turn back without delivering.
---
--- Reported as happening to particular ghosts rather than to a scattering of them. It was
--- reproduced here at every speed tried, and it was not the arms setting off repeatedly from
--- home: traced tick by tick, a claw never went through assign() at all for these. It was
--- caught in redirect(), which is the path a loaded claw takes when it crosses to the next
--- ghost of its round.
---
--- And what redirect() did was take whatever choose() offered without ever looking at
--- whether there was a course to it. choose() filtered on out_of_reach(), which leaves the
--- bearing out on purpose and is therefore generous; holding_course() charges the turn. So a
--- claw crossed to a neighbour the strict test refused on the very next tick, gave it up, was
--- offered the one after, and lost that one the same way -- a tick apiece, delivering to
--- none of them:
---
---   2588 slot 4 gives up on 251.5,198.5 after 1 ticks: course=false
---   2591 slot 4 gives up on 252.5,198.5 after 1 ticks: course=false
---   2592 slot 4 gives up on 251.5,198.5 after 1 ticks: course=false
---
--- Both ends ask the same question now -- see course_to() in control.lua -- and the worst any
--- ghost sees is one attempt. What this fixture measures is the symptom: how many ghosts an
--- arm set off for and never delivered to.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local BELT = "transport-belt"
local BELTS = 400
local RAILS_FROM, RAILS_TO = -60, 500
local RUN = 900

describe("a train at full speed", function()
  local player

  local function clear_arena()
    world.unseat(player)
    local driven = {}
    for _, other in pairs(game.players) do
      if other.character then driven[other.character.unit_number] = true end
    end
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 800 }) do
      if e.valid and not (e.type == "character" and driven[e.unit_number]) then
        e.destroy()
      end
    end
    world.clear(player)
  end

  before_each(function() player = world.player(); clear_arena(player) end)
  after_each(function() clear_arena(player) end)

  --- Flat out is the third of these because the two below it are not fast. A locomotive's
  --- top speed is more than twice the quicker of them, and "an arm on a train at speed
  --- builds nothing" was an open report until this case was written: it builds 182 of 390,
  --- which is what the other two manage as well. The rails have to be long enough for it,
  --- and the speed asked for is past what the engine will give, so the train takes its own
  --- maximum -- 1.203 tiles a tick, which is what really went rather than what was asked.
  for _, how in ipairs{ { name = "a quarter", speed = 0.3 },
                        { name = "half a tile a tick", speed = 0.6 },
                        { name = "flat out", speed = 3, run = 400, rails = 1200,
                          least = 4 } } do
    local run = how.run or RUN
    local rails_to = how.rails or RAILS_TO
    it("does not change its mind every tick, " .. how.name, function()
      local surface, y = player.surface, world.ORIGIN.y
      for x = world.ORIGIN.x + RAILS_FROM, world.ORIGIN.x + rails_to, 2 do
        surface.create_entity{ name = "straight-rail", position = { x, y },
          direction = defines.direction.east, force = player.force }
      end
      local loco = surface.create_entity{ name = "locomotive",
        position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
        force = player.force }
      local wagon = surface.create_entity{ name = "cargo-wagon",
        position = { world.ORIGIN.x - 27, y }, direction = defines.direction.east,
        force = player.force }
      loco.insert{ name = "nuclear-fuel", count = 5 }
      wagon.insert{ name = BELT, count = BELTS }
      local grid = {}
      for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
      grid[#grid + 1] = "battery-equipment"
      world.fit(loco, grid, true)
      loco.train.manual_mode = true
      loco.set_driver(player)
      local started_at = loco.position.x

      local ghosts = {}
      for x = 6, 200 do
        for _, dy in ipairs{ -2, 2 } do
          local ghost = world.ghost(player, BELT, x, dy)
          if ghost then ghosts[#ghosts + 1] = { at = ghost.position, thing = ghost } end
        end
      end

      -- what each arm was last aimed at, so a change of mind can be counted
      local aimed, tries, quickest = {}, {}, {}
      local began = game.tick
      -- How far the train really goes in a tick, which is not what train.speed says: that
      -- property reads back whatever was last written to it whether the engine honoured it
      -- or not. The drift the arms work from is a difference of positions, so this is the
      -- number that matters.
      local fastest, was_at = 0, loco.position.x
      world.once(function()
        loco.train.speed = how.speed
        fastest = math.max(fastest, math.abs(loco.position.x - was_at))
        was_at = loco.position.x
        for slot, record in pairs(storage.constructor_arms[player.index] or {}) do
          local job = record.job
          local now = job and job.ghost and job.ghost.valid
            and ("%.1f,%.1f"):format(job.ghost.position.x, job.ghost.position.y) or nil
          if now ~= aimed[slot] then
            if now then tries[now] = (tries[now] or 0) + 1 end
            aimed[slot] = now
          end
        end
        return game.tick - began > run
      end, function()
        loco.train.speed = 0
        local missed, attempted, most, where = 0, 0, 0, nil
        for _, ghost in ipairs(ghosts) do
          if ghost.thing.valid then
            missed = missed + 1
            local key = ("%.1f,%.1f"):format(ghost.at.x, ghost.at.y)
            if tries[key] then
              attempted = attempted + 1
              if tries[key] > most then most, where = tries[key], key end
            end
          end
        end
        log(("TURN | %-14s asked for %.2f, really went %.3f a tick, %.0f tiles in %d"
          .. " ticks | %d ghosts, %d BUILT, %d still standing, %d of those had an arm set"
          .. " off for them, worst %s at %d attempts"):format(
          how.name, how.speed, fastest, loco.position.x - started_at, run,
          #ghosts, #ghosts - missed, missed, attempted, tostring(where), most))
        -- The pathology was a claw alternating between two or three neighbours a tick
        -- apiece: nine attempts on one ghost and a delivery to none of them. One or two
        -- attempts on something the train simply carried past is ordinary.
        assert.is_true(most <= 3,
          ("an arm set off for the ghost at %s %d times and never delivered to it")
            :format(tostring(where), most))
        -- A third of the field at the two speeds a train takes a while to get past, and a
        -- quarter of it flat out, where the train is past the whole field in a hundred and
        -- sixty ticks and eight arms cannot be everywhere. Measured flat out: 182 of 390.
        local least = how.least or 3
        assert.is_true(#ghosts - missed > #ghosts / least,
          ("only %d of %d were built"):format(#ghosts - missed, #ghosts))
      end, "the run never ended", run + 100)
    end)
  end
end)


--- What a train builds at each speed it passes through, which is the question the constant
--- speed runs above cannot answer.
---
--- Those force train.speed every tick, so the arms see one drift from the first tick to the
--- last. A driven train does not work like that: it accelerates for a long way, and the
--- showroom's own train bay lays its ghosts along the whole track, so what a player sees is
--- a field worked at every speed between nothing and the locomotive's maximum. "At full
--- speed nothing is built" is a claim about the far end of that.
---
--- So this one is driven rather than set, over enough rail to reach the top, and counts what
--- was built and what was carried past in each band of speed. A band where the train passes
--- ghosts and builds none of them is the fault, and says exactly where it starts.
describe("a driven train through the speeds", function()
  local player

  local function clear_arena()
    world.unseat(player)
    local driven = {}
    for _, other in pairs(game.players) do
      if other.character then driven[other.character.unit_number] = true end
    end
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 3000 }) do
      if e.valid and not (e.type == "character" and driven[e.unit_number]) then
        e.destroy()
      end
    end
    world.clear(player)
  end

  before_each(function() player = world.player(); clear_arena(player) end)
  after_each(function() clear_arena(player) end)

  it("builds at the top speed as readily as at a walk", function()
    local surface, y = player.surface, world.ORIGIN.y
    local GHOSTS_TO, RAILS_END, DRIVE = 900, 2400, 1100
    for x = world.ORIGIN.x - 40, world.ORIGIN.x + RAILS_END, 2 do
      surface.create_entity{ name = "straight-rail", position = { x, y },
        direction = defines.direction.east, force = player.force }
    end
    local loco = surface.create_entity{ name = "locomotive",
      position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
      force = player.force }
    local wagon = surface.create_entity{ name = "cargo-wagon",
      position = { world.ORIGIN.x - 27, y }, direction = defines.direction.east,
      force = player.force }
    -- Solid fuel and eight second tier arms, which is what the showroom's train bay carries.
    loco.insert{ name = "solid-fuel", count = 50 }
    wagon.insert{ name = BELT, count = 2000 }
    local grid = {}
    for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
    grid[#grid + 1] = "battery-mk2-equipment"
    world.fit(loco, grid, true)
    loco.train.manual_mode = true
    loco.set_driver(player)

    local laid = 0
    for x = 6, GHOSTS_TO do
      for _, dy in ipairs{ -2, 2 } do
        if world.ghost(player, BELT, x, dy) then laid = laid + 1 end
      end
    end

    --- The bands, by the top of each. A second tier arm extends a twentieth of a tile a
    --- tick, so these are multiples of what the hand itself can do.
    local BANDS = { 0.1, 0.2, 0.4, 0.6, 0.8, 1.0, 1.4 }
    local built_in, passed_in, ticks_in = {}, {}, {}
    for i = 1, #BANDS do built_in[i], passed_in[i], ticks_in[i] = 0, 0, 0 end

    local began, was_at = game.tick, loco.position.x
    local was_left = surface.count_entities_filtered{ type = "entity-ghost",
      position = world.ORIGIN, radius = 3000 }
    local was_passed, fastest = 0, 0
    world.once(function()
      player.riding_state = { acceleration = defines.riding.acceleration.accelerating,
                              direction = defines.riding.direction.straight }
      local at = loco.position.x
      local speed = math.abs(at - was_at)
      was_at = at
      if speed > fastest then fastest = speed end
      local band = #BANDS
      for i, top in ipairs(BANDS) do if speed <= top then band = i break end end

      local left = surface.count_entities_filtered{ type = "entity-ghost",
        position = world.ORIGIN, radius = 3000 }
      built_in[band] = built_in[band] + math.max(0, was_left - left)
      was_left = left

      -- Carried past is arithmetic rather than a search: the ghosts are two to a tile from
      -- x = 6, and anything more than a reach behind the hull is gone for good.
      local behind = math.floor(at - world.ORIGIN.x - 3)
      local passed = math.max(0, math.min(behind, GHOSTS_TO) - 5) * 2
      passed_in[band] = passed_in[band] + math.max(0, passed - was_passed)
      was_passed = passed
      ticks_in[band] = ticks_in[band] + 1

      return game.tick - began > DRIVE
    end, function()
      player.riding_state = { acceleration = defines.riding.acceleration.nothing,
                              direction = defines.riding.direction.straight }
      local rows = {}
      local from = 0
      for i, top in ipairs(BANDS) do
        if ticks_in[i] > 0 then
          rows[#rows + 1] = ("%.1f-%.1f: %d ticks, %d passed, %d BUILT"):format(
            from, top, ticks_in[i], passed_in[i], built_in[i])
        end
        from = top
      end
      log(("SPEEDS | %d ghosts laid, top speed %.3f a tick, %.0f tiles driven\n    %s")
        :format(laid, fastest, loco.position.x - (world.ORIGIN.x - 20),
          table.concat(rows, "\n    ")))
      -- The whole of the point: the fastest band is not a band where nothing happens.
      -- Measured, every band from four tenths of a tile a tick upward builds between 45 and
      -- 48 of every hundred ghosts it carries the hull past, the top one included.
      local top = #BANDS
      assert.is_true(fastest > 1.0,
        ("the train only reached %.3f a tick, so this measured nothing"):format(fastest))
      assert.is_true(passed_in[top] > 200,
        ("only %d ghosts were carried past at the top speed"):format(passed_in[top]))
      assert.is_true(built_in[top] > passed_in[top] / 4,
        ("flat out, %d of the %d ghosts carried past were built"):format(
          built_in[top], passed_in[top]))
    end, "the drive never ended", DRIVE + 200)
  end)
end)
