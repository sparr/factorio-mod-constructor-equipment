--- The four tiers of the equipment, and everything that differs between them.
---
--- This is required from both stages. The data stage builds a set of prototypes out of
--- each entry, and control.lua reads the same numbers back to know how far a given arm may
--- reach and how often it may set off, so there is one place to change a tier rather than
--- two that have to agree.
---
--- What a tier is worth is not written out four times either. The first one is the numbers
--- below and each one after it is a step better, which keeps the progression honest: no
--- tier can quietly end up worse than the one before it, and retuning the lot is one
--- number.
local tiers = {}

--- What the first tier reaches, in tiles. The tiers after it are listed one by one
--- rather than stepped, because a reach is a number a player reads off a tooltip and
--- 4.5 tiles is not a number anybody wants to read.
tiers.RANGE = 2

--- Nothing caps how often an arm may set off. The claw has to come home before it can go
--- out again, so how fast it swings is how often it builds, which is the rate a real
--- inserter works at rather than a rate written down beside it.
---
--- How fast each one swings is that inserter's own figure, along with its prices and its
--- graphics, so an arm behaves like the thing it is made of. That leaves the fourth tier
--- swinging at the third's speed, because the base game gives the fast and bulk inserters
--- the same hand: what the fourth tier buys is a tile of reach, and whatever it is given
--- later.

--- Small enough to be something a person is wearing rather than something bolted to the
--- floor.
tiers.SCALE = 0.2

--- How fast the character walks while the first tier is working, as a fraction of their
--- usual. Each tier takes a smaller share of that penalty, and the last two take none of
--- it at all: a better arm is a lighter one to carry.
tiers.SLOWED = 3/8

--- How many reaches' worth of charge an armour must have before an arm will set off, so
--- that an arm never stops halfway with an item in its hand.
---
--- Three rather than two since the claw started delivering into a box on the ghost. The
--- engine takes the hand all the way onto its target and finishes the swing itself now,
--- where the mod used to call it arrived three tenths of a tile short and cut the swing
--- off there, so a journey costs more than it did: two ghosts half a turn apart were
--- measured at 1.85 reaches where they used to fit inside 1.2. Two reaches banked was
--- enough for the old journey and is marginal for this one.
---
--- Asking for more costs a well powered character nothing, because an equipment buffer
--- refills from charged batteries in a single tick at every tier. What it buys is the
--- badly powered case: an armour that cannot raise three reaches keeps its arm at home
--- rather than sending it out on a journey it cannot finish.
tiers.RESERVE = 3

--- What a base game bulk inserter holds with no capacity research done. The engine gives
--- anything with bulk = true this much and then adds the force's bulk inserter capacity
--- bonus, which the seven technologies take to ten, so a bulk inserter runs from one up to
--- eleven and the last tier is held to the same ceiling.
---
--- Measured, not read. Both the wiki and the base game's own comments in technology.lua
--- say two to twelve: bonus-1 is annotated "result of 3" and bonus-7 "result of 12". A
--- powered bulk inserter moving belts between two chests in 2.1.17 makes seventeen swings
--- in four hundred ticks whatever the research, and carries one, two, three and eleven per
--- swing at nought, one, two and all seven bonuses. Filling its hand from script and
--- reading back what stuck agrees. The annotations look to be left over from 1.1, where
--- the stack inserter this replaced did start at two.
tiers.BULK_BASE = 1

--- The base game's hand sprites are not all the same size, so the size goes with the
--- picture rather than being guessed from it.
local HAND = {
  ["inserter"]             = { base = { 32, 136 }, closed = { 72, 164 },  open = { 72, 164 } },
  ["long-handed-inserter"] = { base = { 32, 136 }, closed = { 72, 164 },  open = { 72, 164 } },
  ["fast-inserter"]        = { base = { 32, 136 }, closed = { 72, 164 },  open = { 72, 164 } },
  ["bulk-inserter"]        = { base = { 32, 136 }, closed = { 100, 164 }, open = { 130, 164 } },
}

