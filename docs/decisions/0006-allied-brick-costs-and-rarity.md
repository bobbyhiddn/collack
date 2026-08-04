# ADR 0006 — Allied-brick ability costs and the five-tier rarity contract

- **Date:** 2026-07-28
- **Status:** Accepted implementation contract
- **Scope:** REQ-BEC-016 and REQ-BEC-017
- **Canonical baseline:** `origin/main` at
  `3e64eed6e160a84ed9c640cb409da6869598f4bc`
- **Follows:** ADR 0005 and the executable grammar in
  `docs/specs/rules-grammar-core.md`
- **Supersedes:** REQ-BEC-015's absolute prohibition on allied-brick harm.
  Its defensive intent remains the default; its absolute ban does not.

## Decision

Allied bricks are protected by a deny-by-default harm boundary. Collision,
splash, Chain, Splice, Shatter, destruction, fields, adjacency, and recursively
created effects cannot reduce an allied brick's integrity, destroy it, move it,
or apply a harmful state.

The only exception is an authored **linked allied-brick ability cost**. It is a
rare-or-higher capability in the canonical RuleSet, resolved to one eligible
orthogonally adjacent ally during setup. It declares an exact integrity cost,
finite cadence, payoff rules and scaling, attribution, and recursion policy.
Execution grants a single-use authorization for that exact activation, source,
linked target, and amount. It is not a friendly-fire switch.

Marbles and bricks use the same canonical rarity ladder. Rarity limits
composition complexity but never adds power budget: every complete marble and
every individual brick has the same 100-point balance envelope. A higher-rarity
item may contain more layers or more complex abilities, but must pay for them
with body efficiency, conditions, cadence, drawbacks, copies, or formation
constraints.

Normative words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** have their usual
requirements meaning.

## 1. Authority and terms

The schema-versioned RuleSet remains the sole mechanical authority. The
canonical-authority remediation on main is not relaxed:

- runtime profiles are projections of the selected RuleSet, never overlay
  tables;
- content identity and the RuleSet must be byte-equivalent at setup and reward
  boundaries;
- executable routing values are visible, attributable, and balanced;
- compact copy, inspection, setup preview, reward attribution, battle events,
  and accounting are projections of the same nodes;
- changing a mechanical value changes canonical identity; changing a shadow
  projection cannot change play.

Definitions:

- **source owner** is the owner stamped on the root RuleSet activation. Every
  descendant inherits it. Content-authored brick harm without a source owner
  is invalid.
- **allied brick** is a live brick whose owner equals the source owner. It does
  not mean “the defender” or “a neighbour”.
- **harm** is integrity loss, destruction, a negative status, forced movement,
  disabling, replacement, or any other mutation classified as harmful by the
  operation vocabulary. Prevention, healing, shields, and positive status are
  not harm.
- **body rule** declares identity, integrity, size, mass, or restitution and
  has no trigger after build.
- **ability group** is one player-visible mechanic and all canonical rules
  needed to execute it. Low-level routing nodes do not create extra groups.
- **passive** means any brick ability group beyond its body rules, regardless
  of whether its trigger is named `passive`, `collision`, `destroyed`, or
  another event.
- **root event** is a physical or scheduled event at cascade generation zero.

Baseline core-release blowback remains symmetric for marbles under
REQ-BEC-003. This decision protects allied **bricks** and does not turn
blowback into an enemy-only marble effect.

## 2. Non-negotiable harm invariants

1. Every mutation of a brick passes through one `apply_brick_harm` boundary.
   Direct HP subtraction elsewhere is invalid.
2. That boundary compares source owner with target owner on every call,
   including calls produced by a field, status, splash, destruction, or
   recursive descendant.
3. Enemy-authored harm is allowed by its target rule. Allied-authored harm is
   denied unless the call carries a valid linked-cost authorization.
4. An authorization is bound to
   `(root_event_id, activation_id, ability_id, source_uid, target_uid, amount)`.
   It is single-use and cannot be widened, copied, inherited, or reused.
5. An authorized cost can mutate only its setup-linked target by exactly its
   declared integer integrity amount. No overkill is credited.
