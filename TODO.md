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

Half done. An arm no longer sets off for something its owner is walking away from that it
could not reach in time, which is the case the walk round was about: a ghost one to three
tiles abeam of somebody under way.

What is left is the delivery itself, and it may not be gettable. Those ghosts are not built
now either. The bearing to a thing one tile abeam of a character at a ninth of a tile a tick
sweeps at 0.0143 turns a tick and the last tier's arm turns at 0.008, so the hand cannot
follow it at any aim: leading the drop was tried at a fixed fraction of the swing, solved for
the arrival time, and solved with the iteration run out to its far root, and where a lead
could be computed at all the arm was already delivering. Either the arms need to turn faster
near their owner, or the claw wants a way of putting the thing down that is not a swing.
