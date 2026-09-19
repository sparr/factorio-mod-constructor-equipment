--- Building something that is not in reach yet.
---
--- One ghost in the arena and one arm, so there is nothing for an arm to choose between and
--- nothing to set off for but the thing the test put there. Whatever happens, happened
--- because of that ghost.
---
--- What separates these from every other fixture is that the character is walking. A
--- stationary wearer reaches what is in reach and nothing else, which is what the mod has
--- always done; a walking one has a claw that can be sent to where a ghost will be.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local BELT = "transport-belt"
local FOURTH = tiers.by_level[4]

--- Comfortably longer than a fourth tier reach, which takes 43 ticks, plus the walk up to
--- wherever the intercept is.
local A_WALK = 200

local player

before_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
  world.equip(player, { FOURTH.name, "battery-equipment" }, true)
  player.insert{ name = BELT, count = 5 }
end)

after_each(function()
  player.walking_state = { walking = false }
  world.clear(player)
end)

---Walk a way for a while, then stop and check.
---@param way defines.direction
---@param ticks integer
---@param done fun()
local function walk(way, ticks, done)
  local began = game.tick
  world.once(function()
    player.walking_state = { walking = true, direction = way }
    return game.tick - began > ticks
  end, function()
    player.walking_state = { walking = false }
    done()
  end, "the walk never ended", ticks + 120)
end

---Walk a way until the ghost is gone, or until patience runs out, and say when.
---@param way defines.direction
---@param ticks integer
---@param done fun(built: integer?)
local function walk_until_built(way, ticks, done)
  local began, built = game.tick, nil
  world.once(function()
    player.walking_state = { walking = true, direction = way }
    if not built and world.ghosts(player) == 0 then built = game.tick - began end
    return built ~= nil or game.tick - began > ticks
  end, function()
    player.walking_state = { walking = false }
    done(built)
  end, "the walk never ended", ticks + 120)
end

describe("a ghost that is not in reach yet", function()
  --- Ten ahead and four to the side, which is 10.8 tiles off to begin with, twice what the
  --- arm reaches. It comes inside the five tiles when its owner has covered seven of them
  --- and is gone again six tiles later, which is forty ticks of being reachable against a
  --- reach that takes forty three to make.
  ---
  --- So an arm that waits until the ghost is in range and only then sets off arrives after
  --- it has gone. This ghost cannot be built at all without leading it, which is the point
  --- of the case: leading is not a quicker way to build something here, it is the only way.
  ---
  --- Four to the side and not four and a half, and the reason is worth writing down because
  --- it cost a wrong diagnosis. A tile's middle is at n + 0.5, which is where world.ORIGIN
  --- puts the character, so an offset from there has to be a whole number of tiles to land
  --- on another middle. Half a tile lands on a corner, and a one by one ghost asked for a
  --- corner is rounded to the next middle up: measured, +3.5 and +4.25 both become +4, and
  --- +4.5 and +4.75 both become +5.
  ---
  --- So asking for four and a half puts the ghost square abeam at exactly the full reach,
  --- where nothing can ever get to it, and the test reads as the mod failing to build
  --- something it should have. Offsets here are whole tiles for that reason.
  it("is built by a character walking past it, which nothing else could do", function()
    world.ghost(player, BELT, 10, 4)
    walk_until_built(defines.direction.east, A_WALK, function(built)
      assert.is_not_nil(built, "the ghost was never built")
      assert.are.equal(1, world.count(player, BELT), "no belt was put down")
      assert.are.equal(4, player.get_item_count(BELT), "it was not paid for out of pocket")
      -- In reach from tick 47 and gone by 88. A claw that waited for it would have set off
      -- on 47 and arrived on 90, two ticks after it had gone.
      assert.is_true(built < 70,
        ("built on tick %d, which is late enough that it was not led"):format(built))
    end)
  end)

  it("is built sooner than waiting for it would allow", function()
    -- Ten ahead and three to the side, which a character does eventually walk into range
    -- of, so this one could be built either way. What says it was led is when.
    world.ghost(player, BELT, 10, 3)
    walk_until_built(defines.direction.east, A_WALK, function(built)
      assert.is_not_nil(built, "the ghost was never built")
      -- In reach from tick 41. Waiting for that and then reaching takes until 84; leading
      -- it puts the claw there as it arrives.
      assert.is_true(built < 70,
        ("built on tick %d, which is when waiting for it would have"):format(built))
    end)
  end)

  it("is left alone by a character standing still", function()
    world.ghost(player, BELT, 10, 3)
    after_ticks(A_WALK, function()
      assert.are.equal(1, world.ghosts(player),
        "a ghost ten tiles off was built by somebody who never moved")
      assert.are.equal(5, player.get_item_count(BELT), "something was paid for")
    end)
  end)
end)