6. Generic selectors such as `orthogonal_neighbours`, `nearby_bricks`,
   `release_area`, `target_column`, or `any` never authorize allied harm.
7. A balance `cost` or `drawback` annotation is accounting metadata. It never
   grants runtime harm authority.
8. Positive allied effects do not grant permission for a harmful child effect.
9. An effect with a missing or ambiguous source owner is denied against a
   brick. No shipped content has environmental brick-harm authority.
10. Presentation, replay, or legacy compatibility code cannot bypass or repair
    this boundary.

These rules cover ordinary collision, behind-target splash, Shrapnel, Chain,
Splice, Shatter, on-destruction effects, persistent fields, status ticks, and
every later propagation family.

## 3. Canonical RuleSet v2 additions

Implementation advances `battle/rule_ast.lua` to schema version 2. Existing
fields remain unless this section tightens them. A complete marble or
individual brick adds:

```text
content_kind = "marble" | "brick"
rarity = "common" | "uncommon" | "rare" | "epic" | "legendary"
rarity_budget = 100
availability = {
  player_draft = boolean,
  player_reward = boolean,
  cpu_recipe = boolean,
  legacy_only = boolean
}
abilities = AbilityGroup[]
```

`rarity_budget` retains its field name for migration compatibility but is a
fixed power envelope, not a larger allowance for rarer items. Values other than
100 are invalid for complete marbles and individual bricks. Component
RuleSets declare their component kind; core RuleSets canonically declare
`min_rarity`, and shell order remains composition order.

Every executable non-body brick rule MUST belong to exactly one ability group.
Every bonus core-release rule MUST belong to exactly one release ability group.
No rule can be double-counted or left outside a group. Baseline blowback is a
mandatory system ability and does not consume a bonus-release group.

An ordinary group has:

```text
{
  id = stable ability id,
  kind = "passive" | "core_release",
  rule_ids = non-empty ordered canonical rule IDs
}
```

A linked allied-cost group has:

```text
{
  id = stable ability id,
  kind = "allied_brick_cost",
  cost_rule_id = one canonical harm rule,
  payoff_rule_ids = one or more ordered canonical rule IDs,
  recursion = {
    accepts_causes = ordered canonical cause vocabulary,
    max_generation = integer from 0 through 3
  }
}
```

The cost rule MUST declare all of the following:

```text
trigger = { event, phase }
condition = { predicate, value? }
target = {
  selector = "setup_linked_allied_brick",
  relation = "allied",
  topology = "orthogonal",
  count = 1,
  exclude_self = true,
  require_alive = true,
  required_tags = string[],
  excluded_tags = string[],
  order = "local_row_col_uid"
}
operation = { verb = "deal", stat = "damage", mode = "set" }
magnitude = { value = positive integer, unit = "damage" }
cadence = {
  unit = canonical trigger or "ticks" or "exchange",
  interval = positive integer,
  charges = integer from 1 through 3
}
lethal = explicit boolean
```

An allied-cost ability is invalid below rare. `charges` is mandatory even when
the interval is greater than one. `lethal = false` requires current target
integrity to remain above zero after payment. `lethal = true` permits exact
payment to reach zero. In either case, a target with less integrity than the
declared amount is ineligible; the engine never clamps a two-point cost into a
one-point payment.

Each payoff rule triggers only from the named ability's successful
`ability_cost_paid` event and includes:

```text
scaling = {
  basis = "cost_damage_applied",
  numerator = non-negative integer,
  denominator = positive integer,
  cap = non-negative integer,
  rounding = "floor"
}
```

Its final magnitude is
`min(cap, floor(cost_damage_applied * numerator / denominator))`. A zero result
is legal only when the generated copy says so. Flat hidden payoff, runtime
lookup by brick behaviour, and a payoff without a canonical rule ID are
invalid.

The validator also rejects a cost selector that can select self, more than one
target, a diagonal target, an enemy, or a target after battle-time retargeting.
It rejects empty payoff lists, repeated rule IDs, mismatched trigger/cadence
data, an unpriced rule, or a recursion allowance above the global cap.

