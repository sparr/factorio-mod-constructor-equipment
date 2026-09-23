--- How far things are, for deciding what is still worth reaching for.
---
--- The swing itself is the engine's business: the inserter entity knows how to move its
--- own arm, including the elbow, and no amount of arithmetic here would do it as well.
--- What is left is measuring, and that needs no game.
local reach = {}

--- Factorio runs Lua 5.2, which spells this math.atan2; 5.3 dropped that name and gave
--- math.atan a second argument instead. The unit tests run on whatever Lua is installed,
--- so the name is looked up rather than written down.
local atan2 = math.atan2 or math.atan

---How far apart two points are.
---@param from {x: number, y: number}
---@param to {x: number, y: number}
---@return number
function reach.distance(from, to)
  local dx, dy = to.x - from.x, to.y - from.y
  return math.sqrt(dx * dx + dy * dy)
end

---Whether the target has got too far away to go on reaching for it.
---
---Checked every tick of a swing rather than only at the start, because the character can
---walk away mid reach and the arm has to give up rather than stretch.
---@param from {x: number, y: number}
---@param to {x: number, y: number}
---@param range number
---@return boolean
function reach.out_of_range(from, to, range)
  return reach.distance(from, to) > range
end

--- How much further than its last step the hand is allowed to be and still count as
--- arriving this tick. Two, because the engine's last step is not its ordinary one: it
--- covers whatever gap is left rather than creeping up and stopping, and the largest
--- overshoot measured was 0.441 against an ordinary 0.25.
reach.OVERSHOOT = 2

---The furthest an arm's hand can move in a tick, going by its prototype.
---
---Extension carries the hand straight out at the tier's extension speed; rotation swings
---it round, and a hand at full stretch travels the whole circumference in one rotation, so
---a turn carries it rotation * 2 * pi * range. The engine does both at once, so this is the
---hypotenuse rather than the larger of the two.
---
---It is a floor and not a prediction. The engine's last step is larger than this, which is
---the whole reason reach.within also takes what the hand was just seen to do.
---@param tier table
---@return number tiles
function reach.step(tier)
  local turning = tier.rotation * 2 * math.pi * tier.range
  return math.sqrt(tier.extension * tier.extension + turning * turning)
end

---How close is close enough for one arm, given how fast its hand is actually moving.
---
---The hand is looked at once a tick, so a window narrower than a tick of travel is a band
---the hand can step clean over. That is not a near miss: the arm is aimed at the ghost the
---whole way out, so an arrival the mod fails to see is one the engine completes itself, by
---putting the load on the ground on the ghost's own tile.
---
---What makes this awkward is that the tier's own numbers do not predict the engine's last
---step. A window worked out from extension and rotation gave 0.30 for a fourth tier arm
---that was then measured stepping 0.459 straight over it. So the width follows what the
---hand has just been seen doing, which needs no model of the engine and adapts to whatever
---it does next.
---
---Widening it for every tier instead was tried and was worse than the disease: delivering
---half a tile short shortens every swing, and on the slow tiers it opened gaps between one
---trip and the next that a player would feel as the arms stuttering.
---@param tier table
---@param threshold number
---@param moved number? how far this hand went last tick
---@return number
function reach.within(tier, threshold, moved)
  return math.max(threshold, reach.step(tier), (moved or 0) * reach.OVERSHOOT)
end

--- Where a freshly built hand sits, in tiles out from the arm's own base along the way it
--- was built facing -- and, deliberately, where an idle claw is held as well. It is what
--- prototypes/inserter.lua asks for as starting_distance and what control.lua uses as REST,
--- so that being built and being at rest are the same place and there is nothing to see
--- between them.
---
--- Two 256ths of a tile: as near the base as the engine can be held to without landing on
--- it. Nothing is not allowed, for the one reason that has nothing to do with birth -- a
--- pickup sitting exactly on the arm's base is no bearing, and the engine answers by turning
--- the hand back towards the way the arm was built facing while it retracts, so a claw folds
--- home the long way round instead of coming in along the line it went out on. Measured on a
--- fourth tier arm, that curve bulges 2.27 tiles out to the side. One 256th off the base is
--- already enough to cure it, measured; see test/ft/resting.lua.
---
--- Two rather than one because the rest point is aimed along whatever bearing the claw was
--- last working on, and the engine snaps each axis to its own 256th rather than the radius.
--- At one 256th a bearing near the diagonal has components of 0.0028, which is inside the
--- rounding window, so both axes can land back on the base and the fold curves round after
--- all. Every component of a two 256th offset is at least 0.0055, which is more than a whole
--- 256th, and a span wider than the grid cannot fit inside one cell of it. So this is the
--- smallest radius that is safe from every bearing rather than merely from the ones a test
--- happened to try.
---
--- What it was, and what it cost. Left at the engine's default of 0.7 a fresh hand appeared
--- 179/256 of a tile out along the way the arm was built facing -- the same on every tier,
--- though one reaches two tiles and another five, and a hair short off the cardinals because
--- each axis is snapped to its own 256th rather than the radius being. An arm is put away
--- when it is idle and built again when it sets off, so that birth radius was where nearly
--- every swing started. It was a head start of 0.7 of a tile: twenty ticks of a first tier
--- swing, seven of a fourth tier one.
---
--- It was also visible, which is what settled it. An arm that appears part way out and then
--- pulls in to its rest point before setting off is an arm seen to flinch -- see the toolbar
--- button in TODO.md -- and the same jump happened every time point() built one again to
--- turn it. Born where it rests, there is nothing to pull in from.
---
--- Nothing else about the prototype has any say in it. Six copies of a fourth tier arm with
--- their pickup_position and insert_position moved about -- a drop three tiles out, a pickup
--- three tiles out, both, a pair pointing across the arm's own facing, and a drop a fifth of
--- a tile long -- all start their hands in exactly the same place, and setting either end
--- from script on the tick the arm is built does not move it either. starting_distance is
--- the one field that does. See test/ft/intercept.lua and test/ft/resting.lua, and the
--- variants test/ft/ce-tests builds for them.
reach.BORN = 2 / 256

