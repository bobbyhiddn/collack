# Executable rules grammar

`battle/rule_ast.lua` defines the sole mechanical data contract for Callack
content. `battle/content/rules.lua` authors that data. The shell, core, sling,
brick, draft, effects, simulation, validation, presentation, attribution, and
balance modules only compile or project it.

## RuleSet contract

Every item is a schema-versioned `rule_set` with:

- stable identity, display name, and gameplay role;
- one or more rules;
- an explicit drawback, including `none` when there is no extra cost;
- compatibility requirements, exclusions, and a maximum copy count;
- one or more synergy tags;
- a rarity budget checked against deterministic balance accounting.

Every rule declares:

- trigger event and phase;
- condition predicate;
- target selector;
- observable operation verb, runtime stat, and set/add mode;
- magnitude or duration with a typed unit;
- cadence interval and optional charges or limit;
- a rule-level cost, including `none`;
- compact, expanded, or internal visibility.

Validation rejects unknown fields and vocabulary, duplicate IDs, invalid
quantities, incomplete nodes, incompatible collections, excess copies, missing
requirements, and rules that exceed their budget. Canonical serialization is
stable across table identity and insertion order.

## Consumers

`rule_ast.project` compiles RuleSets into the legacy-shaped runtime values used
by the continuous simulator. Cadence metadata supplies chain limits and
one-shot charges. Field radii and force, status duration and tick cadence,
collision damage and wear, release duration, sling behavior, brick hit points,
and marble construction all originate in these projections.

`rule_ast.compact` produces at most two card lines. `rule_ast.expanded_lines`
adds role, all player-visible rules, drawback, compatibility, synergy, and
balance. Draft, setup, and battle inspection carry those generated values.
Attributed battle events include a stable rule ID, source, role, verb, target,
magnitude, and unit; presentation callouts render directly from those fields.

`rule_ast.balance` accounts each operation by magnitude or duration, target
scope, cadence, rule cost, and item drawback. It is both a validation gate and
the balance projection exposed with the card.

## Comprehension pool

The player-facing pool is exactly:

- slings: Momentum, Ricochet, Effect Amplifier;
- marbles: Chalk Pebble, Quartz Round, Split Geode, Warden, Lodestone, Cinder;
- kits: Basalt Escort, Anchored Mirror, Living Aegis, Cold Venom, Null Orbit,
  Fault Line, Spliced Fuse, Deep Reserve.

The remaining six pre-existing marble blueprints stay in
`LEGACY_MARBLES` solely so deterministic CPU recipes and old recordings remain
loadable. Draft offer generation uses only the 17-item comprehension pool.

Presentation tokens retain labels, sigils, color, art identity, and layout.
They contain no mechanics prose. Content names, tag glossary descriptions, and
placement suggestions may aid presentation but never alter execution.