The tier table and acquisition weights in sections 7 and 9 live in one
versioned canonical economy RuleSet. Draft, refit, setup, inspection, and test
fixtures project it; none repeats the numbers in a private table.

## 4. Setup link and atomic execution

Formation coordinates are local to each owner, so the same ordering works for
both sides.

At every placement change, setup projects each linked-cost source's eligible
orthogonal neighbours. It filters by the authored tags and the cost's lethal
rule, then sorts by local row, local column, and stable UID. The first candidate
is the previewed link. A source with no candidate produces
`ability_link_missing`, and `lock_setup` is rejected. Moving either brick
recomputes the preview.

Lock writes this value-only record into the battle handoff:

```text
{
  ability_id, source_uid, target_uid,
  source_rule_set_id, cost_rule_id, payoff_rule_ids,
  source_cell, target_cell, cost_amount, lethal, cadence
}
```

`battle.new` recomputes it from the canonical RuleSets and locked formation.
Missing, stale, duplicate, retargeted, or altered records are rejected before
the world steps. A battle link never retargets. If either endpoint dies or the
target can no longer pay exactly, the ability is blocked.

An activation is atomic:

1. Revalidate the source, stable link, accepted cause, cadence, charge, target
   eligibility, and canonical RuleSet identity.
2. Reserve an authorization for the exact source, target, amount, and
   activation.
3. Emit `ability_triggered`.
4. Spend one charge and apply the exact cost through `apply_brick_harm`.
5. Emit the attributed `brick_damaged` and `ability_cost_paid` events.
6. Apply payoff rules in authored order and targets in stable ID order.
7. Emit one `ability_payoff_applied` per payoff mutation.
8. Only after the cost and all payoffs complete, enqueue destruction or other
   descendant triggers.

If any precondition fails, emit `ability_blocked` with a canonical reason,
spend no charge, apply no cost, and grant no payoff. Once payment succeeds, a
later descendant cannot revoke the promised payoff.

Ability-cost damage ignores Aegis, Fortify, reduction, rewind, and redirection.
It is a payment, not hostile damage. This makes the amount exact and prevents a
protection loop from creating a free payoff.

## 5. Deterministic cascades and attribution

Root events retain the continuous engine's stable time-of-impact and body-ID
ordering. Triggered work uses a breadth-first queue ordered by:

```text
tick, trigger phase, generation, source owner A/B,
source local row, source local column, source UID,
ability ID, payoff index, target UID
```

Generation zero is the physical or scheduled root. Descendants may execute at
generations one through three. A fourth-generation attempt is not applied.
Each root is also capped at 16 ability activations and 32 brick-harm mutation
attempts. Hitting any cap emits one `cascade_capped` event for the refused work
with the root, parent, attempted generation, ability, source, target, and cap
reason. Caps never truncate silently and never consume RNG.

Every descendant harm request returns to the ownership gate. Parent
authorization is not inherited. An on-destruction ability accepts an
ability-cost destruction only when its canonical `accepts_causes` includes
`ability_cost`; the default does not.

Attributed mechanical events MUST carry:

```text
event_id, tick, exchange,
root_event_id, parent_event_id, generation,
source_owner, source_entity_id, source_rule_set_id,
rule_id, ability_id, operation, target_selector,
target_owner, target_entity_id, target_relation,
amount, unit, cause
```

`ability_triggered`, `ability_cost_paid`, and `ability_payoff_applied` also
carry `activation_id`, linked source and target UIDs, cadence index, and charges
before/after. `ability_cost_paid` carries the authorization ID, requested and
applied damage, lethal flag, and target integrity before/after. Generated
callouts use these same nodes. Replay records the events but never re-executes
them.

## 6. Chain and Splice replacement rules

### Chain / Powder Keg

The old `death_splash` against orthogonal bricks is removed.

Powder Keg's Chain ability is:

- when destroyed, once per brick, wear the causal enemy marble's current shell
  by one durability if it is alive and in the arena;
- then wear up to two other enemy marbles within 24 world units by one,
  nearest squared distance then stable body ID;
- never target a brick or an allied marble;
- process shell break and core release as ordinary descendants under the
  generation cap.

