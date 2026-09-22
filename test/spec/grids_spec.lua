-- Which categories an arm has to carry to ride the vehicles it knows about. The grids are
-- handed in rather than read off a game, so the cases a game does not contain can be
-- written down here.
local grids = require("lib.grids")

describe("covering the vehicles an arm knows", function()
  local ARMOURED = { "armor" }

  it("adds nothing at all where the arm is already allowed", function()
    assert.are.same({}, grids.cover({ ARMOURED, ARMOURED, ARMOURED }, { armor = true }))
  end)

  it("adds nothing where there are no vehicles to ride", function()
    assert.are.same({}, grids.cover({}, { armor = true }))
  end)

  --- Krastorio 2's own seven, which is what this was written for: three categories, one of
  --- them on every vehicle and two of them narrower.
  it("takes the one category that covers a whole overhaul", function()
    local K2 = {
      { "kr-vehicle", "kr-vehicle-motor", "kr-vehicle-roboport" }, -- car
      { "kr-vehicle", "kr-vehicle-motor", "kr-vehicle-roboport" }, -- tank
      { "kr-vehicle", "kr-vehicle-motor" },                        -- locomotive
      { "kr-vehicle", "kr-vehicle-roboport" },                     -- cargo wagon
      { "kr-vehicle", "kr-vehicle-roboport" },                     -- fluid wagon
      { "kr-vehicle", "kr-vehicle-roboport" },                     -- artillery wagon
      { "kr-vehicle", "kr-vehicle-motor", "kr-vehicle-roboport" }, -- spidertron
    }
    assert.are.same({ "kr-vehicle" }, grids.cover(K2, { armor = true }))
  end)

  it("takes more than one where no single category reaches every vehicle", function()
    local split = {
      { "wheels" }, { "wheels" }, { "rails" }, { "legs" },
    }
    -- wheels covers two, then rails and legs one apiece, chosen by name once tied.
    assert.are.same({ "wheels", "legs", "rails" }, grids.cover(split, { armor = true }))
  end)

  it("leaves the vehicles that already take the arm out of the reckoning", function()
    -- The locomotive is still on "armor", so nothing it names should be picked up.
    local mixed = { { "armor", "trains-only" }, { "wheels" } }
    assert.are.same({ "wheels" }, grids.cover(mixed, { armor = true }))
  end)

  it("breaks a tie by name, so two games choose alike", function()
    assert.are.same({ "aaa" }, grids.cover({ { "zzz", "aaa" } }, {}))
  end)

  it("counts a category named twice in one grid only once", function()
    -- "double" looks like two votes and is one vehicle; "single" covers the other two.
    local odd = { { "double", "double" }, { "single" }, { "single" } }
    assert.are.same({ "single", "double" }, grids.cover(odd, {}))
  end)

  it("skips a vehicle whose grid takes nothing at all", function()
    assert.are.same({ "wheels" }, grids.cover({ {}, { "wheels" } }, {}))
  end)
end)
