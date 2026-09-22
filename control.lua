local build = require("lib.build")
local tiers = require("lib.tiers")
local power = require("lib.power")
local pack = require("lib.pack")
local reach = require("lib.reach")

--- How far an arm reaches and how often it may set off both depend on which tier it is,
--- so they live in lib/tiers.lua where the data stage reads the same numbers.
local CHECK_PER_SECOND = 10
--- Nothing about the cost of building is decided here. The arm is a real electric inserter
--- with nothing to plug into, so it is fed by hand out of the armour every tick and the
--- engine does the billing at the base game's prices for the inserter that tier borrows
--- from. How much an armour must be holding before an arm will set off is per tier too --
--- a couple of that tier's reaches, from lib/tiers.lua -- so that an arm never stops
--- halfway with an item in its hand.

--- Every set of slowdown stickers there is: two per tier that asks for the penalty, one
--- for whatever walks or rolls and one for whatever strides. See prototypes/sticker.lua for
--- why they are stickers rather than a number on the character, and why the same penalty
--- has to be written down twice, and lib/tiers.lua for which tiers have any at all.
---
--- All of them in one list, because the one thing slowing a wearer must do is take every
--- other set off them: they are separate prototypes, so any two the engine keeps are
--- multiplied together, and that includes the two kinds of the same tier's own.
local SETS = {}
for _, tier in ipairs(tiers.list) do
  if tier.stickers then
    table.insert(SETS, tier.stickers)
    table.insert(SETS, tier.stickers.legs)
  end
end

---Which of a tier's two sets of stickers a wearer takes: the legged one if it strides,
---and the one that serves characters and wheels otherwise.
---@param wearer LuaEntity
---@param set table a tier's stickers, from lib/tiers.lua
---@return table
local function stickers_for(wearer, set)
  if wearer.type == "spider-vehicle" and set.legs then return set.legs end
  return set
end


local CHECK_INTERVAL = 60 / CHECK_PER_SECOND
local CHECK_TICK = CHECK_INTERVAL / 2


--- How far off the mounting point the claw is aimed when it has nowhere else to be.
---
--- Not at the mounting point itself. An inserter's hand goes home to its pickup position,
--- and a pickup sitting exactly on the arm's own base is no direction at all: the engine
--- picks one to fold through, and it picked east, so the claw swung out to full stretch
--- sideways before coming home. Anything off the base at all cures that.
---
--- Two tenths because that is where the claw ends up closest to the character, not because
--- it is the smallest that works. The hand will not retract inside a minimum extension of
--- its own, so aiming it nearer than that gains nothing, and aiming it further simply holds
--- it further out: measured against the mounting point, it rests 0.18 away at nought, 0.08
--- at a tenth, 0.02 at two tenths, and 0.42 at six tenths.
local REST = 0.2

--- How close the hand has to get to the character to count as home again.
---
--- A floor rather than an answer: lib/reach.lua widens it to cover however fast the hand in
--- question is actually moving, because a window narrower than a tick of travel is one the
--- hand steps over, and the engine then finishes the swing by dropping the load.
local HOME = 0.4

--- How far from its rest point a hand still is once it has come as far in as it can.
---
--- A hand cannot come closer to its own base than where a fresh one is born, and the rest
--- point is deliberately nearer than that: close enough that the engine can never reach it,
--- and so can never let go of a load there and put it on the ground. What that costs is
--- that a claw which has arrived is still this far from the point its arrival is measured
--- against, so the homecoming window has to be at least this wide.
---
--- It was not, and a claw that never had to travel was never seen to arrive at all. A fetch
--- from under its owner's own feet picked the item up, came in to its birth radius, and sat
--- there holding it until the swing limit gave up on it -- once per item, so a block of
--- nine laid round somebody's feet gave up one and left the other eight on the ground. A
--- claw with a journey behind it got home only because the window widens by what the hand
--- was last seen covering, and a claw that has not moved has covered nothing.
---
--- A tick of travel is allowed on top of it wherever it is used. A hand does not come to
--- rest at exactly this radius on a mount that is moving -- it lags its own base by up to a
--- step -- and an arm on a train was measured home and empty at 0.73 out, holding a job it
--- had finished for eighty three ticks because the window stopped a hair short of that.
local RETRACTED = reach.BORN - REST

--- How little a hand has to move in a tick to count as having stopped.
---
--- What says a claw being folded away has arrived. An ordinary reach is called home as soon
--- as the hand is within HOME of the rest point, which is early on purpose: the load is
--- handed over and the next reach can start without waiting out the last tenth of the
--- retraction. Nothing follows a fold, and being early there is the whole of what the walk
--- round saw -- the button took the arm away with the claw still 0.63 of a tile out and the
--- belt still in it, so the item winked out in mid air and the claw jumped the rest of the
--- way to the stowing position.
---
--- Asked as "has it stopped" rather than as a distance, because how near the base a hand
--- can actually get is not a number the mod owns: a hand will not retract inside a minimum
--- extension of its own, and where that leaves it depends on the tier, on the bearing it
--- came in along and on how far up its owner the arm is strapped. Measured on a first tier
--- arm folding from a two tile reach, it settles 0.19 from the base and stays there. So the
--- claw is home when it has come as far in as it is going to.
local SETTLED = 0.01

---How close is close enough for one arm. See lib/reach.lua, which the tests measure the
---real thing against.
---@param tier table
---@param threshold number
---@return number
local function within(tier, threshold, moved)
  return reach.within(tier, threshold, moved)
end

--- How long the claw takes to shrink away once the arm is stowed, and how far into that
--- it also fades. Short: it is punctuation on the end of a job, not an animation anybody
--- should have to wait through.
local STOW_TICKS = 18

--- The game's own low power mark, borrowed rather than drawn again: the yellow bolt it puts
--- over a machine that has not the charge to work. utility/electricity_icon_unplugged is the
--- other one it has, and says nothing is connected, which is not this arm's trouble.
local POWER_ICON = "utility/electricity_icon"

--- How long a low power mark lives without being renewed. Longer than the gap between the
--- ticks that renew it, so it never blinks, and short enough that one left behind is gone
--- before anybody reads it as a fault.
local MARK_TICKS = 30

--- How long the arm stays out after the last thing it did. An arm that vanished the moment
--- a swing ended would flicker between one ghost and the next; one that never vanished
--- would be worn to bed.
local IDLE_TICKS = 60

--- How long an arm is given to move again before it is taken to be going nowhere.
---
--- An armour that dies partway through a reach leaves the claw where it stands: an empty
--- buffer moves a hand no distance at all, so the arm can neither finish what it set off
--- for nor come home from it. Left alone it hangs at full stretch until the swing limit
--- below writes the whole reach off, five seconds later, holding a load its owner has
--- already been charged for.
---
--- Long enough that a trickle of charge is not mistaken for none. An arm being fed slowly
--- creeps rather than stopping, and any movement at all starts this over.
local STRANDED_TICKS = 60

--- How long a swing is allowed to take before it is written off.
---
--- Nothing should need this: a reach that cannot finish is a fault somewhere else. It is
--- here because the failure it prevents is the mod quietly stopping for good, which is
--- much worse than a swing that gives up early and tries again.
local SWING_LIMIT = 300

--- 2.0 renamed the save table from global to storage, and filling it in at load time is
--- no longer allowed: the file is run before the save is read, so anything put there
--- would be thrown away or would desync. It is set up on_init instead, and again on
--- configuration_changed for a save that predates this.
---
--- Everything about a player's arms lives in one list per player, one entry per arm:
---
---   { entity = the inserter, job = what it is reaching for, busy = when it last had
---     something to do, last = when it last started a reach }
---
--- rather than four tables keyed by player index, which is what it was when there could
--- only ever be one arm.
local function setup()
  storage.constructor_arms = storage.constructor_arms or {}
  -- claws part way through being stowed, by the id of the sprite drawn for each
  storage.constructor_stowing = storage.constructor_stowing or {}
  -- arms switched off part way through a reach, on their way home before being put away
  storage.constructor_folding = storage.constructor_folding or {}
  -- whether the ramp into the slowdown has already been run for the run in progress
  storage.constructor_ramped = storage.constructor_ramped or {}
  -- who has switched their arms off from the toolbar, by player index
  storage.constructor_off = storage.constructor_off or {}
  storage.constructor_shunned = storage.constructor_shunned or {}
  -- what each player's button was last told, so it is only set when it changes
  storage.constructor_button = storage.constructor_button or {}
  -- where each player's wearer stood last tick, and how far they moved to get there
  storage.constructor_drift = storage.constructor_drift or {}

  -- One arm per player, in four parallel tables, is what a save from before multiple
  -- equipment looks like. The arms themselves are entities in the world, so they are taken
  -- away rather than merely forgotten, and everyone starts again from nothing.
  if storage.constructor_inserter then
    for _, arm in pairs(storage.constructor_inserter) do
      if arm and arm.valid then arm.destroy() end
    end
    storage.constructor_inserter = nil
    storage.constructor_busy = nil
    storage.constructor_reach = nil
    storage.constructor_arms = {}
  end
  storage.constructor_last_build_tick = nil

  -- Older versions slowed the character by writing character_running_speed_modifier and
  -- remembering what had been there. A save from one of those can be carrying a player
  -- left at quarter speed, because the value was only put back on the tick after a build
  -- that did not happen. Give it back and forget the bookkeeping.
  local saved = storage.constructor_saved_running_speed_modifier
  if saved then
    for index, previous in pairs(saved) do
      local player = game.get_player(index)
      if player and player.character_running_speed_modifier == -0.75 then
        player.character_running_speed_modifier = previous or 0
      end
    end
    storage.constructor_saved_running_speed_modifier = nil
  end
end

--- The toolbar button, the key binding, and the entry that remembers who has pressed
--- either. One name, because they are one thing to a player. See prototypes/shortcut.lua.
local TOGGLE = "constructor-equipment-toggle"

---Whether this player has switched their arms off.
---
---Theirs alone. The equipment is worn by one person and the button sits in one person's
---toolbar, so a player who wants their arms to stop does not stop anybody else's.
---@param player LuaPlayer
---@return boolean
local function switched_off(player)
  return storage.constructor_off[player.index] or false
end

---What a player's arms hang off, and whose grid feeds them.
---
---A driver's own armour is out of the question: they are sat in a vehicle rather than
---walking about in it, so arms strapped to their back would be swinging about inside the
---cab. What a vehicle has instead is a grid of its own, and the equipment goes in it as
---readily as into armour -- every grid in the base game takes the same category of
---equipment -- so while somebody is driving, the vehicle is what wears the arms, pays for
---them out of its own grid, and takes the slowdown they ask for.
---
---The driver's, and nobody else's. One grid worn by two people would put two sets of arms
---on the same equipment, and a passenger would double what the vehicle can do by climbing
---in. A passenger is in a vehicle all the same, so their armour is off too: they get
---nothing until they take the wheel or get out.
---@param player LuaPlayer
---@return LuaEntity? the character, or the vehicle they are driving, or nothing at all
local function wearer_of(player)
  local vehicle = player.vehicle
  if not vehicle then return player.character end
  if not vehicle.valid then return nil end
  local driver = vehicle.get_driver()
  if not driver then return nil end
  -- a driver who has a character is that character; one without is the player themselves
  if driver == player.character or driver == player then return vehicle end
  return nil
end

---The pockets an arm spends out of and hands things back to.
---
---Whoever is wearing the arms pays for them. On foot that is the player's own inventory,
---which is where it has always come from. In a vehicle it is the vehicle's own hold: the
---arms are the vehicle's, and a driver who loads the boot has said what the vehicle is to
---build with. It also means a vehicle left to build does not quietly empty the pockets of
---whoever happens to be sat in it.
---
---A locomotive has no hold of its own: the prototype has nowhere to put one, so its only
---inventory is a three slot burner box and an insert of anything else into one takes
---nothing. What a train carries is in its wagons, so that is what a locomotive's arms build
---out of and hand back into.
---
---The first wagon holding anything, or failing that the first wagon at all. A train hauling
---one thing is what this is for, and it is not meant to be more than that: nothing here
---looks for the wagon nearest the work, splits a load across several, or asks which end of
---the train an arm is on.
---
---A vehicle with nowhere to put anything and no wagons behind it has no pockets, and an arm
---on one finds nothing to build with rather than reaching into its driver's.
---@param player LuaPlayer
---@param wearer LuaEntity? the character or vehicle the arms are on
---@return LuaInventory?
local function pockets(player, wearer)
  if wearer and wearer.valid and wearer.type ~= "character" then
    local hold = wearer.get_inventory(defines.inventory.car_trunk)
        or wearer.get_inventory(defines.inventory.spider_trunk)
    if hold then return hold end
    if wearer.type == "locomotive" and wearer.train then
      local first
      for _, wagon in pairs(wearer.train.cargo_wagons) do
        local inside = wagon.valid and wagon.get_inventory(defines.inventory.cargo_wagon)
        if inside then
          if not inside.is_empty() then return inside end
          first = first or inside
        end
      end
      if first then return first end
    end
    return wearer.get_output_inventory()
  end
  -- the separate quickbar went away in 0.17; what is left is the character's own
  -- inventory, and the quickbar is a set of references into it
  return player.get_inventory(defines.inventory.character_main)
end

---The stack on the cursor, when it is the thing being asked about and its owner's own.
---
---A stack picked up on to the cursor is out of the inventory while it is held there. So a
---player holding their only belts, which is what holding them to place one by hand means,
---looked to every arm like a player carrying no belts at all, and the whole set went quiet
---at the moment they were most obviously working. It is still theirs and still in reach of
---their own equipment, so it is counted and spent like any other pocket.
---
---Theirs only: a vehicle pays out of its own hold, and whatever its driver happens to be
---holding is not in it.
---@return LuaItemStack?
local function on_cursor(player, wearer, name, quality)
  if wearer and wearer.valid and wearer.type ~= "character" then return nil end
  local stack = player and player.cursor_stack
  if not (stack and stack.valid and stack.valid_for_read) then return nil end
  if stack.name ~= name then return nil end
  if (stack.quality and stack.quality.name or "normal") ~= (quality or "normal") then
    return nil
  end
  return stack
end

---How many of something its owner has, pockets and cursor together.
---@return integer
local function stock_of(player, wearer, inventory, name, quality)
  local total = inventory and inventory.get_item_count{ name = name, quality = quality } or 0
  local stack = on_cursor(player, wearer, name, quality)
  return total + (stack and stack.count or 0)
end

---Take some, out of the pockets first and off the cursor for the rest.
---@return integer how many were actually taken
local function spend(player, wearer, inventory, name, quality, count)
  local taken = inventory
    and inventory.remove{ name = name, quality = quality, count = count } or 0
  if taken >= count then return taken end
  local stack = on_cursor(player, wearer, name, quality)
  if not stack then return taken end
  local more = math.min(count - taken, stack.count)
  if more <= 0 then return taken end
  -- A cursor stack taken down to nothing has to be cleared rather than set to zero, which
  -- is what putting it down means.
  if more >= stack.count then stack.clear() else stack.count = stack.count - more end
  return taken + more
end

---Hand back what spend() took and the journey turned out not to want.
---
---The pockets first, and the cursor for anything they will not take: the reason the stack
---was on the cursor at all may well be that there is no room for it anywhere else.
local function refund(player, wearer, inventory, name, quality, count)
  if count <= 0 then return end
  local back = inventory
    and inventory.insert{ name = name, quality = quality, count = count } or 0
  local over = count - back
  if over <= 0 then return end
  local stack = player and player.cursor_stack
  if not (stack and stack.valid) then return end
  if stack.valid_for_read then
    if on_cursor(player, wearer, name, quality) then stack.count = stack.count + over end
  else
    stack.set_stack{ name = name, quality = quality, count = over }
  end
end

---One of this mod's stickers on a wearer, if it is there.
---@param wearer LuaEntity
---@param name string
---@return LuaEntity?
local function sticker_on(wearer, name)
  for _, sticker in pairs(wearer.stickers or {}) do
    if sticker.valid and sticker.name == name then return sticker end
  end
  return nil
end

---Slow whoever is wearing the arms down, or keep them slowed if they already are.
---
---Character or vehicle, and the same fraction of speed either way. A sticker carries a
---figure for a character and a figure for a vehicle and the engine uses whichever suits
---what it lands on, and where one figure will not do for both kinds of vehicle there is a
---second set to pick from: see stickers_for above and prototypes/sticker.lua.
---
---Slowing is in two parts. The first build of a run puts on the slowing sticker, which
---interpolates from full speed down to the tier's own figure over its lifetime, so the
---character leans into the work rather than stopping dead. When that has run its course
---the flat sticker takes over and holds them there for as long as there is building to do.
---
---Putting the same sticker on a character who already has it does not give them two: the
---engine keeps the one and starts its life over. That is what makes a run of builds one
---unbroken slowdown, and it is also why the slowing sticker must be left alone while it
---runs: refreshing it would start the ramp again and the character would surge.
---
---Every other set has to go, whichever this one is. They are separate prototypes, so the
---engine would keep them all and multiply them together, and someone who put a second arm
---on would end up slower than either arm asks for. The recovery stickers go for the same
---reason, plus one of their own: a character who started speeding up and then found
---something else to build would otherwise keep the tail of the ramp as well.
---@param player LuaPlayer
---@param wearer LuaEntity? the character or vehicle the arms are on

--- Put one of this mod's stickers on a wearer, if it will take one.
---
--- Not everything does. Rolling stock does not, and create_entity raises over it rather
--- than returning nothing, so the first tick after a player climbed into a locomotive
--- wearing arms took the whole session down. There is no prototype field to ask, so it is
--- tried once and the answer remembered against the name.
---
--- Nothing is lost by the refusal. The sticker is how the arms charge their owner part of
--- their speed, and a train's speed is not a thing a sticker can touch, so arms on one are
--- free to carry -- which is a fair price for a vehicle that cannot turn aside to build.
---@param wearer LuaEntity
---@param name string
local refuses = {}
local function stick(wearer, name)
  if refuses[wearer.name] then return end
  local ok = pcall(function()
    wearer.surface.create_entity{ name = name, position = wearer.position, target = wearer }
  end)
  if not ok then refuses[wearer.name] = true end
end

---@param set table which tier's stickers, from lib/tiers.lua
---Global for the same reason press() is: a test cannot climb into a locomotive wearing
---arms, because a locomotive has no equipment grid to wear them in, so the only way to
---exercise the sticker on one is to call this.
function slow(player, wearer, set)
  if not (wearer and wearer.valid) then return end
  set = stickers_for(wearer, set)
  for _, other in ipairs(SETS) do
    local recovery = sticker_on(wearer, other.recovery)
    if recovery then recovery.destroy() end
    if other ~= set then
      local flat = sticker_on(wearer, other.flat)
      if flat then flat.destroy() end
      local slowing = sticker_on(wearer, other.slowing)
      if slowing then slowing.destroy() end
    end
  end

  local flat = sticker_on(wearer, set.flat)
  if flat then
    -- already at the bottom of the ramp; keep it there
    stick(wearer, set.flat)
    return
  end

  -- Part way down. Left to run: refreshing it would start the descent again and the
  -- character would surge. It is not swapped for the flat sticker early either, which is
  -- what this used to do -- the ramp ends at exactly the speed the flat sticker holds, so
  -- letting it expire on its own makes the handover invisible, where swapping out with a
  -- fifth of its life left was a step change in speed.
  if sticker_on(wearer, set.slowing) then return end

  -- Neither is on. Whether that means the ramp has not run yet or that it has been and
  -- gone is not something the character can be asked, because an expired sticker leaves
  -- nothing behind, so it is remembered instead.
  --
  -- Reading it off the sticker was the bug. A run of building is not continuous: an arm
  -- that gets home before its clock is due waits a few ticks, and a ramp that ran out in
  -- one of those gaps was replaced by a second ramp rather than by the flat sticker. The
  -- character kept easing towards a speed they never reached.
  if storage.constructor_ramped[player.index] then
    stick(wearer, set.flat)
    return
  end

  -- The ramp is cosmetic, and a missing sticker prototype is not worth ending someone's
  -- game over. It can go missing for a real reason: game.reload_mods() reloads a mod's
  -- scripts but not its prototypes, so a script that has just learnt about a new sticker
  -- runs against data that has never heard of it. That crashed a session.
  if not prototypes.entity[set.slowing] then
    stick(wearer, set.flat)
    return
  end
  storage.constructor_ramped[player.index] = true
  stick(wearer, set.slowing)
end

---Let a wearer who has run out of things to build come back up to speed.
---
---The slowdown is flat while there is work, because its own life keeps being restarted
---and the interpolation would restart with it -- which would read as stuttering rather
---than as effort. The ramp belongs at the end, where there is one of it. So the flat
---sticker is swapped for one that interpolates from where it left off back to full speed
---over its lifetime, and the engine walks it up as its life runs down.
---
---Whichever set is on is the one that ramps off, so the character comes back up from the
---speed they were actually walking at rather than from some other tier's.
---@param player LuaPlayer
---@param wearer LuaEntity? the character or vehicle the slowdown is on
local function recover(player, wearer)
  storage.constructor_ramped[player.index] = nil
  if not (wearer and wearer.valid) then return end
  for _, set in ipairs(SETS) do
    local slowdown = sticker_on(wearer, set.flat) or sticker_on(wearer, set.slowing)
    if slowdown then
      slowdown.destroy()
      if prototypes.entity[set.recovery] then stick(wearer, set.recovery) end
      return
    end
  end
end

---Which tiers of the equipment this wearer has in its grid, one entry per copy.
---
---One arm each, whatever mixture they are wearing, and each arm has its own tier's reach
---and its own tier's clock. Separate from being able to use them: the arms are strapped to
---their back whether or not there is any charge to work them with, so this is what decides
---how many are drawn and what they look like.
---
---Best tier first, so that the strongest arms take the top of the circle on the back
---rather than whichever the grid happened to list first. Deterministic either way, which
---matters: the order decides which arm is which slot, and an order that wandered would
---have the arms swapping places on someone's back.
---@param wearer LuaEntity? a character or a vehicle, from wearer_of
---@return integer[] the level of each arm
local function worn(wearer)
  local found = {}
  if not (wearer and wearer.valid) then return found end
  local grid = wearer.grid
  if not (grid and grid.valid) then return found end

  local counted = {}
  -- 2.0 turned get_contents into a list of { name, count, quality } rather than a
  -- table keyed by name, so it is searched instead of indexed
  for _, equipment in pairs(grid.get_contents()) do
    local tier = tiers.of(equipment.name)
    if tier then
      counted[tier.level] = (counted[tier.level] or 0) + (equipment.count or 1)
    end
  end
  for level = #tiers.list, 1, -1 do
    for _ = 1, counted[level] or 0 do
      table.insert(found, level)
    end
  end
  return found
end

---Whether this wearer has any of the equipment in its grid at all.
---@param wearer LuaEntity?
---@return boolean
local function wearing(wearer)
  return #worn(wearer) > 0
end

---What one arm is, from what a record remembers of it.
---@param record table
---@return table
local function tier_of(record)
  return tiers.by_level[record.level] or tiers.list[1]
end

--- How far a wearer can move in a tick and still be said to have travelled, in tiles.
---
--- Anything further is not a course, it is a jump: a teleport, a respawn, a script putting
--- somebody somewhere. The two positions either side of one say nothing whatever about where
--- their owner is going, and taking them for a course is not merely useless but expensive,
--- because everything downstream scales with it. The search is drawn a reach plus half the
--- ground its owner will cover while a hand is out, so a hundred and twenty tile jump asks
--- the engine for a circle two and a half thousand tiles across -- twenty one million tiles
--- of ground, which does not come back inside a tick, or a minute.
---
--- Two tiles a tick is comfortably past anything that travels. Measured on straight rail,
--- a locomotive tops out at 1.2031 tiles a tick -- 260 km/h, and the same on coal, solid
--- fuel, rocket fuel and nuclear fuel, since what the fuel buys is acceleration rather than
--- a higher ceiling. That is the fastest wearer there is; a car does 0.54 and a walk 0.15. A
--- wearer
--- genuinely faster than this is only underestimated, which the intercept absorbs the same
--- way it absorbs a vehicle accelerating: the course is worked out again next tick.
local LEAP = 2

---How far a wearer went last tick.
---
---Measured rather than asked for: a character answers walking_state, a car answers speed and
---orientation, a spidertron answers neither in the same units and a train answers for the
---whole train, where the difference between two positions is the same answer for all of
---them, needs no model of any of them, and is what happened rather than what was meant to.
---
---Asked once a tick and remembered, because three things read it now -- where to search,
---whether a reach is worth setting off on, and how far ahead to aim -- and three arms
---working off three measurements of the same walk would disagree about which way their
---owner was going.
---
---Nought on the tick a wearer changes, since the step from a character's position to the
---car they have just climbed into is not a walk. Nought as well when the step is further
---than anything can travel in a tick: see LEAP.
---@param player LuaPlayer
---@param wearer LuaEntity
---@return {x: number, y: number}
local function drift_of(player, wearer)
  local seen = storage.constructor_drift[player.index]
  if seen and seen.tick == game.tick then return seen.drift end
  local at = wearer.position
  local drift = { x = 0, y = 0 }
  -- The same ground as well as the same wearer: a step from one surface to another is not a
  -- walk, and the coordinates either side of one have nothing to do with each other.
  if seen and seen.wearer == wearer.unit_number and seen.surface == wearer.surface.index then
    local dx, dy = at.x - seen.x, at.y - seen.y
    if dx * dx + dy * dy <= LEAP * LEAP then drift = { x = dx, y = dy } end
  end
  storage.constructor_drift[player.index] = {
    tick = game.tick, x = at.x, y = at.y, wearer = wearer.unit_number,
    surface = wearer.surface.index, drift = drift,
  }
  return drift
end