If no enemy marble qualifies, Chain resolves with zero targets and an
attributed callout. Destruction by an allied ability cost does not trigger it
unless a future canonical version explicitly accepts that cause.

Chain remains a formation-edge retaliation and anti-cluster tool. Its
counterplay is destroying it from outside the radius, using a spent or cheap
outer shell, or avoiding a marble cluster.

### Splice / Splice Node

The old `collision_splash` against orthogonal bricks is removed.

On its first damaging collision each exchange, a surviving Splice Node grants
each live orthogonally adjacent allied brick one point of Guard:

- Guard prevents the next one point of hostile brick damage;
- each neighbour receives at most one Guard point;
- Guard does not stack and a later application only refreshes its expiry;
- it expires after 120 simulation ticks or at exchange end, whichever comes
  first;
- it cannot target Splice itself and cannot prevent an allied ability cost.

Targets use up/down/left/right local formation order for events. Splice remains
a contact-triggered adjacency build-around, distinct from Granite's continuous
one-point Fortify aura and Aegis's personal one-shot negate. Its counterplay is
isolating or bursting the node, striking before it triggers, or attacking
unlinked lanes after Guard is spent.

## 7. Five-tier rarity law

Rarity is canonical structured data, not an ID suffix, shell-count inference,
art token, or draft-card field. Rank is always:

```text
common < uncommon < rare < epic < legendary
```

### 7.1 Tier ceilings

| Rarity | Marble shell cap | Bonus core-release groups / MCU | Brick passive groups / MCU | Brick copy cap | Marble copy cap |
|---|---:|---:|---:|---:|---:|
| common | 1 | 0 / 0 | 0 / 0 | 4 | 3 |
| uncommon | 2 | 1 / 2 | 1 / 2 | 3 | 2 |
| rare | 3 | 1 / 4 | 1 / 4 | 2 | 2 |
| epic | 4 | 2 / 6 | 2 / 6 | 1 | 1 |
| legendary | 5 | 2 / 8 | 2 / 8 | 1 | 1 |

Ceilings are not quotas. An epic may use one strong rule-changing passive.
Rarity does not grant integrity, damage, or points.

Every marble has one core and from one shell through its tier cap. Rarity is no
longer derived solely from shell count. The migrated roster continues to fill
its cap, but a future rare one-shell build-around is legal if its whole RuleSet
fits the rare budget and complexity ceiling.

Every core has baseline final-shell blowback. A common core has trajectory plus
baseline blowback only. Authored release bonuses begin at uncommon. A
non-common core may still choose baseline-only release. Each shell keeps an
ordered identity, durability, and exactly one collision family; shell
durability and collision mechanics consume the complete marble's 100 points.

A common brick has body rules and **no passive**. Restitution, mass, dimensions,
and integrity are body stats when they are fixed at build and have no trigger.
A collision response, damage modifier, aura, status, heal, shield, target
change, or on-destruction effect is a passive.

### 7.2 Mechanical complexity units

MCU is derived, never trusted from authored totals. Each ability group costs:

- 1 MCU for the group;
- +1 for every payoff operation after the first;
- +1 if any selector can affect more than one entity or an area/field;
- +1 if it creates tracked state such as duration, status, shield, snapshot,
  charge, or cooldown;
- +1 for a rule-changing verb such as negate, rewind, redirect, retarget,
  break-shell, copy, or replace;
- +1 for recursion or propagation;
- +1 for linked allied-brick cost authority.

A feature that meets several bullets pays each. Conditions and cadence can
reduce power accounting but do not erase comprehension cost. Identity,
rarity, art routing, and build-only body nodes are zero MCU; an executable
effect cannot disguise itself as one of them.

### 7.3 Fixed balance envelope

Every complete marble and individual brick has exactly 100 available points.
The balance projection accounts body stats, every operation, target scope,
expected cadence, duration, charges, field coverage, rule-changing value, and
MCU surcharge. No executable **effect** may have a zero balance weight. A
routing identity may be zero only when it cannot add an effect and every
routed operation is separately priced; it still appears in the ledger.

Extra mechanics are paid for only through canonical, visible levers:

- lower integrity, durability, collision damage, restitution, mass, or other
  body efficiency;
