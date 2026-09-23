# Outstanding

## 12. The walking penalty is switched off

tiers.SLOWS, with thirty tests skipped behind it. It is not only a cost: a slower wearer has
a wider cone, so putting it back makes the low tiers reach further to the side than they do
now.

Everything else under 12 is done. Leading, the cone test, the single-pass choose() and the
oriented search box are all in, and what each of them cost and bought is written where it
was decided -- reach.cone, reach.search_box and choose() in control.lua carry their own
measurements.

## 22. The crossing horizon, if anybody opens it up

Settled for now: a seventh is off every tier's rotation, which is as much as the swing
carries. A third, which is what was asked for, costs a claw its crossings.

The horizon itself is no longer a sum. reach.longest used to add the stretch to the turn,
which is not what a journey costs: the engine runs both speeds at once and neither waits on
the other, so it is the greater of them. It is max() now, and the worst journey an arm can be
asked for -- a hand at its own base with half a turn to make -- still sits inside it, so
nothing reachable was lost. Measured: the train of `test/ft/turning.lua` builds 209 and 226
either way, to the ghost.

Which half binds is now a per-tier question, and that is what the old reasoning missed:

| tier | stretch | turn | horizon | binds |
| --- | --- | --- | --- | --- |
| 1 | 57.1 | 42.0 | 57.1 | the stretch |
| 2 | 60.0 | 29.4 | 60.0 | the stretch |
| 3 | 40.0 | 58.8 | 58.8 | the turn |
| 4 | 50.0 | 73.5 | 73.5 | the turn |

So "slowing the turn widens the horizon by itself" is true only where the turn is already the
binding half. Take a third off instead of a seventh and tiers 3 and 4 widen, from 58.8 to
75.0 and from 73.5 to 93.8; tiers 1 and 2 do not move at all, because the stretch still
binds. If a slower turn costs the low tiers their crossings, the horizon will not be what
gives it back.

What is still unmeasured is whether the horizon is what refuses a crossing at all. Narrowing
it by a third on the fourth tier and by two fifths on the first cost nothing anywhere in the
suite, which is evidence that it is not -- the refusals are coming from somewhere else, and
where wants finding before that number is touched.

## Mods with vehicle and equipment categories of their own

Everything the mod knows about what can carry an arm is written down here rather than asked.
The equipment sits in the "armor" category and nothing else, and the vehicles it expects are
the ones the base game ships plus whatever test/ft/ce-tests hands a grid to.

**Krastorio 2 is the worked case, and it costs the arms every vehicle.** Read off the data
stage of a real load -- Factorio 2.1.20, Krastorio2 2.1.2, this mod, and a probe mod that
asks each vehicle's grid whether it would take an arm:

| where | grid | takes | an arm fits |
| --- | --- | --- | --- |
| car | kr-car-grid | kr-vehicle, kr-vehicle-motor, kr-vehicle-roboport | **no** |
| tank | kr-tank-grid | the same three | **no** |
| locomotive | kr-locomotive-grid | kr-vehicle, kr-vehicle-motor | **no** |
| cargo, fluid and artillery wagons | kr-wagons-grid | kr-vehicle, kr-vehicle-roboport | **no** |
| spidertron | kr-spidertron-equipment-grid | the same three | **no** |
| modular, power, power mk2 armour | the base grids | armor | yes |
| K2's own mk3 and mk4 armour | kr-mk3/mk4-armor-grid | armor | yes |

So on foot everything works, in K2's own armours too, and no vehicle will take an arm at all.

It is deliberate rather than an oversight. K2 declares three categories of its own --
kr-vehicle, kr-vehicle-motor, kr-vehicle-roboport -- and re-grids all seven base vehicles
through one helper, which carries the old grid's categories across **except** "armor":

    if equipment_category ~= "armor" and not equipment_categories_set[equipment_category]

Its own equipment then opts back in by declaring both, `categories = { "armor", "kr-vehicle" }`,
and a fixed list of nine base pieces is hand-patched the same way -- the batteries, the
shields, the solar panel, the fission reactor, belt immunity, and the two laser defences.
Three base pieces are deliberately left out and are armour-only under K2: the exoskeleton,
night vision, and the personal roboport. There is no sweep over everything carrying "armor",
so a third party's equipment is never on the list.

