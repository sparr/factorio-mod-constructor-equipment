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

  for _, how in ipairs{ { name = "a quarter", speed = 0.3 },
                        { name = "half a tile a tick", speed = 0.6 } } do
    it("does not change its mind every tick, " .. how.name, function()
      local surface, y = player.surface, world.ORIGIN.y
      for x = world.ORIGIN.x + RAILS_FROM, world.ORIGIN.x + RAILS_TO, 2 do
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
      local fastest = 0
      world.once(function()
        loco.train.speed = how.speed
        fastest = math.max(fastest, math.abs(loco.train.speed))
        for slot, record in pairs(storage.constructor_arms[player.index] or {}) do
          local job = record.job
          local now = job and job.ghost and job.ghost.valid
            and ("%.1f,%.1f"):format(job.ghost.position.x, job.ghost.position.y) or nil
          if now ~= aimed[slot] then
            if now then tries[now] = (tries[now] or 0) + 1 end
            aimed[slot] = now
          end
        end
        return game.tick - began > RUN
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
        log(("TURN | %-14s top speed %.2f | %d ghosts, %d BUILT, %d still standing, %d of"
          .. " those had an arm set off for them, worst %s at %d attempts"):format(
          how.name, fastest, #ghosts, #ghosts - missed, missed, attempted,
          tostring(where), most))
        -- The pathology was a claw alternating between two or three neighbours a tick
        -- apiece: nine attempts on one ghost and a delivery to none of them. One or two
        -- attempts on something the train simply carried past is ordinary.
        assert.is_true(most <= 3,
          ("an arm set off for the ghost at %s %d times and never delivered to it")
            :format(tostring(where), most))
        assert.is_true(#ghosts - missed > #ghosts / 3,
          ("only %d of %d were built"):format(#ghosts - missed, #ghosts))
      end, "the run never ended", RUN + 100)
    end)
  end
end)