- a narrower validated condition;
- lower charges, a longer interval, or a later trigger;
- an exact drawback, including an allied-brick cost;
- a copy cap below the tier default;
- a setup requirement such as adjacency, tag eligibility, or rear-row
  placement.

Credits are applied once. A condition that is already necessary for targeting
does not also earn drawback credit. Drawback plus formation/copy credit cannot
exceed 25 points, and an allied-cost credit cannot exceed the priced value of
its payoff. Negative net ability cost and unused “credit” transferred to
another item are invalid.

`balance.spent > 100` rejects the RuleSet at content load, offer generation,
reward application, setup lock, and battle handoff. Higher rarity never raises
100. Commons can spend nearly all of it on efficient bodies; upper tiers spend
more on mechanics and constraints.

## 8. Content migration

### 8.1 Current marbles and cores

The six comprehension marbles remain player-eligible. The six legacy marbles
remain CPU/recording-only until a separate pool decision; rarity validation
still applies whenever they are constructed.

| Marble ID | Tier | Shells | Core release | Availability |
|---|---|---:|---|---|
| `chalk_common` | common | 1 | baseline | draft + reward |
| `quartz_common` | common | 1 | baseline | draft + reward |
| `drifter_common` | common | 1 | baseline | legacy/CPU |
| `flint_hook_common` | common | 1 | baseline | legacy/CPU |
| `geode_uncommon` | uncommon | 2 | Shrapnel bonus | draft + reward |
| `silver_seed_uncommon` | uncommon | 2 | Shrapnel bonus | legacy/CPU |
| `banded_guard_uncommon` | uncommon | 2 | baseline | legacy/CPU |
| `warden_rare` | rare | 3 | Concussion bonus | draft + reward |
| `shard_ram_rare` | rare | 3 | Shrapnel bonus | legacy/CPU |
| `lodestone_epic` | epic | 4 | Magnetize bonus | draft + reward |
| `magnet_needle_epic` | epic | 4 | Magnetize bonus | legacy/CPU |
| `cinder_legendary` | legendary | 5 | Scorch bonus | draft + reward |

`dull_quartz`, `cant_pebble`, and `skew_flint` have canonical minimum rarity
common and baseline release. `shrapnel_geode`, `concussion_pearl`,
`lodestone_heart`, and `cinder_nucleus` have minimum rarities uncommon, rare,
epic, and legendary respectively.

Shrapnel must select enemy bricks relative to the releasing core's owner. It
chooses the nearest enemy brick by squared distance then local row, column, and
UID, and its orthogonal splash filters each target through the enemy relation.
It cannot damage the releasing side's bricks even when they are closer.

The current per-card budgets of 98–102 migrate to exactly 100. Ordered shell
identity remains canonical. Catalog rarity and core `min_rarity` shadow fields
are removed or become verified projections.

### 8.2 The 16-behaviour brick roster

Values below are migration targets; final numeric body tuning must fit the
100-point accounting without changing the mechanic or tier.

| Brick ID | Tier | Migration and visible tradeoff |
|---|---|---|
| `basalt_absorber` | common | Remove Absorb and shell-wear passives. Keep a high-integrity, low-restitution raw body. |
| `training_dummy` | common | Remove Harmless. Keep a lower-integrity, high-restitution raw body. |
| `mirror_pane` | uncommon | One surviving-contact reflect passive; burst that destroys it prevents reflection. |
| `moss_regenerator` | uncommon | Restore one integrity after surviving, at most once per exchange; burst is the counter. |
| `granite_fortifier` | uncommon | Continuous one-point protection for orthogonal allies; lower personal body and adjacency constraint pay for it. |
| `shatter_crystal` | uncommon | Wear the striking enemy shell by two on contact; no brick target. |
| `vault_arch` | uncommon | Retain one contact force-routing effect with explicit direction and cadence; its route can aid a prepared enemy angle. |
| `venom_glass` | rare | Enemy-marble poison field with canonical radius, duration, and tick cadence; fragile body. |
| `rime_block` | rare | Enemy-marble freeze field with canonical radius and duration; fragile body. |
| `lodestone_block` | rare | Enemy-marble magnetic field with canonical radius and force; positioning constraint. |
| `powder_keg` | rare | Replace allied destruction splash with the bounded enemy-marble Chain retaliation in section 6; one-integrity body. |
| `splice_node` | rare | Replace allied contact splash with the bounded adjacent Guard in section 6. |
| `aegis_keystone` | epic | Personal one-shot damage negate; one copy and reduced body efficiency. |
| `void_prism` | epic | Break the striking enemy's current shell under explicit cadence; one copy and fragile body. |
| `prismatic_mirror` | epic | Link surviving-contact reflect and one shell wear as two visible effects; one copy and burst vulnerability. |
| `temporal_anchor` | legendary | Once per battle after surviving a damaging collision, restore only itself to its pre-contact integrity/status snapshot; rear-row requirement, one copy, and no rewind of allied costs. |

