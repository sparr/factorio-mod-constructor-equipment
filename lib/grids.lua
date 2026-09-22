--- Which equipment categories an arm has to carry to be allowed on the vehicles it knows.
---
--- The equipment sits in "armor", which is what every grid the base game puts on a vehicle
--- accepts. An overhaul is free to re-grid those vehicles into categories of its own, and
--- one that does takes the arms off every vehicle in the game without meaning anything by it.
--- Krastorio 2 is the worked case: it gives its vehicles kr-vehicle and two narrower
--- categories, carries the old grid's categories across except "armor", and opts its own
--- equipment back in by declaring both.
---
--- So the arm follows, by looking at what the vehicles it already knew about will take now.
--- Nothing here reaches for data.raw: it is handed the grids, so that the cases a game does
--- not contain -- a vehicle with no grid, an overhaul whose vehicles share no category at
--- all -- can be written down and checked without one.
local grids = {}

---The fewest categories that get an arm onto every one of these grids.
---
---A cover rather than a copy, and the difference is the whole of why this is not two lines.
---Copying every category off every vehicle would put an arm into any grid that shares one of
---them, including a grid an author made narrow on purpose -- K2's kr-vehicle-roboport exists
---to keep everything but a roboport out of a wagon. Copying only one would be picking at
---random, and picking wrong means a vehicle the arm can no longer ride.
---
---Taking the category that covers the most grids and repeating gets both: every grid handed
---in ends up accepting the arm, and no category is taken that was not needed to manage it.
---On Krastorio 2 that is exactly { "kr-vehicle" } -- the one its author made for equipment
---that goes on vehicles generally -- and the two narrow ones are left alone.
---
---Ties are broken by name so that two games given the same grids make the same choice, which
---the data stage has to be able to promise.
---@param wanted string[][] the categories each known vehicle's grid accepts, one list a
---  vehicle. A vehicle with no grid is simply not in here.
---@param have table<string, boolean> what the equipment already carries
---@return string[] what to add, in the order it was chosen
function grids.cover(wanted, have)
  have = have or {}
  -- Only the grids that would turn the arm away. In a game nobody has overhauled every one
  -- of these accepts "armor" already, so this is empty and nothing at all is added.
  local left = {}
  for _, categories in ipairs(wanted) do
    local already = false
    for _, name in ipairs(categories) do
      if have[name] then already = true end
    end
    if not already and #categories > 0 then left[#left + 1] = categories end
  end

  local taken = {}
  while #left > 0 do
    local counted = {}
    for _, categories in ipairs(left) do
      -- A grid naming the same category twice must not count for two.
      local seen = {}
      for _, name in ipairs(categories) do
        if not seen[name] then
          seen[name] = true
          counted[name] = (counted[name] or 0) + 1
        end
      end
    end
    local best, best_count
    for name, count in pairs(counted) do
      if not best_count or count > best_count or (count == best_count and name < best) then
        best, best_count = name, count
      end
    end
    -- Nothing to choose from: every grid still here is empty, which cannot happen given the
    -- guard above, but a loop that might not end does not belong in a data stage.
    if not best then break end
    taken[#taken + 1] = best
    local rest = {}
    for _, categories in ipairs(left) do
      local covered = false
      for _, name in ipairs(categories) do
        if name == best then covered = true end
      end
      if not covered then rest[#rest + 1] = categories end
    end
    left = rest
  end
  return taken
end

return grids
