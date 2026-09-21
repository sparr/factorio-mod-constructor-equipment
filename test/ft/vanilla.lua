--- SCRATCH: the same fault with nothing of this mod's in it.
---
--- A stock inserter, a stock chest to take from, and a stock belt in front of it marked for
--- deconstruction. No custom vectors, no teleporting, no script driving it at all beyond
--- keeping it fuelled: everything is where the prototype puts it.
local world = require("test.ft.world")

local BELT = "transport-belt"
local WATCH = 400

local STATUS = {}
for name, value in pairs(defines.entity_status) do STATUS[value] = name end

describe("a stock inserter with something marked in front of it", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  local CASES = {
    { name = "burner inserter, the belt marked",      kind = "burner-inserter", mark = true },
    { name = "burner inserter, the belt not marked",  kind = "burner-inserter" },
    { name = "electric inserter, the belt marked",    kind = "inserter", mark = true },
    { name = "electric inserter, the belt not marked", kind = "inserter" },
    { name = "burner inserter, a marked chest in front", kind = "burner-inserter",
      mark = true, front = "iron-chest" },
    { name = "burner inserter, the source behind it marked", kind = "burner-inserter",
      mark_source = true },
  }

  for _, case in ipairs(CASES) do
    it("PROBE: " .. case.name, function()
      local surface = player.surface
      local at = { x = world.ORIGIN.x + 20.5, y = world.ORIGIN.y + 0.5 }

      local arm = surface.create_entity{ name = case.kind, position = at,
        direction = defines.direction.north, force = player.force }
      assert.is_not_nil(arm, "the inserter would not go down")
      if case.kind == "burner-inserter" then
        -- By name. A burner inserter has no main inventory, so a plain insert on the entity
        -- puts the coal nowhere and it never runs -- which reads exactly like the fault.
        local fuel = arm.get_fuel_inventory()
        assert.is_not_nil(fuel, "a burner inserter with no fuel inventory")
        fuel.insert{ name = "coal", count = 50 }
        assert.is_true(fuel.get_item_count("coal") > 0, "the coal did not go in")
      end

      -- Wherever the prototype says its two ends are, read back rather than assumed.
      local pick = arm.pickup_position
      local drop = arm.drop_position

      local source = surface.create_entity{ name = "iron-chest",
        position = { math.floor(pick.x) + 0.5, math.floor(pick.y) + 0.5 },
        force = player.force }
      assert.is_not_nil(source, "the chest would not go down")
      source.insert{ name = BELT, count = 50 }

      local front = surface.create_entity{ name = case.front or BELT,
        position = { math.floor(drop.x) + 0.5, math.floor(drop.y) + 0.5 },
        direction = defines.direction.east, force = player.force }
      assert.is_not_nil(front, "the thing in front would not go down")
      if case.mark then front.order_deconstruction(player.force) end
      if case.mark_source then source.order_deconstruction(player.force) end

      local began, went, last = game.tick, 0, nil
      world.once(function()
        if case.kind == "inserter" then
          arm.energy = arm.prototype.get_max_energy_usage() * 100
        end
        local hand = arm.held_stack_position
        if last then went = went + math.sqrt((hand.x - last.x) ^ 2 + (hand.y - last.y) ^ 2) end
        last = { x = hand.x, y = hand.y }
        return game.tick - began > WATCH
      end, function()
        log(("VANILLA | %-44s pickup %.1f,%.1f drop %.1f,%.1f | hand travelled %6.2f,"
          .. " %d of 50 left in the chest, status %s"):format(
          case.name, pick.x, pick.y, drop.x, drop.y, went,
          source.valid and source.get_item_count(BELT) or -1,
          STATUS[arm.status] or tostring(arm.status)))
      end, "never ran", WATCH + 60)
    end)
  end
end)

--- The console commands themselves, run as written.
---
--- test/stall/console.lua keeps them as strings precisely so that this can load and run the
--- exact text that gets handed to somebody. A paraphrase would prove nothing about what they
--- actually paste.
describe("the console commands in test/stall/console.lua", function()
  local player
  local COMMANDS = require("test.stall.console")

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  local function run(name)
    for _, command in ipairs(COMMANDS) do
      if command.name == name then
        local chunk, why = load(command.code, name)
        assert.is_not_nil(chunk, ("the %s command would not even compile: %s"):format(
          name, tostring(why)))
        local ok, err = pcall(chunk)
        assert.is_true(ok, ("the %s command errored: %s"):format(name, tostring(err)))
        return
      end
    end
    error("there is no command called " .. name)
  end

  ---@return LuaEntity?
  local function inserter()
    return player.surface.find_entities_filtered{ name = "burner-inserter",
      position = player.position, radius = 10 }[1]
  end

  it("builds a rig whose hand does not move, and frees it when the mark comes off", function()
    run("build")
    run("say")
    local arm = player.surface.find_entities_filtered{ name = "inserter",
      position = player.position, radius = 10 }[1]
    assert.is_not_nil(arm, "the build command put down no inserter")
    local chest = player.surface.find_entities_filtered{ name = "iron-chest",
      position = { math.floor(arm.pickup_position.x) + 0.5,
                   math.floor(arm.pickup_position.y) + 0.5 }, radius = 0.4 }[1]
    assert.is_not_nil(chest, "the build command put no chest at the pickup end")
    assert.is_true(chest.get_item_count(BELT) > 0, "the chest behind it is empty")

    local front = player.surface.find_entities_filtered{ name = BELT,
      position = { math.floor(arm.drop_position.x) + 0.5,
                   math.floor(arm.drop_position.y) + 0.5 }, radius = 0.4 }[1]
    assert.is_not_nil(front, "the build command put no belt at the drop end")
    assert.is_true(front.to_be_deconstructed(), "the belt in front is not marked")

    local start = { x = arm.held_stack_position.x, y = arm.held_stack_position.y }
    local held = chest.get_item_count(BELT)
    after_ticks(WATCH, function()
      -- Powered, and known to be: an unpowered inserter also sits perfectly still and would
      -- pass every assertion below while proving nothing. Asked here rather than on the tick
      -- it was built, because an electric network needs a tick before it is supplying.
      assert.is_true(arm.status ~= defines.entity_status.no_power
        and arm.status ~= defines.entity_status.low_power,
        "the build command left the inserter unpowered, so a still hand means nothing: "
          .. tostring(STATUS[arm.status]))
      local hand = arm.held_stack_position
      assert.are.equal(start.x, hand.x, "the hand moved: this should stall")
      assert.are.equal(start.y, hand.y, "the hand moved: this should stall")
      assert.are.equal(held, chest.get_item_count(BELT), "it moved something: should stall")
      assert.are.equal("disabled", STATUS[arm.status],
        "a stalled one reports itself disabled; this said " .. tostring(STATUS[arm.status]))
      -- and now take the mark off
      run("toggle")
    end)

    after_ticks(WATCH * 2, function()
      assert.is_true(chest.get_item_count(BELT) < held,
        "taking the mark off did not get it going again")
    end)
  end)
end)
