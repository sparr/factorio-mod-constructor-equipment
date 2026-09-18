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

An arm does not set off for something its owner is walking away from that it could not reach
in time. That part is in and measured: twenty four departures become fifteen on a pass of
ghosts laid abeam, and every delivery that landed before still lands.

The rest is open, and the interesting half of it is that an arm only ever looks as far as
its own reach. work_near searches range plus the hull's spread round where its owner is
standing, so a ghost is invisible until it is already in reach, and the hand starts
unfolding at the moment the thing is level rather than being out there waiting for it. A
first tier hand takes 57 ticks to go from folded to full stretch, which is five tiles of
walking. Looking ahead by a full stretch of the slowest arm is the obvious fix and it was
built far enough to measure.

It is not simply a win, and the obstacles are worth writing down.

- The arm is hardly ever idle in a dense row, so there is no time to leave early in: traced
  on twelve ghosts two tiles apart, the first departure was early and every one after it was
  for something already in reach. The case that pays is a scattered yard, where the arm has
  been home for a while. At fourteen tiles apart and a fast walk, a fourth tier arm went from
  four of eight to eight of eight.
- The first tier cannot use it. Its hand extends at 0.035 tiles a tick, so at a walk of 0.13
  there is no meeting to be had at all, and setting off early for one spends the swing that
  would have caught the next. Gating on whether a meeting exists is necessary and was not
  sufficient: the first tier still came out worse.
- Holding the load is the hard part. What a tier calls its range is this mod's own word and
  not a limit the engine keeps: measured on 2.1.19, a two tile arm told to drop six tiles out
  stretched to 5.72 and put the belt on the ground. So an arm out early has to hold what it
  is carrying, which means the pickup and the drop being the same point, which means the mod
  has to make the handover itself -- and every version of that so far has leaked an item or
  two onto the floor across a run.

The way round the last one is probably to set off with an empty claw and load it when the
thing comes into reach. An empty hand reaches for its pickup rather than its drop, which is
the aiming a fetch already uses, so the arm would stretch out towards the meeting point with
nothing in it to drop, and the claw would be filled from the pockets at the moment it
arrives. Nothing to shed means nothing to lose. What that costs is the accounting: the
pockets are charged when an arm sets off, deliberately, so that nothing the engine does
afterwards can mint an item, and moving the charge to arrival wants care.
