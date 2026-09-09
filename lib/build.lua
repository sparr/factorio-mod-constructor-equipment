--- The decisions behind a build, with no game in them.
---
--- There is not much here, because most of what this mod does is ask the game questions:
--- what ghosts are nearby, what is in the grid, what is in the inventory. This is the one
--- part that is arithmetic rather than enquiry, and it is worth pinning down a case at a
--- time.
---
--- It had a second function, for whether a build was due yet. There is no clock any more:
--- an arm sets off when its claw is home and something is in reach, so how often it builds
--- is how fast it swings.
local build = {}

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
