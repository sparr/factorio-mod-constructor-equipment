--- The showroom's leading bays, walked headless.
---
--- Rows 11 and 12 are the only bays that have to be walked rather than stood on, which is
--- exactly what test/demo/probe.sh cannot do: it teleports on to each mark, and a teleport
--- is deliberately not read as a course, so it probes every bay from a standstill and
--- reports these as almost nothing built. That is right for a player who never moves and
--- says nothing about whether the bays work.
---
--- So the layouts are reproduced here and walked. Each bay's note makes a claim in front of
--- somebody who is about to watch it, and a bay that quietly stopped working looks exactly
--- like a bay demonstrating that nothing happens, which is the one failure the showroom
--- cannot show for itself.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local BELT = "transport-belt"
local ROUND_RESEARCH = { "bulk-inserter", "inserter-capacity-bonus-1",
                         "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" }

local player

before_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

after_each(function()
  player.walking_state = { walking = false }
  for _, name in ipairs(ROUND_RESEARCH) do
    local technology = player.force.technologies[name]
    if technology then technology.researched = false end
  end
  player.get_inventory(defines.inventory.character_armor).clear()
  for _, thing in ipairs(player.surface.find_entities_filtered{
        name = { BELT, "item-on-ground", "constructor-equipment-catcher" },
        position = world.ORIGIN, radius = 200 }) do
    if thing.valid then thing.destroy() end
  end
  for _, ghost in ipairs(player.surface.find_entities_filtered{ type = "entity-ghost",
        position = world.ORIGIN, radius = 200 }) do
    if ghost.valid then ghost.destroy() end
  end
  world.clear(player)
end)

---Kit the character the way the bay's own pad does.
---@param level integer which tier of arm
---@param armour string
---@param grid string[] what else goes in the grid
---@param research boolean whether the capacity research is done
local function kitted(level, armour, grid, research)
  if research then
    for _, name in ipairs(ROUND_RESEARCH) do
      local technology = player.force.technologies[name]
      if technology then technology.researched = true end
    end
  end
  player.get_inventory(defines.inventory.character_armor).clear()
  local equipment = { tiers.by_level[level].name }
  for _, name in ipairs(grid) do equipment[#equipment + 1] = name end
  world.equip(player, equipment, true, armour)
  player.insert{ name = BELT, count = 30 }
end

---Lay the bay out, walk east past it, and say how many went up.
---@param where table[] ghost offsets from the mark
---@param check fun(built: integer, journeys: integer) asked once the walk is over
local function walked_past(where, check)
  for _, at in ipairs(where) do world.ghost(player, BELT, at[1], at[2]) end
  local began, journeys, carrying = game.tick, 0, false
  world.once(function()
    player.walking_state = { walking = true, direction = defines.direction.east }
    local record = (storage.constructor_arms[player.index] or {})[1]
    local arm = record and record.entity
    local holding = (arm and arm.valid and arm.held_stack.valid_for_read) or false
    if holding and not carrying then journeys = journeys + 1 end
    carrying = holding
    return world.ghosts(player) == 0 or game.tick - began > 250
  end, function()
    player.walking_state = { walking = false }
    check(#where - world.ghosts(player), journeys)
  end, "the walk never ended", 350)
end

describe("row 11, leading", function()
  --- "The arm reaches five tiles and this belt is ten off: the claw goes to where the belt
  --- will be."
  it("bay 1: meets a belt ten tiles off a five tile arm", function()
    kitted(4, "power-armor", { "fission-reactor-equipment", "battery-equipment" })
    walked_past({ { 10, 0 } }, function(built)
      assert.are.equal(1, built, "the belt ten tiles ahead was walked past")
    end)
  end)

  --- "Keep walking east and this stays a ghost, though you pass within four tiles."
  it("bay 2: leaves a belt four tiles square to the side alone while walking", function()
    kitted(4, "power-armor", { "fission-reactor-equipment", "battery-equipment" })
    walked_past({ { 0, 4 } }, function(built, journeys)
      assert.are.equal(0, built,
        "the belt square abeam went up, so the bay's note is wrong")
      assert.are.equal(0, journeys,
        "the claw set off for something it could never reach")
    end)
  end)

  --- "Stop beside it and it goes up at once." The other half of the same bay, and what
  --- makes the pair worth walking twice: four tiles is well inside a five tile reach, so
  --- nothing about this one is out of range. Only the walk puts it out of reach.
  it("bay 2: builds that same belt for somebody standing still", function()
    kitted(4, "power-armor", { "fission-reactor-equipment", "battery-equipment" })
    world.ghost(player, BELT, 0, 4)
    after_ticks(120, function()
      assert.are.equal(0, world.ghosts(player),
        "standing still beside it did not build it, so the bay cannot say to try")
    end)
  end)

  --- "A two tile arm and a belt six tiles off, and it still gets there."
  it("bay 3: leads from a first tier arm with no reactor behind it", function()
    kitted(1, "modular-armor", { "battery-equipment" })
    walked_past({ { 6, 0 } }, function(built)
      assert.are.equal(1, built, "the first tier arm never got there")
    end)
  end)
end)

describe("row 12, rounds on the move", function()
  --- "The claw sets off holding all four and puts them down one after another without
  --- coming home."
  it("bay 1: puts a row of four down in one trip", function()
    kitted(4, "power-armor", { "fission-reactor-equipment", "battery-equipment" }, true)
    walked_past({ { 10, 2 }, { 11, 2 }, { 12, 2 }, { 13, 2 } }, function(built, journeys)
      assert.are.equal(4, built, "the row was not finished")
      assert.are.equal(1, journeys,
        "the claw came home part way through, so this is not one trip")
    end)
  end)

  --- "Two of these go up and one does not: a walking arm has only about a tile to the
  --- side." Three crammed inside that tile, each with a window of a few ticks, and the
  --- claw cannot make every swing in time. Which one is left over is not fixed, so only
  --- the count is pinned.
  it("bay 2: gets two of three crammed inside the side reach", function()
    kitted(4, "power-armor", { "fission-reactor-equipment", "battery-equipment" }, true)
    walked_past({ { 9, 1 }, { 10, 0 }, { 10, 1 } }, function(built)
      assert.are.equal(2, built,
        "the bay says two of the three go up, and that is no longer what happens")
    end)
  end)
end)