---How long a hand takes to go all the way out, in ticks.
---
---The hand's whole journey is extension: an arm is built facing what it is about to reach
---for, so there is next to nothing left to turn through, and the engine does both at once
---in any case. What it travels is the tier's reach less wherever the hand began.
---
---Checked against the real thing on all four tiers: this says 37.3, 46.1, 33.1 and 43.1,
---and the engine lets go on ticks 37, 46, 33 and 43. The tick it is over by is the engine's
---last step, which covers whatever gap is left rather than creeping up on it.
---@param tier table
---@return number ticks
function reach.full_swing(tier)
  return (tier.range - reach.BORN) / tier.extension
end

---Where to look for work, for arms that may set off at any moment.
---
---Everything an arm reaches for is fixed in the world and the arm is not, so what is worth
---finding is not what is in reach now but what will be in reach at any moment between now
---and the furthest ahead a hand set off with now could arrive. Its owner walks on while the
---hand is out, and a ghost that is two tiles too far away at the moment of asking is one
---the claw meets halfway.
---
---Which is a circle swept along the way its owner is going. An arm that can reach `range`
---and whose hand is out for `ticks` covers everything within `range` of anywhere its owner
---stands between here and `speed * ticks` further on, and the smallest circle round that is
---centred half the travel ahead with the travel's half added to the reach. Standing still
---it is the reach itself, unchanged, which is what this used to be.
---
---Deliberately generous, and this is the only place that is. Every arm covered spends the
---whole of its flight at less than its full stretch, so most of what comes back is out of
---reach at every moment of the journey and will be turned away by whatever asks next. What
---this owes is that nothing reachable is missed, not that nothing unreachable is offered.
---
---Several arms are covered by one circle rather than one apiece, because one search is
---shared out between them. They point the same way -- it is the same owner walking -- so
---the circles all lie on one line and the smallest circle round the lot is the span from
---the furthest any of them reaches behind to the furthest any of them could meet ahead.
---@param arms {range: number, ticks: number}[] each arm's reach and how long its hand is out
---@param drift {x: number, y: number} how far their owner went last tick
---@return {x: number, y: number} offset from the owner to the middle of the search
---@return number radius
function reach.search(arms, drift)
  local speed = math.sqrt(drift.x * drift.x + drift.y * drift.y)
  local behind, ahead = 0, 0
  for _, arm in ipairs(arms) do
    behind = math.max(behind, arm.range)
    ahead = math.max(ahead, arm.range + speed * arm.ticks)
  end
  local along = (ahead - behind) / 2
  if speed <= 0 then return { x = 0, y = 0 }, behind end
  return { x = drift.x / speed * along, y = drift.y / speed * along },
    (ahead + behind) / 2
end

