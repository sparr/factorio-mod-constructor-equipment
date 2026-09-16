--- The chain from research to a working arm: the technology unlocks the recipe, the recipe
--- makes the item, and the item becomes the equipment.
---
--- Every other fixture puts equipment straight into a grid from script, which works
--- whatever the item prototype says. A player has only the item, and the item has to name
--- the equipment it turns into. Nothing tested that, and the item turned out to have been
--- naming it with a property that does not exist, which Factorio quietly ignores: the
--- recipe worked, the item was craftable, and it could not be put into an armour.
local tiers = require("lib.tiers")


for _, tier in ipairs(tiers.list) do
describe("the way to a working arm at tier " .. tier.level, function()
  local NAME = tier.name
  it("is unlocked by researching the technology", function()
    local technology = prototypes.technology[NAME]
    assert.is_not_nil(technology, "there is no technology")
    local unlocks = false
    for _, effect in pairs(technology.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe == NAME then unlocks = true end
    end
    assert.is_true(unlocks, "the technology does not unlock the recipe")
  end)

  it("needs the technology, not just the recipe", function()
    local recipe = prototypes.recipe[NAME]
    assert.is_not_nil(recipe, "there is no recipe")
    assert.is_false(recipe.enabled,
      "the recipe is available without researching anything")
  end)

  it("is crafted into the item", function()
    local results = prototypes.recipe[NAME].products
    assert.are.equal(1, #results, "the recipe makes something other than one thing")
    assert.are.equal(NAME, results[1].name)
  end)

  it("puts that item into an armour as the equipment", function()
    local item = prototypes.item[NAME]
    assert.is_not_nil(item, "there is no item")
    assert.is_not_nil(item.place_as_equipment_result,
      "the item does not turn into any equipment, so it cannot be put into an armour")
    assert.are.equal(NAME, item.place_as_equipment_result.name)
  end)

  it("fits in an armour a player could be wearing by then", function()
    -- The first three fit a modular armour, which their technologies come after. The
    -- fourth is two by six and a modular grid is five tall, so it wants a power armour --
    -- which is the company it keeps anyway, being the tier that wants logistics 3.
    local shape = prototypes.equipment[NAME].shape
    local wanted = tier.level < 4 and "modular-armor" or "power-armor"
    local grid = prototypes.item[wanted].equipment_grid
    assert.is_true(shape.width <= grid.width and shape.height <= grid.height,
      ("the equipment is %dx%d and a %s grid is %dx%d")
        :format(shape.width, shape.height, wanted, grid.width, grid.height))
  end)

  it("has an arm of its own to swing", function()
    local arm = prototypes.entity[tier.inserter]
    assert.is_not_nil(arm, "there is no inserter entity for this tier")
    assert.are.equal("inserter", arm.type)
  end)

  -- The first tier is built out of the inserter whose arm it wears; every tier after it is
  -- built out of the tier below, so the arms are upgraded rather than collected.
  it("is made out of the tier below it, or out of an inserter", function()
    local wanted = tier.below or tier.hand
    local uses_it = false
    for _, ingredient in pairs(prototypes.recipe[NAME].ingredients) do
      if ingredient.name == wanted then uses_it = true end
    end
    assert.is_true(uses_it,
      "tier " .. tier.level .. " is not built out of a " .. wanted)
  end)

  it("waits for what it should in the tree", function()
    -- at runtime a technology's prerequisites are keyed by name, with the prototype as
    -- the value, rather than being a list of names as they are in the data stage
    local prerequisites = {}
    for name in pairs(prototypes.technology[NAME].prerequisites or {}) do
      prerequisites[name] = true
    end
    if tier.level == 1 then
      assert.is_true(prerequisites["modular-armor"], "it does not wait for modular armour")
      -- the arm is a yellow inserter's arm, so it should not come first
      assert.is_nil(tier.below, "the first tier has a tier below it")
    else
      assert.is_true(prerequisites[tier.below],
        "it does not wait for the tier below it")
      for _, requirement in ipairs(tier.requires) do
        assert.is_true(prerequisites[requirement],
          "it does not wait for " .. requirement)
      end
    end
  end)
end)
end

--- Every tier waits for whatever unlocks the inserter it is built out of, and data-final-
--- fixes works out which technology that is rather than naming one.
---
--- Worked out again here from the loaded prototypes, by its own traversal, rather than by
--- calling the same code the data stage used or by listing the answers. Listing them tests
--- the base game's tree rather than the mod, and would have to be rewritten by whoever
--- broke this; calling the same code tests nothing at all.
describe("waiting for the inserter each tier is made of", function()
  local tiers = require("lib.tiers")

  ---Every technology that has to be researched before this one, itself included.
  local function closure(name, seen)
    seen = seen or {}
    if seen[name] then return seen end
    local technology = prototypes.technology[name]
    if not technology then return seen end
    seen[name] = true
    for prerequisite in pairs(technology.prerequisites or {}) do
      closure(prerequisite, seen)
    end
    return seen
  end

  local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
  end

  ---Which technologies unlock a recipe producing this item, and whether any recipe for it
  ---needs no research at all.
  local function unlockers(item)
    local recipes, free = {}, false
    for name, recipe in pairs(prototypes.recipe) do
      for _, product in pairs(recipe.products or {}) do
        if product.name == item then
          recipes[name] = true
          if recipe.enabled then free = true end
        end
      end
    end
    local found = {}
    for name, technology in pairs(prototypes.technology) do
      for _, effect in pairs(technology.effects or {}) do
        if effect.type == "unlock-recipe" and recipes[effect.recipe] then
          table.insert(found, name)
          break
        end
      end
    end
    table.sort(found)
    return found, free
  end

  --- This mod's own technologies, which nothing may be made to wait for.
  local mine = {}
  for _, tier in ipairs(tiers.list) do mine[tier.name] = true end

  for _, tier in ipairs(tiers.list) do
    it("tier " .. tier.level .. " waits for something that unlocks a " .. tier.hand,
      function()
        local candidates, free = unlockers(tier.hand)
        if free then return end
        assert.is_true(#candidates > 0,
          "nothing in the tree unlocks a " .. tier.hand .. ", so this proves nothing")

        local prerequisites = {}
        for name in pairs(prototypes.technology[tier.name].prerequisites or {}) do
          prerequisites[name] = true
        end

        local chosen
        for _, name in ipairs(candidates) do
          if prerequisites[name] then chosen = name end
        end
        assert.is_not_nil(chosen,
          ("tier %d waits for none of what unlocks a %s: %s"):format(
            tier.level, tier.hand, table.concat(candidates, ", ")))

        -- and it must be the cheapest of them to reach, so that waiting for an inserter
        -- never drags a tier further down the tree than it has to go
        local cheapest
        for _, name in ipairs(candidates) do
          local needs = closure(name)
          local circular = false
          for ours in pairs(mine) do
            if needs[ours] then circular = true end
          end
          if not circular then
            local cost = count(needs)
            if not cheapest or cost < cheapest then cheapest = cost end
          end
        end
        assert.are.equal(cheapest, count(closure(chosen)),
          ("tier %d waits for %s, which needs %d technologies, where %d would have done")
            :format(tier.level, chosen, count(closure(chosen)), cheapest or -1))

        -- and it must not be waiting for something that waits for us
        local needs = closure(chosen)
        for ours in pairs(mine) do
          assert.is_falsy(needs[ours],
            ("tier %d waits for %s, which waits for %s"):format(tier.level, chosen, ours))
        end
      end)
  end
end)