--- What actually differs from tier to tier: how far it reaches, whose arm it borrows and
--- so what colour it is, how much room it takes in an armour, and what it is made of.
---
--- The colours are the base game's own inserter tiers rather than tints, so an arm is
--- always a colour a player has seen before. So are the prices: what a tier costs to swing
--- and to sit idle is the price the base game charges for that same inserter.
local DEFINED = {
  {
    reach = 2,
    hand = "inserter", colour = "yellow",
    extension = 0.035, rotation = 0.014,
    width = 1, height = 2, movement = 5000, drain = "0.4kW",
    slows = 1,
    craft = 10,
    ingredients = {
      { type = "item", name = "inserter", amount = 1 },
      { type = "item", name = "electronic-circuit", amount = 1 },
    },
    requires = { "modular-armor" },
    research = { count = 50, time = 15, packs = { "automation" } },
  },
  {
    reach = 3,
    hand = "long-handed-inserter", colour = "red",
    extension = 0.05, rotation = 0.02,
    width = 1, height = 3, movement = 5000, drain = "0.4kW",
    slows = 2/3,
    craft = 15,
    ingredients = {
      { type = "item", name = "constructor-equipment", amount = 1 },
      { type = "item", name = "electronic-circuit", amount = 1 },
      { type = "item", name = "steel-plate", amount = 1 },
    },
    requires = { "logistics-2" },
    research = { count = 100, time = 30, packs = { "automation", "logistic" } },
  },
  {
    reach = 4,
    hand = "fast-inserter", colour = "blue",
    -- Vanilla's rotation, divided by how much further this reaches than the inserter it
    -- borrows. A fast inserter spends a shade longer turning round than reaching its one
    -- tile; keeping its 0.04 on a four tile arm made the turn look instant against a
    -- crawling extension. Dividing by the reach puts the two back in vanilla's proportion.
    extension = 0.1, rotation = 0.01,
    width = 1, height = 4, movement = 7000, drain = "0.5kW",
    slows = 1/3,
    craft = 20,
    ingredients = {
      { type = "item", name = "constructor-equipment-2", amount = 1 },
      { type = "item", name = "advanced-circuit", amount = 1 },
      { type = "item", name = "steel-plate", amount = 1 },
    },
    requires = { "speed-module" },
    -- Red and green, like the tier below. Speed modules descend from advanced circuits and
    -- cost nothing but red and green themselves, so this sits in that band whatever its
    -- number says: chemical science is a different era, and production science is later
    -- still, needing chemical to research at all. What gates this tier is speed modules.
    research = { count = 200, time = 30, packs = { "automation", "logistic" } },
  },
  {
    reach = 5,
    hand = "bulk-inserter", colour = "green",
    -- The same again, over five tiles rather than four. See the tier above.
    extension = 0.1, rotation = 0.008,
    -- Carries what a bulk inserter carries, and is charged what a bulk inserter is
    -- charged. No head start of its own: whatever the capacity research has bought, this
    -- holds exactly that and no more.
    --
    -- It costs about 1.9 times what the tier below costs for each thing it builds, where a
    -- base game bulk inserter costs about 1.4 times a fast one. That looks like this tier
    -- being overcharged and is not. Both are charged the same way -- 2.86 times the power
    -- against the base game's 2.84 -- and the difference is all on the other side: a bulk
    -- inserter doubles what it moves, while this gains only half again, because the extra
    -- tile of reach makes every journey longer and the price is billed by the tile.
    --
    -- That tile is not a cost to be compensated for. Reach is what decides how often the
    -- player has to stop and stand somewhere else, which is the real work of using any of
    -- this, and a fifth tile buys more of that than the throughput figure shows. This tier
    -- is two upgrades bought together and priced as two.
    bulk = true,
    width = 1, height = 5, movement = 20000, drain = "1kW",
    slows = 0,
    craft = 25,
    ingredients = {
      { type = "item", name = "constructor-equipment-3", amount = 1 },
      { type = "item", name = "processing-unit", amount = 1 },
      { type = "item", name = "steel-plate", amount = 1 },
    },
    requires = { "logistics-3" },
    research = {
      count = 500, time = 30,
      packs = { "automation", "logistic", "production" },
    },
  },
}

--- The first tier keeps the name it has always had, so a save from before any of this
--- still finds its equipment, its recipe and its technology where it left them.
tiers.FIRST = "constructor-equipment"

tiers.list = {}
tiers.by_name = {}
tiers.by_level = {}