---The same ground as reach.search, drawn as a box lying along the way its owner is going.
---
---A circle round a moving arm's reach is mostly the ground either side of it. What the arms
---between them can touch runs from a reach behind the wearer to a reach plus a walk ahead,
---and is never wider than the longest reach -- so a circle whose radius is half that length
---is as wide as it is long, and at a train's speed that is fourteen tiles of width around
---five tiles of arm.
---
---find_entities_filtered honours a BoundingBox orientation, so the box can lie along the
---walk instead of boxing it in. Measured on a fourth tier arm in a packed field behind a
---train: 673 candidates and 188 microseconds for the circle against 275 and 100 for the box.
---
---Laid along positive x and then turned, because that is the mapping the engine uses: a box
---along x with orientation a is a box along the bearing a turns clockwise from x.
---
---Nothing is gained standing still, where the box is a square round a circle and a quarter
---more area for nothing, so this hands back nil and the caller draws the circle instead.
---@param arms {range: number, ticks: number}[]
---@param drift {x: number, y: number}
---@return {x: number, y: number}?, number?, number?, number? centre, half length, half
---        width, orientation
function reach.search_box(arms, drift)
  local speed = math.sqrt(drift.x * drift.x + drift.y * drift.y)
  if speed <= 0 then return nil end
  local behind, ahead = 0, 0
  for _, arm in ipairs(arms) do
    behind = math.max(behind, arm.range)
    ahead = math.max(ahead, arm.range + speed * arm.ticks)
  end
  local along = (ahead - behind) / 2
  return { x = drift.x / speed * along, y = drift.y / speed * along },
    (ahead + behind) / 2, behind,
    atan2(drift.y, drift.x) / (2 * math.pi) % 1
end

---Whether an arm could still put something down at a given spot, at any moment between now
---and a swing's time from now.
---
---The same question reach.earliest answers, asked for a yes or no. It was its own piece of
---arithmetic once, and having two of them was a mistake that showed: measured against each
---other over forty thousand arrangements they disagreed on 273, by as much as thirty nine
---ticks, and it was the cruder of the two that control.lua was using.
---
---The exact question the search only answers roughly. A hand is not at full stretch the
---moment it sets off: it starts where it was born and reaches out at the tier's own speed,
---so what it can touch at tick k is whatever lies within `out + extension * k` of wherever
---its owner has walked to by then, capped at the tier's reach. Sweep k from nought to the
---horizon and that is a circle growing along a line -- a cone, and the convex hull of the
---small circle it starts as and the full one it ends as.
---
---Which is a good deal less than the circle the search draws round it. A ghost square
---abeam of a walking character at the very edge of the reach is inside that circle and is
---not inside this: by the time the hand has stretched the five tiles, its owner has carried
---the shoulder six tiles past, and the gap only ever opened. The arm was never going to
---arrive, and this is what says so before a swing is spent finding out.
---
---Two pieces, because the reach is capped. While the hand is still growing the answer is
---where a quadratic in k dips below nought, and once it has reached full stretch the circle
---stops growing and merely slides, so the answer is the distance to a segment.
---@param arm {range: number, extension: number, out: number?} out is how far the hand is
---       out now, defaulting to where a hand is born
---@param drift {x: number, y: number} how far its owner went last tick
---@param offset {x: number, y: number} the spot, seen from the arm's own base
---@param ticks number how far ahead to look
---@return boolean
function reach.meets(arm, drift, offset, ticks)
  return reach.earliest(arm, drift, offset, ticks) ~= nil
end

--- How much later than the first moment a target comes within reach the claw is aimed to
--- arrive.
---
--- One tick, and the whole of why is the engine's drop lag: it lets go against the aim it
--- was given on the tick before, so a claw aimed to land exactly on the moment its target
--- becomes reachable lets go against the lead rather than against the target. A tick later
--- and the aim it lets go against is the target itself, wherever the hand actually arrives.
--- Measured both ways: aiming at the moment itself put the load a whole tick of walking
--- short every time, and aiming a tick past it landed inside a four hundredth of a tile.
reach.MARGIN = 1

---The real roots of a quadratic, in order, or nothing.
---@return number?
---@return number?
local function roots(a, b, c)
  if math.abs(a) < 1e-12 then
    if math.abs(b) < 1e-12 then return nil end
    local only = -c / b
    return only, only
  end
  local under = b * b - 4 * a * c
  if under < 0 then
    -- A path that grazes a boundary rather than crossing it makes this nought, and rounding
    -- can leave it a whisker under. Throwing those away loses a real answer: measured, a
    -- target running tangent to the edge of the reach is met on exactly one tick, and that
    -- tick is there to be had.
    if under < -1e-9 * math.max(1, math.abs(b * b)) then return nil end
    under = 0
  end
  local root = math.sqrt(under)
  local one, other = (-b - root) / (2 * a), (-b + root) / (2 * a)
  if one > other then one, other = other, one end
  return one, other
end

