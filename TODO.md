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

Two sightings from the showroom, which may be one fault:

**A tap of movement.** Stand about 2.1 tiles from a ghost with a first tier arm and tap a
movement key towards it. The arm sets off with a lead, comes home because its owner stopped
at the end of the tap, and then sets off again for a standing delivery. It should have gone
on delivering from the first departure: the ghost never left its reach, and the only thing
that changed was the drift going back to nothing.

**The toolbar button.** Switch the arms on while standing in reach of a ghost. The arm
appears already holding a belt and already part way out -- which will be reach.BORN, the
179/256 of a tile a fresh hand is born at -- then retracts all the way to its owner before
extending out to the ghost. It should go straight there.

Walk both in the showroom again before anything else. Neither reproduces in a headless
fixture: taps of two to thirty ticks at ghosts two to six tiles off and up to two to the
side, stopped both on a tick count and on the tick the lead is taken, and the button pressed
with a ghost two tiles off to each of the four sides -- in every one of them the claw went
straight out. What that sweep did find was a third fault of the same family, which has gone
since these were seen, and either of them may have gone with it.

If they survive, the suspect left is aim() pointing the drop at the rest point on a tick
where the job is not yet set, which is the shape of the bug fixed in redirect() -- see the
commit about a fetch's three ends, and whether the same hole is open on the first tick of a
job rather than on a crossing.

## A heap underfoot is worked last, and should be worked first

The showroom's chest downgrade sheds its plates around and under the player, and the ones
under the player go last. They should go about first: they are the nearest thing there is.

choose() charges work underfoot an extra full extension -- `price + tier.range /
tier.extension` -- on the grounds that taking something up from under the base is the slowest
swing there is, since the hand comes all the way in and whatever is next has to go all the
way out again. That reasoning was measured on a heap with other work round it and it is
right for a claw choosing between one thing underfoot and one thing at arm's length.

It is wrong for a heap that is mostly underfoot. When the next job is another plate off the
same heap, the hand does not have to go all the way out again, so the charge is paying for a
journey that never happens. What is wanted is a price that knows what the next job is likely
to be, or an underfoot charge that falls away when the work is dense.

## An arm on a train at speed builds nothing

Lay two rows of belt ghosts on each side of the track, extend the track to three times the
showroom's length so the train reaches full speed, and at full speed nothing is built at all.

It should be able to. A claw does not have to chase a ghost: it is held on a lead, a point
fixed in the arm's own frame, and the ghost sweeps onto it. A second tier arm wants 26 ticks
to reach two tiles abeam, and a locomotive at full speed covers about 36 tiles in that time,
so the arm has to set off when the ghost is some 36 tiles ahead -- which is inside the 46
ticks of horizon a second tier swing has, and ought to be inside what the search brings back.

So the suspicion is the shape of what is searched or sieved at high drift rather than the
horizon: reach.search_box, reach.cone, or the abeam half of either. Worth measuring what
comes back and what is turned away at a locomotive's top speed before touching any of them.
`test/ft/turning.lua` already drives a train, but at 0.3 and 0.6 tiles a tick against a top
speed nearer 1.4, so the speeds this happens at are not covered by anything.

## What there is to work with

Fixtures and harnesses built for the items above, so that picking one up does not start from
nothing. All of `test/ft` runs from `test/ft/run.sh`; a name is a Lua pattern, so
`test/ft/run.sh turning` runs one file's worth.

| where | what it measures |
| --- | --- |
| `test/ft/turning.lua` | a train along a double line of ghosts, counting the ones an arm set off for and never delivered to, and the worst number of attempts on any one of them. It passes now; it is what a claw changing its mind shows up in. |
| `test/ft/swinging.lua` | a bare inserter turning and stretching at once, tick by tick; one re-aimed part way through a swing; and one making a turn and nothing else at a fixed radius. Between them they pin the law, the tick of grace each half of it gets, and how far the drawing strays from the state. |
| `test/ft/chasing.lua` | a belt in reach of a standing arm whose owner then walks over it, from every phase of the check tick, which is what says whether a ghost met before the walk is still led once there is one. |
| `test/ft/following.lua` | the two numbers control.lua carries for a hand, run against a real inserter through a walk's worth of re-aims. |
| `test/ft/searching.lua` | four search shapes over sixteen scenarios, asserting each holds everything reach.meets says is there and logging what each costs. |
| `test/ft/chunkful.lua` | a whole chunk of the mixed ghosts a blueprint is made of, for what a tick costs one arm in a realistic field, and four arms walking it for what actually gets built. |
| `test/ft/underfoot.lua` | every kind of job placed under its owner's feet and one and three tiles off, and the same under a tank. |
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