---Whether an arm can afford to set off, which is a question about its own equipment.
---
---A full buffer, and nothing else. The equipment holds exactly one reach's reserve, so
---full is the only figure worth asking about, and the armour fills it from empty in a few
---ticks: an arm that has just finished one reach waits no noticeable time for the next.
---Asking for some fraction of a larger buffer was a second number saying the same thing.
---@param record table
---@return boolean
local function ready(record)
  local piece = record.piece
  if not (piece ~= nil and piece.valid) then return false end
  -- What it must be holding, not all it can hold. A buffer that something is drawing from
  -- is never exactly full, and an arm out on its owner's back draws its inserter's standing
  -- drain whether it is working or not. See tiers.DEPARTURE.
  return piece.energy >= tier_of(record).departure
end

---The pieces of a given tier's equipment in a grid, in a settled order.
---@param grid LuaEquipmentGrid
---@param name string
---@return LuaEquipment[]
local function pieces_of(grid, name)
  local found = {}
  for _, equipment in pairs(grid.equipment) do
    if equipment.name == name then table.insert(found, equipment) end
  end
  return found
end

---Take up to this much out of a piece of equipment, and say how much there was.
---@param piece LuaEquipment?
---@param wanted number
---@return number
local function draw(piece, wanted)
  if not (piece and piece.valid) then return 0 end
  local take = math.min(piece.energy, wanted)
  if take > 0 then piece.energy = piece.energy - take end
  return take
end

---Put energy back where it came from: into the arm's own equipment first, and into
---anything else in the grid that will hold it for what does not fit.
---
---The overflow matters. The armour keeps the equipment's buffer topped up, so it is
---usually full, and without somewhere else to put it an arm being put away would simply
---lose whatever was left in it. Coming and going used to hand out free charge; it should
---not cost any either.
---@param grid LuaEquipmentGrid?
---@param piece LuaEquipment?
---@param amount number
local function refund(grid, piece, amount)
  if amount <= 0 then return end
  if piece and piece.valid then
    local room = piece.max_energy - piece.energy
    local give = math.min(room, amount)
    if give > 0 then
      piece.energy = piece.energy + give
      amount = amount - give
    end
  end
  if not (grid and grid.valid) then return end
  power.spill(grid.equipment, amount)
end

---Whether an arm can afford one more delivery and the journey home afterwards.
---
---Setting off in the first place wants a full buffer. Carrying on wants less than that --
---the claw is already out -- but it wants something, or an arm with a queue keeps turning
---to fresh ghosts until it runs dry somewhere out at the end of its own arm and stands
---there until the swing limit gives up on it. One reach's worth is the measure.
---
---Enough even for the worst hop. A claw going from due east to due west travels half a
---circle at full stretch, which is further than the reach itself, so a reach's worth
---sounds tight. It is not: almost all of what a journey costs is extending out and
---retracting home, and swinging round costs very little. Measured on the fourth tier at
---its full five tiles, where a reach's worth is 200kJ, a whole journey out and back came
---to 190kJ, a second delivery a quarter turn away added 3kJ, and one a half turn away
---added 14kJ. The hop and the retraction home together are about half of what this asks
---for.
---@param record table
---@param arm LuaEntity
---@return boolean
local function afford_another(record, arm)
  local piece = record.piece
  local in_hand = (arm and arm.valid) and arm.energy or 0
  local in_store = (piece and piece.valid) and piece.energy or 0
  return in_hand + in_store >= tier_of(record).reach_energy
end

---Fill the arm's buffer back up out of the armour.
---
---The arm is an electric inserter standing on no network, so this is the whole of its
---supply. Doing it this way rather than charging a flat rate per delivery means the engine
---decides what things cost: moving costs what moving costs, and a reach right across the
---range costs more than one to the next tile. It also means an armour that has run dry
---stops the arm where it is, mid swing, instead of the mod noticing later.
---@param record table the arm, which knows which piece of equipment is its own
---@param arm LuaEntity
local function charge(record, arm)
  local short = arm.electric_buffer_size - arm.energy
  if short > 0 then
    arm.energy = arm.energy + draw(record.piece, short)
  end
end

--- Which kinds of wearer are turned by an orientation rather than by a direction.
---
--- A character faces one of sixteen ways and says so in entity.direction. A vehicle turns
--- smoothly and says so in entity.orientation, as a fraction of a turn, and asking one for
--- the other raises rather than returning nothing: reading direction off a car gives the
--- last thing it was built facing and reading orientation off a character is an error. So
--- which to ask is decided by type.
local ORIENTED = {
  ["car"] = true,
  ["spider-vehicle"] = true,
  ["locomotive"] = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true,
}

---Which way a wearer is facing, on the sixteen point scale lib/pack.lua works in.
---
---Fractional for a vehicle, which is the point of asking it this way: a car halfway between
---two of the sixteen has its arms halfway round with it rather than snapping between them.
---@param wearer LuaEntity
---@return number
local function facing_of(wearer)
  if ORIENTED[wearer.type] then return wearer.orientation * pack.DIRECTIONS end
  return wearer.direction
end

---How wide and how long a wearer is, in tiles either side of its middle.
---
---Whichever of its two boxes is the tighter, which on most vehicles is the same box twice:
---a tank and a car give identical collision and selection boxes, so this is the hull either
---way. Rolling stock does not. A locomotive's collision box is 0.6 either side of the
---track and its selection box is 1.0, because a selection box is padded to make a thing
---easier to click on, and the extra four tenths is past the outside of its wheels. Arms
---bolted out there hung off the bottom of the train and were drawn below the wheels rather
---than on the side of the hull above them.
---
---The selection box was what this used, on the grounds that it is drawn round what a player
---sees. That is true of a hull and not of the padding round a train.
---@param wearer LuaEntity
---@return number across half its width
---@return number along half its length
local function hull_of(wearer)
  local seen = wearer.prototype.selection_box
  local solid = wearer.prototype.collision_box
  local across = math.min((seen.right_bottom.x - seen.left_top.x) / 2,
                          (solid.right_bottom.x - solid.left_top.x) / 2)
  local along = math.min((seen.right_bottom.y - seen.left_top.y) / 2,
                         (solid.right_bottom.y - solid.left_top.y) / 2)
  -- A collision box can be nothing at all -- a thing that collides with nothing has one of
  -- zero size -- and an arm bolted to the middle of its owner is an arm nobody can see. So
  -- what a player sees is the fallback rather than the first answer.
  if across < 0.01 or along < 0.01 then
    return (seen.right_bottom.x - seen.left_top.x) / 2,
           (seen.right_bottom.y - seen.left_top.y) / 2
  end
  return across, along
end

--- How far the near side of a hull is drawn above the ground it stands on, as a share of
--- the hull's own half width.
---
--- Nothing in the prototype says how tall a body is drawn, so this is measured off the
--- screen. It was four tenths, taken from where a tank's treads stop, and it put the arms
--- at the foot of the treads rather than on the body above them: a claw hanging off the
--- bottom of a tank driving past, where a player expects one out of its flank.
---
--- A half, with the bases brought inboard by INSIDE below, draws a tank's near arm a fifth
--- of a tile south of its middle -- up on the body, above the running gear, which is where
--- a character wears theirs. Eight tenths was tried first and lifted it past the middle of
--- the hull and out of the top of it.
---
--- A share of the hull rather than a fixed height, so a small vehicle gets a small lift.
local TREADS = 0.5

--- Vehicles whose arms go on the turret rather than along the hull.
---
--- A tank's arms used to stand out on its flanks, which is right for a hull with nothing on
--- top of it and wrong for one with a turret: the claws sat out over the tracks while the
--- thing a player watches, and the only round part of a tank, went by empty.
---
--- By name, because nothing at runtime will answer the question. turret_animation is a data
--- stage field and LuaEntityPrototype does not carry it, and turret_rotation_speed is no
--- substitute -- the car has one too, and no turret to go with it.
local TURRETED = { tank = true }

--- How far north of a turreted vehicle's own position the bottom edge of its turret is
--- drawn, which is where an arm bolted to it sits.
---
--- Measured off the sprite rather than guessed at. The tank's turret mask -- the round part,
--- the thing the tint goes on -- is 66 source pixels tall at half scale, so a little over a
--- tile, and its middle is shifted 35.5 screen pixels north of the tank, which is 1.109
--- tiles. Half the mask's height back south of that is the bottom edge.
local TURRET = 0.6

--- How far in from the edge of a hull an arm is bolted, as a share of the hull's half
--- width.
---
--- On the outer edge is where they were, and on a tracked or wheeled thing the outer edge
--- is the running gear: a tank's arms stood on its tracks and a car's hung off its wheel
--- arches. Brought in a quarter of the way they sit on the body the tracks carry, which is
--- also where a player would expect a thing bolted to a vehicle to be.
local INSIDE = 0.75

