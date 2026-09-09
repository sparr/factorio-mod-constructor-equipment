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

return reach