**Done, and no mod is named to do it.** data-final-fixes looks at what the seven vehicles the
mod already knew about will take now, and works out the fewest categories that get an arm back
onto all of them -- see lib/grids.lua. On K2 that is the single kr-vehicle, which is what its
own equipment declares, and the two narrow categories are left alone. In a game nobody has
overhauled every one of those grids still takes "armor", so the answer is empty and nothing
is added at all: measured, the equipment carries [armor] and no more.

Re-measured after, on the same load: yes to the car, the tank, the locomotive, all three
wagons and the spidertron, and still yes to all five armours.

What is still unmeasured are the other two failures the old note guessed at -- a vehicle whose
arms are never mustered, and a hull pack.lua has no opinion about and mounts everything in the
middle of. Neither could be reached while the equipment would not go into the grid at all, and
both want a game that actually runs to look at.

A caveat on the measurement: Krastorio2 2.1.2 does not finish loading on Factorio 2.1.20 at
all, failing on its own `wood` prototype with `ItemPrototype::fuel_category was removed`,
which the log attributes to "Base mod > Krastorio 2" and which has nothing to do with this
mod. The data stage completes, so what is written above is what the two mods really agree
on; it is not a thing a player can sit down and play today.

## A claw that goes home before it goes out

One sighting from the showroom, still to be run down.

**A tap of movement.** Stand about 2.1 tiles from a ghost with a first tier arm and tap a
movement key towards it. The arm sets off with a lead, comes home because its owner stopped
at the end of the tap, and then sets off again for a standing delivery. It should have gone
on delivering from the first departure: the ghost never left its reach, and the only thing
that changed was the drift going back to nothing.

Walk it in the showroom again before anything else. It does not reproduce in a headless
fixture: taps of two to thirty ticks at ghosts two to six tiles off and up to two to the
side, stopped both on a tick count and on the tick the lead is taken -- in every one of them
the claw went straight out. What that sweep did find was another fault of the same family,
which has gone since this was seen, and it may have gone with it.

If it survives, the suspect left is aim() pointing the drop at the rest point on a tick
where the job is not yet set, which is the shape of the bug fixed in redirect() -- see the
commit about a fetch's three ends, and whether the same hole is open on the first tick of a
job rather than on a crossing.

## Clearing a heap is eighty trips, and nothing else happens meanwhile

An arm clearing eighty plates from under its owner's feet takes about 1150 ticks whatever
order it works in, because a first tier claw carries one plate a trip and that is eighty
trips of some fourteen ticks. Nothing else about heap clearing is worth looking at until
that number moves.

While it grinds, the arm does nothing else: a marked belt two tiles away waits for the whole
heap. Measured, the last of eight things laid round a heap of eighty went at tick 726 against
345 back when the heap was priced to go last. Working the nearest thing first is right and is
what it does now, but a round that scoops eighty plates and then ferries them one at a time
is a long thing to be committed to.

Two places to look. `loot_into` fills the box by whole entities until the round's room is
used, so a heap of ten-plate stacks overshoots what the claw can carry and the rest is
ferried; capping a round at what one trip can hold would cut the commitment rather than the
work. And nothing lets an arm part way through a long round take something else first, which
is what would stop a heap blocking a belt.

Watch on the next walk which of the two a player actually minds.

## An arm on a train at speed, which no longer looks like a fault

Does not reproduce. Left here as a thing to look at on the next walk rather than as work,
because the sighting was made in the showroom and everything below is a fixture.

The report was that with belt ghosts either side of a long enough track nothing is built at
all at full speed. Driven for real over 2400 tiles of rail, with the showroom's own train
bay copied -- solid fuel, eight second tier arms, a mk2 battery, ghosts two tiles out on each
side -- a locomotive reaches 1.262 tiles a tick and builds all the way up:

| tiles a tick | ghosts carried past | built |
| --- | --- | --- |
| 0.4 to 0.6 | 80 | 37 |
| 0.6 to 0.8 | 146 | 63 |
| 0.8 to 1.0 | 264 | 128 |
| 1.0 to 1.4 | 1300 | 587 |