`plain_block` and `chalk_block` are not part of the 16-behaviour roster. They
become common inert fixture bodies with no passive and remain unavailable to
player draft/reward pools unless separately promoted.

### 8.3 Brick kits and rewards

The eight initial kit IDs remain stable but migrate so all 16 behaviours appear
once and self-harm advice disappears:

| Kit ID | Members | Offer tier | Role |
|---|---|---|---|
| `guard_pair` | Basalt Absorber + Training Dummy | common | efficient foundations |
| `mirror_anchor` | Mirror Pane + Vault Arch | uncommon | rebound lane |
| `living_aegis` | Moss Regenerator + Aegis Keystone | epic | renewal plus one-shot guard |
| `venom_rime` | Venom Glass + Rime Block | rare | layered status field |
| `lodestone_void` | Lodestone Block + Void Prism | epic | pull then strip |
| `shatter_keg` | Shatter Crystal + Powder Keg | rare | shell-break retaliation |
| `splice_keg` | Splice Node + Granite Fortifier | rare | bounded adjacent protection |
| `vault_temporal` | Prismatic Mirror + Temporal Anchor | legendary | protected deep build-around |

A kit is packaging, not a second mechanical authority. Its offer tier is the
highest member tier; both members retain individual RuleSets, budgets, rarity,
and copy caps. Generated kit copy concatenates those exact authorities and
never attributes both sets to a one-brick reward. A kit has no independent
100-point pool or passive allowance; its balance view reports the two member
ledgers.

The stable `splice_keg` content ID changes its display name from **Spliced
Fuse** to **Spliced Bastion**. The short-run starting Basalt, Granite, and
Mirror keep their identities; their verified kit provenance becomes
`guard_pair`, `splice_keg`, and `mirror_anchor` respectively.

Remove the hard-coded `BRICK_REWARD_ORDER`. Individual rewards draw from all 16
canonical bricks that are legal for the stage, proposed operation, copy cap,
and potential link requirements. Repair and remove operations always remain
available for the exact owned item regardless of tier.

## 9. Draft odds and reward availability

Slings keep their curated sidegrade offer and do not use item rarity. For each
marble or brick-kit card slot, the deterministic sampler first applies the
slot's build-match, new-direction, or scout-counter predicate. It then rolls a
tier ticket and samples uniformly without replacement from that represented
tier. Weights are renormalized across represented eligible tiers; an empty
semantic predicate falls back to all eligible candidates. Stable shuffled ID
order resolves the item. RNG remains in the draft/refit domain only.

| Acquisition point | common | uncommon | rare | epic | legendary |
|---|---:|---:|---:|---:|---:|
| Full-loadout initial draft | 50% | 28% | 14% | 6% | 2% |
| Short-run reward after win 1 | 50% | 32% | 18% | 0% | 0% |
| Short-run reward after win 2 or later | 35% | 30% | 20% | 12% | 3% |

These are tier odds when all tiers in that row are represented. Sampling
without replacement and semantic filtering can change the realized offer, so
the offer journal records the eligible IDs, normalized tier weights, tier
ticket, and selected ID. No pity timer, reroll, hidden rarity boost, or
player-build inspection may alter the table.

