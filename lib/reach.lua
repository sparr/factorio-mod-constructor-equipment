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
---half a tile short shortens every swing, and on the slow tiers that opened gaps in the
---character's slowdown that a player would feel as their speed stuttering.
---@param tier table
---@param threshold number
---@param moved number? how far this hand went last tick
---@return number
function reach.within(tier, threshold, moved)
  return math.max(threshold, reach.step(tier), (moved or 0) * reach.OVERSHOOT)
end

--- Where a freshly built hand sits, in tiles out from the arm's own base along the way it
--- was built facing.
---
--- Measured on every tier on 2.1.19 and the same on all four, which is what makes it a
--- constant here rather than something read off a prototype: the first tier's hand is born
--- 0.6939 out and so is the fourth's, though one of them reaches two tiles and the other
--- five. See test/ft/intercept.lua, which reads it on the tick the arm is built, before the
--- engine has moved it.
---
--- It matters because it is a head start. A five tile arm travels 4.31 tiles rather than
--- five, which is seven ticks off a swing and a tile off how far its owner walks while the
--- hand is out.
reach.BORN = 0.6939

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

---Whether an arm could still put something down at a given spot, at any moment between now
---and a swing's time from now.
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
  local out = arm.out or reach.BORN
  local e, range = arm.extension, arm.range
  local wx, wy = offset.x, offset.y
  local speed2 = drift.x * drift.x + drift.y * drift.y

  -- While the hand is still growing. The spot is met at tick k when the distance to it has
  -- come down to what the hand has reached, and squaring both sides of that leaves a
  -- quadratic whose dip below nought is the whole answer.
  local growing = math.min(ticks, (range - out) / e)
  if growing >= 0 then
    local a = speed2 - e * e
    local b = -2 * (wx * drift.x + wy * drift.y + out * e)
    local c = wx * wx + wy * wy - out * out
    local function dips(k) return a * k * k + b * k + c end
    local least = math.min(dips(0), dips(growing))
    -- Only where the quadratic opens upward is its turning point a minimum; where it opens
    -- downward or is a straight line, the least over a stretch is at one of the ends.
    if a > 0 then
      local turn = -b / (2 * a)
      if turn > 0 and turn < growing then least = math.min(least, dips(turn)) end
    end
    if least <= 0 then return true end
  end

  -- And once it is at full stretch, when the circle no longer grows and only slides. How
  -- near the spot comes to the line its owner walks over what is left of the horizon.
  --
  -- Which is also the whole of the answer for somebody standing still: the line is a point,
  -- and the question comes back to whether the spot is inside the reach. Written this way
  -- round rather than as a case of its own so that the reach is compared against itself
  -- rather than against a stretch worked out by dividing and multiplying it, which lands a
  -- hair either side of it and made a ghost at exactly the reach a coin toss.
  local along = growing
  if speed2 > 0 then
    along = (wx * drift.x + wy * drift.y) / speed2
    if along < growing then along = growing elseif along > ticks then along = ticks end
  end
  local cap = math.min(range, out + e * along)
  local dx, dy = wx - drift.x * along, wy - drift.y * along
  return dx * dx + dy * dy <= cap * cap
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
    local near = math.min(arm.range, out + arm.extension * from)
    local far = math.min(arm.range, out + arm.extension * to)
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
