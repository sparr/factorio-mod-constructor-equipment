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
