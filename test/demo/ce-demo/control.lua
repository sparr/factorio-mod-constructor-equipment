-- One of every thing Constructor Equipment does, in labelled bays on a surface of its own.
--
-- The point is to be walked round rather than asserted about. Every bay says where to stand
-- and what to do, on the ground above it, so nothing here needs a manual open beside it.
--
-- Rows are kitted rather than cumulative. A pad at the west end of each row gives the
-- character the armour, the equipment and the items that row wants and takes away what it
-- does not, so a row can be walked into cold; a pad at the east end carries you to the next
-- row's west pad. Walking to any row directly and standing on its pad does the same thing,
-- so nothing here has to be done in order.
--
--   /ce-demo    build it all again
--
-- The last four rows are vehicles. Two of them are vehicles the base game gives no
-- equipment grid: the showroom adds one so there is something to look at, and says so.

local BAY = 12          -- how wide a bay is: past the longest reach, and past its own words
local ROW = 14          -- how far apart the rows are
local SURFACE = "ce-demo"

local TIERS = { "constructor-equipment", "constructor-equipment-2",
                "constructor-equipment-3", "constructor-equipment-4" }

local function ground()
  return game.surfaces[SURFACE]
end

---Where a row's west pad stands. Bays run east from there.
---@param row integer counting from 1
---@return number x
---@return number y
local function row_at(row)
  return 0, (row - 1) * ROW
end

--- Which bay is being built, so that pad() can record whose mark it is laying and the
--- marks' own words can be kept clear of the bay's. Set around the bay closures and nil
--- everywhere else, since the row pads are not any bay's.
local building

---@param x number
---@param y number
---@param text string
---@param note string?
---@param colour table?
---@return number how far down the page it got, so what comes next can start below it
local function label(x, y, text, note, colour)
  rendering.draw_text{ text = text, surface = ground(), target = { x, y },
    color = colour or { 1, 0.9, 0.6 }, scale = 1.8, alignment = "left",
    scale_with_zoom = false }
  if not note then return y end
  -- Broken into lines rather than written as one. A bay is twenty two tiles wide and a
  -- sentence is longer than that, so left whole it runs across its neighbour's exhibit and
  -- both become unreadable.
  local line, at = "", 0
  local bottom = y
  local function draw(text_line)
    bottom = y + 1.3 + at * 1.1
    rendering.draw_text{ text = text_line, surface = ground(),
      target = { x, bottom },
      color = { 0.72, 0.78, 0.85 }, scale = 1.1, alignment = "left",
      scale_with_zoom = false }
    at = at + 1
  end
  for word in note:gmatch("%S+") do
    if #line + #word + 1 > 40 then draw(line) line = word
    else line = (line == "") and word or (line .. " " .. word) end
  end
  if line ~= "" then draw(line) end
  return bottom
end

--- Where a bay's own words ended, so that the mark's words go under them rather than
--- through them.
---
--- A bay's note is as long as it needs to be and its mark is at a fixed spot on the ground,
--- so the two were laid out against different things: the note grew downwards from the
--- title and STAND HERE sat a tile and a half below the mark whatever the note had done.
--- Five lines of note reached exactly that far and the two were written over each other.
---@param wanted number where the label would go if nothing were in the way
---@return number
local function under_the_words(wanted)
  local words = building and building.bottom
  if not words then return wanted end
  return math.max(wanted, words + 1.2)
end

---@param name string
---@param x number
---@param y number
---@param extra table?
---@return LuaEntity?
--- How far east the row being built has got. The east pad goes past whatever this ends up
--- being rather than a fixed number of bays along: a bay whose exhibit is wider than a bay
--- -- the vehicle rows are fifteen belts long -- put the pad to the next row in the middle
--- of its own ghosts, where walking the exhibit teleported you away from it.
local eastmost = 0

local function place(name, x, y, extra)
  local args = { name = name, position = { x + 0.5, y + 0.5 }, force = "player" }
  for key, value in pairs(extra or {}) do args[key] = value end
  local made = ground().create_entity(args)
  if not made then
    log(("ce-demo: could not place %s at %d,%d"):format(name, x, y))
  elseif made.valid then
    eastmost = math.max(eastmost, made.bounding_box.right_bottom.x)
  end
  return made
end

---A ghost of something, which is the thing most of this is about.
---@param name string
---@param x number
---@param y number
---@param extra table?
---@return LuaEntity?
local function ghost(name, x, y, extra)
  local args = { inner_name = name }
  for key, value in pairs(extra or {}) do args[key] = value end
  return place("entity-ghost", x, y, args)
end

---The mark to stand on: one tile, so that standing on it means standing where the bay was
---measured from. A three by three patch let you stand a tile and a half off, which on a two
---tile arm is the difference between working and not.
---@param x number
---@param y number
---@param tile string
local function pad(x, y, tile)
  ground().set_tiles{ { name = tile, position = { x, y } } }
  eastmost = math.max(eastmost, x + 1)
  if not building then return end
  storage.marks = storage.marks or {}
  storage.marks[#storage.marks + 1] = {
    row = building.row, bay = building.bay, title = building.title,
    x = x + 0.5, y = y + 0.5,
  }
end