---Whether the hand can be exactly on a spot at a given moment.
---
---A hand is not free to be anywhere. At tick k it can be anywhere between what it can pull
---in to and what it can push out to, and no further either way: retracting takes as long as
---extending. So meeting something is the distance to it falling inside that band, which is
---two inequalities rather than one.
---And it has to be pointing the right way. A hand out on one bearing and wanted on another
---swings round at its tier's own rate and no faster, which for the fourth tier is 2.88
---degrees a tick -- so half a turn is sixty three ticks against nothing at all for the
---stretch, and the turn is very often the whole of the journey. Measured against the engine
---at five angles: 1, 16, 32, 47 and 63 ticks for 0, 45, 90, 135 and 180 degrees, which is
---the rotation speed to the tick.
---
---A hand with no bearing yet is not held to this. That is a fresh arm, which is built facing
---whatever it is about to reach for, so there is nothing to turn through -- see point() in
---control.lua, and the eleven ways an existing hand was found not to be turnable.
---
---Radius and bearing are separate speeds the engine runs at once, not one after the other,
---so the two conditions are independent rather than added together.
---@param arm {range: number, extension: number, out: number?, rotation: number?,
---           facing: {x: number, y: number}?}
---@param drift {x: number, y: number}
---@param offset {x: number, y: number} the spot, from the arm's base, now
---@param k number
---@return boolean
function reach.on_it(arm, drift, offset, k)
  if k < -1e-9 then return false end
  local out = arm.out or reach.BORN
  local dx, dy = offset.x - drift.x * k, offset.y - drift.y * k
  local away = math.sqrt(dx * dx + dy * dy)
  -- A tick's grace on how far the hand has got, because the engine's last step is not
  -- bounded by the extension speed: it covers whatever gap is left in one go rather than
  -- creeping up on it. Measured on all four tiers, a hand is at full stretch on the tick the
  -- nominal speed says it will still be short -- 37, 46, 33 and 43 against 37.3, 46.1, 33.1
  -- and 43.1. Without it, something sitting at exactly the reach of somebody standing still
  -- is refused, which is the plainest case there is.
  local travelled = arm.extension * (k + 1)
  local nearest = math.max(0, out - travelled)
  local furthest = math.min(arm.range, out + travelled)
  if away < nearest - 1e-9 or away > furthest + 1e-9 then return false end
  if not (arm.facing and arm.rotation) then return true end
  if away < 1e-9 then return true end
  local now = atan2(arm.facing.y, arm.facing.x)
  local wanted = atan2(dy, dx)
  local apart = math.abs(wanted - now) % (2 * math.pi)
  if apart > math.pi then apart = 2 * math.pi - apart end
  -- The same tick of grace the radius gets, because the engine's last turn step covers
  -- whatever is left of the turn exactly as its last extension step does.
  --
  -- This said the opposite for a long while, on a measurement that had the hand arriving on
  -- ceil of the nominal. Measured again with the hand held at a fixed three tiles by a
  -- barred box, so that nothing stretches and nothing is delivered, and with arrival asked
  -- as a hundredth of a tile from the spot -- a fifth of a degree at that radius, a twelfth
  -- of a step -- it is floor every time: 45, 90, 135 and 180 degrees took 7, 14, 22 and 29
  -- steps on the second tier against nominals of 7.35, 14.71, 22.06 and 29.41, and 18, 36,
  -- 55 and 73 on the fourth against 18.38, 36.77, 55.15 and 73.53. Eight of eight, two
  -- tiers, never a step over.
  --
  -- What the old figure was measuring is most likely the mod's arrival window rather than
  -- the hand: a window is worth a fraction of a tick of turn, and at three tiles half a
  -- degree of it is a fifth of a step.
  return apart <= arm.rotation * 2 * math.pi * (k + 1) + 1e-9
end

---How long a hand takes to be able to face any way at all, in ticks.
---
---Half a turn at its own rate, since a hand turns whichever way is shorter and nothing is
---further off than that. Past this the bearing has stopped mattering and only the reach and
---the stretch are left, which is what lets the exact arithmetic take over.
---@param arm {rotation: number?}
---@return number
function reach.any_way(arm)
  if not arm.rotation or arm.rotation <= 0 then return 0 end
  return 0.5 / arm.rotation
end