describe("a ghost a walker can never catch", function()
  --- The cone an arm can reach into is a wedge opening the way its owner is going, because a
  --- character outruns their own hand: a fourth tier claw extends a tenth of a tile a tick
  --- against a walk of 0.148, so anything much off to the side is gone before the hand is
  --- out. Not reaching those is right. What is worth checking is that no swing is spent
  --- finding it out.
  ---
  --- Laid down once its owner is already under way, which is the whole of the case. A
  --- character standing still reaches what is in reach, including what is behind them, and
  --- should: it is only once they are moving that where they are going decides anything.
  ---@param dx number
  ---@param dy number
  ---@param complaint string
  local function never_reached_for(dx, dy, complaint)
    local deployed, laid = false, false
    local began = game.tick
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      local since = game.tick - began
      -- Up to speed first, so that the arm never sees a moment of standing still.
      if since == 30 then
        world.ghost(player, BELT, dx + math.floor(player.position.x - world.ORIGIN.x), dy)
        laid = true
      end
      if laid and world.arm(player) then deployed = true end
      return since > 120
    end, function()
      player.walking_state = { walking = false }
      assert.is_true(laid, "the ghost was never laid down")
      assert.is_false(deployed, complaint)
      assert.are.equal(1, world.ghosts(player), "it was built somehow")
      assert.are.equal(5, player.get_item_count(BELT), "something was paid for")
    end, "the walk never ended", 200)
  end

  it("is not reached for, square abeam at the edge", function()
    never_reached_for(0, 5, "an arm was sent out after a ghost square abeam at full reach")
  end)

  it("is not reached for behind a walker", function()
    never_reached_for(-4, 0, "an arm was sent after a ghost its owner was walking away from")
  end)

  it("is not reached for beside a walker, a tile off the line", function()
    -- Measured: a fourth tier cone is 0.94 of a tile wide square abeam, so two tiles to the
    -- side is already outside it however near it looks.
    never_reached_for(0, 2, "an arm was sent after a ghost two tiles abeam")
  end)
end)

--- Nothing is created and nothing is lost, wherever the belt has got to: in the pocket, in
--- the claw, standing on the ground as a built belt, or lying on it as an item.
---@return integer
local function belts_anywhere()
  local held = 0
  local arm = world.arm(player)
  if arm and arm.held_stack.valid_for_read and arm.held_stack.name == BELT then
    held = arm.held_stack.count
  end
  local loose = 0
  for _, item in ipairs(player.surface.find_entities_filtered{
        name = "item-on-ground", position = player.position, radius = 40 }) do
    if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
      loose = loose + item.stack.count
    end
  end
  -- Anything the claw handed over on the way is in the box it hands over through.
  local boxed = 0
  for _, box in ipairs(player.surface.find_entities_filtered{
        name = "constructor-equipment-catcher", position = player.position, radius = 40 }) do
    boxed = boxed + box.get_item_count(BELT)
  end
  return player.get_item_count(BELT) + world.count(player, BELT) + held + loose + boxed
end

describe("an owner who changes their mind mid reach", function()
  ---Walk one way, then another, and see what became of the ghost and the belt.
  ---@param first defines.direction
  ---@param then_ defines.direction? nothing at all means stopping dead
  ---@param done fun(built: boolean)
  local function turn_after(first, then_, done)
    local began = game.tick
    world.once(function()
      local since = game.tick - began
      if since < 25 then
        player.walking_state = { walking = true, direction = first }
      elseif then_ then
        player.walking_state = { walking = true, direction = then_ }
      else
        player.walking_state = { walking = false }
      end
      return since > 220
    end, function()
      player.walking_state = { walking = false }
      done(world.ghosts(player) == 0)
    end, "the walk never ended", 300)
  end

  --- A turn is not a reason to look for something else. The ghost is still the ghost, so the
  --- intercept to it is worked out again from where the hand has got to, and the reach goes
  --- on.
  it("keeps the ghost it had when the turn still leaves it reachable", function()
    world.ghost(player, BELT, 10, 4)
    turn_after(defines.direction.east, defines.direction.southeast, function(built)
      assert.is_true(built, "a ghost still well within reach after the turn was dropped")
      assert.are.equal(5, belts_anywhere(), "a belt was made or lost")
    end)
  end)

  --- And when it does not, the reach is written off rather than stretched after something
  --- its owner has turned their back on. What matters is that the belt comes home.
  it("gives up, and keeps the belt, when the turn takes it out of reach", function()
    world.ghost(player, BELT, 10, 4)
    turn_after(defines.direction.east, defines.direction.north, function(built)
      assert.is_false(built, "a ghost its owner walked away from was built anyway")
      assert.are.equal(1, world.ghosts(player), "the ghost is not standing where it was")
      assert.are.equal(5, belts_anywhere(), "a belt went missing when the reach was given up")
      assert.are.equal(5, player.get_item_count(BELT),
        "the belt never came back to the pocket")
    end)
  end)

  --- Stopping is a course change like any other: the drift falls to nothing, and a wearer
  --- going nowhere reaches what is in reach and nothing else. A ghost still seven tiles off
  --- is no longer coming.
  it("gives up, and keeps the belt, when its owner simply stops", function()
    world.ghost(player, BELT, 10, 4)
    turn_after(defines.direction.east, nil, function(built)
      assert.is_false(built, "a ghost seven tiles from a standing character was built")
      assert.are.equal(5, belts_anywhere(), "a belt went missing when the walk stopped")
      assert.are.equal(5, player.get_item_count(BELT),
        "the belt never came back to the pocket")
    end)
  end)
end)

