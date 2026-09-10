--- How far things are, for deciding what is still worth reaching for.
---
--- The swing itself is the engine's business: the inserter entity knows how to move its
--- own arm, including the elbow, and no amount of arithmetic here would do it as well.
--- What is left is measuring, and that needs no game.
local reach = {}

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

return reach
