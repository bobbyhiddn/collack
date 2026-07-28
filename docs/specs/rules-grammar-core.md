# Executable rules grammar

`battle/rule_ast.lua` defines the sole mechanical data contract for Callack
content. `battle/content/rules.lua` authors that data. The shell, core, sling,
brick, draft, effects, simulation, validation, presentation, attribution, and
balance modules only compile or project it.

## RuleSet contract

Every item is a schema-versioned `rule_set` with:

- stable identity, display name, and gameplay role;
- content kind, canonical five-tier rarity, fixed 100-point envelope, and
  draft/reward/CPU/legacy availability;
- one or more rules;
- an explicit drawback, including `none` when there is no extra cost;
- compatibility requirements, exclusions, and a maximum copy count;
- one or more synergy tags;
- ordered component identity plus canonical core minimum rarity;
- explicit ability groups used to derive passive/release counts and mechanical
  complexity units.

Every rule declares:

- trigger event and phase;
- condition predicate;
- target selector;
- observable operation verb, runtime stat, and set/add mode;
- magnitude or duration with a typed unit;
- cadence interval and optional charges or limit;
- a rule-level cost, including `none`;
- compact or expanded visibility.

Executable routing values such as collision family, release family, brick
behaviour, field force, and fixed-step velocity multipliers are mechanical
rules. They cannot use a hidden visibility class. Composition preserves each
canonical rule ID, deduplicates an identical shared node, rejects conflicting
definitions, and records the exact RuleSet memberships resolved by that ID.

Validation rejects unknown fields and vocabulary, duplicate IDs, invalid
quantities, incomplete nodes, incompatible collections, excess copies, missing
requirements, shell/core tier violations, common passives or bonus releases,
ungrouped executable rules, tier complexity violations, and rules that exceed
the fixed budget. Canonical serialization is stable across table identity and
insertion order.

The rarity ladder is canonical structured data:
`common < uncommon < rare < epic < legendary`. Its shell caps are 1/2/3/4/5.
Common marbles have baseline blowback only and common bricks have no passive.
Upper tiers permit 1/2, 1/4, 2/6, and 2/8 ability-groups/MCU for
uncommon/rare/epic/legendary content. The same economy RuleSet owns copy caps
and the initial/win-one/later-win tier tickets; offer and reward code only
projects that table.

Allied brick harm is denied at the central runtime mutation boundary. A
rare-or-higher `allied_brick_cost` group is the sole exception. Its cost uses
the exact `setup_linked_allied_brick` selector, one orthogonal target, explicit
integer damage, lethal policy, cadence, charges, payoff scaling, and recursion
limit. Setup resolves and locks the stable link. Battle construction recomputes
and compares it, while each activation issues a single-use authorization bound
to the root event, source, target, ability, and amount. A generic allied damage,
splash, status, movement, or shell-wear rule is invalid even when it carries a
`cost` annotation.

## Consumers

`rule_ast.project` compiles fresh RuleSet projections used by the continuous
simulator. Cadence metadata supplies chain limits and
one-shot charges. Field radii and force, status duration and tick cadence,
collision damage and wear, release duration, sling behavior, brick hit points,
and marble construction all originate in these projections.

`rule_ast.compact` produces at most two card lines. `rule_ast.expanded_lines`
adds role, all player-visible rules, drawback, compatibility, synergy, and
balance. Draft, setup, and battle inspection carry those generated values.
Attributed battle events include a stable rule ID, source, role, verb, target,
magnitude, and unit; presentation callouts render directly from those fields.

`rule_ast.balance` accounts each operation by magnitude or duration, target
scope, cadence, rule cost, item drawback, and derived MCU surcharge. It is both
a validation gate and the balance projection exposed with the card. Each
accounting line also carries the canonical mechanical value and cadence, so
even a zero-weight routing value cannot change execution without changing
inspectable accounting.

## Comprehension pool

The player-facing pool is exactly:

- slings: Momentum, Ricochet, Effect Amplifier;
- marbles: Chalk Pebble, Quartz Round, Split Geode, Warden, Lodestone, Cinder;
- kits: Foundation Pair, Anchored Mirror, Living Aegis, Cold Venom, Null Orbit,
  Fault Line, Spliced Bastion, Deep Reserve.

The remaining six pre-existing marble blueprints stay in `LEGACY_MARBLES` for
deterministic CPU recipes and immutable old recordings. Draft offer generation
uses only the 17-item comprehension pool. Individual refit rewards sample all
16 player-authorized behaviour bricks from canonical rarity and copy rules;
plain and chalk fixture bodies never enter those pools.

Presentation tokens retain labels, sigils, color, art identity, and layout.
They contain no mechanics prose. Content names, tag glossary descriptions, and
placement suggestions may aid presentation but never alter execution.
