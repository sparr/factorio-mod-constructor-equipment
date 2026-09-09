--- Working out which technology unlocks a given item.
---
--- Pulled out of the data stage and handed its tables rather than reaching for data.raw
--- itself, because the interesting cases are ones the base game does not contain: a
--- technology that would make the tree loop, two technologies that unlock the same thing,
--- an item nobody can make. Those can be written down here in a few lines each and checked
--- without a game, which is the only practical way to test them at all.
local unlock = {}

---Which recipes produce a given item.
---@param recipes table<string, table> data.raw.recipe, or something shaped like it
---@param item string
---@return table<string, boolean>
function unlock.recipes_for(recipes, item)
  local found = {}
  for name, recipe in pairs(recipes or {}) do
    for _, result in pairs(recipe.results or {}) do
      if result.name == item then found[name] = true end
    end
  end
  return found
end

---Whether any of these recipes can be had without researching anything.
---@param recipes table<string, table>
---@param names table<string, boolean>
---@return boolean
function unlock.free_from_the_start(recipes, names)
  for name in pairs(names) do
    local recipe = recipes[name]
    if recipe and recipe.enabled ~= false then return true end
  end
  return false
end

---Every technology that has to be researched before this one, itself included.
---
---Guards against a tree that already loops, which would otherwise recurse for ever.
---@param technologies table<string, table>
---@param name string
---@param seen table<string, boolean>?
---@return table<string, boolean>
function unlock.closure(technologies, name, seen)
  seen = seen or {}
  if seen[name] then return seen end
  local technology = technologies[name]
  if not technology then return seen end
  seen[name] = true
  for _, prerequisite in pairs(technology.prerequisites or {}) do
    unlock.closure(technologies, prerequisite, seen)
  end
  return seen
end

---How many technologies that is.
---@param set table<string, boolean>
---@return integer
function unlock.count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

---Every technology unlocking one of these recipes, in a settled order.
---
---Sorted because pairs() does not promise an order and this decides a prototype: an answer
---that varied from one load to the next would be a desync rather than an untidiness.
---@param technologies table<string, table>
---@param recipes table<string, boolean>
---@return string[]
function unlock.candidates(technologies, recipes)
  local found = {}
  for name, technology in pairs(technologies or {}) do
    for _, effect in pairs(technology.effects or {}) do
      if effect.type == "unlock-recipe" and recipes[effect.recipe] then
        table.insert(found, name)
        break
      end
    end
  end
  table.sort(found)
  return found
end

---Which technology to wait for before an item can be built out of.
---
---The shallowest of the ones that would do: the one needing the fewest other technologies
---researched first, so that waiting for an item never drags anything further down the tree
---than it has to go. Ties go to whichever sorts first, which is arbitrary but the same
---every load.
---
---Nothing is returned when the item can already be made without research, or when nothing
---makes it at all, or when the only things that would do are themselves waiting on the
---asker. "Either of these" is not something a prerequisite can say, so one of them has to
---be picked whatever happens.
---@param recipes table<string, table> data.raw.recipe, or something shaped like it
---@param technologies table<string, table> data.raw.technology, likewise
---@param item string
---@param mine table<string, boolean>? technologies that must never be waited for
---@return string?
function unlock.gate(recipes, technologies, item, mine)
  local making = unlock.recipes_for(recipes, item)
  if next(making) == nil then return nil end
  if unlock.free_from_the_start(recipes, making) then return nil end

  local best, cheapest
  for _, name in ipairs(unlock.candidates(technologies, making)) do
    local needs = unlock.closure(technologies, name)
    local circular = false
    for ours in pairs(mine or {}) do
      if needs[ours] then circular = true break end
    end
    if not circular then
      local cost = unlock.count(needs)
      if not cheapest or cost < cheapest then best, cheapest = name, cost end
    end
  end
  return best
end

return unlock
