# Outstanding, from the walks round of 2026-09-19 and 2026-09-20

## 12. An arm should aim where its target will be, not where it is

Done for one delivery from rest, for an arm that is already out, and for a claw working
several ghosts in a round. An arm works out where its target will be by the time its hand
could get there, holds the claw on that point as its owner carries it along, and drops the
guess for the thing itself the moment it is really in reach. A ghost that is in reach for
forty ticks against a forty three tick reach could not be built at all before and is built
now. Every tier leads; the first one meets things three times its own reach away. The
bearing a claw has to swing through is part of the sum, so a lead it cannot rotate onto in
time is not offered. All three ways a claw changes its mind mid flight -- the ghost being
taken away, a round moving on to its next, and a turn leaving the course unflyable -- are
exercised against a moving owner. A round is shopped for over its own life rather than over
the one swing the tick's search covers, since a claw refills at home and nowhere else, so
what it sets off carrying is all it will put down that journey.

What an arm cannot do is reach something square abeam of a walk, because the hand extends
slower than its owner walks: about 1.07 tiles at walking pace. Three ghosts crammed inside
that at full speed get two of them, and the same three at half speed get all three. That is
the shape of the cone rather than anything to fix.

What is left.

**The search is wider than it needs to be, and it is now measured what to do about it.**
It draws one circle round a capsule that assumes full stretch from the first tick, hands
every candidate to choose(), and choose() prices each one with a swing and then sorts the
lot. `test/ft/searching.lua` measures four shapes over sixteen scenarios -- two tiers, two
densities, four speeds -- and three ways of handling what they hand back. Every shape holds
everything reach.meets says is really there, so correctness is equal and it is all cost.

find_entities_filtered does honour a BoundingBox orientation: a flat box over a diagonal
line of fifteen ghosts found three of them, and the same box turned found all fifteen.

Microseconds a call, best of three runs of three hundred, on a machine carrying a load
average of two. Tier four, packed, at a train's speed:

| shape | candidates | search | search and sift | sift after a cone test |
| --- | --- | --- | --- | --- |
| capsule, which is what is drawn now | 673 | 188 | 5536 | 1704 |
| the cone's own circle | 490 | 405 | 4010 | 1733 |
| chain of 4 | 242 | 293 | 1848 | 1444 |
| chain of 8 | 198 | 395 | 1644 | 1490 |
| oriented box | 275 | 100 | 2039 | **1380** |

Three things, and the first is much the biggest.

**The sift is the cost, not the search.** Pricing and sorting the candidates runs ten to
thirty times what the engine call costs -- 5536 against 188 for the capsule. So the number
of candidates is what matters, and any judgement made on search time alone is wrong.

**Reject outside the cone with arithmetic, before pricing anything.** A dot product along
the cone's axis, a cross product across it, and a compare against a half width that flares
with the hand and stops at the reach. That one change takes the shape the mod already draws
from 5536 to 1704, better than three times, and it needs no new search at all. Sieving with
reach.meets instead is worse than not sieving: it is a quadratic solve per candidate and
costs 2533 where the arithmetic costs 1490.

**With that in front of it, the oriented box is the shape.** Its extra candidates stop
mattering once they are thrown away for a few flops, and it is the cheapest call there is:
best or equal best in every moving case, at 1380 against the capsule's 1704 here and 780
against 1194 at tier two. Standing still the capsule still wins, as a square round a circle
should. A chain is never worth its extra calls.

So: the cheap cone test first, then the box while its owner moves and the circle while they
stand. Together that is 5536 microseconds to 1380 at tier four in a packed field behind a
train, and 4694 to 780 at tier two.

**Done: the cone test and the scan are in.** reach.cone and reach.in_cone draw the cone as
arithmetic, and choose() no longer sorts. It keeps the best candidate as it goes, skips
anything outside the cone before pricing it, skips the turn -- two arctangents -- for
anything whose stretch alone already costs more than the best so far, and runs the
acceptance test only for a candidate that would take the lead. Measured on a packed field
behind a train at the fourth tier: 5629 microseconds a search to 388.

On a chunkful of the mixed ghosts a blueprint is really made of -- 128 belts, 128 inserters,
24 assemblers, 24 chests, in `test/ft/chunkful.lua` -- a search costs 88 microseconds
standing still against 33, 321 walking against 67, and 680 in a car against 139.

