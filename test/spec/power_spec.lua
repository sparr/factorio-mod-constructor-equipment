local power = require("lib.power")

local function battery(energy, max)
  return { type = "battery-equipment", energy = energy, max_energy = max }
end

local function other(energy, max)
  return { type = "energy-shield-equipment", energy = energy, max_energy = max }
end

describe("putting charge back into a grid", function()
  it("fills a battery that has room", function()
    local cell = battery(100, 1000)
    assert.are.equal(0, power.spill({ cell }, 400))
    assert.are.equal(500, cell.energy)
  end)

  it("fills the battery before anything else", function()
    local cell, shield = battery(0, 1000), other(0, 1000)
    power.spill({ shield, cell }, 600)
    assert.are.equal(600, cell.energy, "the battery should have taken all of it")
    assert.are.equal(0, shield.energy, "nothing should have gone to the shield")
  end)

  it("spills into other things once the batteries are full", function()
    local cell, shield = battery(900, 1000), other(0, 1000)
    power.spill({ shield, cell }, 300)
    assert.are.equal(1000, cell.energy, "the battery should have been filled first")
    assert.are.equal(200, shield.energy, "the rest should have gone to the shield")
  end)

  it("fills several batteries before anything else", function()
    local one, two, shield = battery(0, 100), battery(0, 100), other(0, 1000)
    power.spill({ shield, one, two }, 250)
    assert.are.equal(100, one.energy)
    assert.are.equal(100, two.energy)
    assert.are.equal(50, shield.energy)
  end)

  it("says how much would not fit anywhere", function()
    local cell = battery(900, 1000)
    assert.are.equal(500, power.spill({ cell }, 600))
    assert.are.equal(1000, cell.energy)
  end)

  it("does nothing with nothing to give", function()
    local cell = battery(0, 1000)
    assert.are.equal(0, power.spill({ cell }, 0))
    assert.are.equal(0, cell.energy)
  end)

  it("copes with an empty grid", function()
    assert.are.equal(50, power.spill({}, 50))
  end)

  it("never overfills", function()
    local cell = battery(0, 10)
    power.spill({ cell }, 999)
    assert.are.equal(10, cell.energy)
  end)
end)