---A mark that gives you something different from the rest of its row.
---
---A row is kitted as a whole because that is what lets any row be walked into cold. Now and
---then one bay inside it wants something else, and saying so in words and hoping is not the
---same as handing it over.
---@param x number
---@param y number
---@param kit table what the row's kit would be, with this bay's changes in it
---@param note string what standing on it is for
local function bay_kit(x, y, kit, note)
  pad(x, y, "refined-concrete")
  label(x - 1, under_the_words(y + 1.6), "STAND HERE", note, { 0.55, 0.9, 0.6 })
  storage.bay_kits = storage.bay_kits or {}
  storage.bay_kits[#storage.bay_kits + 1] = { x = x + 0.5, y = y + 0.5, kit = kit }
end

---Ghosts that are not there until you are.
---
---Leading undid every bay that lays its exhibit east of its mark. An arm aims where its
---target will be by the time the claw could get there, so walking up to a bay is walking
---towards its exhibit with a cone of reach in front of you, and the bay is half built
---before you arrive. Moving the mark does not help: the cone is wider than any bay, and a
---fourth tier arm meets things eleven tiles ahead of a walk.
---
---So the exhibit waits. Nothing stands on the ground until its mark is stood on, which is
---also what these bays are about -- arriving rather than walking up.
---
---The ghosts are written down rather than the function that makes them, because storage
---keeps data across a save and cannot keep a closure.
---@param x number the mark, in tiles
---@param y number
---@param ghosts table[] each { name, dx, dy }, offset from the mark
local function lay_on(x, y, ghosts)
  storage.lays = storage.lays or {}
  storage.lays[#storage.lays + 1] = { at = { x = x + 0.5, y = y + 0.5 }, x = x, y = y,
                                      ghosts = ghosts }
end

---Put down whatever a mark was given to lay, for anything not already standing there.
---@param lay table
local function lay_out(lay)
  local surface = ground()
  if not surface then return end
  for _, what in pairs(lay.ghosts) do
    local at = { lay.x + what[2] + 0.5, lay.y + what[3] + 0.5 }
    -- Nothing is laid twice. A ghost already waiting, or the thing itself already built,
    -- both mean this mark has been stood on and not yet cleared, and a bay that piled a
    -- fresh ghost on every tick somebody stood still would be no bay at all.
    if not (surface.find_entity("entity-ghost", at) or surface.find_entity(what[1], at)) then
      surface.create_entity{ name = "entity-ghost", inner_name = what[1], position = at,
        force = "player" }
    end
  end
end

---A mark that puts you somewhere else on the same row, and the mark it puts you on.
---
---Walking up to a line of ghosts offers them one at a time, nearest first, so the shortest
---arm that can reach each one gets it and the long arms are always a step behind. Arriving
---in the middle of them offers all of them at once, which is the other half of the story
---and cannot be done on foot at any speed.
---@param from_x number
---@param from_y number
---@param to_x number
---@param to_y number
---@param note string what standing on it is for
local function hop(from_x, from_y, to_x, to_y, note)
  pad(from_x, from_y, "refined-hazard-concrete-right")
  pad(to_x, to_y, "refined-hazard-concrete-left")
  label(from_x - 1, under_the_words(from_y + 1.6), "STAND HERE", note, { 0.55, 0.9, 0.6 })
  storage.hops = storage.hops or {}
  storage.hops[#storage.hops + 1] = {
    from = { x = from_x + 0.5, y = from_y + 0.5 },
    to = { x = to_x + 0.5, y = to_y + 0.5 },
  }
end

-- --------------------------------------------------------------------------- the rows

--- What each row is, what it gives the character who stands on its pad, and what it builds.
---
--- A kit is the whole of what the character has: the armour is replaced, the grid is filled
--- from scratch and the pockets are emptied first, so a row never inherits the one before
--- it. That is what lets any row be walked into directly.
local ROWS = {
  {
    title = "Building",
    note = "Modular armour, one first tier arm, a pocketful of belts.",
    kit = {
      armour = "modular-armor",
      equipment = { "constructor-equipment", "battery-equipment" },
      items = { ["transport-belt"] = 50, ["rail"] = 20, ["iron-chest"] = 5 },
    },
    bays = {
      { "A ghost in reach",
        "Stand on the mark. The arm comes out of your back and builds it.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          ghost("transport-belt", x + 5, y + 6)
        end },
      { "A ghost out of reach",
        "Stand on the mark. The first tier reaches two tiles and this one is six away.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          ghost("transport-belt", x + 9, y + 6)
        end },
      { "A belt under your feet",
        "Stand on the mark. The belt appears under your feet and goes up anyway: you can stand on a belt, so it is not in your way.",
        function(x, y)
          pad(x + 4, y + 6, "refined-hazard-concrete-left")
          -- Laid when the mark is stood on rather than waiting there. Walking up to a belt
          -- is walking towards it, which is all leading needs: it was built a few tiles
          -- short of the mark every time, and the bay you arrived at was an empty tile.
          lay_on(x + 4, y + 6, { { "transport-belt", 0, 0 } })
        end },
      { "A chest under your feet",
        "Stand on the mark. This one waits, because a chest is a thing you cannot stand in. Step off and it goes up.",
        function(x, y)
          pad(x + 4, y + 6, "refined-hazard-concrete-left")
          -- The other half of the same rule, and the half that still declines. What decides
          -- it is whether the thing could be built where its owner is standing at all, not
          -- whether the claw can reach under itself -- see standing_in() in control.lua.
          lay_on(x + 4, y + 6, { { "iron-chest", 0, 0 } })
        end },
      { "Nothing to pay with",
        "Stand on the mark. You are carrying no steel chest, so it stays a ghost.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          ghost("steel-chest", x + 5, y + 6)
        end },
      { "A ghost that takes three",
        "Stand on the mark. A curved rail wants three rails and the claw holds one:",
        function(x, y)
          -- A rail lies on a grid of its own: asked for x + 6 it comes to rest at x + 7,
          -- which put it 2.55 tiles from a mark a two tile arm stands on and nothing ever
          -- went out to it. So the mark is laid from where the rail ended up, two tiles
          -- west of its middle, which is inside the arm's reach and outside the rail's own
          -- bounding box -- an arm will not reach for something its owner is standing in.
          local rail = ghost("curved-rail-a", x + 6, y + 6,
            { direction = defines.direction.north })
          if rail then
            pad(math.floor(rail.position.x) - 2, math.floor(rail.position.y),
              "refined-hazard-concrete-left")
          else
            pad(x + 4, y + 6, "refined-hazard-concrete-left")
          end
        end },
      { "The slowdown",
        "Stand on the mark and walk east along them. A first tier arm costs you speed while it works.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- laid the way you will be walking, so the work keeps up with you
          for i = 0, 8 do ghost("transport-belt", x + 3 + i, y + 6) end
        end },
    },
  },

  {
    title = "Tiers and numbers",
    note = "Power armour, one arm of every tier, and the capacity research done.",
    kit = {
      armour = "power-armor-mk2",
      equipment = { TIERS[1], TIERS[2], TIERS[3], TIERS[4],
                    "fission-reactor-equipment", "battery-mk2-equipment" },
      items = { ["transport-belt"] = 200 },
      -- inserter-capacity-bonus-1 is the one that raises a bulk hand; the others raise a
      -- plain one. The bulk arm reads the first, so it is here along with what it follows.
      research = { "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "Four arms, four reaches",
        "The mark puts you down among all four at once, and each takes the one that suits its reach.",
        function(x, y)
          -- Arriving rather than walking up, which is the whole of the bay. Walking offers
          -- the ghosts one at a time, nearest first, so the shortest arm that can reach
          -- each one takes it and the long arms are always a step behind whatever the
          -- player's speed. Arriving offers all four on the same tick, and the arms are
          -- asked shortest first, so each takes the one that suits it. There is no way to
          -- arrive all at once on foot.
          --
          -- The mark you stand on is six tiles from the nearest ghost, past every arm, so
          -- nothing is built while you wait to be moved.
          -- One to four rather than two to five. An arm reaches from where it is bolted on
          -- rather than from the middle of its owner, so a ghost at exactly five tiles is
          -- past the five tile arm as often as not, and the bay is about each arm getting
          -- one rather than about the longest arm being caught short.
          hop(x + 1, y + 6, x + 5, y + 6,
            "to be put down among four ghosts at one, two, three and four tiles")
          -- Laid on arrival. Six tiles of clear ground in front of the mark used to be
          -- enough to keep every arm off them while you walked up; leading put the fourth
          -- tier's reach eleven tiles ahead of a walk, and there is no distance inside a
          -- bay that is past that. So they are not there to be reached for until the
          -- player is standing among them, which is the bay's whole point anyway.
          local laid = {}
          for step = 1, 4 do laid[#laid + 1] = { "transport-belt", step, 0 } end
          lay_on(x + 5, y + 6, laid)
        end },
      { "One arm for every copy",
        "Stand on the mark. Four arms work at once, and none of them reaches for the same thing.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 3 do
            ghost("transport-belt", x + 5, y + 4 + i)
            ghost("transport-belt", x + 6, y + 4 + i)
          end
        end },
      { "The bulk claw",
        "Stand on the mark. Five tiles out, so only the green arm reaches: it carries several and turns from one to the next.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- An arc rather than a column: every one of these is between four and four and a
          -- half tiles from the mark, which is past every other arm's reach and inside the
          -- green one's. A straight column at five tiles has its ends at five and a half,
          -- so standing on the mark only reached the middle of it.
          --
          -- The arithmetic matters and was wrong: two of these sat at five and two, which
          -- is 5.39 away and outside the five tile arm that is meant to build them. What a
          -- player saw was the claw going out with a full hand, building what it could and
          -- coming home with the rest, over and over, which reads exactly like a claw that
          -- has forgotten how to deliver. Nothing here is further than 4.5, and an arm
          -- reaches from where it is bolted rather than from its owner's middle, so the
          -- half tile of slack is the mounting's.
          for _, at in pairs{ { 4, -2 }, { 4, 2 }, { 3, -3 }, { 3, 3 }, { 4, 1 } } do
            ghost("transport-belt", x + 1 + at[1], y + 6 + at[2])
          end
        end },
    },
  },

  {
    title = "Power",
    note = "Power armour with nothing but an arm in it, then one with a reactor.",
    kit = {
      armour = "power-armor",
      equipment = { "constructor-equipment" },
      charged = false,
      items = { ["transport-belt"] = 100 },
    },
    bays = {
      { "Flat batteries",
        "Stand on the mark. Your grid has no charge, so the arm never sets off.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 3 do ghost("transport-belt", x + 5, y + 5 + i) end
        end },
      { "The same arm, with power behind it",
        "Stand on the mark. It puts a reactor and a battery in your armour, and now the same arm builds.",
        function(x, y)
          -- The mark hands them over rather than a chest offering them. Rummaging in a
          -- chest is a thing to work out rather than a thing to watch, and the bay is about
          -- what the arm does once the grid has charge in it.
          bay_kit(x + 3, y + 6, {
            armour = "power-armor",
            -- The small battery, not the mark two. A mark two holds so much that a swing
            -- takes an invisible bite out of it, and the next bay is about watching it go
            -- down.
            equipment = { "constructor-equipment", "fission-reactor-equipment",
                          "battery-equipment" },
            items = { ["transport-belt"] = 100 },
          }, "to be handed a reactor and a battery")
          -- Two tiles from the mark, not three. A first tier arm reaches two, so a column
          -- three out needed a step towards it before anything happened, and a mark whose
          -- whole promise is that the same arm builds now should not want a step first.
          for i = 0, 3 do ghost("transport-belt", x + 5, y + 5 + i) end
        end },
      { "What a swing costs",
        "Open your armour. No reactor, so a swing takes a bite; the jump back up is the claw handing its buffer back.",
        function(x, y)
          -- The fourth tier and a ring of forty, where this used to be the first tier and a
          -- ring of eight. A small arm on a small battery takes a bite you have to look for;
          -- the big arm reaches five tiles for every one of them and there are enough of
          -- them to watch the bar go down rather than flicker.
          bay_kit(x + 6, y + 6, {
            armour = "power-armor",
            equipment = { "constructor-equipment-4", "battery-equipment" },
            items = { ["transport-belt"] = 200 },
          }, "for one fourth tier arm, one small battery and no reactor")
          -- The mark is the middle of the ring, and the ring is laid when the mark is stood
          -- on. That is what takes the reactor off before anything is there to build: walk
          -- in wearing the one from the bay before and a ring standing on the ground is
          -- half up before the mark has had a word about it.
          local ring = {}
          for dx = -4, 4 do
            for dy = -4, 4 do
              local away = dx * dx + dy * dy
              if away >= 4 and away <= 16 then
                ring[#ring + 1] = { "transport-belt", dx, dy }
              end
            end
          end
          lay_on(x + 6, y + 6, ring)
        end },
    },
  },

  {
    title = "Switching off, and full pockets",
    note = "Power armour, one arm, and a pocketful you will be asked to fill up.",
    kit = {
      armour = "power-armor",
      equipment = { "constructor-equipment", "battery-mk2-equipment" },
      items = { ["transport-belt"] = 100 },
      -- The button is unlocked by the first tier's technology, and without it there is no
      -- button on the toolbar to press.
      research = { "constructor-equipment" },
    },
    bays = {
      { "The toolbar button",
        "Stand on the mark and press the arm button on the toolbar. It stops mid reach and hands back what it carried.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 7 do ghost("transport-belt", x + 5, y + 2 + i) end
        end },
      { "Pockets full",
        "Empty these chests into your pockets until nothing more will fit, then mark the belts for deconstruction yourself.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- Four full chests rather than one. A character's pockets grow with research and
          -- with what they are wearing, and one chest of stone is not always enough to fill
          -- them.
          for i = 0, 3 do
            local chest = place("steel-chest", x + 3, y + 4 + i)
            if chest then chest.insert{ name = "stone", count = 48 * 50 } end
          end
          -- Left unmarked on purpose: marking them is the thing to do here.
          for i = 0, 3 do place("transport-belt", x + 5, y + 4 + i) end
        end },
    },
  },

  {
    title = "The upgrade planner",
    note = "Power armour, the bulk arm, and better belts to pay with.",
    kit = {
      armour = "power-armor",
      equipment = { TIERS[4], "fission-reactor-equipment", "battery-mk2-equipment" },
      items = {
        ["fast-transport-belt"] = 50, ["fast-underground-belt"] = 20,
        ["iron-chest"] = 10, ["upgrade-planner"] = 1,
      },
      -- Without this a bulk claw holds one thing, and every bay about carrying several
      -- shows it carrying one.
      research = { "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "A belt upgraded",
        "Stand on the mark. These are marked already: the claw swaps each and brings the old one back.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 4 do
            local belt = place("transport-belt", x + 5, y + 4 + i,
              { direction = defines.direction.east })
            if belt then
              belt.order_upgrade{ force = game.forces.player,
                target = prototypes.entity["fast-transport-belt"] }
            end
          end
        end },
      { "An underground pair",
        "Stand on the mark. Both ends go together for the price of two, and the tunnel keeps its load.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          local near = place("underground-belt", x + 4, y + 6,
            { direction = defines.direction.east, type = "input" })
          local far = place("underground-belt", x + 8, y + 6,
            { direction = defines.direction.east, type = "output" })
          for _, one in pairs{ near, far } do
            if one then
              one.order_upgrade{ force = game.forces.player,
                target = prototypes.entity["fast-underground-belt"] }
            end
          end
          if near then
            for line = 3, 4 do
              for spot = 0.2, 1.4, 0.6 do
                near.get_transport_line(line).insert_at(spot, { name = "iron-plate" })
              end
            end
          end
        end },
      { "A chest downgraded",
        "Stand on the mark. What the smaller chest cannot hold is left on the floor, marked, as a robot leaves it.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local chest = place("steel-chest", x + 5, y + 6)
          if chest then
            chest.insert{ name = "iron-plate", count = 4800 }
            chest.order_upgrade{ force = game.forces.player,
              target = prototypes.entity["iron-chest"] }
          end
        end },
    },
  },

  {
    title = "The deconstruction planner",
    note = "Power armour, the bulk arm, a planner and a charge for the cliff.",
    kit = {
      armour = "power-armor",
      equipment = { TIERS[4], "fission-reactor-equipment", "battery-mk2-equipment" },
      items = { ["deconstruction-planner"] = 1, ["cliff-explosives"] = 5 },
      research = { "cliff-explosives", "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "A thing taken up",
        "Stand on the mark. The claw goes out empty and comes home with it.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 4 do
            local belt = place("transport-belt", x + 5, y + 4 + i)
            if belt then belt.order_deconstruction(game.forces.player) end
          end
        end },
      { "A chest with something in it",
        "Stand on the mark. Emptied a clawful at a time, and the chest itself goes last.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local chest = place("steel-chest", x + 5, y + 6)
          if chest then
            chest.insert{ name = "copper-plate", count = 20 }
            chest.order_deconstruction(game.forces.player)
          end
        end },
      { "A patch of tiles",
        "Stand on the mark. The claw goes from one tile to the next without coming home, and visits every one.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local tiles = {}
          for dx = 0, 2 do
            for dy = -1, 1 do
              tiles[#tiles + 1] = { name = "concrete", position = { x + 4 + dx, y + 6 + dy } }
            end
          end
          ground().set_tiles(tiles)
          for _, tile in pairs(tiles) do
            local one = ground().get_tile(tile.position[1], tile.position[2])
            if one then one.order_deconstruction(game.forces.player) end
          end
        end },
      { "One round, both sides",
        "Stand between them. The claw crosses from one to the other and carries both back.",
        function(x, y)
          pad(x + 5, y + 6, "refined-hazard-concrete-left")
          for _, away in pairs{ -4, -3, 3, 4 } do
            local belt = place("transport-belt", x + 5 + away, y + 6)
            if belt then belt.order_deconstruction(game.forces.player) end
          end
        end },
      { "A cliff wants a charge",
        "Stand on the mark. The claw carries one explosive out and comes home with nothing.",
        function(x, y)
          -- The mark goes where the cliff ended up rather than where it was asked for. A
          -- cliff lies on a grid of its own and comes to rest a tile or two off, which on a
          -- five tile arm is the difference between reaching it and standing there.
          -- Researched here rather than left to the kit. A force that has not got cliff
          -- explosives cannot mark a cliff at all: order_deconstruction takes it, says
          -- nothing, and leaves the cliff unmarked, so the bay stood there with nothing to
          -- do and looked exactly like an arm that would not go.
          local knows = game.forces.player.technologies["cliff-explosives"]
          if knows then knows.researched = true end
          local cliff = place("cliff", x + 7, y + 6,
            { cliff_orientation = "west-to-east", force = "neutral" })
          if cliff then
            cliff.order_deconstruction(game.forces.player)
            if not cliff.to_be_deconstructed() then
              log("ce-demo: could not mark the cliff for deconstruction")
            end
            pad(math.floor(cliff.position.x) - 3, math.floor(cliff.position.y),
              "refined-hazard-concrete-left")
          else
            pad(x + 2, y + 6, "refined-hazard-concrete-left")
          end
        end },
      },
  },

  {
    title = "A tank",
    note = "A vehicle the base game gives an equipment grid. Get in and drive along the ghosts.",
    vanilla = true,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on the turret",
        "Get in and drive east. A tank's arms are bolted to its turret and reach from over the middle,",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 14 do
            ghost("transport-belt", x + 5 + i, y + 3)
            ghost("transport-belt", x + 5 + i, y + 9)
          end
        end },
    },
    -- The fourth tier pair first. A grid packs in the order it is given, and two one by
    -- fives after two one by fours leaves nowhere tall enough for them.
    vehicle = { name = "tank", at = { 3, 6 }, fuel = "solid-fuel",
                arms = { TIERS[4], TIERS[4], TIERS[3], TIERS[3] } },
  },

  {
    title = "A spidertron",
    note = "The other vehicle the base game gives a grid, and the one that walks.",
    vanilla = true,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on the legs",
        "Get in and walk it over the ghosts. Eight second tier arms, and it loses the share of its speed you lose of yours.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          -- A long walk with something to build the whole way, and four lines of it rather
          -- than two: eight arms on a hull want more work in reach than two did, or most of
          -- them are along for the ride.
          -- Within three tiles of the middle, which is what a second tier arm bolted to a
          -- leg can reach: a spidertron's legs meet its body less than a tile out, so its
          -- arms reach a good deal less far from the middle than a tank's do from its hull.
          for i = 0, 39 do
            for _, dy in pairs{ 3, 4, 8, 9 } do
              ghost("transport-belt", x + 5 + i, y + dy)
            end
          end
        end },
    },
    vehicle = { name = "spidertron", at = { 3, 6 },
                arms = { TIERS[2], TIERS[2], TIERS[2], TIERS[2],
                         TIERS[2], TIERS[2], TIERS[2], TIERS[2] } },
  },

  {
    title = "A car, with a grid the showroom added",
    note = "NOT VANILLA. A car has no equipment grid in the base game; this one has one so there is something to see.",
    vanilla = false,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on a car",
        "Get in and drive east. Without the grid the showroom gave it, your own armour would go quiet in here.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 14 do
            ghost("transport-belt", x + 5 + i, y + 3)
            ghost("transport-belt", x + 5 + i, y + 9)
          end
        end },
    },
    vehicle = { name = "car", at = { 3, 6 }, fuel = "solid-fuel",
                arms = { TIERS[3], TIERS[3], TIERS[3], TIERS[3] } },
  },

  {
    title = "A locomotive, with a grid the showroom added",
    note = "NOT VANILLA. A locomotive has no equipment grid in the base game either. It builds out of the wagon behind it, because a locomotive has no hold of its own.",
    vanilla = false,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on a train",
        "Get in and drive along the rail and back. Eight second tier arms, and the belts are in the wagon. Long enough to reach full speed and keep it, which is where a train's arms are worth watching.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          -- Three times the track it used to have. A locomotive spends a long way getting
          -- up to speed, and a run that ends before it gets there only ever shows the arms
          -- working at a crawl: the old fifty four tiles were all acceleration.
          local rail
          for i = -2, 78 do
            local laid = place("straight-rail", x + 6 + i * 2, y + 6,
              { direction = defines.direction.east })
            rail = rail or laid
          end
          -- Two rows on each side rather than one, measured off the rail the train will
          -- really sit on rather than off the tape.
          --
          -- Rails lie on a grid of their own, half a tile from the one a belt sits on, so a
          -- row asked for by eye comes out lopsided: two rows either side of y + 6 land at
          -- two and a half and three and a half tiles from the train on one side and one and
          -- a half and two and a half on the other, and a second tier arm reaches three. The
          -- far row is then one no arm can ever touch, and it reads as arms that refuse a
          -- whole row rather than as a row laid in the wrong place. Measured out of a
          -- fixture that made exactly that mistake.
          local middle = rail and rail.position.y or (y + 6.5)
          for i = 0, 131 do
            for _, off in pairs{ -2.5, -1.5, 1.5, 2.5 } do
              place("entity-ghost", x + 6 + i, middle + off - 0.5,
                { inner_name = "transport-belt" })
            end
          end
        end },
    },
    vehicle = { name = "locomotive", at = { 6, 6 }, fuel = "solid-fuel",
                direction = defines.direction.east, on_rail = true,
                arms = { TIERS[2], TIERS[2], TIERS[2], TIERS[2],
                         TIERS[2], TIERS[2], TIERS[2], TIERS[2] },
                -- Enough for the whole field and then some. Four rows of a hundred and
                -- thirty two is more than two hundred, and a train that runs dry part way
                -- along looks exactly like arms that have stopped working.
                belts = 800,
                -- A locomotive prototype has nowhere to put a hold, so its only inventory
                -- is a three slot burner box: an insert of two hundred belts into one takes
                -- none of them, quietly. The arms build out of the train's wagons instead,
                -- so the train needs one.
                wagon = "cargo-wagon" },
  },

  --- Three of AAI's vehicles, for the one thing the base game's four cannot show: a hull of
  --- a shape nobody wrote lib/pack.lua against. A chaingunner is a tile and a half square, an
  --- ironclad is twice as long as it is wide, and a hauler is a big square -- against a tank,
  --- a car and a locomotive, which are all roughly the same long rectangle.
  ---
  --- Each is its own mod and none of them is a dependency of anything here. A row whose
  --- vehicle is missing is left out of the showroom entirely rather than laid out empty, and
  --- the rows after it close up: see clear_and_build(), which does the leaving out and puts
  --- the numbers on afterwards.
  {
    title = "An AAI chaingunner, the smallest hull there is",
    note = "Power armour, and four second tier arms bolted to a hull a tile and a half square.",
    vanilla = false,
    when = function() return prototypes.entity["vehicle-chaingunner"] ~= nil end,
    kit = { armour = "power-armor", equipment = {}, items = {} },
    bays = {
      { "Four arms on a small hull",
        "Get in and drive east. Four arms on a hull this size sit almost on top of one another, which is what this is here to show.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 29 do
            ghost("transport-belt", x + 6 + i, y + 4)
            ghost("transport-belt", x + 6 + i, y + 8)
          end
        end },
    },
    vehicle = { name = "vehicle-chaingunner", at = { 3, 6 }, fuel = "solid-fuel",
                arms = { TIERS[2], TIERS[2], TIERS[2], TIERS[2] } },
  },

  {
    title = "An AAI ironclad, twice as long as it is wide",
    note = "Its own equipment grid, not the showroom's, and six second tier arms down a long hull.",
    vanilla = false,
    -- "ironclad", not "vehicle-ironclad": alone among AAI's vehicles it drops the prefix.
    when = function() return prototypes.entity["ironclad"] ~= nil end,
    kit = { armour = "power-armor", equipment = {}, items = {} },
    bays = {
      { "Arms down a long hull",
        "Get in and drive east. An ironclad carries a grid of its own, so nothing here had to give it one.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          -- Two lines wide apart, since a hull this long puts its end arms a good way from
          -- its middle and a single line would only ever be worked by the near ones.
          for i = 0, 29 do
            ghost("transport-belt", x + 6 + i, y + 3)
            ghost("transport-belt", x + 6 + i, y + 9)
          end
        end },
    },
    vehicle = { name = "ironclad", at = { 3, 6 }, fuel = "solid-fuel",
                arms = { TIERS[2], TIERS[2], TIERS[2],
                         TIERS[2], TIERS[2], TIERS[2] } },
  },

  {
    title = "An AAI hauler, with a grid the showroom added",
    note = "A big square hull and a hold of its own, so the arms build out of what it carries.",
    vanilla = false,
    when = function() return prototypes.entity["vehicle-hauler"] ~= nil end,
    kit = { armour = "power-armor", equipment = {}, items = {} },
    bays = {
      { "Building out of the hold",
        "Get in and drive east. The belts come out of the hauler rather than your pockets, the way a train's come out of its wagons.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 29 do
            ghost("transport-belt", x + 6 + i, y + 4)
            ghost("transport-belt", x + 6 + i, y + 8)
          end
        end },
    },
    vehicle = { name = "vehicle-hauler", at = { 3, 6 }, fuel = "solid-fuel",
                arms = { TIERS[3], TIERS[3], TIERS[2], TIERS[2] } },
  },

  {
    title = "Leading",
    note = "Power armour, one fourth tier arm, a reactor and a pocketful of belts.",
    -- Wider bays than the rest of the showroom. Every bay here is walked rather than stood
    -- on, and a walk long enough to meet something ten tiles off runs into the next bay at
    -- the usual spacing.
    spread = 24,
    kit = {
      armour = "power-armor",
      equipment = { TIERS[4], "fission-reactor-equipment", "battery-equipment" },
      items = { ["transport-belt"] = 100 },
    },
    bays = {
      { "Met on the way",
        "Keep walking east. The arm reaches five tiles and this belt is ten off: the claw goes to where the belt will be.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          ghost("transport-belt", x + 11, y + 6)
        end },
      { "In reach, but not in time",
        "Keep walking east and this stays a ghost, though you pass within four tiles. Stop beside it and it goes up at once.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- Square to the side of the mark rather than ahead of it. A hand stretches out
          -- more slowly than its owner walks -- about a tile to the side is all a walk has
          -- -- so this one is never ahead of you long enough to be met, and the arm knows
          -- it and does not set off. Standing still it is four tiles away and well in
          -- reach, which is what makes the pair of them worth walking twice.
          --
          -- Laid when the mark is stood on, or walking up to it does the very thing the bay
          -- says cannot be done: from back down the row it is ahead and to the side rather
          -- than square abeam, which is plenty of room to lead it, and it went up every
          -- time. Square abeam is a thing you have to start at, not walk into.
          lay_on(x + 1, y + 6, { { "transport-belt", 0, 4 } })
        end },
      { "A small arm leads too",
        "Keep walking east. A two tile arm and a belt six tiles off, and it still gets there.",
        function(x, y)
          bay_kit(x + 1, y + 6, {
            armour = "modular-armor",
            equipment = { TIERS[1], "battery-equipment" },
            items = { ["transport-belt"] = 100 },
          }, "for one first tier arm and nothing else")
          -- Laid once the mark has swapped the arm. Left standing, the fourth tier arm the
          -- player is still wearing from the bay before meets it eleven tiles out and
          -- builds it on the way over, and the bay about a small arm never gets to use one.
          lay_on(x + 1, y + 6, { { "transport-belt", 6, 0 } })
        end },
    },
  },

  {
    title = "Rounds on the move",
    note = "The same arm with the capacity research done, so its claw carries several.",
    spread = 24,
    kit = {
      armour = "power-armor",
      equipment = { TIERS[4], "fission-reactor-equipment", "battery-equipment" },
      items = { ["transport-belt"] = 100 },
      research = { "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "A row in one trip",
        "Keep walking east. The claw sets off holding all four and puts them down one after another without coming home.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- Ten to thirteen tiles ahead and two to the side: past what one swing can reach
          -- or even see when the claw leaves, and inside what the round as a whole covers.
          -- The claw is shopping for the whole round rather than for its first ghost.
          for i = 0, 3 do ghost("transport-belt", x + 11 + i, y + 8) end
        end },
      { "How far off your line",
        "Keep walking east. Each sits a tile further off your line than the last: the near three go up, the far two do not.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- A ladder rather than a count. Each rung sits one tile further from the line the
          -- walk takes than the one before, so what the bay shows is the edge itself --
          -- three rungs built, two left standing, and the step between them where the side
          -- reach runs out. A tuned arrangement that happens to leave one of three standing
          -- shows a number; this shows the boundary, and a watcher can see which rung it
          -- fell on.
          --
          -- Measured walking east on this row's own kit, at four spacings from two tiles
          -- apart to four: two, three and four tiles abeam go up and five and six do not,
          -- every time and whatever the spacing. So the edge is between four and five and
          -- it does not move with how far apart the rungs are.
          --
          -- It was three ghosts crammed a tile abeam. Until an arm reckoned its swing from
          -- where its own arm is rather than from where its claw is drawn, a tile abeam was
          -- the edge; the bay went on claiming a limit that had moved out to four, and all
          -- three of it went up.
          ghost("transport-belt", x + 9, y + 8)
          ghost("transport-belt", x + 12, y + 9)
          ghost("transport-belt", x + 15, y + 10)
          ghost("transport-belt", x + 18, y + 11)
          ghost("transport-belt", x + 21, y + 12)
        end },
    },
  },
}

