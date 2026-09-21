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
  -- go out and come back. Extension is the base game's own figure for the inserter each
  -- tier borrows, which means it does not rise at every tier: the fast and bulk inserters
  -- share a hand, so the fourth tier extends at the third's speed and buys a tile of reach
  -- instead.
  it("extends at the speed of the inserter it borrows", function()
    local wanted = { 0.035, 0.05, 0.1, 0.1 }  -- inserter, long-handed, fast, bulk
    for level, speed in ipairs(wanted) do
      assert.are.equal(speed, tiers.list[level].extension, "tier " .. level .. " extension")
    end
  end)

  -- Rotation is not the base game's figure at any tier. For the last two, those numbers
  -- are tuned against an inserter that reaches one tile, and on a four or five tile arm
  -- they make the turn look instantaneous against an extension that crawls. Dividing by
  -- how much further the tier reaches puts the two halves of a swing back in the base
  -- game's proportion, a shade longer turning round than reaching out. Then every tier is
  -- taken to 0.85 of what that leaves, because an arm at the full figure whips its claw
  -- round. lib.tiers says how far that could go and what stops it going further.
  it("turns at a speed its own reach can keep up with", function()
    local wanted = { 0.0119, 0.017, 0.0085, 0.0068 }
    for level, speed in ipairs(wanted) do
      assert.are.equal(speed, tiers.list[level].rotation, "tier " .. level .. " rotation")
    end
  end)

  -- A hand at full stretch travels the whole circumference in one rotation, so a turn
  -- moves it rotation * 2 * pi * range in a tick. That used to be a tile and a quarter for
  -- the fourth tier, which is four times the width of the window the mod watches for an
  -- arrival in: the hand stepped straight over it, the arrival went unnoticed, and the
  -- engine finished the swing itself by dropping a real item where the ghost stood.
  -- control.lua widens its window to suit, so this is not what makes it correct, but a
  -- tier whose hand moves a tile a tick is a tier worth looking at again.
  it("never whips its hand round faster than half a tile a tick", function()
    for _, tier in ipairs(tiers.list) do
      local turning = tier.rotation * 2 * math.pi * tier.range
      assert.is_true(turning < 0.5,
        ("tier %d moves its hand %.2f tiles a tick while turning"):format(tier.level,
          turning))
    end
  end)

  it("never extends slower as the tiers go up", function()
    for level = 2, #tiers.list do
      assert.is_true(tiers.list[level].extension >= tiers.list[level - 1].extension,
        "tier " .. level .. " extends slower than the tier below")
    end
  end)

  -- Reach and extension are the plain inserter's own. Rotation is not: it is that
  -- inserter's 0.014 taken to 0.85, the same as every tier is.
  it("starts where the plain inserter does", function()
    assert.are.equal(2, tiers.list[1].range)
    assert.are.equal(0.035, tiers.list[1].extension)
    assert.are.equal(0.0119, tiers.list[1].rotation)
  end)

  -- What the base game charges that same inserter, unscaled. Four times these was tried and
  -- taken out again: an arm's buffer is sized from this, so a fourth tier arm spent thirty
  -- nine ticks filling it before it would set off, against four for the tier below.
  --
  -- A discount used to be worked out here from how much of a bulk inserter's load the last
  -- tier carried; it rested on a bulk inserter carrying a fixed twelve, which it does not.
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
      assert.are.equal(tier.reach_energy * tiers.DEPARTURE, tier.departure)
      assert.is_true(tier.departure > 2 * 2 * tier.range * tier.movement * 0.9,
        "tier " .. tier.level .. " sets off on less than two reaches")
    end
  end)

  -- The headroom the standing drain lives in. Setting off on exactly what a piece can hold
  -- means setting off on a buffer that is exactly full, and a buffer something is drawing
  -- from never is: an arm out on its owner's back pulls its inserter's drain whether it is
  -- working or not, and an armour topping that up sat perpetually a hair under the mark.
  it("holds more than it needs in hand to set off", function()
    for _, tier in ipairs(tiers.list) do
      assert.is_true(tier.departure < tier.reserve,
        "tier " .. tier.level .. " can only set off on a completely full buffer")
      assert.is_true(tier.reserve - tier.departure >= tier.reach_energy * 0.4,
        "tier " .. tier.level .. " leaves too little headroom for the drain to live in")
    end
  end)

  -- Two ghosts half a turn apart were measured at 1.85 reaches, so what an arm sets off on
  -- has to be more than that or it can still stop halfway holding something.
  it("sets off on more than the longest journey measured", function()
    for _, tier in ipairs(tiers.list) do
      assert.is_true(tier.departure > tier.reach_energy * 1.85,
        "tier " .. tier.level .. " could set off on a journey it cannot finish")
    end
  end)

  it("reserves more with every tier, since every tier costs more to swing", function()
    for level = 2, #tiers.list do
      assert.is_true(tiers.list[level].reserve > tiers.list[level - 1].reserve,
        "tier " .. level .. " reserves no more than the tier below")
    end
  end)

  it("takes the room in an armour it is meant to", function()
    local wanted = { { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 } }
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

  -- A modular armour is five by five and a power armour seven by seven. The first three
  -- tiers fit the small one, whose technology theirs come after. The fourth is two by six
  -- and wants the larger, which is the company it keeps anyway: it is the tier that asks
  -- for logistics 3.
  it("fits every tier in an armour a player could be wearing by then", function()
    for _, tier in ipairs(tiers.list) do
      local side = tier.level < 4 and 5 or 7
      assert.is_true(tier.width <= side and tier.height <= side,
        ("tier %d is %dx%d, which will not go in a %dx%d grid")
          :format(tier.level, tier.width, tier.height, side, side))
    end
  end)

  it("grows a slot taller with every tier and never wider", function()
    for level = 2, #tiers.list do
      assert.are.equal(tiers.list[level - 1].width, tiers.list[level].width,
        "tier " .. level .. " is a different width from the one below")
      assert.are.equal(tiers.list[level - 1].height + 1, tiers.list[level].height,
        "tier " .. level .. " is not one taller than the one below")
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