Forty five to forty eight in every hundred, at every speed including the top one, and the
same 182 of 390 at a forced constant 1.203 whether the mod is the current one or the tree as
it stood before any of this week's work. So nothing recently fixed it and nothing recently
broke it; the fixture has never seen it.

What limits the arms is not speed but how many of them there are. Eight arms carried past
1300 ghosts in the fastest band; to have taken all of them each swing would have had to place
about a dozen belts. If more of a dense field is wanted at speed, that is the number to argue
with rather than the horizon or the cone.

So the thing to do is walk the showroom train again and see whether it still happens there.
If it does, what differs is in the showroom's own setup rather than in the arms, and the two
fixtures below are the place to put whatever that turns out to be.

## What there is to work with

Fixtures and harnesses built for the items above, so that picking one up does not start from
nothing. All of `test/ft` runs from `test/ft/run.sh`; a name is a Lua pattern, so
`test/ft/run.sh turning` runs one file's worth.

| where | what it measures |
| --- | --- |
| `test/ft/turning.lua` | a train along a double line of ghosts, counting the ones an arm set off for and never delivered to, and the worst number of attempts on any one of them. It passes now; it is what a claw changing its mind shows up in. Three forced speeds up to the locomotive's own maximum, and a fourth case that drives one for real through every speed and counts what each band builds. |
| `test/ft/swinging.lua` | a bare inserter turning and stretching at once, tick by tick; one re-aimed part way through a swing; and one making a turn and nothing else at a fixed radius. Between them they pin the law, the tick of grace each half of it gets, and how far the drawing strays from the state. |
| `test/ft/resting.lua` | where a fresh hand is born, where a folding one stops, and the curve a claw takes home when its rest point sits exactly on the arm's base. |
| `test/ft/chasing.lua` | a belt in reach of a standing arm whose owner then walks over it, from every phase of the check tick, which is what says whether a ghost met before the walk is still led once there is one. |
| `test/ft/following.lua` | the two numbers control.lua carries for a hand, run against a real inserter through a walk's worth of re-aims. |
| `test/ft/searching.lua` | four search shapes over sixteen scenarios, asserting each holds everything reach.meets says is there and logging what each costs. |
| `test/ft/chunkful.lua` | a whole chunk of the mixed ghosts a blueprint is made of, for what a tick costs one arm in a realistic field, and four arms walking it for what actually gets built. |
| `test/ft/underfoot.lua` | every kind of job placed under its owner's feet and one and three tiles off, and the same under a tank. HEAP walks six ratios of work underfoot to work round it and times each to completion; FIELD lays one kind of item both underfoot and out, which is the showroom's case. |
| `test/ft/losing.lua` | every belt in the arena counted every tick while a train builds a line, with a dump of the ticks round any that goes missing. |
| `test/ft/qualities.lua` | a quality piece in the grid, the arm it makes, and what each quality is worth in ticks. |
| `test/ft/spilling.lua` | the showroom's chest downgrade, which sheds sixteen hundred plates for the arms to clear, watching every tick for anything that ends up on the ground without a marker. |
| `test/ft/grabbing.lua` | an idle claw over a chest and over a vehicle's hold, which is what the barred box at the rest point exists to stop. |
| `test/ft/bare.lua` | the deconstruction stall with no mod in the loop: one inserter driven by hand through the same cycle. |
| `test/ft/vanilla.lua` | the same in base game prototypes only, and it runs the console commands in `test/stall/console.lua` as written so what is handed to somebody is what is tested. |
| `test/stall.sh` | a real game laid out on the standing-still stall, with markers drawn for the claw, both ends of the swing and the boxes. `/ce-rig` builds the minimal version of it. |
| `test/demo/run.sh` | the showroom, which is where 20 was seen. |

Two engine behaviours found along the way are written up in `factorio/CLAUDE.md` rather than
here, since they are the game's rather than this mod's: an inserter will not move its hand at
all when its pickup or drop falls on a tile holding something marked for deconstruction, and
find_entities_filtered honours a BoundingBox orientation.
