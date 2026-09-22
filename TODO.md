# Outstanding

## 12. The walking penalty is switched off

tiers.SLOWS, with thirty tests skipped behind it. It is not only a cost: a slower wearer has
a wider cone, so putting it back makes the low tiers reach further to the side than they do
now.

Everything else under 12 is done. Leading, the cone test, the single-pass choose() and the
oriented search box are all in, and what each of them cost and bought is written where it
was decided -- reach.cone, reach.search_box and choose() in control.lua carry their own
measurements.

## 20. Deconstruction leaves items behind

About one in twenty items picked up from around three and a half tiles away is left on the
ground, without even its deconstruct marker.

**Reproduced on the showroom's chest downgrade bay.** The arm takes something like thirty
seconds to pick up what is lying near it, and drops some of it around four tiles from the
player. That is the bay to work from; what follows is what could not be got out of a bare
ring.

Not reproduced by laying rings out, over eight layouts counted to the last item: rings of twenty four marked
belts at 2.5, 3.0, 3.5, 4.0 and 4.5 tiles, a ring of marked loose stacks rather than things
standing, the same ring worked by a second tier arm, and a line of twenty walked past. Every
one of them balances -- what was laid out equals what came home, plus what is still standing,
plus what is on the ground, plus what is in a claw, a box or an escrow -- and in none of them
is anything on the ground at all.

Run against the code as it was before the round of fixes this note sits under as well, in
case one of them had quietly cured it, and the numbers are identical. So it is not that this
was fixed; it is that these are not the layouts it was seen on. Like 9 and 16, it wants the
bay or the save it happened in.

## 22. The crossing horizon, if anybody opens it up

Settled for now: a seventh is off every tier's rotation, which is as much as the swing
carries. A third, which is what was asked for, costs a claw its crossings.

The reason given for opening the horizon up to allow more does not survive a look at it.
reach.any_way, the turning half of the horizon, is already 0.5 / rotation, so slowing the
turn widens the horizon by itself. Where a refused crossing is actually refused wants
measuring before that number is touched.

## The equipment's own quality does nothing

A legendary arm reaches and swings exactly as far and as fast as a common one. Everything
about a tier -- its reach, its extension and rotation speeds, what its claw holds, what its
buffer holds -- comes from lib/tiers.lua by level alone, and nothing anywhere reads the
quality of the piece in the grid.

What the mod does already handle is the quality of the *work*: a ghost of a legendary belt
is paid for with a legendary belt, an upgrade to one takes one, and everything that moves an
item moves it at its own quality. That half is done. It is the equipment itself that is
inert.

What a quality arm should buy is a question before it is a change. Reach is the obvious
candidate and the loudest: it is what decides how often a player has to stop and stand
somewhere else, and a fifth tile is worth more than the throughput figure shows -- see the
note on the fourth tier's price in lib/tiers.lua. Speed and buffer are the quieter ones. The
base game's own scaling for equipment is a place to start rather than a thing to copy, since
a grid's worth of arms is not a solar panel.

Whatever it buys has to come out of the same one number per tier the rest of lib/tiers.lua
is built on, or the progression stops being checkable: no tier, at any quality, may end up
worse than the tier below it at the same quality.

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
| `test/ft/grabbing.lua` | an idle claw over a chest and over a vehicle's hold, which is what the barred box at the rest point exists to stop. |
| `test/ft/bare.lua` | the deconstruction stall with no mod in the loop: one inserter driven by hand through the same cycle. |
| `test/ft/vanilla.lua` | the same in base game prototypes only, and it runs the console commands in `test/stall/console.lua` as written so what is handed to somebody is what is tested. |
| `test/stall.sh` | a real game laid out on the standing-still stall, with markers drawn for the claw, both ends of the swing and the boxes. `/ce-rig` builds the minimal version of it. |
| `test/demo/run.sh` | the showroom, which is where 20 was seen. |

Two engine behaviours found along the way are written up in `factorio/CLAUDE.md` rather than
here, since they are the game's rather than this mod's: an inserter will not move its hand at
all when its pickup or drop falls on a tile holding something marked for deconstruction, and
find_entities_filtered honours a BoundingBox orientation.
