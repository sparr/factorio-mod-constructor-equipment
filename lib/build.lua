--- The decisions behind a build, with no game in them.
---
--- There is not much here, because most of what this mod does is ask the game questions:
--- what ghosts are nearby, what is in the grid, what is in the inventory. These two are
--- the parts that are arithmetic rather than enquiry, and they are the parts worth
--- pinning down a case at a time.
local build = {}

---Whether enough ticks have gone by since this player last built something.
---
---A player who has never built has no last tick, and is due immediately.
---@param tick number
---@param last number?
---@param interval number
---@return boolean
function build.due(tick, last, interval)
  return last == nil or tick >= last + interval
end

---Which item to spend on a ghost, and how many, out of the ones that could place it.
---
---The first one the character is carrying enough of. Enough matters: a curved rail takes
---three rails and a half diagonal takes two, and the mod used to build either for anyone
---holding a single rail and take only that one off them.
---@param items_to_place {name: string, count: number?}[]? as the prototype gives them
---@param carried fun(name: string): number how many of that item the character holds
---@return string? item the item to spend, if any
---@return integer? count how many of it the ghost takes
function build.placing_item(items_to_place, carried)
  for _, entry in pairs(items_to_place or {}) do
    local needed = entry.count or 1
    if carried(entry.name) >= needed then
      return entry.name, needed
    end
  end
  return nil
end

return build