for level, spec in ipairs(DEFINED) do
  local reach = spec.reach
  local name = level == 1 and tiers.FIRST or (tiers.FIRST .. "-" .. level)
  local tier = {
    level = level,
    name = name,
    --- The claw drawn in its place while it is being stowed. See prototypes/sprite.lua.
    claw = name .. "-claw",
    --- One inserter prototype per tier, since they differ in graphics and in speed.
    inserter = name .. "-inserter",
    --- What the tier below is called, which is what the recipe is built out of.
    below = level > 1 and (level == 2 and tiers.FIRST or (tiers.FIRST .. "-" .. (level - 1)))
        or nil,
    hand = spec.hand,
    sizes = HAND[spec.hand],
    --- Whether the claw is a bulk one, which is what lets it hold more than a single thing
    --- and hop from ghost to ghost rather than going home between each.
    bulk = spec.bulk or false,
    colour = spec.colour,
    width = spec.width,
    height = spec.height,
    --- What it is charged to move, to turn, and to sit idle: the base game's figures for
    --- the inserter it borrows from, unscaled. Four times these was tried, to make a swing
    --- take a visible bite out of a battery, and the bite is not what it cost: an arm's
    --- buffer is four times as big at four times the price, and a fourth tier arm spent
    --- thirty nine ticks filling it before it would set off, against four for the tier
    --- below. A green arm that stands about while a blue one works is a worse thing to
    --- watch than a charge meter that barely moves.
    ---
    --- There was a discount here once, worked out from how much of a bulk inserter's load
    --- this one carried, and it was built on a pair of wrong numbers: a bulk inserter does
    --- not carry a fixed twelve, and nor does this.
    movement = spec.movement,
    energy = spec.movement .. "J",
    drain = spec.drain,
    craft = spec.craft,
    ingredients = spec.ingredients,
    --- What this tier waits for in the technology tree, beyond the tier below it. Whatever
    --- unlocks the inserter it is built out of is added to this in data-final-fixes, once
    --- every other mod has finished moving the tree about.
    requires = spec.requires,
    research = spec.research,
    --- How much of the walking penalty this tier asks of its wearer, and the stickers that
    --- apply it. A tier that asks for none of it has neither.
    slowdown = spec.slows > 0 and (1 - (1 - tiers.SLOWED) * spec.slows) or nil,
    stickers = spec.slows > 0 and {
      modifier = 1 - (1 - tiers.SLOWED) * spec.slows,
      flat = name .. "-slowdown",
      slowing = name .. "-slowing",
      recovery = name .. "-recovery",
      --- The same three again, for a wearer that walks on legs rather than rolling on
      --- wheels. What differs is only the number written in the prototype, and why is in
      --- prototypes/sticker.lua: a wheeled vehicle's top speed goes with the square root
      --- of the figure and a spider vehicle's goes with the figure itself, so the same
      --- share of speed has to be asked for twice, in two different currencies.
      legs = {
        modifier = 1 - (1 - tiers.SLOWED) * spec.slows,
        flat = name .. "-slowdown-legs",
        slowing = name .. "-slowing-legs",
        recovery = name .. "-recovery-legs",
      },
    } or nil,
    --- How far it reaches.
    range = reach,
    --- How fast its hand moves and turns, which is the base game's figure for the inserter
    --- it borrows. There is no separate clock: the claw has to come home before it goes
    --- out again, so this is the only thing deciding how often a tier builds.
    extension = spec.extension,
    rotation = spec.rotation,
  }
  --- What one reach out to the edge of its range costs: the hand travels its range and
  --- back, and the engine bills the movement by the tile. Two of those is what an armour
  --- has to be holding before an arm will set off, so that it never stops halfway holding
  --- something.
  ---
  --- Measured against the real thing rather than trusted: a first tier arm working
  --- continuously at its own full reach spends about 12kJ a build and a fourth tier one
  --- about 198kJ, so this comes to between two and three builds' worth at every tier,
  --- nearer two at the tiers where the number is large enough to matter. It reads high
  --- because most ghosts are nearer than the edge of the range, which is the right way for
  --- a safety margin to be wrong.
  tier.reach_energy = 2 * reach * spec.movement
  tier.reserve = tier.reach_energy * tiers.RESERVE
  tiers.list[level] = tier
  tiers.by_name[name] = tier
  tiers.by_level[level] = tier
end

---The tier a piece of equipment belongs to, if it is one of ours.
---@param name string
---@return table?
function tiers.of(name)
  return tiers.by_name[name]
end

return tiers
