--- Putting charge back into an equipment grid.
---
--- Pulled out and handed a plain list rather than reaching for the grid itself, because
--- the case worth checking is one the game rarely produces: the armour keeps every buffer
--- topped up, so a battery is almost always the only thing with room, and the order only
--- shows itself when something else has room too. That is two lines to write down here and
--- most of an afternoon to arrange in a running game.
local power = {}

---Put charge into these, batteries first, and say how much would not fit.
---
---A battery is what is there to hold charge. Filling a shield or somebody else's equipment
---out of ours while a battery has space would be putting it in the wrong pocket.
---@param pieces table[] anything with energy, max_energy and type
---@param amount number
---@return number left over
function power.spill(pieces, amount)
  for _, batteries_first in ipairs{ true, false } do
    for _, piece in pairs(pieces) do
      if amount <= 0 then return 0 end
      if (piece.type == "battery-equipment") == batteries_first then
        local room = piece.max_energy - piece.energy
        local give = math.min(room, amount)
        if give > 0 then
          piece.energy = piece.energy + give
          amount = amount - give
        end
      end
    end
  end
  return amount
end

return power