---The first moment a hand could be exactly on a spot, or nothing if it never can.
---
---Everything an arm reaches for tracks a straight line across the reach, seen from the arm,
---so the obvious cheap test is to look at where that line enters and leaves. It does not
---work, and it is worth saying why, because the reason is not subtle once seen: the two ends
---of that line are exactly where the thing is furthest away -- a whole reach away, by
---definition of the boundary -- which is the hardest place for a hand to get to rather than
---a representative one. Swept over four hundred thousand arrangements, the ends say no and
---the middle says yes in one case in thirteen.
---
---What is true is the same shape with better points. Three things bound a meeting: the thing
---has to be inside the reach, the hand has to stretch far enough, and the hand has to not be
---further in than it can pull to. Each boundary is where a quadratic in k crosses zero, so
---between consecutive roots nothing changes -- a stretch is feasible all through or not at
---all. Test the roots and one point in each gap between them and the whole answer is there,
---in a fixed handful of sums rather than a walk.
---@param arm {range: number, extension: number, out: number?}
---@param drift {x: number, y: number} how far its owner went last tick
---@param offset {x: number, y: number} the spot, from the arm's own base, now
---@param ticks number how far ahead to look
---A whole tick, because that is all there is. The exact answer can be a sliver narrower
---than a tick -- measured, one three thousandth of one, where a thing crosses into the reach
---a moment before the hand has pulled back out of its way -- and a window no tick lands in
---is a window nothing can use.
---@return number? the first whole tick it could be met on
function reach.earliest(arm, drift, offset, ticks)
  local out = arm.out or reach.BORN
  local e, range = arm.extension, arm.range
  local vx, vy = drift.x, drift.y
  local v2 = vx * vx + vy * vy
  local wu = offset.x * vx + offset.y * vy
  local w2 = offset.x * offset.x + offset.y * offset.y

  -- Every boundary there is, as the roots of one quadratic apiece: the edge of the reach,
  -- the furthest the hand could have got, and the nearest it could have pulled to.
  local marks = { 0, ticks }
  local function note(one, other)
    if one then
      if one >= 0 and one <= ticks then marks[#marks + 1] = one end
      if other and other >= 0 and other <= ticks then marks[#marks + 1] = other end
    end
  end
  -- The same tick of grace on_it gives the hand, folded into where it started: reaching
  -- out + e * (k + 1) is reaching (out + e) + e * k. Derived from anything else, these
  -- boundaries would not be the boundaries of the thing they are supposed to bound.
  local far, near = out + e, out - e
  note(roots(v2, -2 * wu, w2 - range * range))
  note(roots(v2 - e * e, -2 * (wu + far * e), w2 - far * far))
  note(roots(v2 - e * e, -2 * (wu - near * e), w2 - near * near))
  table.sort(marks)

  -- While a hand could still be pointing the wrong way, the answer is not a matter of roots
  -- any more: where a bearing gets to is an arctangent rather than a quadratic, and nothing
  -- says feasibility holds all through a gap. So that stretch is looked at a tick at a time,
  -- which is exact and is bounded -- by half a turn at the tier's own rate, sixty three
  -- ticks at worst and fewer on the quicker tiers. Past it the bearing cannot refuse
  -- anything and the roots are the whole answer again.
  -- Rounded up, and the whole tick that half a turn falls inside counts as still turning:
  -- half a turn is 62.5 ticks on the fourth tier, and leaving tick 63 to the roots dropped
  -- it between the two halves of this.
  local scanned = -1
  if arm.facing and arm.rotation then
    scanned = math.min(ticks, math.ceil(math.min(ticks, reach.any_way(arm)) - 1e-9))
    for k = 0, scanned do
      if reach.on_it(arm, drift, offset, k) then return k end
    end
  end

  for index = 1, #marks do
    local from, to = marks[index], marks[index + 1]
    -- Nothing changes between two boundaries, so one look decides a whole stretch: at the
    -- boundary itself, and at the middle of the gap that follows it.
    local open = reach.on_it(arm, drift, offset, from)
    if not open and to and to - from > 1e-9 then
      open = reach.on_it(arm, drift, offset, (from + to) / 2)
    end
    if open then
      local whole = math.ceil(from - 1e-9)
      if whole < 0 then whole = 0 end
      -- Anything inside the turning stretch has been looked at already.
      if whole <= scanned then whole = scanned + 1 end
      if whole <= (to or ticks) + 1e-9 and whole <= ticks
          and reach.on_it(arm, drift, offset, whole) then
        return whole
      end
    end
  end
  return nil
end

---When to aim to arrive, and where to hold the claw until it does.
---
---Everything an arm reaches for is fixed in the world and the arm is not, so a claw sent to
---where its target is now arrives where its target no longer is. What it is sent to instead
---is an offset from its own base -- a point that travels with its owner -- chosen so that
---the target falls exactly on it at the moment the hand gets there.
---
---Which moment is the first one the target is inside the reach, plus the margin above, held
---to the last moment it is still inside: a target only clipped by the corner of the reach
---for a tick or two has not got a spare tick to give away, and for that one the margin is
---whatever is left rather than a whole tick.
---
---A hand part way through a reach is the same question with a different starting radius, and
---it may retract as readily as extend, which is what `out` is for. Nothing here knows about
---turning: the bearing a claw would have to swing through is a separate constraint and a
---separate refusal.
---@param arm {range: number, extension: number, out: number?}
---@param drift {x: number, y: number} how far its owner went last tick
---@param offset {x: number, y: number} the target, seen from the arm's own base, now
---@param ticks number how far ahead to look
---@return number? which tick to arrive on, or nothing if it never comes within reach
---@return {x: number, y: number}? the offset to hold until then
function reach.intercept(arm, drift, offset, ticks)
  local first = reach.earliest(arm, drift, offset, ticks)
  if not first then return nil end
  -- The margin, if there is a tick to spare for it. A thing only clipped by the corner of
  -- the reach has not got one, and for that one the margin is whatever is left rather than
  -- a whole tick.
  local arrival = first
  local later = first + reach.MARGIN
  if later <= ticks and reach.on_it(arm, drift, offset, later) then arrival = later end
  return arrival,
    { x = offset.x - drift.x * arrival, y = offset.y - drift.y * arrival }
end

---Where a hand gets to in one tick, going out or coming in at its own speed.
---
---The engine's own step, and it does not creep up on its target: whatever is left inside one
---step is covered in that step rather than in the one after. Measured on every tier, a hand
---is at full stretch on the tick the nominal speed says it will still be short.
---@param out number how far out it is now
---@param want number how far out it is going
---@param extension number tiles a tick
---@return number
function reach.stepped(out, want, extension)
  if math.abs(want - out) <= extension then return want end
  return out + (want > out and extension or -extension)
end

---Whether a hand has a turn left to make toward a bearing.
---
---More than one step of it, that is: a turn with less than a step left is finished in that
---step, so a hand within a step of where it is going is a hand that is not turning.
---@param pointing {x: number, y: number} a unit vector, as the hand points now
---@param towards {x: number, y: number} where it is going, of any length
---@param rotation number turns a tick
---@return boolean
function reach.turning(pointing, towards, rotation)
  local length = math.sqrt(towards.x * towards.x + towards.y * towards.y)
  if length < 1e-9 then return false end
  local apart = math.abs((atan2(towards.y, towards.x) - atan2(pointing.y, pointing.x)
    + math.pi) % (2 * math.pi) - math.pi)
  return apart > rotation * 2 * math.pi
end

---Which way a hand points after one tick of turning toward a bearing.
---
---The short way round, at the tier's own rate, with the same last step as above: a turn with
---less than a step left to make is finished in that step.
---@param pointing {x: number, y: number} a unit vector, as the hand points now
---@param towards {x: number, y: number} where it is going, of any length
---@param rotation number turns a tick
---@return {x: number, y: number} a unit vector
function reach.turned(pointing, towards, rotation)
  local length = math.sqrt(towards.x * towards.x + towards.y * towards.y)
  -- No bearing to a spot the hand is standing on, so there is nothing to turn toward and
  -- the hand keeps the bearing it has.
  if length < 1e-9 then return pointing end
  local wanted = atan2(towards.y, towards.x)
  local now = atan2(pointing.y, pointing.x)
  local step = rotation * 2 * math.pi
  -- The short way round, as a signed angle in (-pi, pi].
  local apart = (wanted - now + math.pi) % (2 * math.pi) - math.pi
  if math.abs(apart) <= step then
    return { x = towards.x / length, y = towards.y / length }
  end
  local turned = now + (apart > 0 and step or -step)
  return { x = math.cos(turned), y = math.sin(turned) }
end

---The longest a hand could ever need to get anywhere it can get to, in ticks.
---
---Not the same question as full_swing, and the difference is the whole of why both exist.
---full_swing is how far ahead an arm is willing to look before it sets off: one flight, from
---where a fresh hand is born out to full stretch. This is how long a reach already under way
---is allowed to take, which is longer, because a hand part way through one can be anywhere:
---a hand back at its own base reaching the full five tiles wants fifty ticks against a
---swing's forty three, and it may have half a turn to make as well.
---
---As well, not on top. The two are one swing and not two: extension and rotation are speeds
---the engine runs at once and neither waits on the other, so what a journey costs is the
---greater of them and never their sum. This added them for a long while, which made the
---horizon on the fourth tier a hundred and twenty three ticks where the worst journey it can
---ever be asked for is seventy three -- a hand at its own base with half a turn to make,
---fifty ticks of stretch inside seventy three of turn.
---
---The same law reach.on_it is built on, and measured on the same hand. See
---test/ft/swinging.lua, which times every bearing on three tiers against max(stretch, turn)
---and finds the engine on the spot on floor of it, never later.
---
---Measured the hard way to begin with: with a swing's worth as the limit for both, an arm
---coming home and offered something on the far side gave the reach up and took it again on
---every tick, and the ghost took 153 ticks to build against 46 for the one before it.
---@param arm {range: number, extension: number, rotation: number?}
---@return number ticks
function reach.longest(arm)
  return math.max(arm.range / arm.extension, reach.any_way(arm))
end

---The cone an arm can meet, worked out once so that a spot can be tested against it with
---nothing but arithmetic.
---
---reach.meets answers the same question exactly and costs a quadratic solve to do it, which
---is too much to spend on a candidate that is only going to be thrown away. Measured over a
---packed field behind a train, sieving with meets costs more than not sieving at all, while
---sieving with this is three times better than neither.
---
---What it draws is the straight-sided hull of the discs the hand sweeps: a dot product along
---the way its owner is going, a cross product across it, and a compare against a half width
---that flares as the hand grows and stops at the reach.
---
---A superset, never a trim. The flare is the external tangent to the discs at each end,
---which stands off the axis by r / cos a rather than r, and the radius is taken at the spot
---rather than interpolated end to end -- the hand stops growing the moment it is at full
---stretch, and a straight line between the ends runs under the real thing in the middle.
---Measured before that was fixed: two real spots of a hundred and fourteen thrown away.
---
---The tangent is only a bound while there is a tangent to draw. Two discs have an external
---tangent only where neither swallows the other, and the hand swallows its own first disc
---whenever it grows at least as fast as its owner walks: the far disc then holds every disc
---before it, and the hull is that disc sliding rather than a wedge opening. Drawing the
---wedge anyway was measured throwing away work that is really in reach -- eighteen spots of
---three thousand on a hand creeping at a twentieth of a tile a tick -- and the amount
---thrown away grows as the first disc shrinks, so a hand born at its own base feels it
---where a hand born seven tenths out did not. That case gets a capsule instead, which is
---exact rather than merely a superset.
---@param arm {range: number, extension: number, out: number?}
---@param drift {x: number, y: number} how far its owner went last tick
---@param ticks number how far ahead to look
---@return table
function reach.cone(arm, drift, ticks)
  local out = arm.out or reach.BORN
  local speed = math.sqrt(drift.x * drift.x + drift.y * drift.y)
  local length = speed * ticks
  if length <= 1e-9 then
    return { still = true,
             radius = math.min(arm.range, out + arm.extension * (ticks + 1)) }
  end
  if arm.extension >= speed then
    -- Every disc lies inside the one the hand is at when it reaches full stretch: that
    -- disc's centre has moved speed * k while its radius has grown extension * k, and the
    -- one is no less than the other. So what the hand sweeps is that disc from the tick it
    -- stops growing to the end of the horizon, which is a capsule -- and before it stops
    -- growing, the disc at the moment it does holds all of it.
    local full = (arm.range - out) / arm.extension - 1
    if full < 0 then full = 0 elseif full > ticks then full = ticks end
    return { capsule = true,
             fromx = drift.x * full, fromy = drift.y * full,
             tox = drift.x * ticks, toy = drift.y * ticks,
             radius = math.min(arm.range, out + arm.extension * (full + 1)) }
  end
  local grow = arm.extension / speed
  local sina = math.min(grow, 0.999)
  -- How far behind its own base the hand can still touch, which is not simply the first
  -- disc's radius. The disc grows while its owner carries it forward, so where the hand
  -- reaches furthest back is wherever growing has most outrun walking: at the start if the
  -- walk is the faster, and at full stretch if the hand is. Measured before this was worked
  -- out properly, a hand drifting at a twentieth of a tile a tick lost forty three of three
  -- hundred and nineteen spots off its own back doorstep.
  local capped = (arm.range - out) / arm.extension - 1
  if capped < 0 then capped = 0 elseif capped > ticks then capped = ticks end
  local behind = math.max(out + arm.extension,
    math.min(arm.range, out + arm.extension * (capped + 1)) - speed * capped)
  return {
    dirx = drift.x / speed, diry = drift.y / speed,
    length = length, behind = behind, base = out + arm.extension, grow = grow,
    cosa = math.sqrt(math.max(1e-6, 1 - sina * sina)), range = arm.range,
  }
end

---Whether a spot is inside a cone reach.cone worked out.
---@param cone table
---@param offset {x: number, y: number} the spot, seen from the arm's own base
---@return boolean
function reach.in_cone(cone, offset)
  if cone.still then
    return offset.x * offset.x + offset.y * offset.y <= cone.radius * cone.radius
  end
  if cone.capsule then
    -- How far the spot is off the segment the disc's centre slides along, squared so that
    -- nothing here needs a root.
    local dx, dy = cone.tox - cone.fromx, cone.toy - cone.fromy
    local px, py = offset.x - cone.fromx, offset.y - cone.fromy
    local span = dx * dx + dy * dy
    local at = span > 0 and (px * dx + py * dy) / span or 0
    if at < 0 then at = 0 elseif at > 1 then at = 1 end
    local ax, ay = px - dx * at, py - dy * at
    -- A hair of slack, because this is a superset and a spot sitting exactly on the rim is
    -- one the quadratic in reach.earliest says is reachable on its very last tick. Without
    -- it, a spot five tiles out from a hand that arrives at five tiles was lost to the last
    -- bit of a double.
    local rim = cone.radius + 1e-6
    return ax * ax + ay * ay <= rim * rim
  end
  local along = offset.x * cone.dirx + offset.y * cone.diry
  if along < -cone.behind or along > cone.length + cone.range then return false end
  local across = offset.x * cone.diry - offset.y * cone.dirx
  if across < 0 then across = -across end
  local held = along
  if held < 0 then held = 0 elseif held > cone.length then held = cone.length end
  local wide = (cone.base + held * cone.grow) / cone.cosa
  if wide > cone.range then wide = cone.range end
  -- The same hair of slack the capsule above gets, for the same reason: a spot sitting
  -- exactly on the envelope is one reach.earliest says is reachable, and which side of the
  -- line a double lands on is not worth losing a ghost over.
  return across <= wide + 1e-6
end

---The circles to search a cone with, laid end to end along it.
---
---One circle round the whole cone is wasteful when the cone is long and thin, which is what
---a cone becomes as its owner speeds up: a car covers 23 tiles while a hand stretches five,
---so its cone is a ten degree needle and the circle round it is mostly the ground either
---side. Cut the flight into pieces and draw a circle round each, and the chain follows the
---needle instead of boxing it in.
---
---Each piece is the smallest circle holding the two discs at its ends, which is what makes
---the chain cover the cone exactly rather than nearly: the cone between two moments is the
---hull of the discs at those moments, and a circle round both holds all of it. Consecutive
---circles overlap, so a thing can come back twice, and that is cheaper to live with than to
---sift out -- see test/ft/intercept.lua, where the engine is measured charging far less to
---find something than Lua charges to look at it.
---
---More pieces is not better. Every circle has the local width of the cone as a floor, so
---past a handful the chain is paying for that floor over and over: measured on a car's cone,
---one circle sweeps 649 tiles, four sweeps 430, and eight is back up to 500. On a walking
---character, where the cone is stubby, one is always best.
---@param arm {range: number, extension: number, out: number?}
---@param drift {x: number, y: number}
---@param ticks number how far ahead to look
---@param pieces integer how many circles to lay
---@return {at: {x: number, y: number}, radius: number}[] offsets from the arm's own base
function reach.chain(arm, drift, ticks, pieces)
  local out = arm.out or reach.BORN
  local made = {}
  for piece = 0, pieces - 1 do
    local from, to = ticks * piece / pieces, ticks * (piece + 1) / pieces
    -- The same tick of grace the rest of this gives a hand, so that what the circles hold
    -- is what reach.meets says is there.
    local near = math.min(arm.range, out + arm.extension * (from + 1))
    local far = math.min(arm.range, out + arm.extension * (to + 1))
    local apart = math.sqrt(drift.x * drift.x + drift.y * drift.y) * (to - from)
    local along, radius
    if apart + near <= far then
      along, radius = to, far
    elseif apart + far <= near then
      along, radius = from, near
    else
      radius = (apart + near + far) / 2
      -- how far past the near end the middle sits, in ticks of its owner's walk
      along = from + (radius - near) / (apart / (to - from))
    end
    made[#made + 1] = {
      at = { x = drift.x * along, y = drift.y * along },
      radius = radius,
    }
  end
  return made
end

---How far round the arm has to turn to get from one bearing to another, in whole turns.
---
---Never more than half a turn, because an arm turns whichever way is shorter.
---
---A hand sitting on its own base has no bearing at all, so the answer is nought rather
---than an arbitrary angle: there is nothing to turn away from.
---@param from {x: number, y: number} where the arm reaches from
---@param hand {x: number, y: number} where its hand is now
---@param to {x: number, y: number} where it would go
---@return number turns 0 to 0.5
function reach.turn(from, hand, to)
  if reach.distance(from, hand) < 0.1 then return 0 end
  local now = atan2(hand.y - from.y, hand.x - from.x)
  local next_one = atan2(to.y - from.y, to.x - from.x)
  local apart = math.abs(next_one - now) / (2 * math.pi)
  apart = apart % 1
  return math.min(apart, 1 - apart)
end

---Roughly how many ticks the hand would take to get from where it is to a given spot.
---
---An inserter turns and extends at the same time rather than one after the other, so a
---swing takes whichever of the two is slower rather than the sum. That is the whole point
---of measuring it this way: a near thing off to one side costs the turn and gets its
---extension for free, while a far thing straight ahead costs only the extension. Sorting
---by distance alone cannot tell those apart, and on the later tiers, whose turn was slowed
---to stay in proportion with a long reach, the difference is most of the journey.
---
---Rough on purpose. It is used to put targets in order, not to predict anything, and the
---engine's own easing at either end of a swing is not modelled.
---@param tier table
---@param from {x: number, y: number} where the arm reaches from
---@param hand {x: number, y: number} where its hand is now
---@param to {x: number, y: number} where it would go
---@return number ticks
function reach.swing_ticks(tier, from, hand, to)
  local out = math.abs(reach.distance(from, to) - reach.distance(from, hand))
  local turning = reach.turn(from, hand, to)
  return math.max(out / tier.extension, turning / tier.rotation)
end

return reach