CPU recipes are authored asymmetric builds and do not use player odds. They
must still pass rarity, budget, copy, link, and harm validation. Legacy-only
items cannot enter a player offer or add/replace reward. A reward operation is
generated only if the post-operation roster can contain every required
linked-cost target; setup later validates the actual placement.

## 10. Telegraphing and counterplay

Every marble and brick card prints the rarity name and the existing one-through
five bead geometry. Marble shell pips are separate from rarity beads because a
marble may use fewer shells than its cap. Brick cards also print:

- `NO PASSIVE` for common bodies;
- current passive groups versus the tier ceiling;
- balance spent out of 100 and the effective copy cap;
- all cadence, charges, conditions, formation requirements, and drawbacks.

A linked allied cost has one generated compact sentence:

```text
COST 1 linked allied integrity (once per exchange, 2 charges)
→ wear the striking enemy shell by 2.
```

Expanded inspection names the eligibility filter, local tie-break, lethal
rule, exact link, payoff scaling, accepted causes, and recursion limit. Setup
draws a persistent source-to-target tether with the amount and remaining-charge
icon. Invalid placement shows the exact lock error.

Battle presentation uses the attributed activation ID to show the trigger,
cost, and payoff as one causal sequence. Chain points toward enemy marbles;
Splice draws Guard brackets around affected allied bricks. Phone, desktop,
greyscale, mute, and reduced-motion views retain labels and numeric changes;
color or particles are never the only signal.

Counterplay is inspectable: break or soften a linked target until it cannot pay
exactly, destroy the source, deny its trigger, exhaust its charges, attack
outside Chain's radius, spend Splice Guard before a heavy hit, isolate
adjacency pieces, or exploit the upper-tier item's paid body weakness.

## 11. Examples and anti-examples

### Valid focused fixture: Bloodstone Relay

A rare two-integrity Relay links during setup to the first eligible orthogonal
ally by local row, column, and UID. On its first damaging collision each
exchange, with two charges per battle, it nonlethally deals exactly one
integrity damage to that linked ally. Its single payoff wears the striking
enemy shell by two:

```text
cost amount = 1, lethal = false
payoff scaling = 2 / 1 cost damage, cap 2, floor
recursion accepts = ["hostile_collision"], max_generation = 1
```

With a three-integrity linked ally and a three-durability striking shell, the
ally becomes two and the shell becomes one. Events share one activation ID and
show `3→2` and `3→1`. With a one-integrity linked ally, the activation is
blocked, no charge is spent, and the shell remains three.

This fixture proves the capability; it is not added to the shipped roster by
this decision.

### Anti-examples

- Giving old Chain `target = orthogonal_neighbours` plus `relation = allied`
  is invalid; it is generic splash, not a linked cost.
- Setting `cost.kind = risk` on old Splice does not authorize its damage.
- Selecting `nearby_bricks` and filtering allies inside the engine is invalid.
- Paying one damage and looking up an unbounded payoff from `behaviour` is
  invalid; the payoff and scale must be canonical.
- Reusing a Relay authorization for a Chain descendant is denied.
- Retargeting to a second neighbour after the locked target dies is denied.
- A common Mirror Pane with Reflect is invalid even when it spends fewer than
  100 points.
- A common Shrapnel core, a rare marble with four shells, or a legendary marble
  with six shells is invalid.
- A legal-complexity legendary brick at 101 points is invalid.
- A legendary add reward after win one is invalid even when the seeded roll
  would otherwise select it.

## 12. Acceptance and mutation test contract

Implementation is incomplete until all of these are automated.

### Allied-brick safety

1. Parameterize all 16 behaviour bricks through hostile collision, friendly
   collision injection, splash, field, status, destruction, and generation
   three. Assert no allied brick loses integrity or harmful state without an
   authorization.
2. Exercise Chip, Cleave, Splinter, Ward, Heavy, Shrapnel, Shatter, Chain,
   Splice, poison, freeze, magnetic, and core-release descendants against mixed
   ownership. Every target relation matches its RuleSet.
3. Destroy adjacent Powder Kegs. Assert no brick damage, stable enemy-marble
   target ordering, at most three targets per Keg, and a visible cap event for
   a generation-four release cascade.
