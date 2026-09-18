# Outstanding, from the walk round of 2026-09-18

Removed from this list as they are fixed. Numbers are stable so they can be referred to, so
the gaps are the ones already done: 2 and 3 were the tank's and the car's arms, 6 was the
extension and rotation speeds -- changed and then put back, once arms were pointed and the
change turned out to have been paying for a cost that no longer exists -- and 16 was
pointing an arm at what it is reaching for.

Pointing carried four more off with it, which is what the walk round's dispatch and
delivery complaints turned out to be: 7 was the wrong arm going first, 8 was an arm that
did nothing, 9 was the bulk claw coming home mid round, and 10 was an underground pair
going on the floor. 13 was not pointing at all -- a claw that deployed and then stood
there was its box landing on the neighbour's tile, where an inserter cannot see it.

## 1. "Four arms, four reaches": the words overlap

The bay's description text runs down into the "STAND HERE" text below it.

## 4. Spidertron: the claws are drawn over the body

The claw items draw on top of the spidertron. Reverse that if it can be done without side
effects.

## 5. Locomotive: the south side arms are based too far south

Base them at the foot of the wheels, and lift them to draw above the wheels.

## 11. "Pockets full": it deploys with nowhere to put anything

The arm deploys even with no room, and should stay in. Once space is cleared it stays out
and does nothing, while still slowing its owner. Un-marking any one belt sets it going on
the rest, which smells like a stale search.

## 12. "A chest downgraded": it empties the new chest

After picking up some of the shed, the arm goes on to empty the chest it just built, once
that is the nearest target.

## 14. "What a swing costs": the battery refills itself

With no reactor in the armour, the charge still goes back up.

## 15. "The toolbar button": the claw does not arrive

It returns to a short distance from its owner, the item disappears early, and the arm warps
to the stowed position rather than arriving.

## 17. A round at the very edge of the range gets stuck on one ghost

Twelve ghosts on a circle of exactly five tiles, a fourth tier claw with every capacity
bonus researched: it builds five of them and then stands with six belts in its hand, aimed
at the sixth, for as long as it has been watched -- eight hundred ticks -- neither
delivering nor coming home.

Not new, and not the pointing. The same twelve measured the same way before that change:
seven left standing after two thousand four hundred ticks either way. What did change is
the same twelve close in, which went from five still standing after 2400 ticks to the whole
dozen inside 340.

Nothing about the reach itself is impossible. Measured on a bare fourth tier inserter with
a box at the drop: a load taken 4.8 tiles to the far side of an arm built facing the other
way arrives on tick 94, which is the half turn and nothing else.

It reads like the swing limit. By then the reach has run over it, and advance() answers a
reach that has run over by redirecting rather than giving up, while redirect() leaves
job.started where it was -- so the next tick has run over too, and it redirects again,
every tick, for ever. Unverified: the behaviour above is what was measured, that paragraph
is where to look.

## 18. Can an arm be pointed more finely than the four cardinals?

Pointing an arm at what it is reaching for rounds its bearing to the nearest quarter,
because `direction` on an inserter takes the four cardinals and truncates anything else.
That leaves an eighth of a turn to swing through at worst, which hides behind the extension
at any reach worth making and does not at a short one.

Look for the prototype flag that lets an entity be built facing eight or sixteen ways
rather than four, and whether an inserter can carry it. If it can, an arm can be pointed to
within a sixteenth and the residual turn goes away entirely.
