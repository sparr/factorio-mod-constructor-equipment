local unlock = require("lib.unlock")

--- A tiny technology tree, written out rather than loaded, so the cases the base game does
--- not contain can be checked at all.
local function tree(technologies)
  return technologies
end

local function recipe(item, enabled)
  return { enabled = enabled, results = { { type = "item", name = item } } }
end

local function unlocks(recipe_name, prerequisites)
  return {
    effects = { { type = "unlock-recipe", recipe = recipe_name } },
    prerequisites = prerequisites,
  }
end

describe("finding which technology unlocks an item", function()
  it("finds the one that does", function()
    local recipes = { widget = recipe("widget", false) }
    local techs = tree{ widgetry = unlocks("widget", {}) }
    assert.are.equal("widgetry", unlock.gate(recipes, techs, "widget"))
  end)

  it("finds it through a recipe named something else", function()
    local recipes = { ["widget-from-scrap"] = recipe("widget", false) }
    local techs = tree{ salvage = unlocks("widget-from-scrap", {}) }
    assert.are.equal("salvage", unlock.gate(recipes, techs, "widget"))
  end)

  it("waits for nothing when the item needs no research", function()
    local recipes = { widget = recipe("widget", true) }
    local techs = tree{ widgetry = unlocks("widget", {}) }
    assert.is_nil(unlock.gate(recipes, techs, "widget"))
  end)

  it("waits for nothing when nothing makes the item", function()
    assert.is_nil(unlock.gate({}, tree{}, "widget"))
  end)

  it("waits for nothing when nothing unlocks the recipe", function()
    local recipes = { widget = recipe("widget", false) }
    assert.is_nil(unlock.gate(recipes, tree{}, "widget"))
  end)
end)

--- The reason for sorting and for measuring depth: with more than one answer, the choice
--- has to be the same every load and it should not drag the asker down the tree.
describe("choosing between technologies that would all do", function()
  it("takes the one needing the fewest others first", function()
    local recipes = {
      widget = recipe("widget", false),
      ["widget-2"] = recipe("widget", false),
    }
    local techs = tree{
      a = { prerequisites = {} },
      b = { prerequisites = { "a" } },
      deep = unlocks("widget-2", { "b" }),
      shallow = unlocks("widget", {}),
    }
    assert.are.equal("shallow", unlock.gate(recipes, techs, "widget"))
  end)

  it("counts the whole chain, not just the one step", function()
    local recipes = {
      one = recipe("widget", false),
      two = recipe("widget", false),
    }
    local techs = tree{
      root = { prerequisites = {} },
      middle = { prerequisites = { "root" } },
      -- one prerequisite each, but one of them sits on a chain of two
      near = unlocks("one", { "root" }),
      far = unlocks("two", { "middle" }),
    }
    assert.are.equal("near", unlock.gate(recipes, techs, "widget"))
  end)

  it("settles ties the same way every time", function()
    local recipes = {
      one = recipe("widget", false),
      two = recipe("widget", false),
    }
    local techs = tree{
      zebra = unlocks("one", {}),
      aardvark = unlocks("two", {}),
    }
    -- both cost the same, so the earlier name wins, whatever order pairs() hands them over
    for _ = 1, 20 do
      assert.are.equal("aardvark", unlock.gate(recipes, techs, "widget"))
    end
  end)
end)

--- A technology that is itself waiting on the asker cannot be waited for: the tree would
--- have no order at all, and Factorio will not load one that does.
describe("technologies that would make the tree loop", function()
  it("is passed over for one that would not", function()
    local recipes = {
      one = recipe("widget", false),
      two = recipe("widget", false),
    }
    local techs = tree{
      ours = { prerequisites = {} },
      circular = unlocks("one", { "ours" }),
      innocent = unlocks("two", { "root" }),
      root = { prerequisites = {} },
    }
    assert.are.equal("innocent",
      unlock.gate(recipes, techs, "widget", { ours = true }))
  end)

  it("is passed over even when it waits on us at a distance", function()
    local recipes = { one = recipe("widget", false), two = recipe("widget", false) }
    local techs = tree{
      ours = { prerequisites = {} },
      between = { prerequisites = { "ours" } },
      circular = unlocks("one", { "between" }),
      innocent = unlocks("two", {}),
    }
    assert.are.equal("innocent",
      unlock.gate(recipes, techs, "widget", { ours = true }))
  end)

  it("leaves nothing to wait for when every answer would loop", function()
    local recipes = { one = recipe("widget", false) }
    local techs = tree{
      ours = { prerequisites = {} },
      circular = unlocks("one", { "ours" }),
    }
    assert.is_nil(unlock.gate(recipes, techs, "widget", { ours = true }))
  end)

  it("would not be chosen even though it is the shallower of the two", function()
    local recipes = { one = recipe("widget", false), two = recipe("widget", false) }
    local techs = tree{
      ours = { prerequisites = {} },
      -- one prerequisite, against the innocent one's chain of three
      circular = unlocks("one", { "ours" }),
      a = { prerequisites = {} },
      b = { prerequisites = { "a" } },
      innocent = unlocks("two", { "b" }),
    }
    assert.are.equal("innocent",
      unlock.gate(recipes, techs, "widget", { ours = true }))
  end)
end)

describe("a tree that already loops", function()
  -- not something Factorio would load, but the search must not hang on one either
  it("does not send the search round for ever", function()
    local recipes = { one = recipe("widget", false) }
    local techs = tree{
      a = unlocks("one", { "b" }),
      b = { prerequisites = { "a" } },
    }
    assert.are.equal("a", unlock.gate(recipes, techs, "widget"))
  end)
end)

--- The order candidates come back in decides which one is picked when several would do,
--- and that decision ends up in a prototype. pairs() promises no order at all, so an
--- unsorted answer could differ between one load and the next, which is a desync rather
--- than an untidiness. Asserted on the list itself: a tie between two is not enough to
--- catch it, because two keys come back the same way every time within one run.
describe("the order candidates are offered in", function()
  it("is always ascending, whatever order the tree is held in", function()
    local recipes, techs = {}, {}
    for _, name in ipairs{ "zebra", "alpha", "mango", "beta", "quince", "cedar" } do
      recipes[name .. "-recipe"] = { enabled = false,
        results = { { type = "item", name = "widget" } } }
      techs[name] = {
        effects = { { type = "unlock-recipe", recipe = name .. "-recipe" } },
        prerequisites = {},
      }
    end
    local making = unlock.recipes_for(recipes, "widget")
    local offered = unlock.candidates(techs, making)
    assert.are.equal(6, #offered, "not every technology was offered")
    for i = 2, #offered do
      assert.is_true(offered[i - 1] < offered[i],
        ("%s came back before %s"):format(offered[i - 1], offered[i]))
    end
    assert.are.same(
      { "alpha", "beta", "cedar", "mango", "quince", "zebra" }, offered)
  end)
end)