---Where an arm stands on the ground, which is where its reach is measured from.
---
---Two quite different answers. A character wears their arms on their back, in a knot at the
---shoulders. A vehicle carries them along the sides of its hull, because the middle of a
---vehicle is underneath it: an arm bolted there is drawn over by the hull and the player
---sees a claw coming out of nothing. See lib/pack.lua for both.
---@param wearer LuaEntity a character or a vehicle
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number}
---Where a spider vehicle's legs are bolted on.
---
---The one part of a spidertron that does not turn. Its torso swings round to face whatever
---it is aiming at while its legs stay where they are, so an arm mounted on the torso swings
---with it -- which looks right on a tank, whose whole hull turns, and wrong on a spider,
---where a player watching the legs stand still sees the arms slide round them.
---
---Read off the prototype rather than guessed at: a spider engine says where each of its legs
---meets the body, and that is a real place on the chassis rather than a point on a circle.
---@param wearer LuaEntity
---@return {x: number, y: number}[] in the order the prototype lists them
local function leg_mounts(wearer)
  if wearer.type ~= "spider-vehicle" then return {} end
  local engine = wearer.prototype.spider_engine
  local legs = engine and engine.legs
  if not legs then return {} end
  local spots = {}
  for _, leg in ipairs(legs) do
    local at = leg.mount_position
    if at then
      spots[#spots + 1] = { x = at.x or at[1] or 0, y = at.y or at[2] or 0 }
    end
  end
  return spots
end

local function station_on(wearer, slot, count)
  local at = wearer.position
  local offset
  if wearer.type == "character" then
    -- the spot their shoulder is over, not the shoulder: how far up their back the arm is
    -- strapped is the lift below, and is no kind of distance
    offset = pack.ground(facing_of(wearer), slot, count)
  else
    -- The legs first, one arm apiece, and whatever is left over goes round the body the way
    -- a hull's arms do. Eight arms on a spidertron is one on each leg; a ninth has nowhere
    -- of its own to go and rides on the torso.
    local legs = leg_mounts(wearer)
    if TURRETED[wearer.name] then
      -- The turret's middle projected straight down, which is the vehicle's own position:
      -- the sprite is shifted north of it by the turret's height and by nothing else, and
      -- height is the one part of a shift that is not a place on the ground.
      offset = pack.turret(facing_of(wearer), slot, count)
    elseif slot and legs[slot] then
      offset = legs[slot]
    else
      local across, along = hull_of(wearer)
      offset = pack.mount(facing_of(wearer), (slot or 1) - #legs,
        math.max(1, (count or 1) - #legs), across * INSIDE, along * INSIDE)
    end
  end
  return { x = at.x + offset.x, y = at.y + offset.y }
end

---How far an arm is carried up off the ground to be drawn on the body it is bolted to.
---
---Perspective rather than distance. The world is flat and the map has no up, so a sprite
---drawn above its own position is drawn a little to the north of it, and an arm put down
---where the geometry says belongs at the hull's ground line rather than on the body a player
---can see.
---
---A character's own is how far up their back the thing is strapped, which is the same
---trick at a smaller size: two thirds of the way up somebody is most of a tile north of
---their feet.
---@param wearer LuaEntity
---@param at {x: number, y: number} where the arm stands, from station_on
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return number how far north to draw it, in tiles
local function lift_of(wearer, at, slot, count)
  if wearer.type == "character" then return pack.lift(slot, count) end

  -- Up onto the turret, to its bottom edge, which is the far side of the same split a
  -- character's back is answered in: pack.turret gives the part of the ring that is a place
  -- on the ground and the part that is a height, and this is the height.
  if TURRETED[wearer.name] then
    local _, down = pack.turret(facing_of(wearer), slot, count)
    return TURRET - down
  end

  local body = wearer.prototype.height
  if body then
    -- A body that rides above its own position says so. A spider vehicle's torso is carried
    -- a tile and a half up its legs, and every arm goes up with it: the torso is all there
    -- is to bolt one to, and nothing stands in front of it to hide an arm behind.
    return body
  end

  -- A hull is a box, and the sprite draws the side of it facing the camera above the ground
  -- line. An arm out on that side is lifted to meet it; one round the far side stays where
  -- it is, because the hull is drawn over it either way and lifting it would poke it out
  -- over the roof.
  local across = hull_of(wearer)
  local offset = { x = at.x - wearer.position.x, y = at.y - wearer.position.y }
  return TREADS * across * pack.nearness(offset)
end

---Where an arm is drawn, which is where it stands carried up onto the body.
---@param wearer LuaEntity a character or a vehicle
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number} where the arm goes
---@return number how far up that is from where it stands
local function mounting(wearer, slot, count)
  local at = station_on(wearer, slot, count)
  local lift = lift_of(wearer, at, slot, count)
  return { x = at.x, y = at.y - lift }, lift
end

--- What beats a claw's box when an inserter looks round for something to take from.
---
--- An inserter resolves its pickup to one entity, and only one. Measured on 2.1.19, with a
--- box and something else standing in the same place: a transport belt wins, and so does a
--- ghost. A belt that is itself marked for deconstruction is the worst of them -- the belt
--- is chosen and then refused, and the hand does not leave home at all, which is a claw
--- that deploys and then stands there until the swing limit gives up on it.
---
--- An empty chest leaves the box alone and a full one does not, which is the same rule
--- seen from the other side: what the engine looks for is something with items in it. A
--- claw sent to fetch a plate off the floor beside a full chest took five plates out of the
--- chest instead, over and over, while the plate it was sent for lay there -- fourteen
--- hundred of them still on the ground and the chest counting down.
---
--- So what shadows a box is a belt, a ghost, or anything holding anything.
---
--- Which is what a line of belts marked for taking up looks like too. The box goes a lift
--- above the thing it is fetching, and a lift is seven tenths of a tile on a character, so
--- anything with a neighbour one tile to the north put the box on the neighbour's tile.
---
--- Only the pickup end is at risk. The same measurement on the drop end put the load in the
--- box every time, under a belt, a marked belt, a ghost and a chest alike.
local SHADOWS = {
  ["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true,
  ["linked-belt"] = true, ["loader"] = true, ["loader-1x1"] = true,
  ["entity-ghost"] = true,
}

--- The box a claw hands its load over through: the one container a box is allowed to share
--- a tile with, since it is the box. Declared here because standing_clear() has to know it
--- by name and runs long before catcher_at() is reached.
local CATCHER = "constructor-equipment-catcher"

---Whether this is something an inserter would find items in.
---
---Asked of the thing rather than of its type, because it is having something in it that
---matters: an empty chest is no obstacle and the same chest with plates in it takes the
---claw's whole journey.
---@param entity LuaEntity
---@return boolean
local function holding_something(entity)
  if entity.name == CATCHER then return false end
  -- A thing lying on the ground holds nothing; asking it what its inventories are is asking
  -- a stack of plates to open its pockets.
  if entity.type == "item-entity" then return false end
  local ok, most = pcall(function() return entity.get_max_inventory_index() end)
  if not (ok and most) then return false end
  for index = 1, most do
    local held = entity.get_inventory(index)
    if held and not held.is_empty() then return true end
  end
  return false
end

--- How far back along its own bearing a fetch's box may be pulled to find a spot of its
--- own, and in what steps. A quarter of a tile is small enough that the first clear spot is
--- barely off the mark, and a tile and a half is further than any neighbour is wide.
local CLEAR_STEP = 0.25
local CLEAR_BACK = 1.5

--- How far off a tile's edge the box has to stand, which is only enough that rounding
--- cannot put the engine and this on opposite sides of it. A lift is seven tenths of a
--- tile, so the spot a box is asked for is a third of a tile from an edge to begin with and
--- any real margin here would rule out every spot there is.
local CLEAR_EDGE = 0.02

--- How far inside a tile to look for what is standing on it. A belt's box reaches exactly
--- to the edge of its own tile and a search by area counts a box that merely touches, so
--- without this the empty tile beside a belt answers that the belt is on it.
local CLEAR_INSET = 0.1

---Whether anything standing here would be picked from in preference to a box put here.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@return boolean
local function shadowed(surface, at)
  -- By the tile, because that is what an inserter reads. A belt's own collision box is
  -- inset from the tile it stands on, so asking what covers the exact spot says clear for
  -- a spot the engine still resolves to the belt.
  local tx, ty = math.floor(at.x), math.floor(at.y)
  -- And not on a tile's edge, where which of the two the engine reads is a coin toss.
  if at.x - tx < CLEAR_EDGE or tx + 1 - at.x < CLEAR_EDGE then return true end
  if at.y - ty < CLEAR_EDGE or ty + 1 - at.y < CLEAR_EDGE then return true end
  -- Inset, because a search by area counts a box that merely touches the edge of it: the
  -- belt on the next tile along reaches exactly to the boundary and answered every query
  -- about the empty tile beside it.
  for _, entity in pairs(surface.find_entities_filtered{
      area = { { tx + CLEAR_INSET, ty + CLEAR_INSET },
               { tx + 1 - CLEAR_INSET, ty + 1 - CLEAR_INSET } } }) do
    if SHADOWS[entity.type] or holding_something(entity) then return true end
  end
  return false
end

---How far to pull a fetch's box back so that the claw will see it.
---
---Back along the line to the arm, a quarter tile at a time, until the box has a spot to
---itself. Where it ends up is cosmetic: the box is a hand-over point rather than a place
---the claw has to touch, and what is taken up is the thing the job went out for wherever
---the box ends up standing. Stopping a little short of a packed line is better than
---standing still in front of it.
---
---Worked out once for a job and remembered, since it is a search and the answer does not
---change while the claw is on its way. Cleared wherever job.target is.
---@param job table
---@param record table
---@param at {x: number, y: number} where the box would go
---@return {x: number, y: number}? the offset to apply, if any
local function standing_clear(job, record, at)
  if job.shift then
    if job.shift.x == 0 and job.shift.y == 0 then return nil end
    return job.shift
  end
  local arm = record.entity
  if not (arm and arm.valid) then return nil end
  local surface = arm.surface
  job.shift = { x = 0, y = 0 }
  if not shadowed(surface, at) then return nil end

  local dx, dy = arm.position.x - at.x, arm.position.y - at.y
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 0.01 then return nil end
  local back = math.min(CLEAR_BACK, length)
  local step = CLEAR_STEP
  while step <= back do
    local shift = { x = dx / length * step, y = dy / length * step }
    if not shadowed(surface, { x = at.x + shift.x, y = at.y + shift.y }) then
      job.shift = shift
      return shift
    end
    step = step + CLEAR_STEP
  end
  -- Nowhere clear within a tile and a half. Left where it was asked for, which is no worse
  -- than it was before there was anywhere else to try.
  return nil
end


---Which way a freshly built hand points, as a unit vector.
---
---Where the arm was built facing, which is the whole of what decides it -- see reach.BORN.
---Nothing means north, which is what an inserter faces when nobody says otherwise.
---@param record table
---@return {x: number, y: number}
local function born_facing(record)
  local x, y = pack.facing(record.facing or defines.direction.north)
  return { x = x, y = y }
end

---Follow the engine's arm through one tick, so that the mod knows where it is.
---
---The state of an inserter's hand is two numbers: how far out it is, and which way it points.
---Neither is in the API -- orientation reads nought on an inserter, see point() -- and the
---one thing that looks like them is held_stack_position, which is where the claw is *drawn*.
---Past about two thirds of a turn that is not where the arm is: the drawn hand runs ahead of
---its own state in both numbers at once and comes back to it by the end of the turn, by as
---much as half a tile and eleven degrees on a half turn. Fed that, the arithmetic in
---lib/reach.lua came out optimistic by as much as twelve ticks, so a claw set off for things
---it could not reach in the time it thought. Measured in `test/ft/swinging.lua`.
---
---So the two numbers are carried instead. The engine moves each of them toward whatever end
---the hand is chasing, at the tier's own rate, and so does this: same law, same step, no
---drawing in the way. Nothing has to be remembered about what the mod asked for, because the
---entity is asked what it was last told -- drop_position and pickup_position hold whatever
---was last written to them, by aim() or by redirect() or by deliver(), and they travel with
---the entity, so the teleport that puts the arm back on its owner does not disturb them.
---
---Once a tick and before anything reads the state, which is why this is a pass of its own at
---the top of on_tick rather than something aim() does: the order matters. Measured, an
---inserter updates after the scripts do, so a target written this tick is the one the engine
---moves on this tick -- an arm re-aimed on tick five has turned one step by tick six -- and a
---hand charged on the tick it is made has already taken its first step by the next one. So
---the step made here is the one the engine made with the target that stood at the end of the
---tick before.
---@param record table
local function follow(record)
  if record.followed == game.tick then return end
  record.followed = game.tick
  local arm = record.entity
  if not (arm and arm.valid) then
    record.out, record.pointing = nil, nil
    return
  end
  local base = arm.position
  if not (record.out and record.pointing) then
    -- Nothing carried for this arm yet: a save written before the mod carried it, or an arm
    -- that came from somewhere other than arm_of(). The drawing is the only answer there is,
    -- and it is the right one for everything but a hand that is turning, so it is where this
    -- picks the arm up. Seeded rather than stepped, because it is already this tick's state.
    local hand = arm.held_stack_position
    local dx, dy = hand.x - base.x, hand.y - base.y
    local length = math.sqrt(dx * dx + dy * dy)
    record.out = length
    record.pointing = length >= 0.2 and { x = dx / length, y = dy / length }
      or born_facing(record)
    return
  end
  -- Which end the engine was chasing, which is the drop while the hand holds something and
  -- the pickup while it does not. Remembered as that tick ran rather than read back now: the
  -- load leaves the hand during the engine's own update, so an arm that spent the whole of
  -- last tick carrying something out reads as empty by the time this asks.
  local at = record.chasing_drop and arm.drop_position or arm.pickup_position
  local towards = { x = at.x - base.x, y = at.y - base.y }
  local tier = tier_of(record)
  local pointing = record.pointing
  local turning = reach.turning(pointing, towards, tier.rotation)
  record.out = reach.stepped(record.out,
    math.sqrt(towards.x * towards.x + towards.y * towards.y), tier.extension)
  record.pointing = reach.turned(pointing, towards, tier.rotation)
  if turning then return end

  -- A hand that was not turning is a hand whose drawing is exact, so where the engine draws
  -- it is a better answer than any sum: it is the engine's own. Measured over three tiers,
  -- the gap between the two opens only while a hand is turning and is shut again by the time
  -- the turn is -- see test/ft/swinging.lua -- and a hand already on its bearing has no turn
  -- left to make.
  --
  -- Which makes this the ordinary case and the sum above the exception. It is also what
  -- keeps the sum from drifting: an arm with nothing to move with does not move while the
  -- arithmetic says it does, and the tick it is pointed at anything again puts it right.
  local hand = arm.held_stack_position
  local dx, dy = hand.x - base.x, hand.y - base.y
  local length = math.sqrt(dx * dx + dy * dy)
  record.out = length
  if length >= 0.2 then record.pointing = { x = dx / length, y = dy / length } end
end

---How far out an arm's hand is, in tiles from its own base.
---
---Where a freshly built one is born when there is no arm yet, because that is where the next
---swing starts from, and an arm that has not come out yet is exactly the one being decided
---about.
---@param record table
---@return number
local function hand_out(record)
  local arm = record and record.entity
  if not (arm and arm.valid) then return reach.BORN end
  return record.out or reach.BORN
end

---Which way an arm's hand is pointing, or nothing if it has no bearing yet.
---
---Whether an arm can be turned by building it again rather than by swinging round.
---
---Turning a hand is not a thing the engine offers: a hand's rotation is its own state and
---nothing but building the entity again resets it, which was established the hard way in
---eleven different ways -- see point(). So the mod turns an arm by taking it away and making
---a new one facing the right way, and the new one's hand starts where a fresh hand starts.
---
---Which is only honest for an arm whose hand is home. A hand with a load in it cannot be
---taken away without the load going with it. And a hand still out cannot be taken away
---without the claw jumping from wherever it was to wherever a fresh one is born: that is not
---an arm turning round, it is an arm teleporting, and it is a turn that never got made.
---@param record table
---@return boolean
local function rebuildable(record)
  local arm = record and record.entity
  if not (arm and arm.valid) then return true end
  if arm.held_stack.valid_for_read then return false end
  return hand_out(record) < within(tier_of(record), HOME)
end

---Which way an arm's hand is pointing, or nothing if it has no bearing worth honouring.
---
---Nothing for any arm that can be built again, because then the bearing is about to be
---whatever it needs to be and charging for a turn would be charging for one that will not
---happen. The two questions are the same question, so they are asked of the same predicate:
---an arm is held to its bearing exactly when it cannot be pointed.
---
---Nothing as well for a hand sitting on its own base, which is no direction at all: the
---engine picks one, and picking the same one here would be guessing.
---@param record table
---@return {x: number, y: number}?
--- How far off a target has to be before which way it lies means anything. Nearer than
--- this and the bearing is noise, and an arm pointed by noise is an arm pointed anywhere.
local POINTED = 0.3

local function hand_facing(record, towards)
  local arm = record and record.entity
  if not (arm and arm.valid) then return nil end
  local pointing = record.pointing
  if not pointing then return nil end
  -- A hand sitting on its own base points nowhere the engine will honour, whatever bearing
  -- has been carried for it, so the measure is still how far out it is.
  if hand_out(record) < 0.2 then return nil end
  -- Nothing for a bearing that is about to be replaced, which is not the same as one that
  -- could be. It used to be enough that the arm was rebuildable, on the grounds that the
  -- bearing was about to be whatever it needed to be -- but point() rebuilds only when it
  -- has a reason to, and it has none when the arm already faces the right sixteenth or when
  -- what it is going for is nearer than POINTED. Measured over a train run, 167 of 186 calls
  -- to point() refused the rebuild and 5 made one, so the bearing usually does survive.
  --
  -- What that cost: the claw was picked for a job with no turn charged at all, kept a hand
  -- pointing somewhere else entirely, and the next tick charged the turn and found the ghost
  -- unreachable -- so it set off for things it could never meet and gave them up a tick
  -- later, over and over. One case, traced: an arm already facing the right sixteenth with
  -- its hand two tenths out and pointing north east, sent for something east south east.
  if towards and rebuildable(record) then
    local base = arm.position
    local ax, ay = towards.x - base.x, towards.y - base.y
    if ax * ax + ay * ay >= POINTED * POINTED
        and arm.direction ~= pack.towards(ax, ay) then
      return nil
    end
  end
  return pointing
end

---An arm as lib/reach.lua wants to hear about it: what it can do, where its hand is, and
---which way that hand points.
---@param record table
---@param range number
---@return table
local function arm_state(record, range, towards)
  local tier = tier_of(record)
  return {
    range = range,
    extension = tier.extension,
    rotation = tier.rotation,
    out = hand_out(record),
    facing = hand_facing(record, towards),
  }
end

--- A course that is going nowhere, shared rather than made afresh every time it is wanted.
local STILL = { x = 0, y = 0 }

---Whether a thing is out of reach, or will be by the time the hand gets to it.
---
---What this saves is the swing that was never going to arrive. A ghost abeam of somebody
---walking is left behind faster than a claw can follow: measured on two dozen passes, with
---a ghost laid down one to three tiles to the side of a character already under way, nine
---of them were set off for and written off without a delivery. None of those nine is built
---now either -- the arm cannot reach what its owner is walking away from, and no amount of
---aiming changes that -- but none of them costs a swing, the charge that pays for it, or the
---slowdown its owner wears while an arm is working.
---
---Only what its owner is walking away from, which is the whole of why this is a dot product
---rather than a distance. Walking towards a thing shortens the reach as the hand goes, so a
---swing that looks too long from here is finished long before the estimate says it will be:
---predicted both ways, an arm turned down a row of twelve ghosts it had in fact been
---building, every one of them, because the estimate had its owner overshooting past them.
---Walking away is the honest direction -- the reach only gets longer from here.
---
---What is left of this is sizing a round: how many of a thing a claw should shop for before
---it leaves, which is a different question from whether any one of them can be flown to.
---Whether a thing is worth setting off for is course_to(), which charges the turn as well.
---@param record table the arm
---@param from {x: number, y: number} where it reaches from now
---@param at {x: number, y: number} what it would reach for
---@param range number
---@param ticks number? how long the arm has to get there, defaulting to one full swing.
---  Longer for a round being sized, because the claw stays out for the whole of it and its
---  owner carries it further on with every ghost it works.
---@return boolean
local function out_of_reach(record, from, at, range, ticks)
  local drift = (record and record.drift) or STILL
  -- Somebody standing still reaches what is in reach and nothing else, which is the whole
  -- of what this used to be and what every arm on a stationary wearer still does.
  if drift.x == 0 and drift.y == 0 then
    return reach.out_of_range(from, at, range)
  end
  local tier = tier_of(record)
  -- Where the hand is, but deliberately not which way it points. A round is sized over its
  -- whole life, several swings long, by which time the bearing the hand happens to hold now
  -- says nothing; and a bearing costs a walk of up to half a turn's worth of ticks apiece
  -- where the rest is a handful of sums. Generous is what this is allowed to be: nothing
  -- sets off on its answer, and every ghost it counts is put to course_to() in its turn.
  return not reach.meets(
    { range = range, extension = tier.extension, out = hand_out(record) },
    drift, { x = at.x - from.x, y = at.y - from.y }, ticks or reach.full_swing(tier))
end

---The course a claw would fly to reach a thing, or nothing if there is none.
---
---One question asked in one place, because it used to be two. An arm deciding whether to set
---off asked out_of_reach(), which leaves the bearing out on purpose and is therefore
---generous; an arm already going asked set_course(), which charges the turn. A claw that
---crossed from one ghost to the next went through the generous one alone -- redirect() took
---whatever choose() offered and threw set_course()'s answer away -- so it set off for things
---the strict test refused on the very next tick, gave them up, was offered the neighbour,
---and lost that one the same way. Traced on a train, a claw ping ponged between two adjacent
---ghosts a tick apiece and delivered to neither.
---
---So both ends now ask this. What it turns away nothing sets off for, and what it lets
---through is a course the tick after will still recognise.
---@param record table
---@param from {x: number, y: number} where the arm reaches from
---@param at {x: number, y: number} the thing, in the world
---@param range number
---@param setting_off boolean? whether this is an arm deciding to go, rather than one going
---@return {met: boolean, arrival: number?, lead: {x: number, y: number}?}?
local function course_to(record, from, at, range, setting_off)
  -- No arm to speak of is no hand to start from and no turn to charge, so what is in reach
  -- is in reach. The search is asked this before any arm exists.
  if not record then
    if reach.out_of_range(from, at, range) then return nil end
    return { met = true }
  end
  local arm = arm_state(record, range, at)
  -- A hand with no bearing and a thing already in reach wants no lead at all: aim at it and
  -- be done. An empty claw is rebuilt facing wherever it is going, so there is nothing for
  -- it to turn through and the engine's own chase is the short way round.
  if not arm.facing and not reach.out_of_range(from, at, range) then
    return { met = true }
  end
  -- How far ahead to look, and the two cases want different answers. An arm deciding whether
  -- to set off looks one flight ahead, which is the same distance the search covers, so that
  -- it never takes on what it was never offered. An arm already out is not deciding anything
  -- -- it has a ghost and it is going -- so what it wants to know is whether the thing can
  -- still be got to at all, and a hand part way through a reach can want longer than a
  -- flight: one back at its own base reaching five tiles wants fifty ticks against a swing's
  -- forty three.
  local horizon = setting_off and reach.full_swing(tier_of(record)) or reach.longest(arm)
  local arrival, lead = reach.intercept(
    arm, record.drift or STILL, { x = at.x - from.x, y = at.y - from.y }, horizon)
  if not arrival then return nil end
  return { met = false, arrival = arrival, lead = lead }
end

---Where a claw is aimed for a ghost: the ghost, carried up into the frame the arm swings in.
---
---This is what keeps a lifted arm honest. The engine swings a hand out from wherever the
---inserter stands, so an arm drawn up on a body and aimed at a ghost on the ground has
---further to stretch southward than northward -- a spidertron, whose torso rides a tile and
---a half up, was half again as slow to build behind itself as in front, and a character,
---whose pack rides two thirds of the way up them, was twice as quick to build in front of
---themselves as behind. Lifting the target by the same amount it lifted the arm makes the
---whole swing a copy of the one it would have made at ground level: same distance, same
---time, whichever way it faces.
---
---What it costs is the claw stopping a little short of the ghost, up where the arm is. That
---is not a miss. A claw holding something over a tile is drawn exactly there, because this
---game draws height as distance to the north, and the item lands on the ghost because the
---box that catches it went up with the claw. The ghost is revived where it stands.
---@param job table
---@param record table the arm, which remembers how far up it is drawn
---@return {x: number, y: number}
local function aimed_at(job, record)
  local lift = record.lift or 0
  local target = job.target
  -- Still out of reach, so the claw is sent where the ghost will be rather than where it
  -- is: an offset from the arm's own base, which travels with its owner and which the ghost
  -- falls exactly on at the moment the hand arrives. Dropped the tick the ghost is really in
  -- reach, after which where it is beats any guess about where it will be -- and that
  -- handover is the whole point of the lead, because the engine lets go against the aim it
  -- was given a tick earlier rather than this tick's.
  if job.lead and not job.met and record.from then
    target = { x = record.from.x + job.lead.x, y = record.from.y + job.lead.y }
  end
  local at = (lift == 0) and target
    or { x = target.x, y = target.y - lift }
  local shift = job.take and standing_clear(job, record, at) or nil
  if not shift then return at end
  return { x = at.x + shift.x, y = at.y + shift.y }
end

---Where an arm reaches from.
---
---Its own base on a vehicle, and its owner's own position on a character. A character wears
---every arm in one knot at their shoulders, a hand's breadth from their middle, and the
---reach a tier promises has always been the reach from the person wearing it. A hull is
---another matter: a tank is nearly three tiles long, so an arm bolted to the back of one
---and measuring from the tank's middle would be asked to stretch a tile and a half further
---than its tier sells, and would take half again as long doing it. It reaches from where it
---is bolted, so what a tier promises is what every arm wearing it can do.
---@param wearer LuaEntity
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number}
local function reaching_from(wearer, slot, count)
  if wearer.type == "character" then return wearer.position end
  -- where the arm stands rather than where it is drawn: the lift that puts it on the body
  -- is a trick of the camera, and a claw that reached a tile and a half less far to the
  -- south of a spidertron because its torso rides high would be the trick coming true
  return station_on(wearer, slot, count)
end

---How far from a wearer's middle an arm's base can sit.
---
---Nought for a character, whose arms are near enough their middle to ignore. A corner of a
---hull for a vehicle, which is what the ghost search has to be widened by: an arm out there
---reaches its own range from its own base, which can be a corner's worth further out than
---anything measured from the middle would find.
---@param wearer LuaEntity
---@return number
local function spread_of(wearer)
  if wearer.type == "character" then return 0 end
  -- A turreted vehicle's arms are all on the turret, which is over the middle, so they
  -- spread no further than the ring they sit on.
  if TURRETED[wearer.name] then return pack.RADIUS end
  local across, along = hull_of(wearer)
  return math.sqrt(across * across + along * along)
end

---What a piece of work leaves behind: the prototype of the thing that ends up on the tile.
---
---A ghost says so itself. An entity marked for upgrade says so through the order the
---planner hung on it, which names what to replace it with and at what quality.
---@param work LuaEntity a ghost, or an entity marked for upgrade
---@return LuaEntityPrototype?
---@return LuaQualityPrototype?
local function outcome_of(work)
  if work.type == "entity-ghost" then return work.ghost_prototype, work.quality end
  -- Nothing is put down on a cliff or on something being taken away, so neither has an
  -- outcome to ask about.
  if work.type == "cliff" or work.to_be_deconstructed() then return nil end
  return work.get_upgrade_target()
end

---How one piece of work is told from another, so that no two arms set off for the same one.
---
---A unit number where there is one, and where there is not, the ground it stands on. A
---cliff has no unit number: it is scenery the map generator laid down rather than something
---built, and a search for one comes back with nothing to key a claim on.
---
---Which ground, surface and all. A unit number is the whole game's, and claims and the
---shunned list are both the whole game's too, so a key made of coordinates alone has a
---cliff on Nauvis and a cliff at the same spot on Vulcanus claiming and shunning each
---other.
---@param work LuaEntity
---@return string|integer
local function claim_of(work)
  return work.unit_number
    or ("at " .. work.surface.index .. ":" .. work.position.x .. "," .. work.position.y)
end

---Set a piece of work aside for a while, because it has just defeated an arm.
---
---An arm that runs over the swing limit gives the thing up and comes home, and then chooses
---again. What it chooses is the same thing: nothing about the choosing has changed, and it
---was the best by cost a moment ago. So it sets off, fails the same way, and the two of them
---go round for as long as anybody is watching. Measured on eight things marked in a ring
---round somebody standing still, three were taken up and the arm spent the rest of the run
---on the other five, three hundred ticks at a time, and took none of them.
---
---Set aside for one swing limit, which is long enough that the arm has something else in
---hand by the time it comes round again, and short enough that nothing is written off.
---@param work LuaEntity?
local function set_aside(work)
  if not (work and work.valid) then return end
  storage.constructor_shunned = storage.constructor_shunned or {}
  storage.constructor_shunned[claim_of(work)] = game.tick
end

---Whether this is something an arm has just failed at and should leave alone for now.
---@param work LuaEntity
---@return boolean
local function set_aside_still(work)
  local list = storage.constructor_shunned
  if not list then return false end
  local key = claim_of(work)
  local when = list[key]
  if not when then return false end
  -- Forgotten as it is asked about rather than swept: what is asked about is what is in
  -- reach, and anything out of reach costs nothing to leave in the table.
  if game.tick - when > SWING_LIMIT then
    list[key] = nil
    return false
  end
  return true
end

---Whether a piece of work is something to be taken up rather than put down.
---
---Asked before the upgrade question, because a thing marked for deconstruction is still a
---thing standing there and answers yes to both otherwise.
---@param work LuaEntity
---@return boolean
local function taking(work)
  if work.type == "entity-ghost" or work.type == "cliff" then return false end
  return work.to_be_deconstructed()
end

---Whether a piece of work is a cliff waiting to be blown up.
---
---A cliff marked for deconstruction is not a demolition the arm can carry out. It is a
---delivery: the claw brings an explosive and comes home empty, which is what a construction
---robot does with one. Measured on 2.1.17, a marked cliff stood untouched while a network
---with no explosives in it finished everything else, and went the moment one was put in a
---chest, at a cost of exactly one.
---@param work LuaEntity
---@return boolean
local function exploding(work)
  return work.type == "cliff"
end

---What a cliff asks to be brought, in the shape items_to_place_this comes in.
---
---Read off the cliff rather than named here: which explosive a cliff wants is a property of
---the cliff, and a planet that wants a different one says so in its own prototype.
---@param work LuaEntity
---@return {name: string, count: integer}[]?
local function explosive_for(work)
  local wanted = work.prototype.cliff_explosive_prototype
  if not wanted then return nil end
  return { { name = wanted, count = 1 } }
end

---The projectile an explosive throws, which is what actually breaks the cliffs.
---
---Thrown rather than the cliff simply being destroyed, so that the blast does what a blast
---does: it takes the neighbours in its radius with it, which is why a robot clearing a wall
---of cliffs does not spend one charge per cliff.
---@param name string the explosive item
---@return string?
local function projectile_of(name)
  local item = prototypes.item[name]
  local capsule = item and item.capsule_action
  local attack = capsule and capsule.attack_parameters
  local ammo = attack and attack.ammo_type
  for _, action in pairs(ammo and ammo.action or {}) do
    for _, delivery in pairs(action.action_delivery or {}) do
      if delivery.type == "projectile" then return delivery.projectile end
    end
  end
  return nil
end

---Whether a piece of work is a thing standing there waiting to be swapped rather than a
---ghost waiting to be raised.
---
---Asked of the entity every time rather than remembered on the job, so a job whose target
---has gone cannot be wrong about which of the two it was.
---@param work LuaEntity
---@return boolean
local function upgrading(work)
  return work.type ~= "entity-ghost"
end

---Whether a piece of work is still worth reaching for.
---
---A ghost is, as long as it is still a ghost. An upgrade is only while the order is still
---on it: a player can call the planner off between the arm setting out and the claw
---arriving, and the thing left standing there is then somebody's working belt rather than
---anything this mod should be pulling up.
---@param work LuaEntity?
---@return boolean
local function still_wanted(work)
  if not (work and work.valid) then return false end
  if exploding(work) or taking(work) then return work.to_be_deconstructed() end
  -- a ghost somebody has since marked for deconstruction is not something to build
  if not upgrading(work) then return not work.to_be_deconstructed() end
  return work.to_be_upgraded() and not work.to_be_deconstructed()
end

---The one item a thing turns into when it is taken up, if it is only one.
---
---Everything the replacement cannot hold is spilled on the floor by the engine, so what is
---left to bring home is the entity itself. In the base game that is a single item every
---time; anything stranger than that is left where the engine put it rather than guessed at.
---@param work LuaEntity
---@return string? name
---@return integer? count
local function sole_product(work)
  local mineable = work.prototype.mineable_properties
  local products = mineable and mineable.products
  if not products or #products ~= 1 then return nil end
  local product = products[1]
  if product.type ~= "item" then return nil end
  return product.name, product.amount or product.amount_min or 1
end

---What the next clawful out of something would be.
---
---A round carries one kind of thing, because the claw brings it home in one hand and the
---bag has one slot, so the next thing has to give more of the same. A thing holding
---something gives up what is inside it before it gives up itself, which is what a robot does
---with one, so that is what is asked of it first.
---@param work LuaEntity
---@return string? name
---@return string quality
local function yields(work)
  if work.type == "item-entity" then
    if not work.stack.valid_for_read then return nil, "normal" end
    return work.stack.name, work.stack.quality and work.stack.quality.name or "normal"
  end
  if work.type == "deconstructible-tile-proxy" then
    local tile = work.surface.get_tile(work.position.x, work.position.y)
    local mineable = tile and tile.prototype.mineable_properties
    local products = mineable and mineable.products
    if products and products[1] and products[1].type == "item" then
      return products[1].name, "normal"
    end
    return nil, "normal"
  end
  for index = 1, work.get_max_inventory_index() do
    local held = work.get_inventory(index)
    if held and not held.is_empty() then
      for slot = 1, #held do
        local stack = held[slot]
        if stack.valid_for_read then
          return stack.name, stack.quality and stack.quality.name or "normal"
        end
      end
    end
  end
  local name = sole_product(work)
  return name, work.quality and work.quality.name or "normal"
end

---Which end of a pair a thing is.
---
---An underground belt and a loader are each two things wearing one name, and which end
---this one is does not live in its direction. Left unsaid, both the question of whether
---the replacement fits and the swap itself treat it as an input, whichever end it is.
---@param work LuaEntity
---@return string?
local function end_of(work)
  if work.type == "underground-belt" then return work.belt_to_ground_type end
  if work.type == "loader" or work.type == "loader-1x1" then return work.loader_type end
  return nil
end

---The other end of an underground belt's pair, when that end is marked for upgrade too.
---
---A pair is one thing wearing two hulls. Replacing one end alone leaves a fast belt joined
---to a slow one until the arm comes back for the other, and turns the tunnel out: measured
---on 2.1.17, a robot upgrading one end put the eight items that were in the tunnel on the
---floor, where its network then collected them. Nothing is lost by it; it is simply a mess
---somebody has to clear up. So both ends are one piece of work, reached from whichever end
---the arm found, paid for with two items the way a curved rail is paid for with several.
---@param work LuaEntity
---@return LuaEntity? other
local function paired_with(work)
  if work.type ~= "underground-belt" then return nil end
  local other = work.underground_belt_neighbour
  if not (other and other.valid and other.to_be_upgraded()) then return nil end
  if other.to_be_deconstructed() then return nil end
  return other
end

---Whether a ghost could actually be built where it stands, right now.
---
---This is the whole of the question about standing on one, too. The mod used to refuse any
---ghost whose footprint its owner was inside, which is broader than the truth: a belt does
---not collide with a character and goes up perfectly well under one, the way a construction
---robot would put it up. What decides it is whether the thing being built would collide
---with whoever is standing there, and the engine already answers exactly that -- measured,
---can_place_entity on a belt under a character says yes, on a chest or an assembler says no,
---and on a medium electric pole says no until the character is far enough off centre to be
---clear of its collision box rather than merely of its tile.
---
---Asked because reaching for one that cannot be is a wasted journey that repeats: the claw
---goes out, the revive fails, it comes home, and the same ghost is picked again next tick.
---Standing near a thing is enough to stop it going up -- a character half a tile from a
---power pole is inside the space the pole needs -- and that is a case a player walks into
---constantly.
---
---Asked last of the tests, because it is the only one that costs anything.
---@param ghost LuaEntity
---@return boolean
local function buildable(work)
  -- Nothing is put down on a cliff or in the place of a thing being taken away, so there is
  -- no room to ask about. The blast makes its own space, and taking a thing up makes room
  -- rather than wanting it.
  if exploding(work) or taking(work) then return true end
  local prototype = outcome_of(work)
  if not prototype then return false end
  return work.surface.can_place_entity{
    name = prototype.name,
    position = work.position,
    direction = work.direction,
    type = end_of(work),
    force = work.force,
    -- A ghost asks the question a construction robot asks. An upgrade cannot: the thing
    -- being replaced is standing in the space its replacement needs, so every check but
    -- the manual one answers no for that reason alone. Measured on 2.1.17, a fast belt
    -- over a belt marked for upgrade is allowed under manual and refused under each of
    -- ghost_revive, script, script_ghost, manual_ghost and blueprint_ghost.
    build_check_type = upgrading(work) and defines.build_check_type.manual
      or defines.build_check_type.ghost_revive,
  }
end

---Whether a spot falls inside a thing's own footprint.
---
---Measured against the tiles the thing takes up, not its collision box. Plenty of entities
---have a collision box far smaller than their footprint -- a medium electric pole occupies
---a whole tile and collides across a third of one -- and using the box let a character
---stand a fifth of a tile off a pole's centre and still count as clear of it.
---@param work LuaEntity
---@param at {x: number, y: number}
---@return boolean
local function underfoot(work, at)
  local prototype = outcome_of(work) or work.prototype
  local across = (prototype and prototype.tile_width or 1) / 2
  local down = (prototype and prototype.tile_height or 1) / 2
  local middle = work.position
  return at.x >= middle.x - across and at.x <= middle.x + across
     and at.y >= middle.y - down and at.y <= middle.y + down
end


---Whether whoever is standing there is actually in the way of this piece of work.
---
---It used to be enough that their feet were inside the footprint, which is broader than the
---truth and refused things a construction robot would happily have put up. A belt does not
---collide with a character: you can stand on one, and a ghost of one under you goes up
---exactly as it would if you were a tile away. A chest does collide, and an assembler
---collides across three tiles, and those cannot.
---
---So the question is whether the thing that would be built collides with whoever is there,
---and the engine answers precisely that -- including for the vehicle somebody is driving,
---since it is the vehicle standing on the ground rather than them. Measured: a belt under a
---character is placeable, a chest and an assembler are not, and a medium electric pole is
---not until the character is far enough off centre to be clear of its collision box rather
---than merely of its tile.
---
---Taking something up, an upgrade and a cliff are all exempt before that is even asked.
---None of them wants room it has not already got, and a heap of plates is most often
---exactly where you are standing.
---@param ghost LuaEntity
---@param at {x: number, y: number}
---@return boolean
local function standing_in(ghost, at)
  if exploding(ghost) or taking(ghost) or upgrading(ghost) then return false end
  if not underfoot(ghost, at) then return false end
  return not buildable(ghost)
end

---Every piece of work near enough to a wearer that some arm of theirs might reach it.
---
---Searched once and handed to every arm, rather than each arm searching for itself. The
---search is the expensive part of a tick and the answer is the same for all of them: only
---the range each arm judges it by differs, and that is a comparison rather than a search.
---Widened by how far out an arm's base can sit, because each arm judges what it found
---from its own base rather than from the middle of what it is bolted to.
---
---And widened again by wherever its owner is going. A hand set off with now arrives a swing
---from now, by which time its owner has walked on, so what is worth finding is everything
---some arm could meet at any point between here and there rather than everything in reach
---of where they stand this instant. lib/reach.lua draws that circle; what comes back from it
---is a superset and nothing here prunes it, because every arm judges each candidate against
---its own reach anyway -- see choose(), which turns away what it cannot get to.
---@param wearer LuaEntity the character or vehicle the arms are on
---@param list table[] the arms, whose tiers say how far and how long each reaches
---
---Global, and for the same reason press() is: what this promises is that nothing an arm
---could meet is left out, and the only way to see what a search actually brought back is to
---make it. The circle itself is arithmetic and is checked in test/spec/reach_spec.lua; this
---is where that circle meets the engine.
---@param drift {x: number, y: number} how far their owner went last tick
---@return LuaEntity[]
---@param rounds number? how many swings' worth of ground to cover, defaulting to one.
---  More than one is for sizing a round: a claw that carries several stays out for all of
---  them, so the ground it will cover before it comes home is that much further on than
---  the ground it can reach this instant. Only worth paying for where a round is actually
---  being sized, which is once a journey rather than once a tick.
function work_near(wearer, list, drift, rounds)
  local arms = {}
  for _, record in pairs(list) do
    local tier = tier_of(record)
    arms[#arms + 1] = { range = tier.range, ticks = reach.full_swing(tier) * (rounds or 1) }
  end
  -- A radius, and a radius rather than a square. Two things went wrong with the square this
  -- replaces. A square of side twice the range reaches 1.41 times as far at its corners, and
  -- find_entities_filtered returns anything whose own box merely overlaps the area, so a
  -- ghost whose centre was well over four tiles away came back as a candidate. It was then
  -- abandoned as out of range on the very next tick, and found again the tick after: the arm
  -- swung out and back for ever, and because a swing counted as under way, no ghost that was
  -- actually in reach got a turn.
  -- A box lying along the walk where there is one, and the circle where there is not. The
  -- four searches below all draw the same shape, so the saving is four times over.
  local spread = spread_of(wearer)
  local offset, radius = reach.search(arms, drift)
  radius = radius + spread
  local at = { x = wearer.position.x + offset.x, y = wearer.position.y + offset.y }
  local middle, long, wide, turned = reach.search_box(arms, drift)
  local shape
  if middle then
    local centre = { x = wearer.position.x + middle.x, y = wearer.position.y + middle.y }
    shape = { area = { left_top = { centre.x - long - spread, centre.y - wide - spread },
                       right_bottom = { centre.x + long + spread, centre.y + wide + spread },
                       orientation = turned } }
  else
    shape = { position = at, radius = radius }
  end

  ---Everything of a kind inside whichever shape this search is drawn as.
  ---@param filter table
  local function inside(filter)
    for key, value in pairs(shape) do filter[key] = value end
    return wearer.surface.find_entities_filtered(filter)
  end

  local found = inside{ type = "entity-ghost" }

  -- An upgrade order is not a ghost and never was. The planner leaves the belt standing
  -- where it stood and hangs an order on it, so a search for ghosts finds nothing at all,
  -- which is the whole of why the arms ignored the upgrade planner. The orders have a
  -- search of their own.
  -- A deconstruction order is not a ghost either, and a tile marked for removal is an
  -- entity of its own -- a deconstructible-tile-proxy standing on the tile -- so the same
  -- search finds both.
  for _, marked in pairs(inside{ to_be_deconstructed = true }) do
    if marked.type ~= "entity-ghost" and marked.type ~= "cliff" then
      found[#found + 1] = marked
    end
  end

  for _, cliff in pairs(inside{ type = "cliff", to_be_deconstructed = true }) do
    found[#found + 1] = cliff
  end
  for _, marked in pairs(inside{ to_be_upgraded = true }) do
    -- A ghost can carry an upgrade order too, and is in the list already. Anything with no
    -- unit number is left out rather than reached for: two arms are kept off the same
    -- piece of work by its number, and work that cannot be claimed cannot be shared out.
    if marked.type ~= "entity-ghost" then found[#found + 1] = marked end
  end

  return found
end

---Whether there is anywhere to put what taking this up would bring back.
---
---An arm that sets off for something it has nowhere to put comes home holding it and
---stands there, worn, slowing its owner and doing nothing, until somewhere turns up. That
---is the right thing to do once the claw is holding a player's belt -- dropping it on the
---floor because their pockets filled is worse -- and it is no reason to set off in the
---first place. So a fetch is only taken on if what it will bring back will go somewhere.
---
---What it will bring back is the first clawful rather than the thing itself: a chest with
---something in it is emptied before it goes, so what has to fit is what is inside it.
---@param inventory LuaInventory
---@param work LuaEntity
---@return boolean
local function room_for(inventory, work)
  local name, grade = yields(work)
  -- Nothing comes back from it, so nowhere to put it is no obstacle. A tile marked for
  -- removal whose prototype yields nothing is still worth taking up.
  if not name then return true end
  return inventory.can_insert{ name = name, quality = grade, count = 1 }
end

---Pick something to build out of what was found near the player.
---
---Asks nothing about power: a claw already out and carrying does not have to bank a fresh
---reserve to turn to the next ghost. Setting off in the first place does, which is
---job_for below.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arms are on
---@param from {x: number, y: number} where this arm reaches from, from reaching_from
---@param nearby LuaEntity[] from work_near
---@param claimed table<integer, boolean>? ghosts another arm is already reaching for
---@param range number how far this arm can reach
---@return LuaEntity? ghost
---@return string? item
---@return integer? count
---@return string? quality what quality of that item it has to be
local function choose(player, wearer, from, nearby, claimed, range, record)
  local inventory = pockets(player, wearer)
  if not inventory then return nil end
  ---How many of an item the wearer has at a given quality.
  ---
  ---At that quality and no other. A ghost of a legendary belt is raised legendary and an
  ---order to upgrade to one puts a legendary one down, so paying for either with a normal
  ---belt out of the pocket would be minting the difference.
  local function carried_at(quality)
    return function(name)
      return stock_of(player, wearer, inventory, name, quality)
    end
  end

  -- Soonest first. The order find_entities_filtered hands things back in is the order they
  -- sit in the map's own index, which walks rows and then columns, so a claw clearing a
  -- patch crossed it in bands rather than working outward from itself.
  --
  -- Nearest first was the fix for that and is not quite the right question either. An
  -- inserter turns and extends at once, so what a target costs is whichever of those two
  -- is slower, and on the later tiers the turn is nearly always the slower one: a fourth
  -- tier arm crosses its five tiles in fifty ticks and turns right round in sixty-two. So
  -- a belt a tile away behind the claw costs more than one four tiles out in front of it,
  -- and sorting by distance sends the hand back and forth across the character while
  -- nearer work in front of it waits.
  --
  -- Where the hand is now is the whole of what makes this different from distance, so an
  -- arm still in its box is sorted by distance alone -- which is what the cost comes to
  -- anyway once there is no bearing to turn away from.
  local standing = wearer.position
  local tier = record and tier_of(record)
  local arm = record and record.entity
  -- Put back into the world before it is measured against anything in the world. An arm is
  -- teleported a lift above its owner so it rides on the body rather than at their feet, and
  -- everything it is aimed at has the same lift taken off it, so the hand reads a lift north
  -- of where it looks. Left as it comes, the bearing of the hand is taken from the wrong
  -- origin -- 0.70 of a tile on a character, which on a hand two tiles out is a fifth of a
  -- right angle of error in the one number this sort is for.
  local hand = nil
  if tier and arm and arm.valid then
    -- The hand the mod carries rather than the claw the engine draws, for the same reason
    -- course_to() asks of the carried one: past about two thirds of a turn the drawing is
    -- not where the arm is, and this is what decides which ghost is cheapest. Built back up
    -- from the two numbers, which is a radius along a bearing from the arm's own base.
    --
    -- No lift to put back on, either, which the drawing needed and this does not. An arm is
    -- drawn a lift above its owner and everything it is aimed at has the same lift taken
    -- off, so a hand read off the entity is a lift north of where it looks -- 0.70 of a tile
    -- on a character, which on a hand two tiles out is a fifth of a right angle of error in
    -- the one number this sort is for. A radius and a bearing are the same either way.
    local out, pointing = hand_out(record), record.pointing
    if pointing then
      hand = { x = from.x + pointing.x * out, y = from.y + pointing.y * out }
    end
  end
  -- One pass keeping the best, rather than pricing everything and sorting it.
  --
  -- choose() does not want a sorted list. It wants the cheapest piece of work that will
  -- actually do, and it was paying n log n over a comparator that can measure two distances
  -- to find one. Everything below is the same answer by a shorter road: the cheapest
  -- candidate that passes, ties broken by distance, exactly as the sort had it.
  --
  -- Three things are skipped rather than done. Anything outside the cone the hand can
  -- really sweep goes before it is priced at all, by arithmetic rather than by the
  -- quadratic solve reach.meets costs. Anything whose price cannot beat the best so far
  -- goes before its turn is worked out -- a swing costs the greater of stretching and
  -- turning, so the stretch alone is a floor under it, and the stretch is one distance
  -- where the turn is two arctangents. And the acceptance test below, which is a handful
  -- of prototype and inventory lookups, runs only for a candidate that would take the lead.
  --
  -- Measured over a packed field behind a train at the fourth tier: 5629 microseconds a
  -- search to 388.
  local cone
  if tier and record then
    cone = reach.cone(
      { range = range, extension = tier.extension, out = hand_out(record) },
      record.drift or STILL, reach.full_swing(tier))
  end
  local reaching = hand and reach.distance(from, hand) or 0

  local best, best_price, best_far
  local best_item, best_needed, best_quality
  for _, work in pairs(nearby) do
    if work.valid then
      local at = work.position
      if not cone or reach.in_cone(cone, { x = at.x - from.x, y = at.y - from.y }) then
        local far = reach.distance(from, at)
        local skip = false
        if hand and best then
          -- the floor under this swing's price, which costs one distance to know
          skip = math.abs(far - reaching) / tier.extension > best_price
        end
        if not skip then
          local price = hand and reach.swing_ticks(tier, from, hand, at) or far
          -- What standing on a thing really adds, which is one extension of the arm.
          --
          -- Taking something up from under the base is the slowest swing there is: the hand
          -- comes all the way in, and whatever is next has to go all the way out again. So
          -- it belongs behind work that is merely near, and that is all -- there used to be
          -- a hundred thousand ticks here, which is not a queue position but a refusal.
          -- Anything underfoot waited for a moment when nothing else was in reach at all,
          -- and somebody standing among their own work never gives it that moment; what it
          -- read as was an arm that would not pick up what you were standing on.
          --
          -- Measured on a heap underfoot with eight marked belts round it: banished, the
          -- heap went last at tick 317 and the lot was clear at 317; with nothing added it
          -- went first at tick 3 and the lot took until 592, because every journey after it
          -- started from a fully folded hand. One extension is the cost the next job
          -- actually pays.
          if taking(work) and underfoot(work, standing) then
            price = price + (tier and tier.range / tier.extension or 0)
          end

          local better
          if not best then better = true
          elseif price < best_price then better = true
          elseif price == best_price then
            -- Ties are common, because a swing that is all turn costs the same whatever
            -- its reach. Distance breaks them, so the claw still works outward from itself.
            better = far < best_far
          end

          if better then
            local ghost = work
            if still_wanted(ghost) then
              local outcome, outcome_quality = outcome_of(ghost)
              local quality = outcome_quality and outcome_quality.name or "normal"
              local item, needed
              if taking(ghost) then
                item, needed = nil, 0
              elseif exploding(ghost) then
                item, needed = build.placing_item(explosive_for(ghost), carried_at(quality))
              elseif outcome then
                item, needed = build.placing_item(outcome.items_to_place_this,
                  carried_at(quality))
                if item and paired_with(ghost) then
                  needed = needed * 2
                  if carried_at(quality)(item) < needed then item = nil end
                end
              end
              if (item or (taking(ghost) and room_for(inventory, ghost)))
                  and not (claimed and claimed[claim_of(ghost)])
                  and not set_aside_still(ghost)
                  -- The whole course, bearing and all, rather than the generous filter that
                  -- used to stand here. What this offers is taken -- assign() and redirect()
                  -- both set off for it -- so offering something the next tick's
                  -- holding_course() would refuse is how a claw comes to change its mind
                  -- every tick.
                  --
                  -- Asked here rather than of every candidate because only one that would
                  -- take the lead gets this far, which is a handful a search. Measured on the
                  -- train of test/ft/turning.lua, which is eight arms over nine hundred ticks
                  -- of a packed double line: 927 and 801 milliseconds against 903 and 790.
                  and course_to(record, from, ghost.position, range, record.job == nil)
                  and buildable(ghost) then
                best, best_price, best_far = ghost, price, far
                best_item, best_needed, best_quality = item, needed, quality
              end
            end
          end
        end
      end
    end
  end
  if best then return best, best_item, best_needed, best_quality end
  return nil
end

---How many things a claw may put down in one trip out.
---
---A trip is what carries several, not the claw: it holds one at a time and is refilled
---where it stands, because a hand holding more than one is what crashes the game. What is
---saved either way is the journey home between one ghost and the next.
---
---At most how many of the same thing to go looking for.
---
---Whatever the inserter it borrows from would be holding at the same research: one for a
---plain inserter and two for a bulk one, plus the relevant capacity bonus. No tier gets a
---head start of its own on top of that, so an arm never carries more than the thing it is
---made of.
---
---An upper bound only. What the claw actually takes is whatever the engine lets it hold,
---which is read back off the hand once it is filled, so the queue of ghosts and the load in
---the claw cannot disagree -- when they did, an arm set out queued for six deliveries
---holding four, ran dry two short, and threw the rest of the journey away.
---@param force LuaForce
---@param tier table
---@return integer
local function trips_for(force, tier)
  if tier.bulk then
    return tiers.BULK_BASE + math.max(0, math.floor(force.bulk_inserter_capacity_bonus or 0))
  end
  return 1 + math.max(0, math.floor(force.inserter_stack_size_bonus or 0))
end

---How many of the same thing are worth queueing for one trip.
---
---As many as the trip allows, but never more than there is work for or the character is
---carrying: queueing more than there are ghosts for only means going home early.
---@param nearby LuaEntity[]
---@param claimed table<integer, boolean>?
---@param standing {x: number, y: number} where the wearer is, for what it is standing on
---@param from {x: number, y: number} where the arm reaches from
---@param range number
---@param item string
---@param count integer how many the ghost being reached for takes
---@param carried integer how many the character has
---@param capacity integer how many loads the claw holds
---@return integer
local function loads_for(record, nearby, claimed, standing, from, range, item, quality,
                         count, carried, capacity)
  if capacity <= 1 then return 1 end
  -- What the claw is shopping for is the whole round, and a round is not one swing long.
  -- The claw stays out from the first ghost to the last, and its owner walks on the whole
  -- time, so the second thing on the list is met from a good deal further along than the
  -- first. Sized against one swing apiece the list stopped at whatever was already close
  -- enough to reach immediately, which on anything that moves is the near end of the work
  -- and no more: four ghosts ten to thirteen tiles ahead of a walk came out as a round of
  -- two, the claw went home with the round spent, and the walk had carried the other two
  -- square abeam by the time it was free again -- where nothing walking can ever reach
  -- them. A swing apiece is the budget instead, so the nth thing on the list has n of them
  -- to be met in.
  local swing = reach.full_swing(tier_of(record))
  local wanted = 1
  for _, ghost in pairs(nearby) do
    if wanted >= capacity then break end
    if still_wanted(ghost) and not (claimed and claimed[claim_of(ghost)])
        and not standing_in(ghost, standing)
        -- Whether the arm could meet it at any point in the flight rather than whether it
        -- happens to be in reach this instant. Generous, and deliberately not the whole
        -- course choose() works out: this is counting how many to carry, and each one is put
        -- to course_to() properly when the claw comes to cross to it.
        -- Asked the old way, a round set off for by an arm that is leading its first ghost
        -- counted nothing at all -- the whole round is ahead of its owner at that moment --
        -- so the claw carried one and crossed to nothing. Measured on four ghosts ten to
        -- thirteen tiles ahead of a walk: one built, no crossing.
        and not out_of_reach(record, from, ghost.position, range, swing * (wanted + 1)) then
      local outcome, outcome_quality = outcome_of(ghost)
      local other, needed
      if outcome then
        other, needed =
          build.placing_item(outcome.items_to_place_this, function() return count end)
      end
      if other == item and needed == count
          and (outcome_quality and outcome_quality.name or "normal") == quality then
        wanted = wanted + 1
      end
    end
  end
  return math.max(1, math.min(wanted, math.floor(carried / count)))
end

---Pick something for an arm to set off after, which it may only do on a full buffer.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arms are on
---@param from {x: number, y: number} where this arm reaches from
---@param nearby LuaEntity[] from work_near
---@param claimed table<integer, boolean>? ghosts another arm is already reaching for
---@param record table the arm asking, which knows which equipment feeds it
---@param range number how far this arm can reach
---@return LuaEntity? ghost
---@return string? item
---@return integer? count
---@return LuaEntity? ghost the one to reach for, if it can set off now
---@return string? item
---@return integer? count
---@return boolean waiting whether there is work but not yet the charge to do it
local function job_for(player, wearer, from, nearby, claimed, record, range)
  if not ready(record) then
    -- Still worth knowing whether there is anything to do. Setting off wants a full
    -- buffer, and a delivery spends some of it, so an arm that has just finished one is
    -- not ready on the very next tick. Filling it again takes a single tick from charged
    -- batteries -- measured at every tier -- but a single tick was enough: with no arm
    -- reporting work the run was declared over, the character started easing back to full
    -- speed, and a fresh slowdown began a tick later, so they oscillated instead of
    -- settling. The run ends when the work runs out, not when an arm is a tick short of
    -- being able to start the next trip.
    local ghost = choose(player, wearer, from, nearby, claimed, range, record)
    return nil, nil, nil, nil, ghost ~= nil
  end
  local ghost, item, count, quality = choose(player, wearer, from, nearby, claimed, range,
    record)
  return ghost, item, count, quality, false
end

---The list of a player's arms, one per copy of the equipment they are wearing.
---
---Taking a copy out of the grid takes the last arm away rather than a particular one:
---which of several identical arms goes is not a question worth answering, and the ones
---that stay keep whatever they were doing.
---@param player LuaPlayer
---@return table[]
local function arms(player)
  local list = storage.constructor_arms[player.index]
  if not list then
    list = {}
    storage.constructor_arms[player.index] = list
  end
  return list
end

---The inserter for one arm, made if it is not there yet.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle it is mounted on
---@param record table
---@return LuaEntity?
local function arm_of(player, wearer, record)
  local arm = record.entity
  if not (arm and arm.valid) then
    arm = wearer.surface.create_entity{
      name = tier_of(record).inserter,
      position = wearer.position,
      force = player.force,
      -- Which way it is built facing is which way its hand starts, and a hand cannot be
      -- turned afterwards. See point(), which is what decides this; nothing here means
      -- north, which is what an inserter faces when nobody says otherwise.
      direction = record.facing,
    }
    -- Filled the moment it exists, out of its own equipment, so that it never spends a
    -- tick on empty. Out of the equipment, not out of nothing: handing it a free bufferful
    -- here while refunding the remainder when it is put away would have made an arm coming
    -- and going a way of generating power.
    if arm and wearer.grid then
      charge(record, arm)
    end
    record.entity = arm
    -- A fresh hand is born at reach.BORN along the way the arm was built facing, and follow()
    -- carries it from there. Deliberately not marked as followed for this tick: measured, an
    -- arm charged on the tick it is made has already taken its first step by the next one,
    -- so the step follow() makes on the next tick is one the engine really made.
    record.out, record.pointing = reach.BORN, born_facing(record)
    record.chasing_drop = arm and arm.held_stack.valid_for_read or false
  end
  return arm
end

---Draw the claw shrinking away where the arm was.
---
---The arm itself cannot do this. An entity's sprites are scaled in its prototype, and
---nothing changes that at runtime, so the entity goes and a drawn copy of its folded claw
---takes its place for a fifth of a second: a sprite's scale and tint are script's to set.
---@param tier table
---@param surface LuaSurface
---@param at {x: number, y: number}
local function stow(tier, surface, at, wearer)
  -- Sprites are not among the prototypes script can look up, so the path is checked rather
  -- than the prototype. Worth checking at all for the same reason the stickers are: a
  -- script reloaded without its data stage runs against prototypes that never heard of it.
  if not helpers.is_valid_sprite_path(tier.claw) then return end
  -- Pinned to whoever was wearing it rather than to a spot on the ground. A claw fading
  -- where the character used to be, while the character walks off, is the one thing about
  -- putting an arm away that looked like a fault, and it happened every time an idle arm
  -- went away from somebody on the move.
  --
  -- Only while they are still on the same ground, though. A wearer can leave the surface
  -- between one tick and the next -- boarding a rocket does exactly that -- and the arm does
  -- not go with them, so by the time it is put away the two are in different worlds. A
  -- sprite drawn on one surface and pinned to an entity on another is not something the
  -- engine shrugs at: it raises, and it raises out of on_tick, which takes the whole mod
  -- down with it. Left where the arm is instead, which is where it was.
  local target = { at.x, at.y }
  if wearer and wearer.valid and wearer.surface == surface then
    target = { entity = wearer,
               offset = { at.x - wearer.position.x, at.y - wearer.position.y } }
  end
  local drawn = rendering.draw_sprite{
    sprite = tier.claw,
    surface = surface,
    target = target,
    x_scale = tiers.SCALE,
    y_scale = tiers.SCALE,
    render_layer = "object",
  }
  if drawn then
    storage.constructor_stowing = storage.constructor_stowing or {}
    storage.constructor_stowing[drawn.id] = game.tick
  end
end

---Shrink and fade everything part way through being stowed, and clear away what is done.
local function stowing()
  storage.constructor_stowing = storage.constructor_stowing or {}
  for id, started in pairs(storage.constructor_stowing) do
    local drawn = rendering.get_object_by_id(id)
    local gone = (game.tick - started) / STOW_TICKS
    if not (drawn and drawn.valid) or gone >= 1 then
      if drawn and drawn.valid then drawn.destroy() end
      storage.constructor_stowing[id] = nil
    else
      local left = 1 - gone
      drawn.x_scale = tiers.SCALE * left
      drawn.y_scale = tiers.SCALE * left
      drawn.color = { r = 1, g = 1, b = 1, a = left }
    end
  end
end

---Show, or stop showing, that there is work in reach and not the charge to go for it.
---
---A character standing among ghosts with nothing happening has no way of telling a flat
---armour from a broken mod. The game already marks every machine that is short of power, so
---this borrows that rather than inventing a second vocabulary for it.
---
---The mark goes on the wearer rather than on an arm, because in this state there is usually
---no arm: an armour that cannot raise a full buffer never sends one out, so what a player
---sees is their own back and nothing on it. That is the whole of the complaint the mark
---answers.
---
---What it is asked is the mod's own question -- is there work in reach that no arm can be
---sent to for want of charge -- rather than what any inserter reports about itself. Reading
---an arm's own status was the first attempt and was wrong both ways round. Measured on a
---character walking a row of belts with a charged battery it fired once for twelve ticks, on
---the cold start, which is a blip nobody needs marking; and on a flat grid it never fired at
---all, because an arm that cannot set off is never made and there is nothing to read a
---status from. The mod's own answer fires nought times in six hundred ticks in the first
---case and two hundred and ninety four out of three hundred in the second.
---@param player LuaPlayer
---@param wearer LuaEntity?
---@param waiting boolean whether some arm has work in reach and not the charge for it
local function flag_power(player, wearer, waiting)
  storage.constructor_marks = storage.constructor_marks or {}
  local id = storage.constructor_marks[player.index]
  local shown = id and rendering.get_object_by_id(id)
  if not (waiting and wearer and wearer.valid) then
    if shown and shown.valid then shown.destroy() end
    storage.constructor_marks[player.index] = nil
    return
  end
  -- Still up: keep it up. Its life is extended rather than the mark redrawn, so there is
  -- never a tick with two of them.
  if shown and shown.valid then
    shown.time_to_live = MARK_TICKS
    return
  end
  if not helpers.is_valid_sprite_path(POWER_ICON) then return end
  local drawn = rendering.draw_sprite{
    sprite = POWER_ICON,
    surface = wearer.surface,
    target = { entity = wearer, offset = { 0, -2 } },
    x_scale = 0.4,
    y_scale = 0.4,
    render_layer = "entity-info-icon",
    -- It dies on its own if nothing renews it. The alternative is an owner responsible for
    -- taking it down, and a character who stops being one leaves nobody to ask -- a mark
    -- hanging over an empty back for the rest of the game. A life a few check ticks long
    -- costs a redraw nobody sees and cannot be leaked.
    time_to_live = MARK_TICKS,
  }
  storage.constructor_marks[player.index] = drawn and drawn.id or nil
end

---Take one inserter away, emptying its hand first so nothing is conjured out of it.
---
---Nothing goes back into the inventory, because nothing ever came out of it: the hand is
---filled from nothing and the inventory is only debited when something arrives. So an arm
---Put items from the box back into the claw, where they are still the player's.
---@param record table
---@param name string
---@param quality string?
---@param count integer
local function take_back(record, name, quality, count)
  if count <= 0 then return 0 end
  local arm = record.entity
  if not (arm and arm.valid) then return 0 end
  local held = arm.held_stack.valid_for_read and arm.held_stack.count or 0
  arm.held_stack.set_stack{ name = name, quality = quality, count = held + count }
  -- What actually stuck, rather than what was asked for, and the box is only debited by
  -- that much. A hand holds what its inserter holds and the engine caps a stack set past
  -- that without a word: measured, a first tier claw asked to hold two undergrounds took
  -- one, and the other was not on the floor, or in the box, or anywhere. Emptying the box
  -- first and setting the stack afterwards is how that item used to disappear.
  local now = arm.held_stack.valid_for_read and arm.held_stack.count or 0
  local took = now - held
  local box = record.catcher
  if took > 0 and box and box.valid then
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then inside.remove{ name = name, quality = quality, count = took } end
  end
  return took
end


--- How near the claw has to be before its box exists at all. Generous on purpose: being
--- early costs nothing, and the whole point of the box is to stop measuring arrivals
--- finely. It only has to be absent while the claw is far enough away that somebody else
--- could get a whole swing in.
local OPEN = 2.5

---Give something back to whoever an arm was mustered against, and put on the floor what
---they cannot take.
---
---Pockets fill. Inserting and walking away destroys the difference, which is how a stack
---goes missing every time somebody's inventory is full at the wrong moment. Spilling is what
---the game does with what a character cannot hold, and the stack goes down as it stands so a
---damaged or a quality thing stays what it was. Unmarked: it is the player's own.
---@param player LuaPlayer
---@param wearer LuaEntity?
---@param inventory LuaInventory?
---@param stack table
local function give_to(player, wearer, inventory, stack)
  local count = stack.count or 0
  if count <= 0 then return end
  local quality = stack.quality and (stack.quality.name or stack.quality) or nil
  local took = inventory and inventory.insert{ name = stack.name, quality = quality,
                                               count = count } or 0
  if took >= count then return end
  if not (wearer and wearer.valid) then return end
  wearer.surface.spill_item_stack{
    position = wearer.position,
    stack = { name = stack.name, quality = quality, count = count - took },
    enable_looted = true,
    force = player.force,
  }
end

---Empty a box of everything in it, so that taking it away costs nothing.
---
---A box is not always holding its own arm's load. It stands wherever its claw is aimed, and
---while a claw is leading that is a guess at where its ghost will be, so two arms bolted to
---one hull can put their guesses on the same tile however far apart their ghosts are. The
---engine empties a hand into whatever container stands at its drop position and does not
---ask whose it is, so a box can be holding another arm's load at the moment it is taken
---away -- and that arm's own claw is somewhere else, with a hand that may already be full.
---
---The claw first, since it is going home anyway and the load is most likely its own. Then
---the pockets the arm was mustered against, and then the floor, which is where anything
---goes that will not fit.
---
---Measured on eight second tier arms on a locomotive: about one belt in two hundred went
---exactly that way. Arm three's load landed in arm four's box, arm four's hand was already
---holding its own belt so the claw would not take it, and the box was destroyed with it
---still inside. The theft is old and costs a journey; destroying what was stolen was the
---whole of the loss.
---@param record table
local function catcher_empty(record)
  local box = record.catcher
  if not (box and box.valid) then return end
  local inside = box.get_inventory(defines.inventory.chest)
  if not inside or inside.is_empty() then return end

  for _, stack in pairs(inside.get_contents()) do
    take_back(record, stack.name, stack.quality and (stack.quality.name or stack.quality)
      or nil, stack.count)
  end
  if inside.is_empty() then return end

  -- Whoever the arm was mustered against, which for an arm on a locomotive is the train's
  -- cargo: where the load came out of in the first place.
  local player = record.owner and game.get_player(record.owner)
  local hold = player and pockets(player, record.wearer) or nil
  for _, stack in pairs(inside.get_contents()) do
    local quality = stack.quality and (stack.quality.name or stack.quality) or nil
    local took = hold and hold.insert{ name = stack.name, quality = quality,
                                       count = stack.count } or 0
    if took < stack.count then
      -- On the floor where the box stood, rather than away with it. Not onto a belt: a
      -- lane swallows a stack whole and it is then nowhere anybody would look for it.
      box.surface.spill_item_stack{
        position = box.position,
        stack = { name = stack.name, quality = quality, count = stack.count - took },
        enable_looted = true,
        force = box.force,
        allow_belts = false,
      }
    end
    inside.remove{ name = stack.name, quality = quality, count = stack.count }
  end
end

---The box belonging to this arm, present only while this claw is near enough to be the one
---filling it.
---
---An open box is a hole in the world: it accepts insertions, so an inserter of the
---player's own pointing at a tile a ghost stands on would quietly feed it and the mod would
---take a stranger's item for its own delivery. Whether a container accepts automated
---insertion is fixed in its prototype and cannot be turned off and on, so the box is
---created and destroyed instead of being opened and shut.
---@param record table
---@param surface LuaSurface
---@param at {x: number, y: number}
---The box it hands back has to be pinned as the arm's drop_target by whoever asked for
---it, on the same tick. See pin_to() below for why, and for what happens when nobody does.
---@param near boolean whether this claw is close enough for a delivery to be possible
---@return LuaEntity?
local function catcher_at(record, surface, at, near)
  local box = record.catcher
  if not near then
    -- Nothing of ours should be in it yet. Something else's may be, and whatever is there
    -- is handed out before the box goes rather than destroyed with it.
    if box and box.valid then
      catcher_empty(record)
      box.destroy()
    end
    record.catcher = nil
    return nil
  end
  if box and box.valid then
    if box.position.x ~= at.x or box.position.y ~= at.y then box.teleport(at) end
    return box
  end
  -- The arm's own force, not neutral: an inserter will not put anything into another
  -- force's container, and a neutral box was quietly ignored while the load went on the
  -- ground beside it.
  local owner = record.entity and record.entity.valid and record.entity.force or "player"
  box = surface.create_entity{ name = CATCHER, position = at, force = owner }
  record.catcher = box
  return box
end

---A box with nothing in it and no room for anything, stood where an idle claw rests.
---
---An inserter takes from whatever container is at its pickup position, and an arm's claw
---rests two tenths of a tile from where it is bolted on -- which is on its owner. So an arm
---with nothing to do helps itself to whatever its owner is standing on. Measured: a
---character standing on an iron chest of fifty belts had one out of it and into the claw,
---and an arm bolted to a tank took one out of the tank's own hold the same way.
---
---What that costs on its own is a chest quietly emptied by somebody walking over it, since
---the belt goes to the player's pockets when the arm is put away. What it used to cost as
---well was the belt itself: the next job's load was written straight over the hand.
---
---So an idle claw is given something to reach into that can never give it anything. Its own
---box, with the bar down, so that nothing can be put in it either and there is therefore
---never anything to take out.
---@param record table
---@param surface LuaSurface
---@param at {x: number, y: number}
---@return LuaEntity?
local function keeper_at(record, surface, at, shut)
  local box = record.keeper
  if not (box and box.valid) then
    local owner = record.entity and record.entity.valid and record.entity.force or "player"
    box = surface.create_entity{ name = CATCHER, position = at, force = owner }
    record.keeper = box
  elseif box.position.x ~= at.x or box.position.y ~= at.y then
    box.teleport(at)
  end
  if not box then return nil end

  -- Shut for an idle claw, so there is never anything in it to help itself to. Open for one
  -- with a job, because a claw coming home has to be able to come home: measured, an arm
  -- whose drop is a box with no room in it is told there is no space and holds its hand
  -- where it is rather than bringing it in, and the load then never reaches the pockets at
  -- all. Open, the engine treats the rest point as somewhere it could let go and travels
  -- there -- and it never does let go, because the rest point is nearer the base than a
  -- hand can reach, which is the arrangement the homecoming has always run on.
  local inside = box.get_inventory(defines.inventory.chest)
  if inside and inside.supports_bar() then inside.set_bar(shut and 1 or (#inside + 1)) end
  return box
end

---Take the idle claw's box away, for an arm that has work to do again.
---@param record table
local function keeper_away(record)
  local box = record.keeper
  record.keeper = nil
  if box and box.valid then box.destroy() end
end

---Say that this box, and nothing else, is where this claw hands over.
---
---An inserter's drop target is not worked out fresh from its drop position every tick: the
---engine keeps it, and what it keeps beats what the position would say. Left to itself it
---picks the wrong thing twice over.
---
---Measured on a bare arm inserter of the fourth tier, over four runs, dropping into a box
---on a tile with a belt already standing on it:
---
---  box alone                                 2 into the box, 0 onto the belt
---  a belt on the box's tile                  0 into the box, 2 onto the belt
---  that, and teleported onto itself each tick 0 into the box, 2 onto the belt
---  that, and this line                       2 into the box, 0 onto the belt
---
---So a belt outranks the box on a shared tile, and the arms build belts: the tile a claw is
---aimed at along the way to a ghost is very often a tile one of them has just finished. And
---teleporting the entity clears the target outright -- even a teleport to the spot it is
---already standing on, which is what aim() does to every arm on every tick -- after which
---the engine resolves by position again and the belt wins again.
---
---Hence on the same tick as the teleport, every tick, from whoever positioned the box. The
---engine's update for the next tick runs before the next aim(), so the pin is always in
---force at the moment the hand lets go.
---@param record table
---@param box LuaEntity? what catcher_at handed back, if anything
local function pin_to(record, box)
  local arm = record.entity
  if not (arm and arm.valid and box and box.valid) then return end
  arm.drop_target = box
end

---The same for the other end of the swing: this box, and nothing else, is what this claw
---reaches into.
---
---A fetch is where it matters, because a fetch is the one job whose box stands at the
---pickup. A claw reaches for a source because there is something at its pickup position to
---reach for, and the teleport in aim() throws the engine's answer to that away every tick
---the same as it throws away the drop's.
---
---A delivery survives that, because the engine re-resolves when the hand lets go and there
---is a whole swing of ticks for it to happen in. A fetch does not: with nothing resolved
---there is nothing to set off towards, so the hand sits at the radius it was born at,
---reporting itself working, for the whole of the swing limit. Measured on eight things
---marked in a ring round a character standing still -- three go and the claw stalls on the
---fourth, with its box standing exactly on its own pickup position and pickup_target empty.
---@param record table
---@param box LuaEntity? what catcher_at handed back, if anything
local function pin_from(record, box)
  local arm = record.entity
  if not (arm and arm.valid and box and box.valid) then return end
  arm.pickup_target = box
end

---Take the box away, losing nothing that was in it.
---
---Every caller used to be trusted to deal with what this handed back, and five of the six
---ignored it. So the emptying happens here, where it cannot be forgotten, and there is
---nothing left to hand back.
---@param record table
local function catcher_away(record)
  local box = record.catcher
  if not (box and box.valid) then record.catcher = nil return end
  catcher_empty(record)
  record.catcher = nil
  box.destroy()
end

---put away mid reach, whether because the character walked off or because they took the
---equipment out of their armour, costs them nothing.
---@param player LuaPlayer
---@param record table
local function put_away(player, record)
  keeper_away(record)
  local arm = record.entity
  local wearer = record.wearer or player.character
  local inventory = pockets(player, wearer)

  ---Hand something back to whoever the arm was mustered against, and put on the floor
  ---whatever they cannot take.
  ---
  ---Pockets fill, and an arm being put away is holding things that were paid for out of
  ---those pockets or fetched on their behalf. Inserting and then clearing regardless
  ---destroys the difference, which is a stack lost every time the toolbar button is pressed
  ---with a full inventory. A vehicle makes it worse than an edge case: a locomotive has no
  ---hold at all, only a three slot burner box, so every insert into one takes nothing.
  ---
  ---Spilling is what the game does with what a character cannot hold, and the stack goes
  ---down as it stands so that a damaged or a quality thing stays what it was. Unmarked: it
  ---is the player's own, not a shed.
  ---@param stack LuaItemStack|table
  local function hand_back(stack)
    local count = stack.count or 0
    if count <= 0 then return end
    local took = inventory and inventory.insert(stack) or 0
    if took >= count then return end
    if not (wearer and wearer.valid) then return end
    if took > 0 then stack.count = count - took end
    wearer.surface.spill_item_stack{
      position = wearer.position,
      stack = stack,
      enable_looted = true,
      force = player.force,
    }
  end

  -- The box goes with the arm, and what it was holding is not the box's. A claw that had
  -- just put a belt in it, or one being handed what it had come to fetch, had that thrown
  -- away with the box: for a long time catcher_away said what was left in it and nobody
  -- was listening. It hands it back itself now.
  catcher_away(record)

  if arm and arm.valid then
    -- Whatever it was carrying was paid for out of the pockets, so it goes back in them
    -- rather than being destroyed with the arm. The pockets it was mustered against, for
    -- the same reason the charge goes back to the grid it was mustered against: an arm put
    -- away as its owner climbs out of a vehicle is holding the vehicle's belt, not theirs.
    local job = record.job
    if job and (job.escrow or 0) > 0 and job.item then
      hand_back{ name = job.item, quality = job.quality, count = job.escrow }
      job.escrow = 0
    end
    if arm.held_stack.valid_for_read then
      hand_back(arm.held_stack)
      arm.held_stack.clear()
    end
    -- whatever it was holding in its buffer goes back where it came from, so that taking
    -- the arm out and putting it away again is not itself a way of burning charge
    --
    -- The grid the arm was mustered against, rather than whatever its owner is wearing by
    -- now. Getting into a vehicle changes which grid that is, and the arms of the one just
    -- left are put away on that very tick: refunding into the new grid would take charge
    -- out of the armour and hand it to the car.
    if record.grid and record.grid.valid then
      refund(record.grid, record.piece, arm.energy)
    end
    -- Where the arm is bolted on, which by now is where it belongs: an arm switched off
    -- part way through a reach has already swung home before this runs, so there is nothing
    -- left out in the air for the picture to have to account for. Stowing at the hand
    -- instead put the claw out at the rest point, a tile off to one side of its owner,
    -- which is not where an arm goes when it is put away.
    stow(tier_of(record), arm.surface, arm.position, wearer)
    arm.destroy()
  end
  record.entity = nil
  record.job = nil
  record.busy = nil
  record.run = nil
  record.lift = nil
  record.stranded = nil
end

---Put every one of a player's arms away and forget they had any.
---@param player LuaPlayer
local function dismiss(player)
  local list = storage.constructor_arms[player.index]
  if not list then return end
  for _, record in pairs(list) do put_away(player, record) end
  storage.constructor_arms[player.index] = nil
end

---Switch a player's arms off without taking them away where they stand.
---
---An arm halfway through a delivery is a hand out in the air holding something. Taking it
---away there is the arm ceasing to exist mid reach, which reads as a fault whatever the
---fade is doing. What putting a tool away looks like is the hand coming back first: the
---claw retracts along the line it was working on, hands over what it was carrying, and only
---then folds up.
---
---The arm is lifted out of its owner's list the moment the button is pressed, so it takes
---no more work from that tick on, and swings home on its own. Kept apart from the list
---rather than flagged inside it, so that nothing walking that list has to learn about an
---arm that is present and not to be used.
---
---One that is already home is simply put away: there is nothing to watch.
---@param player LuaPlayer
local function fold(player)
  local list = storage.constructor_arms[player.index]
  if not list then return end
  storage.constructor_folding = storage.constructor_folding or {}
  for _, record in pairs(list) do
    local arm, rest = record.entity, record.rest
    if arm and arm.valid and rest and record.bearing
        and reach.distance(arm.held_stack_position, rest) >= within(tier_of(record), HOME) then
      arm.pickup_position = { rest.x, rest.y }
      -- An empty hand comes home to the pickup position by itself. A full one goes
      -- wherever it was told to drop, so it has to be told, and told the rest point rather
      -- than the mount: that is where home is measured from, and aiming anywhere else has
      -- the engine put the load on the ground before this notices it arrived.
      if arm.held_stack.valid_for_read then arm.drop_position = { rest.x, rest.y } end
      record.job = nil
      record.folded = game.tick
      storage.constructor_folding[#storage.constructor_folding + 1] = {
        player = player.index, record = record,
      }
    else
      put_away(player, record)
    end
  end
  storage.constructor_arms[player.index] = nil
end

---Bring every folding arm a tick nearer home, and put away the ones that have arrived.
---
---It goes on riding on whoever was wearing it: they can walk off while it comes in, and an
---arm left hanging where it was switched off would be worse than the snap this replaces.
---The bearing is the one it was working on, so this is a retraction rather than a swing.
local function folding()
  local list = storage.constructor_folding
  if not (list and #list > 0) then return end
  local left = {}
  for _, entry in pairs(list) do
    local record = entry.record
    local player = game.get_player(entry.player)
    local arm, wearer = record.entity, record.wearer
    local home = true
    if player and arm and arm.valid and wearer and wearer.valid and record.bearing then
      -- Fed on the way in, the same as aim() feeds one on the way out. Without this a
      -- folding arm retracts on whatever happened to be left in its buffer and stops dead
      -- when that runs out: measured, a fourth tier claw carrying a belt ran its buffer
      -- down over three tiles of retraction and halted 0.98 from its own base with twenty
      -- megajoules in the battery beside it. It then hung there until the swing limit gave
      -- up on it five seconds later, which is when the player finally got their belt back.
      charge(record, arm)
      local mount, lift = mounting(wearer, record.slot, record.count)
      arm.teleport(mount)
      record.lift = lift
      local rest = { x = mount.x + record.bearing.x * REST,
                     y = mount.y + record.bearing.y * REST }
      record.rest = rest
      arm.pickup_position = { rest.x, rest.y }
      if arm.held_stack.valid_for_read then arm.drop_position = { rest.x, rest.y } end

      local hand = arm.held_stack_position
      local moved = record.came and reach.distance(hand, record.came) or nil
      record.came = { x = hand.x, y = hand.y }
      -- The same window the ordinary homecoming uses, widened by what the hand was just
      -- seen doing, because the engine's last step is larger than any tier's own figures
      -- predict. The limit is the backstop: a wearer that stops moving mid retraction, or
      -- a hand that cannot reach its rest point for some reason nobody has thought of,
      -- must not leave an arm hanging about for the rest of the game.
      -- Home when the hand has stopped coming in, rather than when it is near enough. It
      -- has to be near the base as well, so that a hand held up somewhere out in the air --
      -- by a flat armour, or by anything nobody has thought of -- is not read as a claw that
      -- has arrived; that one waits for the limit below.
      home = (moved ~= nil and moved < SETTLED
            and reach.distance(hand, mount) < within(tier_of(record), HOME, moved))
          or game.tick - (record.folded or game.tick) > SWING_LIMIT
    end
    if not home then
      left[#left + 1] = entry
    elseif player then
      put_away(player, record)
    elseif arm and arm.valid then
      arm.destroy()
    end
  end
  storage.constructor_folding = left
end

---Match the list of arms to the equipment being worn, tier for tier.
---
---An arm whose tier has not changed carries on with whatever it was doing. One whose tier
---has is a different arm: it is put away, and a new one of the right sort takes its place.
---Taking a copy out of the grid therefore takes the last arm of that tier away rather than
---a particular one, which is not a question worth answering.
---
---An arm belongs to the grid it was mustered against as much as to its tier: the same
---first tier equipment in a car is not the arm that was on its driver's back a tick ago,
---and carrying one over would have the armour's charge feeding the vehicle's arm. So a
---change of grid retires an arm exactly as a change of tier does.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle wearing the equipment
---@return table[]
---Take back an arm that is still swinging home from having been switched off.
---
---Pressing the button off lifts an arm out of its owner's list and leaves it folding on its
---own; pressing it on again straight away used to build a second one beside it, with a
---second load out of the pockets, while the first was still coming in. There is only one
---piece of equipment, so there should only ever be one arm.
---
---Matched on the tier and the grid, which is what muster matches everything else on.
---@param player LuaPlayer
---@param level integer
---@param grid LuaEquipmentGrid?
---@return table? the record, no longer folding
local function reclaim(player, level, grid)
  local folding = storage.constructor_folding
  if not (folding and #folding > 0) then return nil end
  for index, entry in ipairs(folding) do
    local record = entry.record
    if entry.player == player.index and record and record.level == level
        and record.grid == grid and record.entity and record.entity.valid then
      table.remove(folding, index)
      -- Only one with an empty hand. A claw still carrying what it set off with is carrying
      -- something out of its owner's pockets, and the handing back happens when an arm is
      -- put away: kept as it is, the load stayed in the hand while the fresh job took a
      -- second one out for the same ghost. Putting it away hands it back, and the arm that
      -- takes its place is made at the next departure, so there is still only ever one.
      if record.entity.held_stack.valid_for_read then
        put_away(player, record)
        return nil
      end
      -- It is an arm again rather than one on its way out: it has no job, so it will be
      -- given one or put away like any other idle arm.
      record.folded = nil
      record.came = nil
      return record
    end
  end
  return nil
end

local function muster(player, wearer)
  local list = arms(player)
  local want = worn(wearer)
  local grid = wearer.grid

  while #list > #want do
    put_away(player, list[#list])
    list[#list] = nil
  end
  for slot = 1, #want do
    local record = list[slot]
    if not record then
      list[slot] = reclaim(player, want[slot], grid) or { level = want[slot] }
    elseif record.level ~= want[slot] or record.grid ~= grid then
      put_away(player, record)
      list[slot] = reclaim(player, want[slot], grid) or { level = want[slot] }
    end
  end

  -- Each arm is powered by one piece of the equipment that put it there, so they are
  -- paired off: the first arm of a tier to the first piece of that tier, and so on. Which
  -- piece is which does not matter, only that two arms never feed from the same one.
  local taken = {}
  for _, record in ipairs(list) do
    local name = tier_of(record).name
    taken[name] = (taken[name] or 0) + 1
    record.piece = pieces_of(grid, name)[taken[name]]
    -- remembered so that putting the arm away can hand its charge and its load back where
    -- they were drawn from, whoever its owner is wearing by then. The player too, so that a
    -- box being taken away can find the pockets to empty itself into without every caller
    -- having to carry one down to it.
    record.grid = grid
    record.wearer = wearer
    record.owner = player.index
  end
  return list
end


---Build an arm facing what it is about to reach for.
---
---An inserter's hand starts where its entity faces and swings round from there, and a claw
---turns slowly. Measured on the fourth tier at its full five tiles, with every arm built
---facing north whatever it was about to do: a ghost due north was delivered on tick 32 and
---one due south on tick 97, with the bearings between them spread evenly across that
---range. The same reach, three times the wait, for a reason nothing on the screen explains.
---
---What a reach costs is the longer of two things happening at once: extending out, which
---is the same whichever way it faces, and turning to face it, which at a half turn is
---three times the extension and at nothing at all is free. So an arm is pointed before it
---sets off, and there is next to nothing left to turn through.
---
---Sixteen directions, which is as fine as the game counts them. An inserter takes the four
---cardinals and truncates anything else unless it is flagged building-direction-16-way, and
---these are: see prototypes/inserter.lua, where that is measured. So what is left to turn
---through is a thirty-second of a turn at worst, which is nothing at any reach.
---
---It will not turn one that already exists, and that has been looked into properly. A hand
---resting to the north was asked to face east eleven ways on 2.1.19: setting direction,
---which changes what direction reads and moves nothing; writing orientation, which is taken
---and reads back nought; rotate(), which is taken and leaves direction where it was;
---nudging the entity a quantum, four quantums and a sixteenth of a tile; teleporting it
---forty tiles away and back; and cloning it. Every one of them left the hand creeping round
---at its own speed, tick for tick identical to doing nothing at all. (active is read only
---on an inserter, so that one cannot even be tried.) The hand's rotation is its own state
---and nothing but building the entity again resets it.
---
---So pointing means building it again, which is why this happens once, as it leaves, and
---never during a reach: the claw is empty on the way out and there is nothing in the air to
---drop.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param job table what it is about to reach for
local function point(player, wearer, record, slot, count, job)
  local mount, lift = mounting(wearer, slot, count)
  -- The target in the frame the arm swings in, which is what aimed_at() answers: the same
  -- lift, and the lead where there is one. An arm is built facing where it is going, and
  -- where it is going is the lead rather than the ghost while the ghost is still out of
  -- reach -- built facing the ghost it would spend the whole swing turning off it.
  record.lift = lift
  local towards = aimed_at(job, record)
  local dx, dy = towards.x - mount.x, towards.y - mount.y
  if dx * dx + dy * dy < POINTED * POINTED then return end
  local wanted = pack.towards(dx, dy)

  local arm = record.entity
  if not (arm and arm.valid) then
    -- There is none yet, and an arm that is about to be made can simply be made this way
    -- round. This is the common case: an idle arm is put away, so most departures are a
    -- first departure.
    record.facing = wanted
    return
  end
  if arm.direction == wanted then return end
  -- Only an arm whose hand is home and empty. A hand with something in it is part way
  -- through a journey, whatever the list says, and nothing here is worth taking a load out
  -- of the air for. A hand still out is the same refusal for a different reason: building
  -- the arm again would jump the claw from wherever it had got to across to wherever a
  -- fresh hand starts, which is not turning round. Anything else swings round at its own
  -- rate, and lib/reach.lua charges it for exactly that -- see hand_facing(), which is the
  -- same question asked of the same predicate.
  if not rebuildable(record) then return end

  -- The charge goes back where putting the arm away would put it and the new one draws it
  -- out again on the same tick, so pointing an arm is not a way of burning a buffer. No
  -- claw is drawn shrinking away either: this is an arm turning round, not one going away.
  if record.grid and record.grid.valid then
    refund(record.grid, record.piece, arm.energy)
  end
  arm.destroy()
  record.entity = nil
  record.facing = wanted
  -- A fresh hand starts somewhere else entirely, and the window that decides whether the
  -- claw has arrived is measured from wherever it was last seen.
  record.last_hand = nil
  arm_of(player, wearer, record)
end

---Keep the inserter on its wearer and pointed at whatever it is reaching for.
---
---Both ends are set every tick. The pickup end is the wearer, so the hand comes home to
---them rather than to wherever they were standing when the swing began. The drop end has to
---be re-aimed as well, because an inserter's drop position travels with the inserter: move
---the entity and the target moves with it, so a fixed vector would drift off the ghost as
---the character walked -- or, in a vehicle, as they drove.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param job table? what it is reaching for, if anything
---@return LuaEntity? the inserter
local function aim(player, wearer, record, slot, count, job)
  local arm = arm_of(player, wearer, record)
  if not (arm and arm.valid) then return nil end

  -- Fed whether or not it has anything to do. The standing drain an idle arm pulls used to
  -- keep its equipment a hair under full, and setting off waited on exactly full, so an
  -- idle arm had to be starved to keep it able to leave at all. Now that setting off asks
  -- for two and a half reaches out of a buffer that holds three, the drain lives in the
  -- half reach of headroom and touches nothing. An arm that has been standing about is
  -- therefore full when work arrives, rather than spending its first ticks filling up.
  charge(record, arm)
  local mount, lift = mounting(wearer, slot, count)
  arm.teleport(mount)
  -- Remembered for as long as the arm is out, because everything aimed at from here is
  -- aimed in the frame the arm was drawn in, and a vehicle that turns moves that frame.
  record.lift = lift

  -- Where the claw rests: a little way out from the mounting point, along the bearing it
  -- is working on, so that coming home is a retraction rather than a swing. With nothing
  -- to work on it rests above the character, which is where a folded arm looks right.
  local towards = job and aimed_at(job, record)
  local bearing = { x = 0, y = -1 }
  if towards then
    local dx, dy = towards.x - mount.x, towards.y - mount.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0.01 then bearing = { x = dx / length, y = dy / length } end
  end
  local rest = { x = mount.x + bearing.x * REST, y = mount.y + bearing.y * REST }
  record.rest = rest
  -- Kept so that an arm lifted out of its owner's list can go on doing this for itself.
  -- See fold(): a switched off arm swings home on its own, which means staying on the back
  -- that is walking away and retracting along the line it was working on.
  record.bearing = bearing
  record.slot = slot
  record.count = count
  arm.pickup_position = { rest.x, rest.y }
  -- Which end is pointed at the rest point, which starts as the pickup and is moved about
  -- by the job below. Tracked rather than read back off the entity, because the engine
  -- keeps a position to the nearest two hundred and fifty sixth of a tile and a comparison
  -- against what was written would be a comparison against a rounded copy of it.
  local picks_at_rest, drops_at_rest = true, false

  -- A box of the mod's own, standing on the rest point, whatever the arm is doing.
  --
  -- It was here only for an idle claw to begin with, to stop one helping itself out of
  -- whatever its owner is standing on. It is here always now because of a second thing the
  -- engine does with that tile: an inserter whose pickup or drop position falls on a tile
  -- holding something marked for deconstruction will not move its hand at all, reporting
  -- itself working the whole time. A fetch drops at the rest point, and somebody clearing
  -- ground stands in the middle of what they have marked, so that tile is a marked one
  -- exactly when the arms are wanted most.
  --
  -- Measured on a bare inserter of the arms' own prototype: with the drop on a marked tile
  -- and nothing else there the hand never moves, and with a box of any kind on that tile it
  -- moves normally. A box with its bar down is enough -- the engine calls that waiting for
  -- space in the destination, which is honest, and it is what the mod wants anyway since it
  -- takes the load out of the hand itself. The pickup end is the same fault and is cured
  -- differently, by naming a target rather than by standing something there, which is what
  -- the pinning below does.
  local keeper = keeper_at(record, arm.surface, rest, job == nil)

  if job then
    if job.going == "out" then
      local target = aimed_at(job, record)
      if job.take then
        -- The other way round: the claw reaches for the thing rather than at it, and what
        -- it picks up comes back to where home is measured from.
        arm.pickup_position = { target.x, target.y }
        picks_at_rest = false
        if job.crossing then
          arm.drop_position = { target.x, target.y }
        else
          arm.drop_position = { rest.x, rest.y }
          drops_at_rest = true
        end
      elseif job.crossing then
        -- Crossing from the ghost just built to the next one of the round. The pickup end
        -- goes with the drop end, and the two have to be the same point exactly, because
        -- the engine will not carry a load past its pickup: an inserter that has just let
        -- go swings back to wherever it picks up from before it will look at a new drop,
        -- whatever is in its hand. Left pointing home, that is a round trip per ghost --
        -- out, build, all the way back in, out again -- which is the whole of what the
        -- bulk claw was meant to save. Pointed at the next ghost, the return swing is the
        -- journey there.
        --
        -- The same arrangement a fetch crosses under, above, and for the same reason. It
        -- lasts until the hand arrives, which is where advance() puts the pickup back on
        -- the rest point so that the engine can make the drop: an inserter will not put
        -- anything into the very thing it is picking up from.
        arm.pickup_position = { target.x, target.y }
        arm.drop_position = { target.x, target.y }
        picks_at_rest = false
      else
        arm.drop_position = { target.x, target.y }
      end
    elseif arm.held_stack.valid_for_read then
      -- Still carrying something on the way back, which happens when a reach is given up
      -- on: an empty hand comes home by itself, but a full one goes wherever it was told
      -- to drop, so it has to be told to come here.
      --
      -- Here is the resting point, not the mounting point. Sending it to the mount while
      -- home is measured from the rest point means the claw arrives somewhere nothing is
      -- watching for it, and the engine puts what it is holding on the ground before this
      -- ever notices. Aimed at the same place home is measured from, the item comes out of
      -- the hand a little before the claw gets there.
      arm.drop_position = { rest.x, rest.y }
      drops_at_rest = true
    end
    -- An empty hand on the way back is left alone. Aiming it at the mount points it at the
    -- arm's own base, which is no direction at all, and the engine picks one: the claw
    -- swept out east at full stretch before coming home, which on a fast tier reads as the
    -- arm being flung sideways.
  end

  -- A hand still holding something with no job at all, which the branch above cannot help
  -- with because it lives inside the job. It happens whenever a job ends while the claw is
  -- still carrying: a round that took more than its last ghost wanted, or work that went
  -- away with the claw already loaded.
  --
  -- Left alone, the drop goes on pointing wherever it last did -- out in the world, with
  -- the box already taken away from under it -- and the engine finishes the swing on its
  -- own schedule and lets go over bare ground. Measured on a car driven straight through a
  -- field of ghosts: the arm carried a belt with no job for twelve ticks and put it on the
  -- floor on the thirteenth, at the same tick every run.
  if not job and arm.held_stack.valid_for_read then
    arm.drop_position = { rest.x, rest.y }
    drops_at_rest = true
  end

  -- And whichever end is pointed at the rest point is pointed at the box standing there, by
  -- name, after the teleport that threw the engine's own answer away. The other end is
  -- named by advance(), at the box standing on whatever this arm is working on.
  --
  -- Both ends matter and they are cured differently. A drop is cured by the box merely
  -- being there; a pickup is not, and has to be named. Naming both costs nothing and means
  -- neither has to be reasoned about at the call sites.
  if keeper and keeper.valid then
    if picks_at_rest then arm.pickup_target = keeper end
    if drops_at_rest then arm.drop_target = keeper end
  end
  return arm
end

--- Declared here because deliver, below, turns to another ghost through it, and it is
--- defined after deliver. Without this the name is a global at that point, which is to say
--- nil, and the call takes the whole run down with an error the log never shows.
local redirect

---Work out where an arm should hold its claw to meet what it is going for.
---
---A lead is only wanted while the ghost is out of reach. One already in reach is aimed at
---directly, which is what the mod has always done and what every case on a wearer who is
---standing still is.
---
---A hand with a load in it is the case a lead exists for. It cannot be turned -- see point(),
---which refuses -- so it has to swing round at its own rate, and aimed at something that
---moves it chases the bearing instead of cutting to where the bearing is going. Measured on a
---hand four and a half tiles out: aimed at the ghost it never arrived at all, and held on a
---lead it arrived on the tick the arithmetic named.
---@param record table
---@param from {x: number, y: number} where the arm reaches from
---@param range number
---@param setting_off boolean? whether this is an arm deciding to go, rather than one going
---@return boolean whether there is still a reach worth making
local function set_course(record, from, range, setting_off)
  local job = record.job
  if not job then return false end
  local course = course_to(record, from, job.target, range, setting_off)
  if not course then
    job.met, job.lead, job.arrival = false, nil, nil
    return false
  end
  job.met = course.met
  job.lead = course.lead
  job.arrival = course.arrival and (game.tick + course.arrival) or nil
  return true
end

---Keep a reach aimed at something it can still get to, as its owner's course changes.
---
---Three things happen here and the order is the point of it. A ghost that has come inside
---the reach is handed over to, and from then on the reach is judged on where the ghost is
---rather than where it will be, because the engine can still finish a swing a prediction
---would call hopeless. A ghost still outside it has its intercept worked out again.
---
---Worked out again every tick rather than only when the course changes, and that is
---deliberate. A course that has not changed gives the same answer -- the owner has moved by
---exactly the drift the last answer assumed, so the point the claw is held on is the same
---point in the world -- so there is nothing to detect and nothing to cache. A course that
---has changed simply gives a different answer, which is the one wanted. It costs a scan of
---at most the tier's own swing, for one ghost, and buys not having to decide how much of a
---wobble counts as a turn: measured, a spidertron's legs swing its body a degree a tick
---while it walks dead straight, which is the same order as a tank turning as hard as it
---will, so no threshold separates them.
---
---Turning is not a reason to go looking for something else. The ghost is still the ghost,
---and only an intercept that comes back with nothing says it has really gone.
---@param record table
---@param from {x: number, y: number}
---@param range number
---@return boolean whether the reach is still worth finishing
local function holding_course(record, from, range)
  local job = record.job
  if job.met then return not reach.out_of_range(from, job.target, range) end
  if not set_course(record, from, range) then return false end
  -- Handed over when the arrival is upon us rather than the moment the ghost is in range,
  -- and the difference only shows on an arm that is already out.
  --
  -- A lead is a fixed point, so the bearing to it does not move, so the claw turns straight
  -- onto it. The ghost itself is not fixed -- it is its owner who moves, but from the arm it
  -- comes to the same thing -- so a claw aimed at the ghost chases the bearing round instead
  -- of cutting to where the bearing is going, and arrives later or not at all. Measured on a
  -- hand four and a half tiles out: aimed at the ghost it never arrived, and held on a lead
  -- it arrived on the tick the arithmetic named.
  --
  -- Handing over is still wanted, and for the reason it always was: the engine lets go
  -- against the aim it was given a tick earlier, so the last tick before the drop has to be
  -- the ghost itself or the load lands where the ghost was going to be. A tick is all it
  -- needs, and a tick is what it gets.
  --
  -- A wearer standing still is not affected either way. With no drift the lead is the ghost,
  -- so holding one and aiming at the other are the same thing.
  if job.arrival and game.tick + 1 >= job.arrival
      and not reach.out_of_range(from, job.target, range) then
    job.met, job.lead, job.arrival = true, nil, nil
  end
  return true
end

---Give up on a reach without building anything.
---
---Whatever is in the hand stays in it and comes back with the claw, which is what it looks
---like from outside: the arm carries the thing home again rather than the item winking out
---of a closed claw halfway across the ground. It is taken out of the hand when the claw
---gets there. Nothing is given back to the inventory because nothing was ever taken from
---it: the hand is filled from nothing and the inventory is only debited on arrival.
---@param job table
--- Whether this player would rather have a returned item on the ground than in the claw.
---@param player LuaPlayer
---@return boolean
local function spills(player)
  local chosen = settings.get_player_settings(player)["constructor-equipment-spill-when-full"]
  return chosen and chosen.value or false
end

---Hand back what an arm is carrying, because it has already been paid for.
---
---The claw is loaded out of the character's pockets, so anything in it is the player's
---item and not a copy: destroying it on the way home would be taking it off them. If it
---will not fit, the player has said which they would rather have -- it on the ground, or
---kept in the claw with the arm holding station until there is room.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table
---@return boolean whether the claw is empty now
local function give_back(player, wearer, record)
  local arm = record.entity
  local job = record.job
  local inventory = pockets(player, wearer)

  -- What was set aside for this round but never went into the claw goes back first. It
  -- was taken from the pockets when the arm set off and nothing was built with it, so it
  -- is simply the player's again. There is nothing holding it and nowhere for it to fall,
  -- so it does not need the spill or hold question that the claw's own load does.
  if job and (job.escrow or 0) > 0 and job.item and inventory then
    local returned = inventory.insert{ name = job.item, quality = job.quality, count = job.escrow }
    job.escrow = job.escrow - returned
    if job.escrow > 0 and spills(player) then
      if wearer and wearer.valid then
        wearer.surface.spill_item_stack{
          position = wearer.position,
          stack = { name = job.item, quality = job.quality, count = job.escrow },
          enable_looted = true,
          force = player.force,
        }
      end
      job.escrow = 0
    end
    if job.escrow > 0 then return false end
  end

  -- What the job owes: taken off the world on the way and too much for the hand to hold,
  -- so it travelled with the job. The claw is home, so it is the player's now.
  if job and job.owed and (job.owed.count or 0) > 0 then
    local put = inventory and inventory.insert{ name = job.owed.name,
      quality = job.owed.quality, count = job.owed.count } or 0
    job.owed.count = job.owed.count - put
    if job.owed.count > 0 then
      if not spills(player) then return false end
      if wearer and wearer.valid then
        wearer.surface.spill_item_stack{
          position = wearer.position,
          stack = { name = job.owed.name, quality = job.owed.quality,
                    count = job.owed.count },
          enable_looted = true,
          force = player.force,
        }
      end
      job.owed.count = 0
    end
  end

  if not (arm and arm.valid and arm.held_stack.valid_for_read) then return true end
  -- The stack as it stands rather than its name and number: what the claw is carrying may
  -- be the very thing an upgrade pulled up, which can be damaged and can be any quality.
  local count = arm.held_stack.count
  local took = inventory and inventory.insert(arm.held_stack) or 0
  if took >= count then
    arm.held_stack.clear()
    return true
  end
  if took > 0 then arm.held_stack.count = count - took end
  if spills(player) then
    if wearer and wearer.valid then
      wearer.surface.spill_item_stack{
        position = wearer.position,
        stack = arm.held_stack,
        enable_looted = true,
        force = player.force,
      }
    end
    arm.held_stack.clear()
    return true
  end
  -- kept in the claw: the arm stays out rather than folding away with the player's item
  return false
end

---Put everything an inventory holds on the floor and mark it, which is what a construction
---robot does with what it cannot carry away.
---
---Marked from the entities spill_item_stack hands straight back rather than by looking
---around afterwards: a pile spreads as the square root of its size, so there is no distance
---to search that is right for every one of them.
---
---The stacks go down as they are rather than by name and number, so a damaged thing stays
---damaged and a quality one stays that quality.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param force LuaForce
---@param inventory LuaInventory
local function shed(surface, at, force, inventory)
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read then
      for _, item in pairs(surface.spill_item_stack{
            position = at,
            stack = stack,
            enable_looted = false,
            force = force,
            allow_belts = false,
          } or {}) do
        if item.valid then item.order_deconstruction(force) end
      end
      stack.clear()
    end
  end
end

---@param record table the arm giving up
---@param job table
local function abandon(record, job)
  job.going = "back"
  job.ghost = nil

  -- And anything still standing in the box, which is about to be destroyed with it. A
  -- fetch fills the box itself and the engine takes it into the hand a tick later, so a
  -- round that ends in that gap -- the last thing mined, nothing else in reach -- had the
  -- box taken away with the load still in it. Two tiles of four went that way, and the
  -- census is what found them.
  local holding = record and record.entity
  local box = record and record.catcher
  if box and box.valid and holding and holding.valid then
    local inside = box.get_inventory(defines.inventory.chest)
    if inside and not inside.is_empty() then
      for _, stack in pairs(inside.get_contents()) do
        local quality = stack.quality and (stack.quality.name or stack.quality) or nil
        local held = holding.held_stack.valid_for_read and holding.held_stack.count or 0
        if held == 0 or holding.held_stack.name == stack.name then
          holding.held_stack.set_stack{ name = stack.name, quality = quality,
                                        count = held + stack.count }
          local now = holding.held_stack.valid_for_read and holding.held_stack.count or 0
          if now > held then
            inside.remove{ name = stack.name, quality = quality, count = now - held }
          end
        end
      end
      -- Whatever the hand will not take goes on the floor marked, rather than away with
      -- the box.
      if not inside.is_empty() then
        shed(holding.surface, box.position, holding.force, inside)
      end
    end
  end

  -- Re-aimed now rather than left to the next tick's aim(). The claw is still full and
  -- still pointed at the ghost, and the engine finishes swings on its own schedule: given
  -- a tick of grace it puts the load down on the ghost's own tile. That loses the delivery
  -- and mints a free item, because the claw is filled from nothing rather than from the
  -- inventory -- and worse, an item lying on a ghost stops that ghost being revived at
  -- all, so every attempt after the first fails the same way and drops another one.
  local arm = record and record.entity
  if arm and arm.valid and arm.held_stack.valid_for_read and record.rest then
    arm.drop_position = { record.rest.x, record.rest.y }
  end
  catcher_away(record)
end

---A porter to be handed whatever a swap displaces, with room for all of it.
---
---A character is what create_entity will accept as the receiver, and this one is the mod's
---own rather than the player: see prototypes/porter.lua for why. It is given a slot for the
---thing being replaced and one for every stack that thing is holding, which is as many as
---the engine can possibly need, so it never has to shed or destroy any of it.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param force LuaForce
---@param work LuaEntity the thing about to be replaced
---@return LuaEntity?
local function porter_for(surface, at, force, work)
  local porter = surface.create_entity{
    name = "constructor-equipment-porter", position = at, force = force }
  if not porter then return nil end
  local slots = 1
  for index = 1, work.get_max_inventory_index() do
    local inventory = work.get_inventory(index)
    if inventory then slots = slots + (#inventory - inventory.count_empty_stacks()) end
  end
  porter.character_inventory_slots_bonus = slots
  return porter
end

---Swap a thing marked for upgrade for what it is marked to become, the way a construction
---robot does it.
---
---fast_replace is what makes this an upgrade rather than a demolition and a rebuild: the
---belt's cargo, an assembler's recipe and modules, an inserter's filters and its stack size
---override all carry over, exactly as they do when a player fast replaces by hand.
---
---Nothing is raised. The revive below raises nothing either, and the two paths say the same
---amount about themselves.
---@param porter LuaEntity who is to be handed what the swap displaces
---@param work LuaEntity
---@param quality string?
---@return LuaEntity? placed
local function swap(porter, work, quality)
  local prototype = work.get_upgrade_target()
  if not prototype then return nil end
  return work.surface.create_entity{
    name = prototype.name,
    quality = quality,
    position = work.position,
    direction = work.direction,
    -- Which way round a handed thing is built. Every entity answers this, whether or not
    -- it is the sort of thing that can be mirrored.
    mirror = work.mirroring,
    type = end_of(work),
    force = work.force,
    fast_replace = true,
    spill = false,
    character = porter,
    create_build_effect_smoke = false,
  }
end

---Replace both ends of an underground pair at once, keeping what is in the tunnel.
---
---The items between the two ends sit on the third and fourth transport lines, and replacing
---either end turns them out: the base game drops them on the floor for its network to pick
---up, and this mod would hand them to the porter and shed them. Neither loses anything, and
---both leave the player's belt line short of what was travelling in it.
---
---So they are lifted into an inventory of the mod's own before either end is touched and
---laid back down on the new pair afterwards, at the positions they were at. What was in the
---tunnel is still in the tunnel.
---
---Both ends are emptied rather than the one that holds the cargo, which is the input end:
---measured on 2.1.17, a tunnel loaded through the input kept all of it on that end's third
---and fourth lines, with nothing on the output end's. Reading the wrong one of the two left
---two of six items behind, and reading both cannot be wrong whichever end the arm reached
---for. Blueprint Shotgun picks the input end deliberately, through a variable it calls
---output.
---@param porter LuaEntity
---@param work LuaEntity the end the arm reached for
---@param partner LuaEntity the other end
---@param quality string?
---@return LuaEntity? made
---@return LuaEntity? other
local function swap_pair(porter, work, partner, quality)
  local surface, at, force = work.surface, work.position, work.force

  ---Lift the tunnel's share of one end into an inventory of our own.
  local function lift(from)
    local lines = {}
    for line = 3, 4 do
      local contents = from.get_transport_line(line).get_detailed_contents()
      local held = game.create_inventory(math.max(1, #contents))
      for index = #contents, 1, -1 do
        held[index].transfer_stack(contents[index].stack)
      end
      lines[line - 2] = { contents = contents, held = held }
    end
    return { was = from.belt_to_ground_type, lines = lines }
  end

  local rescued = { lift(work), lift(partner) }

  local made = swap(porter, work, quality)
  local other = made and swap(porter, partner, quality) or nil

  ---Put one end's share back on whichever new end is the same end of the pair.
  local function lay_back(saved)
    local onto = (made and made.belt_to_ground_type == saved.was) and made
      or ((other and other.belt_to_ground_type == saved.was) and other)
    for index, line in ipairs(saved.lines) do
      local onto_line = onto and onto.get_transport_line(index + 2)
      for slot = 1, #line.held do
        local stack = line.held[slot]
        if stack.valid_for_read then
          -- Whether it went on is measured rather than asked. force_insert_at says nothing
          -- at all: measured on 2.1.19 it puts the item on the line and answers nil either
          -- way, and it does not empty the stack it was handed either. Read as a refusal,
          -- that laid every item back in the tunnel and then put a copy of it on the floor
          -- as well -- which is where the showroom's pair kept its load and grew two iron
          -- plates beside it, one for each of the tunnel's two lines.
          local before = onto_line and onto_line.get_item_count() or 0
          if onto_line then
            onto_line.force_insert_at(line.contents[slot].position, stack)
          end
          -- Half a swap, or a line that will not take it back, and it goes on the floor
          -- rather than into the void, which is where the base game would have left it.
          if not (onto_line and onto_line.get_item_count() > before) then
            surface.spill_item_stack{ position = at, stack = stack,
              enable_looted = false, force = force, allow_belts = false }
          end
        end
      end
      line.held.destroy()
    end
  end

  for _, saved in ipairs(rescued) do lay_back(saved) end
  return made, other
end

---Put the thing that came off in the claw, to be carried home the way a robot carries it
---back to the network.
---
---The stack itself rather than its name and number, so that whatever it carries beyond
---those comes home too: a belt pulled up damaged is still damaged, and stays the quality it
---was. Nothing is made here -- the porter was handed the real one.
---
---The claw has to be empty, which it is: a trip that is going to make a swap carries one
---thing out and nothing turns to a swap partway through.
---The whole stack, and the engine takes what the hand will hold. There was a count here to
---take less, and nothing wanted one: the only caller wants as much of it as will go in, and
---asking for a number means having a model of how big a hand is, which the hand already is.
---@param record table the arm
---@param stack LuaItemStack
local function fill_claw(record, stack)
  local arm = record.entity
  if not (arm and arm.valid) then return false end
  if arm.held_stack.valid_for_read and arm.held_stack.count > 0 then return false end
  arm.held_stack.set_stack(stack)
  return true
end

---How many the claw is holding, which decides whether it can be given anything.
---@param record table
---@return integer
local function arm_holding(record)
  local arm = record.entity
  if not (arm and arm.valid and arm.held_stack.valid_for_read) then return 0 end
  return arm.held_stack.count
end

---Put one trip's worth of a thing into the box, for the claw to carry home.
---
---What it is holding goes first, a stack at a time, and the thing itself comes up only once
---it is empty. That is what a robot does: measured on 2.1.17, fifty of them took a full
---steel chest away in hundred plate mouthfuls over a minute, and the chest went last. A claw
---carries one thing at a time, so it works that way by nature rather than by arrangement,
---and mining is only ever asked of something empty -- which matters, because mining into an
---inventory too small to take the whole yield empties what it can and then fails, leaving
---the thing standing and lighter than it was.
---Only ever a clawful. A hand holds what its inserter holds, and anything put in the box
---beyond that is left there when the box goes: a hundred plates went in and one came home.
---Putting in what the claw can carry makes the box a step on the way rather than a place
---something can be left behind in.
---@param box LuaEntity
---@param work LuaEntity
---@param capacity integer how many the claw can hold
---@return boolean whether anything was put in
local function loot_into(box, work, capacity)
  local inside = box.get_inventory(defines.inventory.chest)
  if not (inside and capacity > 0) then return false end

  -- A thing lying on the ground holds nothing; asking it what its inventories are is asking
  -- a stack of plates to open its pockets.
  for index = 1, (work.type == "item-entity") and 0 or work.get_max_inventory_index() do
    local held = work.get_inventory(index)
    if held and not held.is_empty() then
      for slot = 1, #held do
        local stack = held[slot]
        if stack.valid_for_read then
          local quality = stack.quality and stack.quality.name or nil
          local moved = inside.insert{ name = stack.name, quality = quality,
            count = math.min(capacity, stack.count) }
          if moved > 0 then
            if moved >= stack.count then stack.clear() else stack.count = stack.count - moved end
            return true
          end
          return false
        end
      end
    end
  end

  local surface, at, force = work.surface, work.position, work.force
  local products = work.prototype.mineable_properties.products
  local size = math.max(1, products and #products or 1)
  local room = game.create_inventory(size)
  local mined = work.mine{ inventory = room, force = false, raise_destroyed = true }
  -- Grown a slot at a time until it fits, the way Blueprint Shotgun does it: what a thing
  -- yields is not always as long as its product list, and a mine that will not fit is a
  -- mine that half happened.
  local tries = 0
  while not mined and tries < 8 do
    size = size + 1
    room.resize(size)
    mined = work.mine{ inventory = room, force = false, raise_destroyed = true }
    tries = tries + 1
  end
  if not mined then room.destroy() return false end

  local took = false
  if room[1].valid_for_read then
    local quality = room[1].quality and room[1].quality.name or nil
    local moved = inside.insert{ name = room[1].name, quality = quality,
      count = math.min(capacity, room[1].count) }
    if moved > 0 then
      took = true
      if moved >= room[1].count then room[1].clear()
      else room[1].count = room[1].count - moved end
    end
  end
  -- More than a claw can carry goes on the floor marked, where a robot leaves what it
  -- cannot take, rather than waiting on a trip that would have nowhere to put it.
  shed(surface, at, force, room)
  room.destroy()
  return took
end

---Take something up: wait for the claw to arrive, give it a load, and send it home.
---
---The mirror of a delivery, and it leans on the same box. An inserter with a container at
---its pickup position reaches out to it and waits there with an open hand -- measured, the
---hand sits at full stretch reporting no source items until something appears, and takes it
---the moment it does. So arrival is not a distance this has to measure either: it is the
---box being near enough to exist, and the claw filling itself is the engine's own report
---that it got there.
---@param player LuaPlayer
---@param wearer LuaEntity
---@param record table
---@param job table
---@param claimed table<string|integer, boolean>? what the other arms are reaching for
---@param nearby fun(): LuaEntity[] the tick's own search, made when first asked for
---@param from {x: number, y: number} where this arm reaches from
---@param range number how far it reaches
local function take_up(player, wearer, record, job, claimed, nearby, from, range)
  local arm = record.entity
  if not (arm and arm.valid) then return end

  local waiting_box = record.catcher
  local waiting_inside = waiting_box and waiting_box.valid
    and waiting_box.get_inventory(defines.inventory.chest)
  if arm.held_stack.valid_for_read and arm.held_stack.count > 0 and not job.crossing
      and not (waiting_inside and not waiting_inside.is_empty()) then
    job.going = "back"
    job.ghost = nil
    -- Belt and braces: the box should be empty, since only a clawful ever goes in it, and
    -- anything still there would go with it.
    local box = record.catcher
    if box and box.valid then
      local inside = box.get_inventory(defines.inventory.chest)
      if inside and not inside.is_empty() then
        shed(arm.surface, box.position, arm.force, inside)
      end
    end
    catcher_away(record)
    if record.rest then arm.drop_position = { record.rest.x, record.rest.y } end
    return
  end

  -- Arrival is the inserter's own word for it. An arm reaching for a source with nothing in
  -- it stretches out and reports that it is waiting for source items, and it says so only
  -- once it is there: measured, the hand sat at full stretch in that state until something
  -- appeared and took it the tick after.
  --
  -- The box's own existence will not do, the way it does for a delivery. It is made as soon
  -- as the claw is near enough that it might arrive between one tick and the next, and that
  -- window is widened by how far the hand moved, which on the first tick of a swing is the
  -- whole re-aiming. A delivery does not mind -- the engine fills the box when it gets
  -- there -- but a fetch fills the box itself, and an early box means a thing mined while
  -- the claw is still two tiles off.
  if job.crossing then
    -- Against where the claw was actually sent, which is not job.target. Everything an arm
    -- aims at is aimed in the frame it is drawn in: the arm is teleported a lift above its
    -- owner so it rides on the body rather than at their feet, and aimed_at() takes the
    -- same lift off whatever it is pointed at. So the hand, the pickup and the drop all
    -- live a lift above the world, and comparing the hand against a world position is out
    -- by exactly that -- 0.70 of a tile on a character, every time, in every direction.
    --
    -- That cost an afternoon. The hand was measured sitting 0.70 from its target and never
    -- getting closer, which reads as the engine resting a hand short of what it reaches
    -- for, and a window was widened to a whole tile to allow for it. The hand was never
    -- short of anything; the tape measure had one end in the wrong frame.
    if reach.distance(arm.held_stack_position, aimed_at(job, record))
        > within(tier_of(record), HOME) then
      return
    end
    -- Arrived. The box may already be holding part of the round -- what was mined at the
    -- thing before this one, if the hand had not taken it before the claw set off, travels
    -- along in the box since the box is teleported ahead of the claw each tick. A box with
    -- something in it is ordinarily a reason to wait, and here it is not: that is the claw's
    -- own round rather than something its hand is about to take. So the next thing goes into
    -- the box on top of it and the claw picks the lot up in one grab.
    local box = record.catcher
    if not (box and box.valid) then return end
    local inside = box.get_inventory(defines.inventory.chest)
    if not inside then return end
    local room = trips_for(player.force, tier_of(record))
    local held = arm.held_stack.valid_for_read and arm.held_stack.count or 0
    local carried = held + inside.get_item_count()
    if carried < room then loot_into(box, job.ghost, room - carried) end
    job.crossing = nil
    if record.rest then arm.drop_position = { record.rest.x, record.rest.y } end
    return
  end
  -- Arrived, measured as a distance rather than asked of the engine. An inserter reaching
  -- for an empty source reports waiting_for_source_items once it is there, and that was
  -- what this used -- but only once it is there and *settled*. An arm rides on somebody who
  -- is walking, so the hand is re-aimed every tick and never settles: measured on a
  -- character strolling past ten marked plates at a ninth of a tile a tick, the claw
  -- reached every one of them, sat on it, and took none of the ten.
  --
  -- The same window and the same frame the crossing branch above uses, which has always
  -- measured it this way.
  if reach.distance(arm.held_stack_position, aimed_at(job, record))
      > within(tier_of(record), HOME) then
    return
  end

  local box = record.catcher
  if not (box and box.valid) then return end
  local inside = box.get_inventory(defines.inventory.chest)
  if inside and not inside.is_empty() then return end

  local room = trips_for(player.force, tier_of(record))
  if not loot_into(box, job.ghost, room) then return end

  -- And that is the whole of what this trip takes: the thing the claw went to, and nothing
  -- else. A thing standing over one target does not reach out to another, however much room
  -- is left in its hand, because an arm that picks up what it did not go to is not an arm
  -- doing anything a player can watch.
  --
  -- There was a sweep here and it was a mistake of mine twice over. It went in to stop a
  -- patch of tiles being a journey each, gathering whatever was marked within two tiles of
  -- where the claw stood; then a change meant to avoid a second search handed it the tick's
  -- own search instead, which covers the whole of the arm's range, and quietly turned two
  -- tiles into five. What a player saw was a yard of shed plates winking out at once while
  -- the claw sat over one of them.
  --
  -- A hand that holds several still fills up, but only where filling up means more out of
  -- the one thing it is standing at: a chest goes a clawful at a time, which is what a
  -- robot does with one. Anything else is another journey.
end

---Put the thing down: raise the ghost or make the swap, pay for it, and let the arm start
---coming home.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param from {x: number, y: number} where this arm reaches from
---@param record table the arm making the delivery
---@param job table
---@param claimed table<integer, boolean>? what the other arms are reaching for
local function deliver(player, wearer, from, record, job, claimed, nearby)
  local ghost = job.ghost
  local box = record.catcher

  -- What the box was given is the delivery. Until something is in it, nothing has
  -- arrived, and that is the whole of the arrival test: no distance, nothing to step over.
  local landed = 0
  if box and box.valid then
    landed = box.get_item_count{ name = job.item, quality = job.quality }
  end
  if landed < 1 then return end

  -- A ghost can want more than a claw can hold: a plain inserter carries one item and a
  -- half diagonal rail takes two. The rest was taken from the pockets when the arm set off
  -- and has been travelling with the job rather than in the claw, so it is here to be
  -- spent and nothing needs asking of the pockets now.
  local short = job.count - landed
  if short > (job.escrow or 0) then
    -- the round is short of what this ghost wants, which should not happen: everything was
    -- reserved at the start. Give back what there is rather than build half a thing.
    take_back(record, job.item, job.quality, landed)
    abandon(record, job)
    return
  end

  if not still_wanted(ghost) then
    -- the ghost went, or the upgrade was called off, while the claw was on its way; the
    -- load goes back in the claw and comes home, since it has already been paid for
    take_back(record, job.item, job.quality, landed)
    abandon(record, job)
    return
  end

  if exploding(ghost) then
    local surface, at, force = ghost.surface, ghost.position, ghost.force
    local thrown = projectile_of(job.item)

    -- The charge is spent whatever happens next: it came out of the pockets when the arm
    -- set off and it has just been handed over.
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then
      inside.remove{ name = job.item, quality = job.quality,
        count = math.min(landed, job.count) }
    end
    if short > 0 then job.escrow = job.escrow - short end

    job.going = "back"
    job.ghost = nil
    catcher_away(record)

    if thrown then
      -- Thrown rather than the cliff simply being taken away, so the blast takes the
      -- neighbours in its radius with it the way a robot's charge does.
      surface.create_entity{ name = thrown, position = at, target = at, speed = 1,
        force = force }
    else
      -- An explosive with no projectile to throw is not something the base game has. Take
      -- the cliff down by hand rather than charging for nothing.
      ghost.destroy{ do_cliff_correction = true, raise_destroy = true }
    end
    return
  end

  if upgrading(ghost) then
    -- Everything worth knowing about what comes off is read here rather than afterwards,
    -- because afterwards there is nothing left standing to ask.
    local surface, at, force = ghost.surface, ghost.position, ghost.force
    local product = sole_product(ghost)
    local quality = ghost.quality and ghost.quality.name or "normal"

    -- Somebody has to be named to catch what the swap displaces -- name nobody and the
    -- engine destroys it -- and it is not the player: a porter is made for the job, handed
    -- the lot, emptied and destroyed, all before the tick is out. Naming the player would
    -- not lose anything either, but it would scatter it between their pockets, the floor
    -- and the new belt's own lane, and leave the mod taking it back out again.
    local porter = porter_for(surface, at, force, ghost)
    if not porter then
      take_back(record, job.item, job.quality, landed)
      abandon(record, job)
      return
    end

    local partner = paired_with(ghost)
    local made
    if partner then
      made = swap_pair(porter, ghost, partner, quality)
    else
      made = swap(porter, ghost, quality)
    end
    local carried = porter.get_main_inventory()

    if not made then
      if carried then shed(surface, at, force, carried) end
      porter.destroy()
      take_back(record, job.item, job.quality, landed)
      abandon(record, job)
      return
    end

    -- The swap is made, so what paid for it is spent. It came out of the pockets when the
    -- arm set off, so nothing is charged here: this is where it stops existing.
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then
      inside.remove{ name = job.item, quality = job.quality,
        count = math.min(landed, job.count) }
    end
    if short > 0 then job.escrow = job.escrow - short end

    -- The box goes and the claw is turned for home before anything is put in its hand, in
    -- that order. An inserter standing over a container with something in its hand puts it
    -- in the container, and the box is about to be taken away with it: the belt that came
    -- off went into the box and out of the world, once, before this was written down.
    job.going = "back"
    job.ghost = nil
    catcher_away(record)
    local returning = record.entity
    if returning and returning.valid and record.rest then
      returning.drop_position = { record.rest.x, record.rest.y }
    end

    -- The thing itself rides home in the claw. Everything the replacement could not hold
    -- goes on the floor, marked, where a robot would have shed it.
    --
    -- Both ends of a pair come off together and are the same item, so the claw takes as
    -- many as its hand holds rather than one: shedding the second put an underground belt
    -- on the lane of the belt that had just replaced it, riding away.
    if carried then
      if product then
        -- Into the claw first, and as much of it as the hand will take. How much that is
        -- is asked of the hand rather than of trips_for(): set the whole stack and read
        -- back what stuck. The engine caps a stack set past a hand's capacity, so this is
        -- the hand's own answer, and it cannot disagree with the mod's model of a hand
        -- because it does not consult one.
        local stack = carried.find_item_stack{ name = product, quality = quality }
        if stack and arm_holding(record) == 0 then
          fill_claw(record, stack)
          local carrying = arm_holding(record)
          if carrying >= stack.count then stack.clear()
          else stack.count = stack.count - carrying end
        end
        -- Only what would not go in the claw travels with the job, which on any hand that
        -- holds two is nothing at all. Two ends come off together and a claw that holds one
        -- can carry one of them; shedding the other put an underground belt on the floor
        -- beside the tunnel for the arm to come back out for, which is a second journey for
        -- something it had been standing over.
        --
        -- With the job rather than in the box, because the box has already gone: it is
        -- taken away before the claw is loaded, on purpose, since an inserter standing over
        -- a container with something in its hand puts it in the container. And with the job
        -- rather than in the hand because the hand will not take it -- measured, a first
        -- tier claw asked to hold two undergrounds takes one and the other is not on the
        -- floor, or in the box, or anywhere.
        --
        -- This is the same arrangement a curved rail already travels under, the other way
        -- round: what the claw cannot carry is set aside against the job and settled when
        -- it gets home.
        local over = carried.get_item_count{ name = product, quality = quality }
        if over > 0 then
          job.owed = { name = product, quality = quality,
                       count = (job.owed and job.owed.count or 0) + over }
          carried.remove{ name = product, quality = quality, count = over }
        end
      end
      -- Whatever is left is what the replacement could not hold, which goes on the floor
      -- marked, where a robot would have shed it.
      shed(surface, at, force, carried)
    end
    porter.destroy()
    return
  end

  local _, built = ghost.revive()
  if not built then
    take_back(record, job.item, job.quality, landed)
    abandon(record, job)
    return
  end

  -- The ghost is up, so the items that built it are spent. They came out of the pockets
  -- when the claw was loaded, so nothing is charged here: this is simply where they stop
  -- existing.
  local inside = box.get_inventory(defines.inventory.chest)
  if inside then
      inside.remove{ name = job.item, quality = job.quality,
        count = math.min(landed, job.count) }
    end
  if short > 0 then job.escrow = job.escrow - short end
  -- whatever else the claw brought is still the player's, and goes back in the claw for
  -- the next ghost of this round
  take_back(record, job.item, job.quality, math.max(0, landed - job.count))

  -- More of this trip left, and another of the same thing in reach, means going home would
  -- be a wasted journey. So the claw turns to the next one with the rest of its load still
  -- in hand. That is the whole of what a carrying claw buys: one journey out, several
  -- ghosts, one journey back.
  local arm = record.entity
  job.left = (job.left or 1) - 1
  -- What is left of the round is what is left in the claw, not what the job set out to do.
  -- Those two came apart once: a trip loaded with two put one down, found its hand empty
  -- and carried on regardless, because only the counter was consulted.
  if job.left > 0 and arm and arm.valid
      and arm.held_stack.valid_for_read and arm.held_stack.count >= job.count
      and afford_another(record, arm)
      and redirect(player, wearer, from, record, job, claimed, tier_of(record).range,
        nearby) then
    local target = aimed_at(job, record)
    arm.drop_position = { target.x, target.y }
    -- Both ends, and both now rather than on the next tick's aim(). The engine has just
    -- let go and its next move is towards its pickup: a tick of that still pointing home
    -- is a tick of the claw setting off the wrong way.
    arm.pickup_position = { target.x, target.y }
    -- shut to begin with: the claw is still at the ghost it has just built, and advance
    -- opens the box once it is near the new one
    catcher_at(record, arm.surface, target, false)
    return
  end

  job.going = "back"
  job.ghost = nil
  -- Re-aimed now rather than left to the next tick's aim(), which is what abandon() has
  -- always done and this path never did. A round that ends with something still in the
  -- claw -- a hand that holds more than the last ghost wanted -- leaves the drop standing
  -- on the ghost it has just built, and the box is about to be taken away from under it.
  -- The engine finishes swings on its own schedule: given that tick of grace it lets go
  -- over bare ground and the load is on the floor. Measured on a car driven straight
  -- through a field of ghosts, one belt on the ground at tick 193, every run.
  local carrying = record.entity
  if carrying and carrying.valid and carrying.held_stack.valid_for_read and record.rest then
    carrying.drop_position = { record.rest.x, record.rest.y }
  end
  catcher_away(record)
end

---Point a reach at something else that takes the same item, if there is anything.
---
---The claw is already out and already holding the right thing, so going home to fetch an
---identical item and coming back out is a wasted trip. Anything that needs something else
---does mean a trip home, because the hand can only hold one thing.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param from {x: number, y: number} where this arm reaches from
---@param job table
---@param claimed table<integer, boolean>? ghosts the other arms are reaching for
---@param range number how far this arm reaches
---@param nearby fun(): LuaEntity[]? the tick's own search, if this was reached from one
---@return boolean whether it found somewhere else to go
function redirect(player, wearer, from, record, job, claimed, range, nearby)
  local ghost, item, count, quality = choose(player, wearer, from,
    -- The tick's own search where there is one, which there is whenever this is reached
    -- from an arm being advanced. A claw turning to the next ghost is asking the same
    -- question the arms with no job are asking, of the same ground, on the same tick.
    nearby and nearby() or work_near(wearer, { record }, drift_of(player, wearer)),
    claimed, range, record)
  if not ghost then return false end

  -- A round of pickups: the claw goes on to the next thing rather than carrying one home
  -- and coming straight back out. Asked before the questions below, which are about an item
  -- carried out to a ghost, and a fetch carries nothing out.
  if job.take then
    if not taking(ghost) then return false end
    local arm = record and record.entity
    if not (arm and arm.valid) then return false end
    -- What the claw is carrying: its hand, and whatever it has just put down in the box it
    -- is standing over, which is the same round a tick from being picked up again.
    local box = record.catcher
    local inside = box and box.valid and box.get_inventory(defines.inventory.chest)
    local held = (arm.held_stack.valid_for_read and arm.held_stack.count or 0)
      + (inside and inside.get_item_count() or 0)
    if held == 0 then return false end
    if held >= trips_for(player.force, tier_of(record)) then return false end
    -- One kind of thing to a round: it comes home in one hand.
    local name, grade = yields(ghost)
    local carried_name, carrying
    if arm.held_stack.valid_for_read then
      carried_name = arm.held_stack.name
      carrying = arm.held_stack.quality and arm.held_stack.quality.name or "normal"
    elseif inside then
      for _, stack in pairs(inside.get_contents()) do
        carried_name = stack.name
        carrying = stack.quality and (stack.quality.name or stack.quality) or "normal"
        break
      end
    end
    if name ~= carried_name or grade ~= carrying then return false end

    -- The course before the job, so that a refusal leaves the claw on the ghost it had
    -- rather than on one it cannot fly to. choose() has asked this already and this asks it
    -- again of the job as it now stands; what it costs is one intercept, and what it buys is
    -- that nothing is ever crossed to on an answer nobody looked at.
    local was_ghost, was_target = job.ghost, job.target
    job.ghost, job.target = ghost, ghost.position
    if not set_course(record, from, range) then
      -- Put the job back exactly as it was, course included: set_course writes the lead as a
      -- side effect, so a refusal has already cleared the one the claw was flying.
      job.ghost, job.target = was_ghost, was_target
      if job.target then set_course(record, from, range) end
      return false
    end
    if claimed then claimed[claim_of(ghost)] = true end
    -- A new thing to stand over, so where its box goes is asked again.
    job.shift = nil
    -- Crossing to it, which takes aiming the drop at where it is going. An inserter will
    -- not carry a load past its drop position: measured, a claw holding one belt and sent to
    -- the next thing with its drop still at home put the belt down at home -- which for a
    -- fetch is bare ground at its owner's feet -- and went on empty. Aimed at the thing it
    -- is crossing to, it carries the load the whole way in its hand.
    --
    -- The drop and the pickup are the same point, which is what keeps the load in the hand:
    -- an inserter will not put something into the very thing it is picking up from. They
    -- have to be the same point exactly. Off by a fraction and the engine treats them as
    -- two places, deposits the round into the box and takes it straight back out, a tick
    -- each way, for ever.
    --
    -- Aimed now rather than left to the next tick's aim(), which has already run by the
    -- time this is reached: a tick of the drop still pointing home is a tick of the claw
    -- setting off the wrong way and having to turn round again.
    job.crossing = true
    -- In the arm's own frame, for the same reason: pointed at the world position it would
    -- be aimed a lift below the box it is meant to be putting the round into.
    local to = aimed_at(job, record)
    arm.drop_position = { to.x, to.y }
    -- A new leg of the journey, so the swing limit counts from here rather than from the
    -- start of a round that may take half a dozen of them. The leg rather than the journey:
    -- job.started says which journey this is and does not move, since a round that turns to
    -- a fresh thing is still the same round.
    job.leg = game.tick
    return true
  end

  if item ~= job.item then return false end
  -- The claw is already carrying this item at the quality it set off with, and a ghost
  -- wanting another quality of the same thing is a different errand.
  if quality ~= job.quality then return false end
  -- Never onto a swap or a cliff. What comes off a swap is carried home in the claw, and a
  -- claw part way through a round is still holding the round; a charge is a round of its own.
  if upgrading(ghost) or exploding(ghost) or taking(ghost) then return false end

  -- A ghost wanting a different number of the same thing is still worth turning to. What
  -- was set aside covers the ghost the arm set out for, so turning to a smaller one hands
  -- the difference straight back rather than carrying it around: an arm that set off for a
  -- curved rail with one in the claw and two put by, and finds a straight rail instead,
  -- gives the two back on the spot.
  if count ~= job.count then
    local arm = record and record.entity
    local held = arm and arm.valid and arm.held_stack.valid_for_read
      and arm.held_stack.count or 0
    if held < count then return false end
    if (job.escrow or 0) > 0 then
      local inventory = pockets(player, wearer)
      if inventory then
        local returned = inventory.insert{ name = job.item, quality = job.quality, count = job.escrow }
        job.escrow = job.escrow - returned
      end
      -- anything that would not fit stays put by and goes home with the arm
    end
    job.count = count
    job.left = math.floor(held / count)
    if job.left < 1 then return false end
  end

  -- The same again: the course is worked out before the job is changed over, and a refusal
  -- puts the job back as it was. A claw that crossed on an answer nobody looked at spent its
  -- journey changing its mind -- see course_to().
  local was_ghost, was_target = job.ghost, job.target
  job.ghost, job.target = ghost, ghost.position
  if not set_course(record, from, range) then
    -- The same restoration: a refusal has already cleared the lead the claw was flying.
    job.ghost, job.target = was_ghost, was_target
    if job.target then set_course(record, from, range) end
    return false
  end
  if claimed then claimed[claim_of(ghost)] = true end
  job.shift = nil
  -- Crossing to it, the way a fetch does. The claw is holding the rest of the round and
  -- the engine has just let go of what it delivered, so its next move is back to wherever
  -- it picks up from whatever its hand holds. Pointed home that is a wasted journey each
  -- way; aim() points it at the ghost instead for as long as this is set, and advance()
  -- clears it when the hand gets there.
  job.crossing = true
  -- A new leg, so the swing limit counts from here. The fetch path above has always done
  -- this and this one did not, so a long round wrote itself off partway through on a clock
  -- that had been running since its first ghost.
  job.leg = game.tick
  return true
end

---What every arm in the game is already reaching for, so that no two go for the same
---ghost.
---
---Every arm rather than the asking player's own. This was built from one wearer's list, so
---nothing stopped a second player's arm setting off for something already spoken for: both
---claws cross to the same ghost, one of them builds it, and the other carries its load all
---the way home for nothing. Leading makes it likelier by lengthening how long an arm is
---committed to what it chose.
---
---The asking list is walked first and then everybody else's, skipping it where it comes
---round again: it is the stored table itself, so the two are the same object.
---@param list table[] the arms about to be asked
---@return table<string|integer, boolean>
local function claims(list)
  local claimed = {}
  local function note(records)
    for _, record in pairs(records) do
      local job = record.job
      if job and job.ghost and job.ghost.valid then
        claimed[claim_of(job.ghost)] = true
        local partner = paired_with(job.ghost)
        if partner then claimed[claim_of(partner)] = true end
      end
    end
  end
  note(list)
  for _, other in pairs(storage.constructor_arms or {}) do
    if other ~= list then note(other) end
  end
  return claimed
end

---Move one arm's reach on by one tick.
---
---The swing is the inserter's own, so this does not drive it. It watches: the hand arrives
---at what it was aimed at, which is the moment of delivery, and the hand coming back to
---the character is the end of the job.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param claimed table<integer, boolean> what the other arms are reaching for
---Put what the ghost underneath takes out of the claw and into its box.
---
---The engine's own drop, made by hand, for the one case the engine will not make it: a
---claw crossing to the next thing of a round, whose pickup and drop are the same point so
---that the load rides across in the hand. See advance(), which is the only caller.
---
---Only what this one ghost takes. The rest of the round stays in the hand for the things
---after it.
---@param record table
---@param job table
local function hand_over(record, job)
  local arm = record.entity
  local box = record.catcher
  if not (arm and arm.valid and box and box.valid) then return end
  if not arm.held_stack.valid_for_read then return end
  local inside = box.get_inventory(defines.inventory.chest)
  if not inside then return end

  local quality = arm.held_stack.quality and arm.held_stack.quality.name or nil
  local wanted = math.min(job.count, arm.held_stack.count)
  if wanted < 1 then return end
  local put = inside.insert{ name = arm.held_stack.name, quality = quality,
                             count = wanted }
  if put < 1 then return end
  local left = arm.held_stack.count - put
  if left > 0 then arm.held_stack.count = left else arm.held_stack.clear() end
end

--- How many ticks running a course has to be unflyable before the claw gives it up.
---
--- One is too few. A course at speed is often marginal by a hair, and whether an intercept
--- exists flickers from tick to tick as its owner carries the arm along -- so a claw that
--- gave up on the first refusal spent its whole journey changing its mind: it took a
--- neighbour, lost that one the next tick, took the first one back, and delivered to
--- neither. Measured on a train along a double line of ghosts, twenty three of them were
--- set off for and never built at a quarter of a tile a tick.
---
--- Genuine losses do not flicker, and they are told apart by where the thing now is rather
--- than by waiting: an owner who stops walking, turns away, is teleported or leaves the
--- surface puts it outside the cone the hand can sweep altogether, and that is given up on
--- at once. The grace is only for a course lost by a hair.
local ADRIFT = 4

---Whether an arm should give up the course it is on.
---
---Asked every tick, and answered yes only once the course has been refused ADRIFT ticks
---running. holding_course() is what does the refusing, and it re-solves the lead as a side
---effect, so it has to be called every tick whatever the answer.
---@param record table
---@param from {x: number, y: number}
---@param range number
---@return boolean
local function lost_course(record, from, range)
  if holding_course(record, from, range) then
    record.adrift = nil
    return false
  end
  -- Grace only where the loss could be a flicker. A course that has gone because its owner
  -- stopped, turned away, was teleported or left the surface is gone for good and the claw
  -- should come home at once; one that has gone by a hair, with the thing still inside the
  -- cone the hand sweeps, is the kind that comes back a tick later.
  local job = record.job
  local tier = tier_of(record)
  local cone = reach.cone(
    { range = range, extension = tier.extension, out = hand_out(record) },
    record.drift or STILL, reach.full_swing(tier))
  if not (job and job.target and reach.in_cone(cone,
      { x = job.target.x - from.x, y = job.target.y - from.y })) then
    record.adrift = nil
    return true
  end
  record.adrift = (record.adrift or 0) + 1
  return record.adrift >= ADRIFT
end

local function advance(player, wearer, record, slot, count, claimed, nearby)
  local job = record.job

  if not (wearer and wearer.valid) then
    record.job = nil
    return
  end

  -- Where this arm's own base is, which is what its reach is measured from. Asked again
  -- every tick rather than remembered: the vehicle it is bolted to turns, and an arm on the
  -- back of one that has turned round is somewhere else entirely.
  local from = reaching_from(wearer, slot, count)

  -- How far its owner went last tick, which is what out_of_reach() reads the future from.
  -- The wearer's own figure rather than one of this arm's own: see drift_of(), and the
  -- search, which has to be drawn from the same walk the arms are aimed along.
  record.drift = drift_of(player, wearer)
  -- Kept so that aimed_at() can put a lead down relative to it. It is the arm's own base
  -- rather than its owner's middle, because that is what a reach is measured from.
  record.from = from

  if job then
    record.busy = game.tick
    -- Which is not the same as having a job this tick. A swing that has got home waits a
    -- few ticks for its clock, and the slowdown has to hold across that gap: the ramp
    -- sticker is sixty ticks long, so one that ran out in a gap was replaced by a fresh
    -- ramp rather than handing over to the flat sticker, and the character oscillated
    -- instead of settling at the speed their tier asks for. Cleared when there is nothing
    -- left to build, which is decided on the check tick.
    record.run = game.tick
  else
    -- Nothing to do. The arm stays out for a moment in case another ghost turns up, and is
    -- put away if none does, rather than being worn while the character wanders about.
    if record.busy and game.tick - record.busy <= IDLE_TICKS then
      aim(player, wearer, record, slot, count, nil)
    else
      put_away(player, record)
    end
    return
  end

  local arm = aim(player, wearer, record, slot, count, job)
  if not arm then return end

  -- How far this hand went since the last look. The window for arriving is measured from
  -- it rather than from the tier's numbers: what the engine does on its last step is not
  -- what the prototype says its speed is, and a window narrower than the step is one the
  -- hand jumps clean over.
  local hand = arm.held_stack_position
  local moved = record.last_hand and reach.distance(record.last_hand, hand) or 0
  record.last_hand = { x = hand.x, y = hand.y }

  -- An arm that is standing still because it has nothing to move with. aim() has just
  -- topped its buffer up out of its own equipment, so an empty buffer here means the
  -- equipment had nothing to give either, and the hand is not going anywhere -- not on to
  -- the ghost, and not home. Being stopped for want of charge is what is asked, rather
  -- than merely being stopped: a claw waiting over a box for something to be put into it
  -- is standing perfectly still as well, and there is nothing wrong with that one.
  --
  -- Put away rather than left hanging. What it is holding goes back to the pockets it came
  -- out of, the claw folds up where the arm is bolted on, and it comes back out when there
  -- is charge for it again, which is what happens to an arm that never set off in the
  -- first place.
  if moved == 0 and arm.energy < 1 then
    record.stranded = (record.stranded or 0) + 1
    if record.stranded > STRANDED_TICKS then
      put_away(player, record)
      return
    end
  else
    record.stranded = nil
  end

  if job.going == "out" then
    -- The box waiting on the ghost is opened only once this claw is near enough to be the
    -- one that fills it. Left open the whole way out, any inserter of the player's own
    -- pointing at that tile could put something in it, and the mod would take a stranger's
    -- item for its own delivery.
    local target = aimed_at(job, record)
    -- A fetch wants its box from the first tick, not once the claw is near. An inserter
    -- reaches for a source because there is a container at its pickup position: with no box
    -- there, nothing tells the claw to go, so it never gets near, so the box is never made
    -- and the arm stands out of its owner's back doing nothing at all. A delivery is the
    -- other way round and the box is held back until the claw is close, so that no other
    -- inserter of the player's can fill it first.
    local waiting = catcher_at(record, arm.surface, target, job.take
      or reach.distance(hand, target) <= within(tier_of(record), OPEN, moved))
    -- A fetch's box stands at the pickup rather than the drop, so it is the other end of
    -- the swing that has to be told about it.
    if job.take then pin_from(record, waiting) else pin_to(record, waiting) end

    -- The claw has crossed to the next ghost of its round and got there, so the handover
    -- is made here rather than left to the engine.
    --
    -- The engine cannot make it. While the pickup and the drop are the same point it will
    -- not let go -- an inserter never puts anything into the very thing it picks up from --
    -- and that sameness is the only reason the load travelled across in the hand at all.
    -- Putting the pickup back on the rest point to free the drop does not help either: a
    -- hand that has not dropped is on its way to its pickup whatever is in it, so the claw
    -- simply turned round and went home from the ghost it had just reached. Measured, that
    -- is a twenty five tick detour each way, which is the whole of what the bulk claw was
    -- meant to save.
    --
    -- So what this ghost takes goes from the hand into the box, and deliver() finds it
    -- there further down this same tick. Nothing else can get at it in between, which
    -- matters: the box is standing at the claw's own pickup position, and a tick of grace
    -- would let the engine take the load straight back out of it.
    --
    -- A fetch is not this case; take_up() does its own crossing, the other way round.
    if job.crossing and not job.take
        and reach.distance(hand, target) <= within(tier_of(record), HOME, moved) then
      -- The claw has reached what it was aimed at, which on a crossing is not always the
      -- ghost. A crossing works out a fresh lead, and the claw can be standing on that
      -- guess with the ghost still a tile and more away.
      --
      -- Handed over there, the box is wherever the ghost was going to be and the thing is
      -- built from that distance. Measured on a round of four two tiles abeam of a walk,
      -- the second, third and fourth went up on three consecutive ticks with the hand not
      -- travelling between them at all, 1.11, 1.70 and 1.85 tiles from each.
      --
      -- So reaching the guess drops the guess: the aim and the box move on to the ghost
      -- itself, and nothing is handed over on that tick. The claw covers the rest the way
      -- it covered the first one, and hands over when it truly arrives.
      if job.met then
        hand_over(record, job)
      elseif not reach.out_of_range(from, job.target, tier_of(record).range) then
        job.met, job.lead, job.arrival = true, nil, nil
        target = aimed_at(job, record)
        arm.drop_position = { target.x, target.y }
        arm.pickup_position = { target.x, target.y }
        pin_to(record, catcher_at(record, arm.surface, target, true))
      end
    end

    -- the character can walk off mid swing, or the vehicle drive off, and an arm that
    -- stretched to follow would be no kind of inserter
    -- A reach that has run over its limit is a reach that is not getting anywhere, and
    -- pointing it at something else will not unstick it. It is written off where it
    -- stands, and the claw comes home.
    --
    -- Turning to another ghost instead is what it used to do, and it could not stop: the
    -- limit is measured from when the leg began, redirect left that where it was, so the
    -- next
    -- tick had run over as well. Measured on a round of twelve at five tiles, the claw
    -- built three, reached three hundred ticks of age on the third, and then turned to a
    -- fresh ghost on every tick for as long as it was watched -- four hundred turns, no
    -- deliveries, and never home.
    local over = game.tick - (job.leg or job.started or game.tick) > SWING_LIMIT
    if over then
      -- Before abandon(), which is what takes the ghost off the job. Whatever has just cost
      -- an arm a whole swing limit is the last thing it should pick next.
      set_aside(job.ghost)
      abandon(record, job)
    elseif not still_wanted(job.ghost)
        or standing_in(job.ghost, wearer.position)
        or lost_course(record, from, tier_of(record).range) then
      local tier = tier_of(record)
      if not redirect(player, wearer, from, record, job, claimed, tier.range, nearby) then
        abandon(record, job)
      end
    elseif job.take then
      take_up(player, wearer, record, job, claimed, nearby,
        from, tier_of(record).range)
    else
      -- A round that has run out without noticing. What is left of a round is what is left
      -- in the claw, which redirect() checks before it turns a claw to the next ghost and
      -- nothing checked afterwards. A hand that empties some other way leaves the counter
      -- saying there is another delivery to make, and deliver() waits for a load into a box
      -- that nothing is going to fill.
      --
      -- What that looks like is the claw sitting on the ghost it crossed to, turning and
      -- stretching to stay exactly on it as its owner drives away, holding nothing and
      -- doing nothing, until the swing limit gives up. Measured on a train run along a line
      -- of ghosts: seventy three ticks of it, with the hand empty, the box empty, nothing
      -- set aside, and the counter still saying one to go.
      local inside = record.catcher and record.catcher.valid
        and record.catcher.get_inventory(defines.inventory.chest)
      if not arm.held_stack.valid_for_read and (job.escrow or 0) == 0
          and (not inside or inside.is_empty()) then
        abandon(record, job)
      else
        -- deliver() does nothing until the box has been given something, so there is no
        -- arrival to measure and nothing to step over: it can simply be asked every tick
        deliver(player, wearer, from, record, job, claimed, nearby)
      end
    end
  elseif reach.distance(arm.held_stack_position, record.rest or mounting(wearer, slot, count))
        < within(tier_of(record), math.max(HOME, RETRACTED + reach.step(tier_of(record))),
            moved)
      or game.tick - (job.leg or job.started or game.tick) > SWING_LIMIT then
    -- Home is the mounting point, which is not where the character's feet are. Anything
    -- still in the claw was paid for on the way out, so it is handed back rather than
    -- destroyed. If it will not fit and the player would rather not have it on the ground,
    -- the arm holds station with it until there is room.
    if give_back(player, wearer, record) then
      record.job = nil
      -- What the box carried home goes to the pockets too. It is only ever there because
      -- the claw could not hold it -- the far end of an underground pair, say -- and for a
      -- long time catcher_away said what was in it to nobody in particular, which was a
      -- quiet way to lose exactly one underground belt. It puts it back into these same
      -- pockets itself now.
      catcher_away(record)
    end
  end
end

---Hand out work to whichever of a player's arms are free.
---
---There is no clock. An arm sets off the moment it has nothing else to do and there is
---something in reach, and how often that comes round is decided by how long its claw takes
---to go out and come back -- which is the arm's own speed, and the thing a better tier
---buys. The mod used to cap the rate separately, at two builds a second whatever the arm
---was doing. That was left over from when there was no inserter to time, and it did harm:
---at short reaches the claw got home well before its next slot was due, and the arm stood
---waiting. Those gaps are what broke the slowdown ramp and the speed recovery, twice.
---
---One search serves every arm. It is the expensive part, the answer is the same for all of
---them, and only the range each judges it by differs.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arms are on
---@param list table[]
---@param tick integer
---@return boolean whether any arm has anything to do
local function assign(player, wearer, list, tick, nearby)
  local claimed = claims(list)
  nearby = nearby or function()
    return work_near(wearer, list, drift_of(player, wearer))
  end
  local working = false
  -- Shortest arm first. Every arm takes the soonest thing it can reach that nobody else has
  -- claimed, so whichever is asked first gets the pick of the ground -- and a five tile arm
  -- asked first takes the ghost two tiles away and leaves the two tile arm nothing, while
  -- the work at four and five tiles waits for it to come back. Asking in order of reach
  -- hands each tier the nearest thing the tiers below it cannot get to, which on a
  -- character wearing one of each is one ghost apiece.
  --
  -- The order of asking only; the list itself keeps the order the grid is in, because that
  -- is what decides which side of a hull an arm is bolted to.
  -- Whether any arm has work in reach it cannot be sent to for want of charge.
  local starved = false
  local asking = {}
  for slot in ipairs(list) do asking[#asking + 1] = slot end
  table.sort(asking, function(one, other)
    local mine, theirs = tier_of(list[one]).range, tier_of(list[other]).range
    if mine == theirs then return one < other end
    return mine < theirs
  end)

  for _, slot in ipairs(asking) do
    local record = list[slot]
    if record.job then
      working = true
    else
      local tier = tier_of(record)
      local from = reaching_from(wearer, slot, #list)
      local ghost, item, count, quality, waiting =
        job_for(player, wearer, from, nearby(), claimed, record, tier.range)
      if waiting then
        -- work in reach, buffer a tick short of full: the run is still on
        working = true
        starved = true
        record.run = game.tick
      end
      if ghost then
        claimed[claim_of(ghost)] = true
        -- The far end of a pair goes up with this one, so it is spoken for too.
        local partner = paired_with(ghost)
        if partner then claimed[claim_of(partner)] = true end
        record.job = {
          ghost = ghost,
          target = ghost.position,
          item = item,
          -- What quality of it, since a ghost of a legendary belt takes a legendary belt
          -- and an order to upgrade to one takes a legendary one. Everything that moves
          -- this item afterwards moves it at this quality.
          quality = quality,
          count = count,
          going = "out",
          -- When this journey began, which is what says one journey from the next. It does
          -- not move when the claw turns to another thing: that is the same journey going
          -- on.
          started = tick,
          -- When this leg of it began, which is what the swing limit is measured from. A
          -- round of half a dozen is half a dozen legs and each gets its own clock.
          leg = tick,
        }
        -- Where to hold the claw, which is not where the ghost is unless the ghost is
        -- already in reach. choose() only offers what an intercept exists for, so this
        -- finding none is a race rather than an ordinary answer, and the job goes back.
        if not set_course(record, from, tier.range, true) then
          record.job = nil
          claimed[claim_of(ghost)] = nil
          if partner then claimed[claim_of(partner)] = nil end
        end
      end
      if record.job then
        -- Paid for on the way out, not on arrival. Filling the claw from nothing made
        -- every item in it a counterfeit, so any path where the engine put one somewhere
        -- the mod did not intend -- and there were several -- minted a real item out of
        -- air. Taking it from the pockets now means whatever happens to it afterwards,
        -- nothing is created: it is either delivered, brought back, or lost by the player
        -- who owned it. The last tier fills its claw with as many as there is work for.
        local inventory = pockets(player, wearer)
        -- A trip that is going to make a swap carries one thing and no more. The claw
        -- comes home with what came off, and a claw already holding the rest of a round
        -- has nowhere to put it.
        if taking(ghost) then
          -- Nothing is carried out and one thing comes back, so there is nothing to queue.
          record.job.left = 1
          record.job.take = true
        elseif upgrading(ghost) or exploding(ghost) then
          -- A trip that is going to make a swap carries one thing; so does one carrying a
          -- charge, because the blast may take the next cliff on the list with it.
          record.job.left = 1
        else
          local capacity = trips_for(player.force, tier)
          -- A round is shopped for over its own life rather than over the one swing the
          -- tick's search covers. That search is drawn for what an arm can reach now,
          -- because every arm asks it every tick and it has to be cheap; a claw that
          -- carries several is out for all of them and its owner walks the whole time, so
          -- what the round can take in is a good deal further ahead than what the search
          -- brings back. Sized off the tick's own search the list stopped at whatever was
          -- already close enough -- four ghosts ten to thirteen tiles ahead of a walk came
          -- back as three, because the fourth was outside the search altogether -- and the
          -- walk carried the rest square abeam, where nothing walking can reach them,
          -- before the claw was free again.
          --
          -- A second search rather than a wider one for everybody: this is paid once when
          -- a claw sets off, where the tick's search is paid by every arm on every tick.
          local shopping = nearby()
          if capacity > 1 then
            shopping = work_near(wearer, { record }, drift_of(player, wearer), capacity)
            -- In the order the claw will work them, which is what the growing horizon in
            -- loads_for assumes. A fresh search comes back in the map's own index order.
            table.sort(shopping, function(one, other)
              if not (one.valid and other.valid) then return false end
              return reach.distance(from, one.position) < reach.distance(from, other.position)
            end)
          end
          record.job.left = loads_for(record, shopping, claimed, wearer.position, from,
            tier.range, item, quality, count,
            stock_of(player, wearer, inventory, item, quality),
            capacity)
        end
        -- Pointed before it is aimed, and before anything is put in its hand: pointing an
        -- arm is building it again, and a claw loaded first would be loaded into the arm
        -- that is about to be replaced.
        point(player, wearer, record, slot, #list, record.job)
        local arm = aim(player, wearer, record, slot, #list, record.job)
        -- An arm takes a job with an empty hand, and the hand is not always empty.
        --
        -- A claw rests a little way out from where the arm is bolted on, which on a vehicle
        -- is inside the hull -- and a hull with a hold of its own is a container as far as
        -- the engine is concerned, so it helps itself to a belt out of the boot between one
        -- tick and the next, unasked. The loading below then either set_stacks over what is
        -- in the hand or clears it, and either way what the engine put there stops existing.
        --
        -- Measured on a tank turning through a field of ghosts: at tick 530 of the drive the
        -- hold went down by two where one belt was spent, and the second was the one the
        -- engine had picked up a few ticks earlier and set_stack wrote over. One belt in a
        -- hundred and twenty, and only ever on a wearer that has somewhere to keep things.
        --
        -- Handed back rather than kept: it came out of these same pockets, so giving it
        -- back nets to nothing, and the load this job is about is counted out below.
        if arm and arm.held_stack.valid_for_read then
          local inventory = pockets(player, wearer)
          give_to(player, wearer, inventory, {
            name = arm.held_stack.name,
            quality = arm.held_stack.quality and arm.held_stack.quality.name or nil,
            count = arm.held_stack.count,
          })
          arm.held_stack.clear()
        end
        if arm and record.job.take then
          -- Nothing leaves the pockets for a fetch. The claw sets off empty.
          record.job.carried = 0
          record.job.escrow = 0
        elseif arm then
          -- Everything the round will need comes out of the pockets now, whether or not
          -- the claw can hold it. A claw holds what its inserter holds -- one thing for a
          -- plain one -- and a curved rail wants three, so the claw takes as many as fit
          -- and the rest are set aside against this job. A construction robot carries all
          -- three at once regardless of its cargo size, so this is the same bargain by
          -- other means: the items are spent when the arm sets off and given back if it
          -- comes home without building anything.
          local want = count * record.job.left
          local taken = spend(player, wearer, inventory, item, quality, want)
          if taken < count then
            -- not even one ghost's worth left in the pockets
            if taken > 0 then
              refund(player, wearer, inventory, item, quality, taken)
            end
            arm.held_stack.clear()
            record.job = nil
          else
            record.job.left = math.floor(taken / count)
            arm.held_stack.set_stack{ name = item, quality = quality, count = taken }
            -- what the claw actually took, and what is being carried on its behalf
            record.job.carried = arm.held_stack.valid_for_read and arm.held_stack.count or 0
            record.job.escrow = taken - record.job.carried
          end
        end
        -- The box has to be standing on the target before the engine next moves the hand,
        -- rather than on the tick after. A freshly built arm's hand starts seven tenths of
        -- a tile out along the way it faces -- measured, at every tier and every direction
        -- -- so an arm pointed at something inside that is at its drop position already on
        -- the tick it is loaded. The engine puts a load down when the hand arrives whether
        -- anything is there to take it or not: with no box, a belt on the floor and the
        -- ghost still standing. advance() opens the box once the claw is near, and on the
        -- tick an arm sets off advance has already run.
        if arm and record.job and not record.job.take then
          local target = aimed_at(record.job, record)
          if reach.distance(arm.held_stack_position, target) <= within(tier, OPEN) then
            pin_to(record, catcher_at(record, arm.surface, target, true))
          end
        end
        working = true
      end
    end
  end
  flag_power(player, wearer, starved)
  return working
end

---Whether there is anything left to build, asked ten times a second rather than every tick.
---
---Lifted out of on_tick so that what the tick has to remember for the next one can happen
---after everything, rather than behind a return that only check ticks reach.
---@param tick integer
local function check(tick)
  for _, player in pairs(game.players) do
    local wearer = wearer_of(player)
    if wearer and wearer.valid and not switched_off(player) then
      -- Nothing left in reach is when the character starts getting their speed back, not
      -- merely no arm swinging this instant: the search runs ten times a second and a claw
      -- can be home for a few ticks before the next one, and recovering in those gaps had
      -- the character surging between one ghost and the next all the way along a
      -- blueprint. So this asks whether there is anything to build.
      local list = storage.constructor_arms[player.index] or {}
      -- No arm working after that means no arm could find anything, because an arm with
      -- nothing to do takes work the instant there is any: without a clock there is no
      -- such thing as free but not yet due. So this needs no second search of its own.
      if not assign(player, wearer, list, tick, nearby) then
        -- the run is over, which is what lets the slowdown ramp off
        for _, record in pairs(list) do record.run = nil end
        recover(player, wearer)
      end
    end
  end
end

---@param event EventData.on_tick
local function on_tick(event)
  stowing()
  folding()

  for _, player in pairs(game.players) do
    local wearer = wearer_of(player)
    -- Greyed out when there is no arm to switch off, the way the exoskeleton's button is.
    -- Asked here rather than on an event because the answer changes for half a dozen
    -- reasons -- a piece put in, one taken out, an armour swapped, a vehicle climbed into
    -- or out of -- and only one of those has an event worth hanging it on.
    if prototypes.shortcut[TOGGLE] then
      local available = #worn(wearer) > 0
      if storage.constructor_button[player.index] ~= available then
        storage.constructor_button[player.index] = available
        player.set_shortcut_available(TOGGLE, available)
      end
    end
    if wearer and wearer.valid and wearing(wearer) and not switched_off(player) then
      local list = muster(player, wearer)
      -- Where every hand has got to, brought up to date before anything asks. A pass of its
      -- own and before the arms are worked, because aim() writes this tick's targets and
      -- follow() has to step on the one that stood when the engine last moved -- see
      -- follow(), and the order measured there.
      for _, record in pairs(list) do follow(record) end
      local claimed = claims(list)
      -- One search a tick at most, shared by the arms already out and the ones about to set
      -- off, and only made if one of them asks. Most ticks nobody does: every arm is out on
      -- a job it already has, and searching the ground round somebody who has nothing to
      -- decide is four find_entities_filtered calls spent on an answer nothing reads.
      local searched
      local function nearby()
        if not searched then
          searched = work_near(wearer, list, drift_of(player, wearer))
        end
        return searched
      end
      -- Slowed for as long as an arm is working, not only at the moment one arrives.
      -- Applying it on delivery alone left a gap: the ramp ran out partway through the
      -- next swing and the character surged until the next thing was delivered.
      --
      -- One slowdown however many arms are working, and where they disagree it is the
      -- heaviest that lands: a tier that asks for nothing does not excuse the tier working
      -- beside it that does. So a good arm worn on its own costs its wearer no speed, and
      -- worn alongside an old one it costs whatever the old one costs.
      local worst, running = nil, false
      for slot, record in ipairs(list) do
        advance(player, wearer, record, slot, #list, claimed, nearby)
        if record.run then
          running = true
          local set = tier_of(record).stickers
          if set and (not worst or set.modifier < worst.modifier) then worst = set end
        end
      end
      if worst then
        slow(player, wearer, worst)
      elseif running then
        -- arms are in a run and none of them asks for any penalty, so give the speed back
        -- rather than waiting for the work to run out
        recover(player, wearer)
      end
      -- An arm in no run at all is deliberately left alone here rather than recovered.
      -- Whether there is anything left to build is asked on the check tick, where it can
      -- be answered properly, and that is what ends a run.
    else
      -- taken off, switched off, the character is gone, or they are riding in a vehicle as
      -- a passenger: no arms and no half finished swings
      dismiss(player)
    end
  end

  if event.tick % CHECK_INTERVAL == CHECK_TICK then check(event.tick) end

  -- And what each hand will be chasing when the engine comes to move it, remembered while
  -- the tick can still see it. The load leaves a hand during the engine's own update, so an
  -- arm asked next tick which end it spent this one going to would answer the wrong one.
  for _, player in pairs(game.players) do
    for _, record in pairs(storage.constructor_arms[player.index] or {}) do
      local arm = record.entity
      record.chasing_drop = (arm and arm.valid and arm.held_stack.valid_for_read) or false
    end
  end
end

---Getting into or out of a vehicle changes which grid the arms come out of.
---
---The next tick would notice on its own, because an arm is retired when the grid it was
---mustered against is no longer the one being worn. This is here so that the handover
---happens on the tick it is asked for rather than the one after: a claw halfway out when
---its owner climbs into a car would otherwise spend a tick reaching from the car with the
---armour's charge behind it.
---
---The slowdown is handed back on both sides, because either of them can be carrying one. A
---driver who gets out while the arms are working leaves the vehicle slowed for as long as
---the sticker lasts, and a character who climbs in mid run would be walking slowly when
---they got out again.
---@param event EventData.on_player_driving_changed_state
local function on_driving_changed(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  dismiss(player)
  recover(player, event.entity)
  recover(player, player.character)
end

---Switch a player's arms on or off, and put the button in the matching state.
---
---Switching off is not merely a refusal to start anything new. A claw halfway out is
---brought home the same way taking the equipment off brings it home -- items back in the
---pockets, charge back in the grid -- and whatever speed the arms were costing is handed
---back on the spot rather than left to expire.
---@param player LuaPlayer
---@param on boolean
local function switch(player, on)
  storage.constructor_off[player.index] = (not on) or nil
  if prototypes.shortcut[TOGGLE] then player.set_shortcut_toggled(TOGGLE, on) end
  if on then return end
  fold(player)
  -- both, because the arms may be on either and a character who climbs out of a vehicle
  -- should not find their own legs still slowed
  recover(player, wearer_of(player))
  recover(player, player.character)
end

---Put the button where the save says it should be, and grey it out when there is nothing
---for it to switch off.
---
---The exoskeleton's button does the same: a toggle nobody can act on reads as a thing that
---is broken rather than a thing that is not there. Available means an arm is worn, which is
---a question about the grid in front of the player rather than about the technology, since
---the technology only decides whether the button exists at all.
---@param player LuaPlayer
local function show(player)
  if not prototypes.shortcut[TOGGLE] then return end
  player.set_shortcut_toggled(TOGGLE, not switched_off(player))
  local available = #worn(wearer_of(player)) > 0
  storage.constructor_button[player.index] = available
  player.set_shortcut_available(TOGGLE, available)
end

---Press the button: whatever the arms are doing now, do the other thing.
---
---Global, and for one reason: on_lua_shortcut is one of the events the engine will not let
---a script raise, so a test cannot press the button by pretending to be the toolbar. It can
---call this, which is what the toolbar reaches in the end.
---@param player LuaPlayer
function press(player)
  switch(player, switched_off(player))
end

---@param event EventData.on_lua_shortcut
local function on_shortcut(event)
  if event.prototype_name ~= TOGGLE then return end
  local player = game.get_player(event.player_index)
  if player then press(player) end
end

---@param event EventData.CustomInputEvent
local function on_toggle_key(event)
  local player = game.get_player(event.player_index)
  if player then press(player) end
end

---@param event EventData.on_player_created
local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then show(player) end
end

--- Everything setup() does, and then the button, which needs a game to exist and so cannot
--- be done from on_init.
local function configured()
  setup()
  for _, player in pairs(game.players) do show(player) end
end

script.on_init(setup)
script.on_configuration_changed(configured)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_player_driving_changed_state, on_driving_changed)
script.on_event(defines.events.on_lua_shortcut, on_shortcut)
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(TOGGLE, on_toggle_key)

--- What an arm is doing, for a harness to read. There is no way for another mod to see
--- storage, and the interesting half of a stall is in the job rather than in the entity.
---
--- Gated on ce-stall being loaded for the same reason the fixtures are gated on ce-tests:
--- neither is published, so neither can be present in a player's game, and the mod carries
--- no debug surface it did not ask for.
if script.active_mods["ce-stall"] then
  remote.add_interface("constructor-equipment", {
    ---@param index integer a player index
    ---@return table[] one entry per arm, in the order they are mounted
    arms = function(index)
      local out = {}
      for slot, record in pairs(storage.constructor_arms and storage.constructor_arms[index]
          or {}) do
        local job = record.job
        out[slot] = {
          arm = record.entity and record.entity.valid and record.entity.unit_number or nil,
          catcher = record.catcher and record.catcher.valid
            and record.catcher.position or nil,
          keeper = record.keeper and record.keeper.valid and record.keeper.position or nil,
          rest = record.rest,
          lift = record.lift,
          level = record.level,
          busy = record.busy,
          run = record.run,
          job = job and {
            item = job.item, take = job.take, going = job.going, left = job.left,
            carried = job.carried, escrow = job.escrow, crossing = job.crossing,
            met = job.met, target = job.target, leg = job.leg, started = job.started,
            arrival = job.arrival, lead = job.lead,
            ghost = job.ghost and job.ghost.valid or false,
          } or nil,
        }
      end
      return out
    end,
  })
end

--- ce-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["ce-tests"] then
  require("__factorio-test__/init")({
    "test.ft.building",
    "test.ft.delivering",
    "test.ft.characterless",
    "test.ft.slowdown",
    "test.ft.interpolation",
    "test.ft.power",
    "test.ft.several",
    "test.ft.equipping",
    "test.ft.tiers",
    "test.ft.vehicles",
    "test.ft.toggle",
    "test.ft.upgrading",
    "test.ft.cliffs",
    "test.ft.taking",
    "test.ft.intercept",
    "test.ft.course",
    "test.ft.leading",
    "test.ft.steering",
    "test.ft.notatrest",
    "test.ft.showroom",
    "test.ft.losing",
    "test.ft.grabbing",
    "test.ft.bare",
    "test.ft.vanilla",
    "test.ft.searching",
    "test.ft.chunkful",
    "test.ft.underfoot",
    "test.ft.turning",
    "test.ft.swinging",
    "test.ft.following",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
