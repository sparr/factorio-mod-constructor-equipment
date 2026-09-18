# Outstanding, from the walk round of 2026-09-19

## 9. An arm stops when its owner stands on what it was reaching for

It should give up on that one and go to something else rather than waiting.

Not reproduced. A walk of the whole showroom built everything that should have been built
and left standing only what each bay exists to leave standing, and a character who steps
onto a ghost mid reach gives up on it within a few ticks and builds the next one along. The
paths that could have waited are all covered: choose() passes over what its owner stands in
and sorts a pickup underfoot to the back of the queue, advance() asks again every tick and
turns to something else, and a spot a vehicle has rolled onto fails buildable() and is never
offered. So this wants the bay, the save or the tier it was seen on before there is anything
to fix.

## 12. An arm should aim where its target will be, not where it is

Half done, and the other half looks like a dead end.

An arm does not set off for something its owner is walking away from that it could not reach
in time. That part stands: twenty four departures become fifteen on a pass of ghosts laid
abeam, and every delivery that landed before still lands.

Aiming a held course at the meeting point does not pay, and the reason is worth keeping.
The earliest meeting on a fixed bearing is the smaller root of |D - v*n| = r0 + n*extension,
which is a quadratic, and the straight line to it is the shortest path there -- that much is
right, and it was implemented and checked against a brute force scan. What it leaves out is
that the engine turns and extends at once, so the hand's reach at time t is not a disc of
radius r0 + t*extension but an annulus sector, and a curve through that sector meets the
target nearer in and sooner than any straight line can. Measured on a ghost one tile abeam
of a fourth tier arm, on a fixture scrubbed between cases: chasing it took 17 ticks at a
twentieth of a tile a tick where a course took 10, but 6 against 11 at seven hundredths, and
3 against 7 at a ninth. One win, two losses, and the losses are the bigger share of the
swing.

So the next attempt wants the sector rather than the disc: the soonest t at which the
target's track crosses both what the hand can extend to and what it can turn to by then,
and aim at that. Whether it beats simply aiming at the thing -- which is what the arms do
now, and which already arrives at about that bound wherever the bearing is trackable -- is
the question to answer before writing any of it.

The tiers' own numbers are the other half. A first tier hand extends at 0.035 tiles a tick
against a walk of 0.09 to 0.15, so it cannot reach most of what goes past its owner whatever
it aims at, and the fourth tier's 0.1 is only just enough.