4. Trigger Splice beside zero through four allies. Assert one non-stacking
   Guard each, exact expiry, hostile-only prevention, and no allied-cost
   prevention.

### Linked-cost capability

5. Run the Bloodstone Relay fixture at exact-pay, lethal, insufficient-HP,
   missing-link, dead-link, spent-charge, cadence-blocked, and denied-cause
   boundaries.
6. Assert cost and payoff atomic ordering, one activation ID, exact before/after
   values, exact charge state, stable replay events, and no retargeting.
7. Mutate source owner, target UID, amount, lethal flag, cadence, payoff rule,
   scale, accepted cause, generation, RuleSet ID, or handoff link. Setup or
   `battle.new` rejects before stepping.
8. Copy, reuse, widen, omit, or attach the authorization to generic splash.
   The harm boundary denies it and state remains unchanged.

### Rarity, balance, and economy

9. Accept every tier exactly at its shell, group, MCU, copy, and 100-point
   boundary; reject one above each boundary.
10. Reject zero shells, common bonus release, core below `min_rarity`, common
    brick passive, ungrouped rule, double-grouped rule, free executable weight,
    excessive credit, and canonical/projection rarity mismatch.
11. Validate all 12 current marble blueprints, all seven cores, seven shells,
    16 behaviour bricks, two inert fixtures, eight migrated kits, starting
    loadout, three CPU recipes, and every repair/add/replace/remove reward.
12. Exhaust the 100 tier tickets at each acquisition point with represented
    fixture candidates and assert the exact table. Repeated seed generation is
    byte-identical and does not consume opponent or battle RNG.
13. Mutate a legacy-only item into a player offer, an unavailable tier into a
    reward, a kit tier below its highest member, or a reward beyond its copy
    cap. Offer/reward validation rejects it without changing state.

### Balance outcome and presentation

14. With identical Momentum slings and marble bags at seed `17017`, a coherent
    lower-rarity wall of two Basalt Absorbers, two Training Dummies, and two
    adjacent Granite Fortifiers must defeat a sparse incoherent set containing
    Temporal Anchor, Prismatic Mirror, Void Prism, and Aegis Keystone. Store
    checkpoint hashes and reproduce the result across render-frame partitions.
15. Phone 390×844 and desktop evidence must show rarity label/beads, shell pips,
    passive count, balance, copy cap, Chain target, Splice Guard, and all three
    linked-cost stages. Greyscale and reduced-motion review remain legible.
16. Compact copy, expanded inspection, setup link, reward attribution, runtime
    event, causal ledger, and replay callout resolve the same canonical rule and
    ability IDs. Handwritten mechanics prose or hidden runtime overlay fails
    the authority mutation suite.

## 13. Implementation handoff

This commit intentionally changes no runtime code. Implement in this order:

1. Extend `battle/rule_ast.lua` to schema v2, canonical rarity/component
   minima, ability grouping, linked-cost validation, MCU, fixed 100-point
   accounting, generated copy, and event attribution.
2. Migrate `battle/content/rules.lua`, then keep
   `bricks.lua`, `cores.lua`, `shells.lua`, and `draft.lua` as verified
   projections. Apply the roster, core, Shrapnel, kit, and availability tables
   above.
3. Update `battle/draft.lua` and `battle/short_run.lua` with the deterministic
   tier sampler, stage availability, individual reward authority, and copy
   validation.
4. Resolve and validate links in `battle/setup_rules.lua`; carry them through
   both player and opponent handoffs and revalidate them at `battle.new`.
5. Centralize brick mutations in `battle/engine.lua`, implement atomic ability
   payment and the breadth-first cascade queue, then replace Chain and Splice.
   `battle/effects.lua` remains a RuleSet compiler, not an authority.
6. Project the same data through presentation and the art-token grammar. Update
   the existing rules, authority, economy, determinism, replay, and browser
   suites with the acceptance and mutation cases above.

Do not keep a schema-v1 runtime fallback for newly constructed content. Old
recordings may be replayed as immutable frames, but are never re-simulated
through weaker validation. Do not ship the Bloodstone Relay fixture as content,
change baseline marble blowback, add currency/rerolls, or expand the
three-fight run as part of this implementation.
