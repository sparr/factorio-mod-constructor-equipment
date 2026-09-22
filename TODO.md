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
The equipment sits in categories this mod names, and the vehicles it expects are the ones the
base game ships plus whatever test/ft/ce-tests hands a grid to. A mod that adds a vehicle
with a grid of its own, or an equipment category of its own, is not considered anywhere.

What that is likely to cost: an arm that will not go into a grid it would fit, a vehicle
whose arms are never mustered, or a hull whose shape pack.lua has no opinion about and
mounts everything in the middle of. None of it is measured -- there is no fixture with a
modded vehicle in it -- so the first thing is to find out which of those actually happen.

## What there is to work with

Fixtures and harnesses built for the items above, so that picking one up does not start from
nothing. All of `test/ft` runs from `test/ft/run.sh`; a name is a Lua pattern, so
`test/ft/run.sh turning` runs one file's worth.

| where | what it measures |
| --- | --- |
| `test/ft/turning.lua` | a train along a double line of ghosts, counting the ones an arm set off for and never delivered to, and the worst number of attempts on any one of them. It passes now; it is what a claw changing its mind shows up in. |
| `test/ft/swinging.lua` | a bare inserter turning and stretching at once, tick by tick; one re-aimed part way through a swing; and one making a turn and nothing else at a fixed radius. Between them they pin the law, the tick of grace each half of it gets, and how far the drawing strays from the state. |
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
