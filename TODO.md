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

## A hand part way through a big turn is not where its claw is drawn

reach.on_it is right, and this entry used to say it was wrong. The law it carries -- the
radius inside out +/- extension * (k + 1), the bearing inside rotation * 2pi * k, both at the
same k -- is the law the engine flies. Extension and rotation are two speeds it runs at once
and neither waits on the other, so a hand told to go somewhere arrives on the greater of the
two times. Measured over three tiers, five bearings and two radii in `test/ft/swinging.lua`,
the engine landed on the tick max() names every time, never later than it and at worst a tick
before, which is its last step covering whatever gap is left rather than creeping up on it.

What the old entry measured was a hand on its way to a *further* target passing through a
band that describes arriving at a nearer one, which those two inequalities never claimed
anything about. The real fault is underneath: **the state the law is asked of.**

hand_out() and hand_facing() take the hand's radius and bearing from held_stack_position,
which is where the claw is *drawn*. Past about two thirds of a turn that is not where the
engine's arm is: the drawn hand runs ahead of its own state in the radius and in the bearing
at once, and comes back to it by the end of the turn. In the model's own two numbers, each
already allowed the one step of grace on_it gives it:

| turn | radius | bearing |
| --- | --- | --- |
| up to 120 degrees | nothing at all | nothing at all |
| 135 degrees | 0.011 to 0.072 tiles | 0 to 2.4 degrees |
| 150 degrees | 0.140 to 0.201 | 2.6 to 5.5 degrees |
| 180 degrees | 0.504 to 0.559 | 5.8 to 11.3 degrees |

The same on all three tiers measured, which is what says it is the drawing rather than a
speed. Decomposed, the drawn hand is the state plus an offset that lies along the world's own
vertical whichever way the arm faces, nought at both ends of the turn and widest in the
middle.

Fed the drawn hand, the arithmetic comes out **optimistic**. Ninety re-aims of a loaded claw
part way through a swing, timed to the delivery: where the swing was a half turn, the drawn
hand's answer was short of what it actually took on 39 of them, by as much as twelve ticks.
Asked of the state instead -- the birth radius carried out at the extension speed, the birth
bearing carried round at the rotation speed -- the same arithmetic was right to the tick on
all ninety.

So an arm still sets off for what it cannot get to in the time it thinks, and that is what is
left of this.

ADRIFT, the four ticks of grace a course gets before the claw gives it up, is no longer what
stops the flicker. With the crossing test fixed, `test/ft/turning.lua` reports one attempt on
any ghost at either speed whether the grace is four ticks or one. What it still buys is small
and pulls both ways -- 202 and 225 built with it against 204 and 220 without -- so it stays
until something measures it properly.

**What a fix needs.** The engine's own two numbers, carried by the mod rather than read back:
a radius moving toward whatever end the arm is chasing at the tier's extension speed, and a
bearing moving toward it at the tier's rotation speed, both reset to reach.BORN and the built
direction whenever point() builds the arm again. Nothing in the API offers them -- orientation
reads nought on an inserter, see point() -- so they have to be integrated tick by tick. What
that has to survive: an arm with no charge, whose hand does not move while the sum would; the
ends being re-aimed outside aim(), which redirect() and deliver() both do; and the tick the
load leaves the hand, where which end is being chased changes.

`test/ft/swinging.lua` is the fixture. It holds the drawn hand to its state up to 120 degrees,
records the gap past that, and times a re-aimed claw against both readings; a fix is what lets
the drawn hand be held to its state at every turn.

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
| `test/ft/swinging.lua` | a bare inserter turning and stretching at once, tick by tick, and one re-aimed part way through a swing. This is where the law is measured right and the state it is asked of is measured wrong. |
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
