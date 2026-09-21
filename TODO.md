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

**The search is wider than it needs to be, and which shape to draw is unmeasured.** It
draws one circle round a capsule that assumes full stretch from the first tick. What an arm
can really meet is a cone, and reach.meets and reach.chain measure that exactly, but only
meets is wired and only for judging a candidate rather than for finding one.

Three shapes are available and none of them wins everywhere. One circle round the cone is a
single cheap call that over-reaches most at speed. A chain of circles follows a long thin
cone but costs a call apiece. An oriented bounding box is one call that fits a needle, and
should beat the chain once the cone is long enough. First numbers, on a fourth tier arm: 211
candidates and 0.084ms for the capsule's circle against 116 and 0.036ms for the cone's own,
and a car's cone at 330 candidates in one oriented call against 435 in four circles.

What is wanted is a benchmark over the axes that decide it -- the cone's length and width,
how many things are standing in it, and how thickly -- and from that the thresholds for
picking a shape. Wants a quiet machine.

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

## An arm will not take up what its owner is standing on

Things marked for taking up -- what a downgraded chest spills, say -- are left where they
are when the player is standing on them.

The first place to look is not the engine but the mod: choose() deliberately passes over
what its owner stands in and sorts a pickup underfoot to the back of the queue. That rule
predates leading and predates the deconstruction work, and it may simply be wrong now.

The engine has a hand in it too, and that part is understood: an inserter whose pickup or
drop falls on a tile holding something marked for deconstruction will not move its hand.
The drop end is covered, since the box at the rest point stands on that tile, and the pickup
end is cured by naming the target, which pin_from does. So if the mod is not refusing it by
its own rule, the thing to check is whether that naming survives the case where the thing
being fetched is the tile the arm is standing on.

## Arms turn back from some ghosts when a train is at full speed

Driving forward at full speed, an arm sets off for a ghost and then turns back without
delivering, and it is the same ghosts every time rather than a scattering of them.

That it is specific ghosts rather than random ones points at the course rather than at the
swing: set_course offers a lead only where an intercept exists inside the horizon, and
holding_course drops one that stops being flyable. A claw that sets off and turns back is
one that had an intercept and then lost it. `test/ft/steering.lua` drives a train, and
test/ft/losing.lua drives one at half speed and faster, so the layout is to hand.