--- Every quality the game has, worst first, and never the placeholder.
---@return table[] each { name, level }
local function qualities()
  local found = {}
  for name, quality in pairs(prototypes.quality) do
    if name ~= "quality-unknown" then
      found[#found + 1] = { name = name, level = quality.level }
    end
  end
  table.sort(found, function(one, other) return one.level < other.level end)
  return found
end

table.insert(ROWS, {
  title = "Quality",
  note = "The same arm at every quality. Each mark along the row hands you a better one.",
  vanilla = false,
  -- Nothing worth showing where there is only the one quality, which is every game without
  -- the quality mod in it. A row of a single bay saying "this is normal" is not a row.
  when = function() return #qualities() > 1 end,
  kit = {
    armour = "power-armor",
    equipment = { TIERS[4], "fission-reactor-equipment", "battery-mk2-equipment" },
    items = { ["transport-belt"] = 100 },
  },
  -- Worked out when the row is laid rather than written down, because which qualities exist
  -- is a question about the game rather than about the mod.
  bays = function()
    local bays = {}
    for _, quality in ipairs(qualities()) do
      bays[#bays + 1] = {
        quality.name:sub(1, 1):upper() .. quality.name:sub(2),
        -- The multiplier is the engine's own figure rather than a sum written here: a
        -- quality prototype carries it, and it is exactly what the inserter's two speeds
        -- come out scaled by.
        ("Stand on the mark. The arm you are handed is %s, and the engine swings it %s."):
          format(quality.name, quality.level == 0 and "at its ordinary rate"
            or ("%.1f times as fast"):format(
              prototypes.quality[quality.name].default_multiplier)),
        function(x, y)
          -- The mark hands over an arm of this quality and lays the work at the same time,
          -- so the whole of the instruction is standing on it.
          local kit = {
            armour = "power-armor",
            equipment = { { TIERS[4], quality.name }, "fission-reactor-equipment",
                          "battery-mk2-equipment" },
            items = { ["transport-belt"] = 100 },
          }
          bay_kit(x + 2, y + 6, kit,
            ("for a %s arm, and a wall of belts to put up with it"):format(quality.name))
          -- A block rather than a line, and all of it inside the reach of a five tile arm,
          -- so that what is being watched is how fast the claw works rather than how far it
          -- can lean. Same block at every quality, so the only thing that differs along the
          -- row is the arm.
          local laid = {}
          for dx = 4, 6 do
            for dy = 4, 8 do
              laid[#laid + 1] = { "transport-belt", dx, dy }
            end
          end
          lay_on(x + 2, y + 6, laid)
        end,
      }
    end
    return bays
  end,
})

-- --------------------------------------------------------------------------- kitting

---Give the character exactly what a row wants and nothing else.
---@param player LuaPlayer
---@param row table
local function kit(player, row)
  local wanted = row.kit or {}
  local main = player.get_inventory(defines.inventory.character_main)
  local worn = player.get_inventory(defines.inventory.character_armor)
  if main then main.clear() end
  if worn then worn.clear() end

  if wanted.armour then
    player.insert{ name = wanted.armour, count = 1 }
    local armour = worn and worn[1]
    if armour and armour.grid then
      -- A name, or { name, quality } for a piece that is not the ordinary one. A quality
      -- the game does not have -- which is every one of them without the quality mod -- is
      -- left out rather than refused, so a row asking for legendary arms in a game with no
      -- quality in it simply gets none rather than failing to lay itself out.
      for _, want in pairs(wanted.equipment or {}) do
        local name = want
        local quality = nil
        if type(want) == "table" then name, quality = want[1], want[2] end
        if prototypes.equipment[name]
            and (not quality or prototypes.quality[quality]) then
          armour.grid.put{ name = name, quality = quality }
        end
      end
      for _, piece in pairs(armour.grid.equipment) do
        piece.energy = (wanted.charged == false) and 0 or piece.max_energy
      end
    end
  end

  for name, count in pairs(wanted.items or {}) do
    if prototypes.item[name] then player.insert{ name = name, count = count } end
  end

  for _, name in pairs(wanted.research or {}) do
    local technology = player.force.technologies[name]
    if technology then technology.researched = true end
  end
end

-- --------------------------------------------------------------------------- building

local function clear_and_build()
  local made = ground()
  if not made then
    made = game.create_surface(SURFACE, { width = 2000, height = 2000 })
  end
  made.always_day = true

  -- Only the rows this game can actually show, worked out before anything is measured off
  -- them. A row about a mod's vehicle is laid out when that mod is here and left out
  -- entirely when it is not: half a row, with a mark and a heading and no vehicle to get
  -- into, is worse than no row at all.
  --
  -- A row may also work its bays out when it is laid rather than say them outright, which is
  -- what a row about qualities needs: which of them exist is not known until there is a game
  -- to ask. Both happen here, so that the ground, the chunks and the counting downstream are
  -- all measured off the showroom that is really going to be built.
  local showing = {}
  for place, row in ipairs(ROWS) do
    if not row.when or row.when() then
      if type(row.bays) == "function" then row.bays = row.bays() end
      -- Where it sits in ROWS, so that a pad can find its own row again afterwards.
      row.index = place
      showing[#showing + 1] = row
    end
  end

  local width = 0
  for _, row in pairs(showing) do
    local wide = row.spread or BAY
    width = math.max(width, #row.bays * wide + wide)
  end
  local tall = #showing * ROW + ROW

  made.request_to_generate_chunks({ width / 2, tall / 2 },
    math.ceil(math.max(width, tall) / 32) + 2)
  made.force_generate_chunk_requests()

  local left, top, right, bottom = -BAY, -ROW, width + BAY, tall
  for _, thing in pairs(made.find_entities_filtered{
      area = { { left, top }, { right, bottom } } }) do
    if thing.valid and thing.type ~= "character" then thing.destroy() end
  end
  for _, drawn in pairs(rendering.get_all_objects("ce-demo")) do drawn.destroy() end

  -- The checkerboard the testing scenarios use. Solid white is too bright to look at for
  -- long, and a floor with no pattern in it gives the eye nothing to judge a tile against.
  local floor = {}
  for x = left, right do
    for y = top, bottom do
      floor[#floor + 1] = {
        name = ((x + y) % 2 == 0) and "lab-dark-1" or "lab-dark-2",
        position = { x, y },
      }
    end
  end
  made.set_tiles(floor)
  -- Tiles alone do not clear the ground: the grass and the rocks the generator scattered
  -- are decoratives rather than entities, and they survive both the tiling above and the
  -- sweep of entities before it.
  made.destroy_decoratives{ area = { { left, top }, { right, bottom } } }

  storage.pads = {}
  storage.hops = {}
  storage.lays = {}
  storage.marks = {}
  storage.bay_kits = {}

  -- The number in a heading is put on here rather than written into the title, so that a row
  -- left out leaves no hole in the counting: a showroom that goes seven, eight, eleven reads
  -- as one that has lost something.
  for index, row in ipairs(showing) do
    local rx, ry = row_at(index)
    label(rx, ry + 1, ("%d. %s"):format(index, row.title), row.note,
      row.vanilla == false and { 1, 0.65, 0.4 } or nil)

    -- the west pad, which kits whoever stands on it, and the east one, which moves them on
    pad(rx + 1, ry + 6, "refined-concrete")
    label(rx - 1, ry + 7.6, "STAND HERE",
      "for what this row wants", { 0.55, 0.9, 0.6 })
    -- Which entry of ROWS this is, remembered because the two numberings are not the same:
    -- the pads are numbered by what was laid out and ROWS holds every row there could be. A
    -- showroom with no AAI vehicles in it lays Leading eleventh while ROWS has a chaingunner
    -- eleventh, and standing on Leading's pad handed over the chaingunner's kit.
    storage.pads[index] = { west = { x = rx + 1.5, y = ry + 6.5 }, row = row.index }

    -- A row may ask for wider bays than the rest. Leading is the one thing here that needs
    -- room to happen in: an arm sets off for something ten tiles off and the walk that
    -- meets it is longer still, so a bay that fits a standing demonstration puts the next
    -- one's ghosts inside the walk.
    local wide = row.spread or BAY
    eastmost = rx
    for bay, what in ipairs(row.bays) do
      local x = rx + bay * wide
      -- A tile and a half down rather than three, so that three lines of note end above
      -- the marks at six rather than across them. Three lines is what every bay's note is
      -- held to for the same reason: there is no more room than that between a title and
      -- the ground the bay is laid out on.
      local bottom = label(x, ry + 1.5, what[1], what[2])
      building = { row = index, bay = bay, title = what[1], bottom = bottom }
      what[3](x, ry)
      building = nil
    end

    -- Past the end of the row rather than one bay along from the last one. Two tiles of
    -- clear ground either side, so that walking the last exhibit does not end with being
    -- carried off it, and so the pad is never touching the thing it stands beyond.
    local east = math.max(rx + (#row.bays + 1) * wide, math.ceil(eastmost) + 2)
    if index < #showing then
      pad(east, ry + 6, "refined-hazard-concrete-right")
      label(east - 2, ry + 7.6, "STAND HERE",
        row.vehicle and ("to go to row %d, vehicle and all"):format(index + 1)
          or ("to go to row %d"):format(index + 1), { 0.95, 0.8, 0.4 })
      storage.pads[index].east = { x = east + 0.5, y = ry + 6.5 }
    end

    if row.vehicle then
      local where = { rx + row.vehicle.at[1] + BAY, ry + row.vehicle.at[2] }
      local made_vehicle
      if row.vehicle.on_rail then
        -- A locomotive goes where a rail is rather than where the tape measure says: rails
        -- lie on a grid of their own and the one built for it is not quite where it was
        -- asked for.
        local rails = made.find_entities_filtered{
          position = { where[1] + 0.5, where[2] + 0.5 }, radius = 8,
          type = "straight-rail" }
        for _, rail in pairs(rails) do
          for _, facing in pairs{ rail.direction, (rail.direction + 8) % 16 } do
            if not made_vehicle then
              made_vehicle = made.create_entity{ name = row.vehicle.name,
                position = rail.position, direction = facing, force = "player" }
            end
          end
        end
        if not made_vehicle then
          log(("ce-demo: could not put a %s on the rail"):format(row.vehicle.name))
        end
      else
        made_vehicle = place(row.vehicle.name, where[1], where[2],
          { direction = row.vehicle.direction })
      end
      if made_vehicle then
        if row.vehicle.fuel then
          made_vehicle.insert{ name = row.vehicle.fuel, count = 50 }
        end
        local hold = made_vehicle
        if row.vehicle.wagon then
          -- On a rail rather than at a measured spot, for the same reason the locomotive
          -- is: rolling stock goes where the track lets it. Far enough back not to be the
          -- rail the locomotive is standing on, near enough to be the same train.
          local wagon
          local rails = made.find_entities_filtered{
            position = made_vehicle.position, radius = 12, type = "straight-rail" }
          table.sort(rails, function(one, other)
            local function away(rail)
              local dx = rail.position.x - made_vehicle.position.x
              local dy = rail.position.y - made_vehicle.position.y
              return dx * dx + dy * dy
            end
            return away(one) < away(other)
          end)
          for _, rail in pairs(rails) do
            local dx = rail.position.x - made_vehicle.position.x
            local dy = rail.position.y - made_vehicle.position.y
            if not wagon and (dx * dx + dy * dy) >= 36 then
              for _, facing in pairs{ made_vehicle.direction,
                                      (made_vehicle.direction + 8) % 16 } do
                wagon = wagon or made.create_entity{ name = row.vehicle.wagon,
                  position = rail.position, direction = facing, force = "player" }
              end
            end
          end
          if wagon then hold = wagon
          else log(("ce-demo: could not put a %s behind the %s"):format(
            row.vehicle.wagon, row.vehicle.name)) end
        end
        hold.insert{ name = "transport-belt", count = row.vehicle.belts or 200 }
        local grid = made_vehicle.grid
        if grid then
          -- Two of the third tier unless the row asks for something else. A spidertron and
          -- a locomotive ask for eight of the second, which is what makes their arms worth
          -- looking at: eight along a hull is where the mounting has something to say.
          local arms = row.vehicle.arms or { TIERS[3], TIERS[3] }
          for _, name in pairs(arms) do
            if not grid.put{ name = name } then
              log(("ce-demo: no room in the %s grid for %s"):format(row.vehicle.name, name))
            end
          end
          grid.put{ name = "fission-reactor-equipment" }
          grid.put{ name = "battery-mk2-equipment" }
          for _, piece in pairs(grid.equipment) do piece.energy = piece.max_energy end
        end
      end
    end
  end

  local ghosts = made.count_entities_filtered{ type = "entity-ghost" }
  local vehicles = 0
  for _, row in pairs(showing) do if row.vehicle then vehicles = vehicles + 1 end end
  local bays = 0
  for _, row in pairs(showing) do bays = bays + #row.bays end
  log(("ce-demo: built %d rows of %d, %d bays, %d ghosts, %d vehicles"):format(
    #showing, #ROWS, bays, ghosts, vehicles))

  for _, player in pairs(game.players) do
    if player.character then
      player.teleport({ 1.5, 6.5 }, made)
    else
      player.set_controller{ type = defines.controllers.god }
      player.create_character()
      player.teleport({ 1.5, 6.5 }, made)
    end
    kit(player, ROWS[1])
  end
end

-- --------------------------------------------------------------------------- the pads

--- Which row a player last had a kit from, so that standing on a pad does not hand them one
--- every tick for as long as they are on it.
local function on_pad(player, at)
  local dx, dy = player.position.x - at.x, player.position.y - at.y
  -- The mark's own tile and a little more, rather than a tile and a half either side of it.
  -- A mark is one tile precisely so that standing on it means standing where the bay was
  -- measured from, and a radius of one and a half carried people off who were walking past
  -- it rather than standing on it.
  return (dx * dx + dy * dy) < 0.64
end

script.on_event(defines.events.on_tick, function()
  if game.tick % 15 ~= 0 then return end
  local made = ground()
  if not (made and storage.pads) then return end
  storage.stood = storage.stood or {}
  storage.settled = storage.settled or {}
  for _, player in pairs(game.connected_players) do
    if player.surface == made and (player.character or player.vehicle) then
      -- Whether they have stopped. A mark that carries you off does it when you have come
      -- to rest on it, not the moment you cross it: walking east along a row of exhibits
      -- meant being snatched away from the one you were watching, and there is no way to
      -- pass a mark on foot without standing on it for a poll or two.
      local was = storage.stood[player.index]
      local at = player.position
      local put = was and math.abs(was.x - at.x) < 0.1 and math.abs(was.y - at.y) < 0.1
      -- Two polls of standing still rather than one. A poll is a quarter of a second, and
      -- one of them is satisfied by the pause between two steps or by a turn on the spot,
      -- which carried people off mid stride.
      local still = put and storage.settled[player.index]
      storage.settled[player.index] = put
      storage.stood[player.index] = { x = at.x, y = at.y }

      -- Standing on a mark kits you once. Stepping off it and back on kits you again, which
      -- is what somebody who has spent their belts wants: the marks were one use only.
      local anywhere = false
      for _, pads in pairs(storage.pads) do
        if on_pad(player, pads.west) or (pads.east and on_pad(player, pads.east)) then
          anywhere = true
        end
      end
      for _, bay in pairs(storage.bay_kits or {}) do
        if on_pad(player, bay) then anywhere = true end
      end
      if not anywhere then storage.standing = nil end

      local jumped = false
      if still then
        for _, jump in pairs(storage.hops or {}) do
          if on_pad(player, jump.from) then
            local riding = player.vehicle
            if riding and riding.valid then riding.teleport({ jump.to.x + 3, jump.to.y }) end
            player.teleport({ jump.to.x, jump.to.y }, made)
            storage.stood[player.index] = { x = jump.to.x, y = jump.to.y }
            -- Charged on arrival. An arm will not set off until its own buffer is full and
            -- a fourth tier arm's is ten times a first tier arm's, so a character put down
            -- among four ghosts with a half empty grid watches the short arms go first and
            -- the long ones follow several ticks later. That is the grid filling up, not
            -- the arms choosing, and this bay is about the choosing.
            local armour = player.get_inventory(defines.inventory.character_armor)[1]
            if armour and armour.valid_for_read and armour.grid then
              for _, piece in pairs(armour.grid.equipment) do
                piece.energy = piece.max_energy
              end
            end
            jumped = true
            break
          end
        end
      end

      -- A bay that wants something other than its row's kit. No teleport, so no waiting:
      -- standing on it is the whole of the instruction.
      if not jumped then
        for number, bay in pairs(storage.bay_kits or {}) do
          if on_pad(player, bay) and storage.standing ~= "bay" .. number then
            kit(player, { kit = bay.kit })
            storage.standing = "bay" .. number
            jumped = true
            break
          end
        end
      end

      -- Laid once the kit is settled rather than before it. A bay that swaps your arm for
      -- a smaller one wants the smaller one looking at its ghosts: laid first, the arm the
      -- player walked in wearing gets a look at them, and the bay is about the other one.
      for _, lay in pairs(storage.lays or {}) do
        if on_pad(player, lay.at) then lay_out(lay) end
      end

      for index, pads in pairs(storage.pads) do
        if jumped then break end
        if pads.east and on_pad(player, pads.east) then
          -- Only once they have stopped on it, for the same reason the hops wait.
          local next_row = storage.pads[index + 1]
          if still and next_row and storage.standing ~= index + 1 then
            -- A player in a vehicle cannot be teleported out from under it: the vehicle
            -- goes too, or nothing moves and the message repeats at somebody sitting still
            -- on the pad.
            local riding = player.vehicle
            if riding and riding.valid then
              riding.teleport({ next_row.west.x + 3, next_row.west.y })
            end
            player.teleport({ next_row.west.x, next_row.west.y }, made)
            storage.stood[player.index] = { x = next_row.west.x, y = next_row.west.y }
            local went_to = ROWS[next_row.row]
            kit(player, went_to)
            storage.standing = index + 1
            player.print(("%d. %s -- %s"):format(index + 1, went_to.title, went_to.note))
          end
          break
        elseif on_pad(player, pads.west) and storage.standing ~= index then
          local stood_on = ROWS[pads.row]
          kit(player, stood_on)
          storage.standing = index
          player.print(("%d. %s -- %s"):format(index, stood_on.title, stood_on.note))
          break
        end
      end
    end
  end
end)

script.on_init(function()
  if remote.interfaces["freeplay"] then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
  clear_and_build()
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not ground() then clear_and_build() end
  player.teleport({ 1.5, 6.5 }, ground())
  kit(player, ROWS[1])
  storage.standing = 1
end)

commands.add_command("ce-demo", "Build the showroom again", function()
  clear_and_build()
  storage.standing = nil
end)

--- What the probe drives the showroom through. See test/demo/probe.sh: a bay that misbehaves
--- in the showroom and behaves in the tests is a difference between the two, and the only
--- way to find it is to work the showroom itself rather than a replica of it.
remote.add_interface("ce-demo", {
  ---Every mark, in the order the rows were built.
  marks = function() return storage.marks or {} end,
  ---Give a player exactly what a row wants, the same as standing on its west pad does.
  kit = function(player_index, row)
    local player = game.get_player(player_index)
    -- By the number on the ground rather than the place in ROWS, which is what the probe
    -- and anybody reading the showroom sees.
    local pads = (storage.pads or {})[row]
    local wanted = pads and ROWS[pads.row] or nil
    if player and wanted then kit(player, wanted) end
  end,
  ---Which surface it all stands on.
  surface = function() return SURFACE end,
})
