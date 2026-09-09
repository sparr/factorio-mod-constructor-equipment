local tiers = require("lib.tiers")

describe("the tiers", function()
  it("has four of them", function()
    assert.are.equal(4, #tiers.list)
  end)

  it("keeps the first one's name, so old saves still find it", function()
    assert.are.equal("constructor-equipment", tiers.list[1].name)
    assert.are.equal("constructor-equipment-inserter", tiers.list[1].inserter)
  end)

  it("names the rest after their level", function()
    assert.are.equal("constructor-equipment-2", tiers.list[2].name)
    assert.are.equal("constructor-equipment-3", tiers.list[3].name)
    assert.are.equal("constructor-equipment-4", tiers.list[4].name)
  end)

  it("gives each of them their own arm entity", function()
    local seen = {}
    for _, tier in ipairs(tiers.list) do
      assert.is_nil(seen[tier.inserter], "two tiers share " .. tier.inserter)
      seen[tier.inserter] = true
    end
  end)

  it("knows which tier is below it, for the technology tree", function()
    assert.is_nil(tiers.list[1].below, "the first tier has something below it")
    for level = 2, #tiers.list do
      assert.are.equal(tiers.list[level - 1].name, tiers.list[level].below,
        "tier " .. level .. " does not know the tier below it")
    end
  end)

  it("reaches further with every tier", function()
    for level = 2, #tiers.list do
      assert.is_true(tiers.list[level].range > tiers.list[level - 1].range,
        "tier " .. level .. " does not reach further than the one below it")
    end
  end)

  it("reaches a whole number of tiles, which is what a tooltip has to say", function()
    for _, tier in ipairs(tiers.list) do
      assert.are.equal(math.floor(tier.range), tier.range,
        ("tier %d reaches %.2f tiles"):format(tier.level, tier.range))
    end
  end)

  -- Nothing caps how often an arm sets off, so the rate is however long the claw takes to
  -- go out and come back. The hand speeds are the base game's own, which means they do not
  -- rise at every tier: the fast and bulk inserters share a hand, so the fourth tier swings
  -- at the third's speed and buys a tile of reach instead.
  it("swings at the speed of the inserter it borrows", function()
    local wanted = {
      { 0.035, 0.014 },  -- inserter
      { 0.05,  0.02 },   -- long-handed
      { 0.1,   0.04 },   -- fast
      { 0.1,   0.04 },   -- bulk
    }
    for level, speeds in ipairs(wanted) do
      assert.are.equal(speeds[1], tiers.list[level].extension, "tier " .. level .. " extension")
      assert.are.equal(speeds[2], tiers.list[level].rotation, "tier " .. level .. " rotation")
    end
  end)

  it("never swings slower as the tiers go up", function()
    for level = 2, #tiers.list do
      assert.is_true(tiers.list[level].extension >= tiers.list[level - 1].extension,
        "tier " .. level .. " extends slower than the tier below")
      assert.is_true(tiers.list[level].rotation >= tiers.list[level - 1].rotation,
        "tier " .. level .. " turns slower than the tier below")
    end
  end)

  it("starts where the plain inserter does", function()
    assert.are.equal(2, tiers.list[1].range)
    assert.are.equal(0.035, tiers.list[1].extension)
    assert.are.equal(0.014, tiers.list[1].rotation)
  end)

  -- What the base game charges that same inserter, unscaled. A discount used to be worked
  -- out here from how much of a bulk inserter's load the last tier carried; it rested on a
  -- bulk inserter carrying a fixed twelve, which it does not.
  it("charges what the inserter it borrows charges", function()
    local wanted = { 5000, 5000, 7000, 20000 }
    local drains = { "0.4kW", "0.4kW", "0.5kW", "1kW" }
    for level, movement in ipairs(wanted) do
      assert.are.equal(movement, tiers.list[level].movement, "tier " .. level .. " movement")
      assert.are.equal(drains[level], tiers.list[level].drain, "tier " .. level .. " drain")
    end
  end)

  it("gives only the last tier a bulk claw", function()
    local wanted = { false, false, false, true }
    for level, bulk in ipairs(wanted) do
      assert.are.equal(bulk, tiers.list[level].bulk, "tier " .. level)
    end
  end)

  -- an arm that set off on less would stop halfway, holding something, over a ghost
  it("wants a couple of its own reaches in hand before setting off", function()
    for _, tier in ipairs(tiers.list) do
      assert.are.equal(tier.reach_energy * tiers.RESERVE, tier.reserve)
      assert.is_true(tier.reserve > 2 * 2 * tier.range * tier.movement * 0.9,
        "tier " .. tier.level .. " reserves less than two reaches")
    end
  end)

  it("reserves more with every tier, since every tier costs more to swing", function()
    for level = 2, #tiers.list do
      assert.is_true(tiers.list[level].reserve > tiers.list[level - 1].reserve,
        "tier " .. level .. " reserves no more than the tier below")
    end
  end)

  it("takes the room in an armour it is meant to", function()
    local wanted = { { 2, 4 }, { 2, 5 }, { 3, 5 }, { 3, 5 } }
    for level, size in ipairs(wanted) do
      assert.are.equal(size[1], tiers.list[level].width, "tier " .. level .. " width")
      assert.are.equal(size[2], tiers.list[level].height, "tier " .. level .. " height")
    end
  end)

  -- one of the base game's own inserter colours each, so an arm is always a colour the
  -- player has seen before and no two tiers look alike
  it("gives each of them a colour of their own", function()
    local wanted = { "yellow", "red", "blue", "green" }
    local seen = {}
    for level, colour in ipairs(wanted) do
      assert.are.equal(colour, tiers.list[level].colour)
      assert.is_nil(seen[tiers.list[level].hand], "two tiers borrow the same arm")
      seen[tiers.list[level].hand] = true
    end
  end)

  it("knows every one of its own equipment by name", function()
    for _, tier in ipairs(tiers.list) do
      assert.are.equal(tier, tiers.of(tier.name))
    end
    assert.is_nil(tiers.of("battery-equipment"))
    assert.is_nil(tiers.of("constructor-equipment-9"))
  end)

  it("fits every tier in a modular armour", function()
    -- a small equipment grid is five by five, and the technology comes after modular armour
    for _, tier in ipairs(tiers.list) do
      assert.is_true(tier.width <= 5 and tier.height <= 5,
        ("tier %d is %dx%d, which will not go in a modular armour")
          :format(tier.level, tier.width, tier.height))
    end
  end)
end)

--- Which science a tier asks for should match where its prerequisites actually sit, not
--- just be one more pack than the tier below.
describe("what each tier costs to research", function()
  local tiers = require("lib.tiers")

  it("asks for the packs it is meant to", function()
    local wanted = {
      { "automation" },
      { "automation", "logistic" },
      -- Speed modules and faster belts are both red and green, and they are what gate this
      -- tier. Chemical science is a different era: it needs sulfur processing, and
      -- production science is later still, needing chemical science to research at all.
      { "automation", "logistic" },
      -- logistics 3 needs production science, and production science needs chemical to
      -- research at all, so anyone here has blue whether this asks for it or not
      { "automation", "logistic", "production" },
    }
    for level, packs in ipairs(wanted) do
      assert.are.same(packs, tiers.list[level].research.packs,
        "tier " .. level .. " asks for the wrong science")
    end
  end)

  it("never gets cheaper as the tiers go up", function()
    for level = 2, #tiers.list do
      assert.is_true(tiers.list[level].research.count > tiers.list[level - 1].research.count,
        "tier " .. level .. " costs no more to research than the tier below")
    end
  end)

  it("builds each tier out of the one below it", function()
    for level = 2, #tiers.list do
      local uses_below = false
      for _, ingredient in ipairs(tiers.list[level].ingredients) do
        if ingredient.name == tiers.list[level].below then uses_below = true end
      end
      assert.is_true(uses_below,
        "tier " .. level .. " is not built out of the tier below it")
    end
  end)
end)