**Done: the shape as well.** work_near draws a box lying along the walk wherever its owner
is moving, and the circle where they are not -- reach.search_box, which hands back nothing
at all standing still so that the caller falls back by itself. All four of work_near's
searches share the shape, so the saving is four times over.

Per search on the chunkful, order rotated between runs and each warmed up first, because
whichever pipeline goes last goes fastest and two doing identical work differed by two to
one on position alone:

| | candidates, circle then box | sorted, as it was | scanned | box and scanned |
| --- | --- | --- | --- | --- |
| standing still | 23, 23 | 99us | 30us | 33us |
| walking | 61, 49 | 324us | 75us | 52us |
| in a car | 122, 60 | 697us | 149us | 81us |

Standing still the box is the circle, since search_box declines, and the two differ only by
noise. Moving, the whole is six to nine times what it was.

Nothing is left of 12 but the walking penalty below.

**The walking penalty is switched off.** tiers.SLOWS, with thirty tests skipped behind it.
It is not only a cost: a slower wearer has a wider cone, so putting it back makes the low
tiers reach further to the side than they do now.

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

## 22. An arm turns too fast

A seventh is off every tier's rotation and that is as much as the swing carries without
opening the crossing horizon up to match. Measured over the whole fixture suite: a third
off, which is what was asked for, costs a claw its crossings -- a row of four two tiles
abeam went from four built on one journey to two over two, and a block of nine marked for
deconstruction wanted thirty of the harness's cycles where it had wanted six. A quarter off
still loses a walk past marked things and a bulk claw's round of four. A fifth off costs
nothing any fixture measures.

Settled there. The horizon is left alone: a claw gives up a crossing it cannot make the next
bearing for in time, and opening that up is what would let the full third come off, but a
seventh is what the arms keep for now.

One thing to check before anybody opens it. reach.any_way, which is the turning half of the
horizon, is already 0.5 / rotation -- so slowing the turn widens the horizon by itself, which
undercuts the idea that the horizon is what a slower turn runs into. Where a refused crossing
is actually refused wants measuring before the number is touched.

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

## A meeting planned behind the arm is fragile, and ADRIFT covers for it

Half of this is fixed. A course was being decided with no turn charged at all, because
hand_facing() gave no bearing for any arm that *could* be rebuilt -- on the grounds that the
bearing was about to be whatever it needed to be. point() only rebuilds when it has a reason
to, and over a train run 167 of 186 calls refused while 5 rebuilt, so the bearing usually
survives. It asks what point() will really do now.

What is left is the other half. Some flips have a bearing on both ticks and flip anyway:

    t2474 offset 4.481,1.948  facing -0.823,-0.568 -> 19
    t2477 offset 3.583,1.948  facing -0.968,-0.249 -> nil

The ghost is ahead by three and a half tiles and the hand points almost due west, because the
lead is behind the arm: at arrival nineteen with a drift of 0.3 the meeting point is a tile
and a half back down the track. The train has passed the thing and the plan is to reach
backwards for it while being pulled away. The arithmetic is honest and the answer is fragile,
and a tick of drift takes it away.

Measured with the bearing fixed and no grace at all, that alone still leaves eight ghosts at
a quarter of a tile a tick set off for and never delivered, worst five attempts. So ADRIFT is
still doing real work and is still a plaster.

What would settle it is deciding what to do about a meeting that is already behind the arm
and receding -- refuse it outright, or require a margin that survives the drift it is built
on -- and then taking ADRIFT back out. `test/ft/turning.lua` is what to measure against.

## Mods with vehicle and equipment categories of their own

Everything the mod knows about what can carry an arm is written down here rather than asked.
The equipment sits in categories this mod names, and the vehicles it expects are the ones the
base game ships plus whatever test/ft/ce-tests hands a grid to. A mod that adds a vehicle
with a grid of its own, or an equipment category of its own, is not considered anywhere.

What that is likely to cost: an arm that will not go into a grid it would fit, a vehicle
whose arms are never mustered, or a hull whose shape pack.lua has no opinion about and
mounts everything in the middle of. None of it is measured -- there is no fixture with a
modded vehicle in it -- so the first thing is to find out which of those actually happen.
