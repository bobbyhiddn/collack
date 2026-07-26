# Callack vertical-slice art, audio, and UX bible

- Status: implementation contract for the Battle Engine Prototype, version 1
- Visual target: warm, handcrafted tabletop play
- Runtime target: the existing LÖVE/Lua client on web, desktop, and Capacitor
- Token source: [`src/ui/art_tokens.lua`](../../src/ui/art_tokens.lua)

This is not a moodboard. Every visual and sound below can be produced with
LÖVE 11.4 primitives, a small deterministic texture cache, and procedural PCM.
The slice adds no downloaded font, raster texture, shader, or recorded sound.
It does not change battle rules. The renderer continues to consume the
canonical battle event log.

## 1. Product read

Callack should feel like a prized game carried to a well-used table:

- marbles are luminous collector glass with mineral shells visible from the
  outside in;
- formations are small mineral bricks with chipped edges, weight, and readable
  carved marks;
- slings are walnut, braided cord, and brass hardware;
- the table is deep green felt over warm dark wood;
- magic appears only when a core releases, a status is applied, or a rare brick
  answers a hit;
- cards read like cream stock labels from a collector's cabinet, not neon game
  HUD panels.

The tactile materials carry the fantasy. UI chrome stays quiet. Brass means
craft, selection, and focus; it does not mean "everything important." Player A
and B colours identify ownership only. Rarity, effect, durability, and state
each have a second non-colour channel.

### Non-goals

- No photorealistic textures, baked lighting, bloom pipeline, or full-screen
  spell fog.
- No font or icon downloaded from a web CDN.
- No generated bitmap concept art promoted to a shipping asset.
- No animation or audio state may feed back into `battle/`.
- No hidden information conveyed by colour alone.

## 2. Current build and presentation constraints

These facts come from the current `main` client and build scripts.

| Constraint | Current fact | Directional consequence |
| --- | --- | --- |
| Web runtime | `love.js@11.4.1`, declaring LÖVE 11.4 | Use APIs available in LÖVE 11.4; do not require an 11.5-only feature. |
| Desktop runtime | packaged with LÖVE 11.5 | Treat 11.4 as the shared API floor. |
| Web memory | 64 MiB compatibility build | Cache small primitive canvases and about 51 KiB of generated PCM; do not ship texture atlases. |
| Web isolation | compatibility build, no SharedArrayBuffer requirement | Audio and rendering must work on ordinary static hosting and Capacitor. |
| Mobile wrapper | Capacitor 6.x, same love.js canvas | Respect CSS safe-area insets and browser first-gesture audio rules. |
| Logical phone surface | fixed 390×844 | This is the touch acceptance surface and the canonical portrait reference. |
| Current window floor | 320×568 | It is boot-compatible, but not a touch-layout acceptance target; a uniformly scaled 56 px control is only about 38 px tall there. |
| Current desktop behaviour | the 390×844 view is uniformly scaled and letterboxed | Add a separate 1280×800 layout rather than stretching the portrait composition. |
| Current renderer | immediate-mode circles, lines, and rounded rectangles; MSAA 0; high-DPI off | Build the identity from the same primitives. Align 1 px lines to half pixels. |
| Current filters | nearest filtering and a pixelated browser canvas | Procedural geometry remains crisp. Texture recipes must not depend on photographic detail. |
| Current typography | LÖVE runtime default font at 9–25 logical px | Raise the floor to 11 px and use the bundled default font plus code-native display lettering. |
| Current event cadence | one canonical event every 0.16 s | A visual scheduler may assign event-specific durations, but it must consume the same immutable event sequence. |
| Input | keyboard, mouse, and touch; a one-second guard suppresses synthetic mouse duplication | Keep a single hit-test path and 48×48 minimum interactive regions. |
| Audio modules | all modules remain enabled because disabling love.js modules caused indirect-call boot failures | Generate cues through `love.sound`/`love.audio`; do not change module flags to optimize bundle size. |
| Build inclusion | `src/` plus `battle/` are zipped into the `.love` archive | Runtime tokens live under `src/ui/`; documentation SVGs stay out of the shipped archive. |
| Simulation purity | `battle/` is plain Lua and rejects `love.*` | Material jitter, particles, and sound RNG belong only in presentation code and use their own local seed. |

The comment near the top of `src/conf.lua` says audio modules are disabled, but
the active configuration deliberately keeps every module enabled. Implement
against the active configuration, not that stale sentence.

The current result is a cool, technical event monitor. Its strongest properties
should survive the restyle: deterministic replay, clear A/B ownership, visible
ordered queues, exact brick HP, a readable current event, pause/step, replay,
and new-seed controls.

## 3. Sources of truth and implementation boundary

`src/ui/art_tokens.lua` is the machine-readable source for colour, logical
surfaces, spacing, type sizes, touch metrics, rarity geometry, material
parameters, behaviour labels, screen rectangles, motion durations, particle
caps, and procedural audio recipes.

The two SVGs beside this document are authored layout references:

- `phone-390x844.svg` shows all four portrait screens at their canonical
  coordinates.
- `desktop-1280x800.svg` shows the landscape dual-arena battle at its canonical
  coordinates.

They contain no linked files, embedded font, bitmap, or external CSS. They are
not exported sprite sheets and should not be loaded by the game. Their purpose
is to give implementers and screenshot review the same geometry.

Content names and rules remain owned by `battle/content/`, `battle/effects.lua`,
and `battle/marble.lua`. The UI maps their existing IDs to a visual treatment;
it must not duplicate or reinterpret their mechanics.

## 4. Palette

Use sRGB hex values exactly as listed. The Lua tokens also expose normalized
0–1 triples for `love.graphics.setColor`.

### Table, chrome, and type

| Token | Hex | Use |
| --- | --- | --- |
| `shadow` | `#0C0907` | Contact shadows and the darkest creases; never body text. |
| `ink` | `#17130F` | Outer letterbox and deepest outlines. |
| `walnut_900` | `#241A14` | Header/footer chrome and dark wood recesses. |
| `walnut_700` | `#4A3022` | Wood body. |
| `walnut_500` | `#75492E` | Wood highlight and active sling arm. |
| `felt_900` | `#18271F` | Main play surface. |
| `felt_700` | `#294238` | Raised play panel. |
| `felt_500` | `#3A5B4D` | Hover/selected felt edge, never a full screen. |
| `paper_100` | `#F5E8CF` | Card face and bright ledger text. |
| `paper_300` | `#DAC8A7` | Card divider, disabled paper, empty pip. |
| `paper_ink` | `#2A211A` | All text on paper cards. |
| `chalk` | `#FFF4DE` | Primary text on dark surfaces. |
| `muted` | `#CBB995` | Secondary text on dark surfaces. |
| `brass_600` | `#B88636` | Dark brass edge. |
| `brass_300` | `#E3C06B` | Craft accent and active border. |
| `brass_100` | `#F7E3A2` | Tiny brass glint only. |
| `damage` | `#DF684F` | Damage flash and lost durability. |
| `restore` | `#7EAD74` | Regeneration and recovered HP. |
| `focus` | `#FFD36A` | Keyboard focus ring; reserved exclusively for focus. |
| `player_a` | `#E09A45` | Player A ownership trace. |
| `player_b` | `#63B8A6` | Player B ownership trace. |

`paper_100` on `ink` has 15.25:1 contrast and `muted` on `felt_700` has
5.65:1. Player A and B both remain just over 4.5:1 on `felt_700`. Do not lower
their opacity for text. Muted non-text decoration may use lower alpha.

### Rarity

| Rarity | Hex | Required geometry |
| --- | --- | --- |
| Common | `#B7AA92` | 1 bead, 1 px rim, smooth shoulders |
| Uncommon | `#71A66E` | 2 beads, 2 px rim, 1 shoulder notch |
| Rare | `#5794BF` | 3 beads, 2 px rim, 2 shoulder notches |
| Epic | `#9A73B5` | 4 beads, 3 px rim, 3 shoulder notches |
| Legendary | `#E1A547` | 5 beads, 3 px rim, 4 shoulder notches |

Every rarity label prints its name. Colour, bead count, rim weight, and card
shoulder shape all repeat the same rank. A greyscale screenshot must still make
the rank recoverable.

### Brick families

| Family | Hex | Silhouette mark |
| --- | --- | --- |
| Basic | `#8D7F68` | square stamp |
| Defensive | `#5E8E86` | shield/chevron stamp |
| Effect | `#8C6C9B` | diamond stamp |
| Utility | `#B07142` | linked-hex stamp |
| Rare | `#C09A4A` | four-point star stamp |

Family colour occupies no more than 18% of a brick or card. The mineral body
remains dominant.

### Shell minerals

| Mineral | Base | Pattern |
| --- | --- | --- |
| Jade | `#5F9F78` | lattice |
| Obsidian | `#342C3C` | shard facets |
| Quartz | `#D8D0B8` | two bands |
| Flint | `#987564` | spiral |
| Silver | `#AAB5B2` | one branching vein |
| Granite | `#756F68` | five mottles |
| Chalk | `#E8DDBF` | plain with two edge nicks |

Lighten a material by mixing toward `paper_100`; darken it by mixing toward
`ink`. Do not add ad hoc colours per component.

## 5. Typography and lettering

The slice has no font-file dependency.

Body text, card copy, names, numerals, and battle captions use
`love.graphics.newFont(size)` so the glyph source ships with the LÖVE runtime
on every target. Cache exactly one font at each token size:

| Role | Size | Rules |
| --- | ---: | --- |
| Micro | 11 | timestamps and keyboard hints only; uppercase, never rules copy |
| Meta | 12 | rarity, family, lane, and resource labels |
| Label | 13 | buttons and short tags |
| Body | 16 | card rules, event caption, settings |
| Card title | 18 | marble, brick, and sling names |
| Section | 20 | screen section heading |
| Display | 28 | phase title and compact verdict |
| Result | 36 | winner/draw line |

Use 1.22× line height, left alignment for all sentences, tabular manual columns
for numeric comparisons, and sentence case for rules. Uppercase is limited to
short labels of 14 characters or fewer.

`CALLACK`, phase numerals, and compact material stamps use a code-native 5×7
stroke alphabet. Implement uppercase A–Z, digits 0–9, space, hyphen, colon,
slash, plus, and multiplication sign as cell masks. Draw each occupied cell as
a rounded 2×2 or 3×3 logical rectangle. The title uses a 3 px cell and 1 px gap;
small stamps use a 2 px cell and 1 px gap. Missing glyphs fall back to the
runtime default font and log once in development. Do not silently show an empty
box.

This gives the title a handmade maker's-mark character while keeping long text
in a proven readable face. If a repository font is introduced later, it must be
SIL OFL or equivalently redistributable and include its license in the same
commit; that is not required for this slice.

### Text fitting

- Never shrink rules text below 16 px.
- Names get one line; a name over the available width wraps to a second line in
  a detail view rather than ellipsizing.
- Rule text gets two lines on an offer row and four on a desktop card. Overflow
  opens the details sheet; do not truncate mechanical terms.
- HP and durability use pips plus an `current/max` accessible text line in
  inspect views.
- Behaviour IDs always have a short text fallback (`ABS`, `REF`, `REG`, etc.)
  from `art_tokens.behaviour`.

## 6. Efficient material recipes

All randomness in this section is visual-only. Use a tiny local MINSTD or
xorshift generator seeded from the material ID and stable board coordinate.
Never consume the battle RNG and never call `math.random` while drawing.
Precompute stable points when an object is created.

### Felt

1. Fill the play region with `felt_900`.
2. Once at load, render a 128×128 Canvas with 72 fibres using seed 9125. Each
   fibre is a 2–6 px line, alternating `paper_300` and `ink` at alpha 0.055.
3. Tile that Canvas across play panels. Rotate every other tile 180 degrees to
   hide repetition.
4. Draw a 1 px inner line in `felt_500` at alpha 0.28 and a 3 px outer contact
   shadow.

Budget: one 128×128 RGBA canvas, no per-frame fibre iteration, no shader.

### Walnut and brass

Walnut pieces use a rounded `walnut_700` body, a 2 px `walnut_900` shadow edge,
and a 1 px `walnut_500` light edge. Five stable, slightly curved grain lines
cross a large panel at alpha 0.14. Small controls get two lines, not five.

Brass hardware uses three shapes: `brass_600` outer circle, `brass_300` inset,
and a single 20-degree `brass_100` arc at alpha 0.75. Never use a gradient or
bloom. A selected brass rim is 2 px; keyboard focus adds a separate 3 px
`focus` ring with a 2 px gap.

### Collector-glass marble

Render back to front at radius `r`:

1. contact shadow: circle at `(x + 0.12r, y + 0.18r)`, radius `1.03r`,
   `shadow` at 0.34;
2. rarity rim: circle line at `r`, rarity colour and the rank-specific width;
3. shell body: outer mineral circle at alpha 0.78;
4. depth: inner circle at `0.78r`, the same mineral mixed 45% toward `ink`, at
   alpha 0.42;
5. shell pattern: 1–2 px lines at 60% material highlight;
6. inner-shell glimpses: for each covered shell after the first, draw one
   24-degree arc on the lower-right rim, outside-in, with a 3 px separation;
7. core: circle at `0.22r`, `paper_100` mixed with the release colour, plus the
   release mark;
8. highlight: ellipse at `(-0.24r, -0.28r)`, radii `(0.24r, 0.13r)`,
   `paper_100` at 0.62;
9. one 70-degree shadow arc on the lower-right edge, `ink` at 0.34.

Do not use blur. A "glow" is at most two circles: a larger colour circle at
alpha 0.08 and a smaller one at alpha 0.14.

Pattern construction:

- lattice: two clipped diagonals in each direction;
- shard: four polygons meeting off-centre;
- banded: two concentric 80-degree arcs;
- spiral: one 2.25-turn polyline with 18 segments;
- veined: a seven-segment trunk with two three-segment branches;
- mottled: five stable circles at 5–12% of `r`;
- plain: no interior line; two 3 px edge nicks identify chalk.

At 56 px diameter or smaller, reduce every pattern to its boldest one or two
strokes. Pattern identity must survive in the formation queue.

### Mineral brick

1. Draw a rounded 4 px contact shadow at `(x + 2, y + 3)`.
2. Draw the family-neutral mineral body.
3. Draw a 3 px top/left bevel mixed 24% toward `paper_100`.
4. Draw a 2 px bottom/right bevel mixed 38% toward `ink`.
5. Add 2–5 stable edge chips as 2–4 px triangular cuts.
6. Add the family stamp in the upper-left 18% and the behaviour sigil centered.
7. Draw HP as three possible round sockets along the lower edge. Filled sockets
   are `paper_100`; lost sockets are `ink` at 0.45 and crossed on the damage
   frame.

The brick's behaviour mark and HP pips remain visible at battle size. Full
`current/max` text appears on focus, pointer hold, or the current-event card.

### Sling

The sling silhouette is two 6 px walnut arms joined by three 1 px curved grain
lines. Each arm has a 7 px brass pin. The pouch is a rounded `walnut_900`
quadrilateral. The band is three parallel 1 px polylines: `paper_300`,
`walnut_900`, `paper_300`. During commitment, the pouch moves 8 px backward;
during release it moves 12 px through rest over the 0.15 s cue.

Archetypes add one small brass part, not a different colour wash:

- volley: twin pins;
- momentum: weighted lower plate;
- ricochet: angled brass shoe;
- spread: forked band guide;
- precision: sight ring;
- effect amplifier: inset mineral bead.

### Paper card

Cards use `paper_100`, `paper_ink`, a 2 px walnut backer offset down 3 px, and a
1 px `paper_300` inner rule. Rarity occupies a 4 px edge plus bead row, never a
full card fill. Selected cards lift 3 px, gain a 2 px brass rim, and show a
check-seal containing text `PICKED`. Keyboard focus is still the separate
yellow ring.

The entire card is the target. Small shell, core, and effect chips inside a card
open details only when they are at least 48×48; otherwise they are descriptive,
not separate controls.

## 7. Visual grammar

### Rarity grammar

Rank is always encoded four ways: printed name, colour, bead count, and shoulder
notches. The shell cap already equals rank (common 1 through legendary 5), so a
marble portrait's visible rings reinforce the same ladder without inventing a
new scale.

Do not use pulsing, animated borders for rarity. Legendary gets the same static
rim treatment as other ranks plus five beads. Motion is reserved for selection
and battle events.

### Shell grammar

The marble portrait is a cutaway:

- `shells[1]`, the current outer shell, owns the full body and pattern;
- later shells appear as lower-right rim arcs in array order;
- durability is a row of 1–3 sockets from 4 o'clock to 8 o'clock;
- a spent durability socket is empty, not red-filled;
- a shell break removes the outer pattern, ejects 6–10 short shards, and reveals
  the next ring;
- an exposed core is never shown as a live rack state. It appears only during
  `core_release` and then leaves play.

Collision type is a small primitive mark beside the shell name: wedge for chip,
double slash for cleave, fork for splinter, barred ring for ward, and filled
hammer for heavy. Cards print the collision label too.

### Effect and brick grammar

Every brick has a family silhouette stamp and one primitive behaviour sigil:

| Behaviour | Label | Sigil |
| --- | --- | --- |
| inert | BASE | centre dot |
| absorb | ABS | inward brackets |
| reflect | REF | opposed chevrons |
| regenerate | REG | broken ring with leaf |
| fortify | FORT | three-block wall |
| poison | PSN | droplet with dot |
| freeze | FRZ | six-spoke flake |
| magnetic | MAG | horseshoe |
| shatter | SHT | broken diamond |
| chain | CHN | linked ovals |
| vault | VLT | stone arch |
| splice | SPL | branching Y |
| dummy | DMY | X crosshair |
| aegis | AEG | pointed shield |
| void | VOID | hollow disc |
| mirror | MIR | split vertical pane |
| temporal | TMP | hourglass |

Persistent status is attached to the affected marble, not painted over the
whole arena: poison gets two green bubbles at the lower-left and freeze gets
three pale edge ticks at the upper-right. Always print the status name and
remaining duration in the inspect card. Magnetic is a one-beat pair of inward
brass ticks at collision; shatter is a one-beat coral crack on the struck shell.
Neither is presented as a persistent status.

Core release marks are outward ring, four shards, double ring, inward ring, and
three-flame for baseline, shrapnel, concussion, magnetize, and scorch. Magic
uses a maximum 0.28 s halo and six motes. There is no idle aura.

### Selection and state

- available: normal material;
- hover/pointer proximity: 1 px `felt_500` or `paper_300` edge;
- pressed: translate down 2 px for 70 ms;
- selected: 2 px brass rim plus text `PICKED` or `PLACED`;
- keyboard focus: 3 px `focus` ring with 2 px gap;
- unavailable: retain hue, add 45% `ink` veil, print the reason;
- damaged: coral flash for 90 ms, then material returns;
- healed: green edge travel for 140 ms, never a full green fill;
- destroyed: material drops to 28% alpha, chips remain as a static silhouette
  until the event beat ends.

## 8. Shared UX rules

All phone coordinates below are `[x, y, width, height]` on the 390×844 logical
surface and are duplicated in the token module.

- Outer content guard: 12 px; main panel inset: 16 px.
- Minimum interactive region: 48×48; primary actions: 56 px high.
- One primary action per phase sits on the bottom reach line.
- A short tap selects. A second tap on the selected object or an explicit
  `DETAILS` control opens the inspector. A 350 ms hold may also open it, but no
  required action depends on holding.
- Dragging is an enhancement. Tap source then tap destination performs the same
  placement or reorder.
- Reorder handles show order numerals. Screen readers and keyboard users receive
  `MOVE EARLIER` and `MOVE LATER` actions.
- A 12 px edge guard prevents cards and drag targets from colliding with browser
  gestures.
- Toasts never cover the primary action. Errors stay until corrected and name
  the cause.
- Player identity uses `A`/`B`, name, and colour together.

## 9. Four phone compositions

The phone layout reference shows these exact regions.

### 9.1 Draft

| Region | Rect |
| --- | --- |
| Chrome | `[12,12,366,52]` |
| Pick progress | `[16,72,358,28]` |
| Offer 1 | `[16,108,358,148]` |
| Offer 2 | `[16,264,358,148]` |
| Offer 3 | `[16,420,358,148]` |
| Current loadout | `[16,584,358,112]` |
| Details hint | `[16,708,358,44]` |
| Confirm pick | `[16,772,358,56]` |

Three offers stack vertically so body text remains 16 px. Each row has a 4 px
rarity edge, 92×92 marble/brick/sling render at left, title and printed rarity
at top-right, two rule lines, then shell/effect chips. A selected offer lifts
and the bottom button changes from `CHOOSE AN OFFER` to `CONFIRM <NAME>`.

The current loadout is a horizontal rack of 52 px portraits with order numbers
and rarity beads. It scrolls only if it exceeds five visible slots. Draft
currency or pick count uses physical brass counters, not a floating HUD number.

On desktop, the current loadout/catalog occupies `[24,96,240,568]`. The offer
panel `[288,96,968,568]` contains three 296×456 cards at x 308, 624, and 940,
with 20 px gaps. The shared action footer is `[24,688,1232,88]`.

### 9.2 Formation and order setup

| Region | Rect |
| --- | --- |
| Chrome | `[12,12,366,52]` |
| Formation/order tabs | `[16,72,358,44]` |
| Board | `[16,124,358,220]` |
| Exact grid | `[21,158,348,148]` |
| Brick bench | `[16,356,358,128]` |
| Marble order rack | `[16,496,358,140]` |
| Sling panel | `[16,648,358,92]` |
| Lock formation | `[16,772,358,56]` |

The 3×7 setup grid uses 48×48 targets with 2 px gaps: exactly 348×148. Row 1,
the front row, receives a brass edge label. Empty cells are felt sockets with a
1 px stitched outline. Placed bricks show behaviour sigil and HP pips; their
full names remain in the bench or inspector.

The bench is a horizontally scrolling run of 96×112 cards. Tap a card, then a
cell; dragging does the same operation. The order rack uses 56 px marbles on a
wood rail. Each has a brass order plate below it. Tap two marbles to swap or
drag one by its 32 px handle. The sling panel shows the code-native sling render,
archetype name, and only the stats the current content record supplies.

`LOCK FORMATION` remains disabled with a written reason until placement and
order are valid. Locking is the only transition to battle.

Desktop uses catalog `[24,96,280,568]`, board `[328,96,616,568]`, and
loadout/sling `[968,96,288,568]`. The central grid uses 72×72 cells with 8 px
gaps: 552×232 inside the board. The catalog can show full 128×168 cards; the
right panel keeps the ordered rack vertical so every order number and name is
visible.

### 9.3 Dual-arena battle

| Region | Rect |
| --- | --- |
| Chrome | `[12,12,366,52]` |
| Opponent arena | `[16,72,358,246]` |
| Volley/event spine | `[16,326,358,156]` |
| Player arena | `[16,490,358,246]` |
| Controls | `[16,744,358,84]` |

The phone table is vertically mirrored around the event spine:

- opponent rack is at the outer top and its formation faces downward toward
  centre;
- player formation faces upward toward centre and its rack is at the outer
  bottom;
- a 3×7 battle grid uses 44×38 noninteractive cells with 4 px gaps;
- row 1 is always the row closest to the centre line;
- lane numbers remain left-to-right for both players.

At `volley_start`, both next marbles receive a brass commitment ring before
either moves. During a cascade, the source sling flexes and the active marble
travels through the centre line to the target grid. Only one resolved cascade
moves at a time, matching the canonical log, but both commitment rings remain
until the volley ends. This communicates simultaneous commitment without
pretending resolution is simultaneous.

The event spine shows, in order: `VOLLEY 07`, two committed marble portraits,
the current event in one 16 px sentence, progress notches, and pause/step/speed/
mute controls. History is a pull-up ledger, not six permanently tiny lines.
Pause never hides the current formation state.

Desktop battle uses opponent arena `[24,96,500,568]`, event spine
`[548,96,184,568]`, player arena `[756,96,500,568]`, and footer
`[24,688,1232,88]`.

In landscape, the two arenas face horizontally:

- opponent rack sits at the far left; its row 1 is the rightmost formation
  column;
- player rack sits at the far right; its row 1 is the leftmost formation
  column;
- the seven lanes run top-to-bottom;
- each brick is 76×52 with 8 px row gaps and 6 px lane gaps;
- opponent formation begins at x 252 and player formation at x 784;
- active trajectories cross the event spine, which temporarily collapses to a
  translucent 80 px lane during travel.

The simulation coordinates do not rotate. A presentation transform maps
`(row,col)` to the chosen axis. Event text, lane labels, and inspect data keep
the canonical row/column numbers.

### 9.4 Result

| Region | Rect |
| --- | --- |
| Chrome | `[12,12,366,52]` |
| Marble-and-sling still life | `[16,80,358,196]` |
| Verdict card | `[16,292,358,170]` |
| Match ledger | `[16,478,358,190]` |
| Primary next action | `[16,692,358,56]` |
| Review battle | `[16,760,174,56]` |
| Replay seed | `[200,760,174,56]` |

Freeze the final material state; do not replace it with generic celebration
art. Move the winning sling and its last living marble into a small tabletop
still life. A draw sets two marbles opposite one another with a shared brass
counter between them.

The cream verdict card prints winner or `DRAW`, canonical reason in plain
language, volley count, bricks remaining, marbles remaining, and seed. The
ledger has three event-derived lines: turning point, final break, and outcome.
If those summaries are not derivable from existing events, show the last three
canonical events rather than inventing analytics.

The primary action is the next slice-defined flow (`DRAFT AGAIN` or `CONTINUE`);
review opens the immutable event ledger; replay uses the same seed. Result
motion is one 0.4 s settle and at most eight brass/paper flecks—no endless
confetti.

Desktop result uses still life `[24,96,596,568]`, ledger
`[644,96,612,568]`, and the shared footer. The left keeps the final arena
remnants behind the still life at 35% contrast; the right shows full event and
seed details.

## 10. Responsive layout rules

The renderer has two authored logical surfaces:

1. Phone portrait: 390×844.
2. Desktop landscape: 1280×800.

Select desktop mode only when physical width is at least 900 and the aspect
ratio is at least 1.2. Otherwise select phone mode. Scale the chosen logical
surface uniformly with `min(windowW/baseW, windowH/baseH)` and center it. Do not
interpolate panel positions between modes.

Desktop acceptance begins at 1024×720. At widths above 1440, center a maximum
1440 px table and extend only felt/wood background. At 1024×720, the 1280×800
surface scales to 80%; pointer targets remain at least 44 physical px. Touch
devices below desktop acceptance use the portrait layout.

The browser shell already applies `env(safe-area-inset-*)` outside the canvas.
Keep an additional 12 logical px internal edge guard. Capacitor and web use the
same rules. A native build without CSS must provide equivalent outer insets
before computing its viewport.

At 390×844, no control may intersect the bottom 12 px or top 12 px. Text does
not rotate. On a desktop window taller than the chosen surface, add walnut
letterbox at top/bottom; on a wider window, extend felt with a walnut edge
rather than pure black.

The existing 320×568 minimum may continue to boot a centered phone surface, but
it is not approved for drafting or formation touch interaction. Either raise
the shipped minimum to the 390×844 acceptance surface or add a later compact
layout; do not claim 48 px targets after uniform downscaling.

## 11. Motion and screen response

Use only three easing functions:

- move/settle: cubic out, `1 - (1 - t)^3`;
- deliberate travel: quadratic in/out;
- opacity: linear.

Do not use elastic looping, idle bobbing, or physics-derived motion.

| Action/event | Duration | Response |
| --- | ---: | --- |
| Tap down | 70 ms | translate 2 px down |
| Tap release | 150 ms | cubic return |
| Card deal | 180 ms | 12 px rise + fade, 45 ms stagger |
| Drag settle | 140 ms | cubic snap into socket |
| `volley_start` | 240 ms | both commitment rings close |
| `launch` | 260 ms | sling release and marble travel start |
| `collision` | 140 ms | 3 px target nudge and contact ring |
| `brick_destroyed` | 200 ms | bevel separates into 4–6 chips |
| `shell_break` | 220 ms | ring peels outside-in, 6–10 shards |
| `core_release` | 280 ms | one restrained halo and six motes |
| `battle_end` | 400 ms | table settles into result still life |

Current playback uses 160 ms for every event. The implementation may replace
that with the table above in presentation code, or preserve 160 ms ingestion
and let visual responses overlap. Either way, event ordering and final state
must remain identical.

Screen response limits:

- camera/table nudge: maximum 3 logical px for 90 ms, toward the impact;
- hit stop: maximum 35 ms on shell break or brick destruction, never on every
  chip;
- damage veil: target arena only, `damage` at alpha 0.08 for 90 ms;
- release glow: target lanes only, release colour at alpha 0.08;
- no rotation of the whole screen;
- no vibration unless a later platform setting opts in.

### Particle language and budget

Particles are pooled tables drawn as circles, lines, or three-point polygons.
No particle allocates a Canvas or Image.

| Material/event | Count | Life | Shape |
| --- | ---: | ---: | --- |
| Felt/card settle | 2–3 | 120 ms | 1 px dust circles |
| Brick chip | 4–6 | 180 ms | mineral triangles |
| Shell break | 6–10 | 220 ms | mineral/glass line shards |
| Brass selection | 3 | 140 ms | 1 px warm sparks |
| Core release | 6 | 280 ms | ring motes |
| Result settle | 8 max | 400 ms | brass/paper flecks |

Cap all live particles at 48 on phone and 96 on desktop. Oldest nonessential
particles are reclaimed first. Particle direction is visual-seeded from event
sequence number and object ID; replays look consistent without affecting the
battle.

## 12. Procedural audio

There is no background music in this slice. Table ambience would become a
large, repetitive asset and is not needed to prove the battle.

At load, generate six mono 16-bit SoundData buffers at 22,050 Hz from
`art_tokens.audio`. Their combined nominal PCM is about 51 KiB. Create static
Sources and reuse a three-source pool per cue. A cue-local MINSTD stream
generates noise; it never touches the battle seed or RNG.

For each sample:

1. interpolate each voice frequency linearly from `from` to `to`;
2. integrate phase, then produce sine, triangle, or seeded white noise;
3. apply a linear attack and an exponential-feeling squared release
   (`remaining^2`);
4. sum voices, multiply master gain 0.72, and clamp to `[-0.92, 0.92]`.

| Cue | Duration | Event use |
| --- | ---: | --- |
| `ui_select` | 45 ms | card pick, placement, order swap, button |
| `sling_release` | 150 ms | `launch` |
| `brick_hit` | 110 ms | `collision`; pitch 0.82 for destroyed brick |
| `shell_break` | 170 ms | `shell_break` only |
| `core_release` | 260 ms | `core_release`; suppress immediate duplicate `blowback` cue |
| `result` | 420 ms | `battle_end`; minor-feeling draw variant lowers middle voice to 311.13 Hz |

Do not sound both `collision` and its following `brick_damaged`; the collision
owns that impact. Enforce a 60 ms per-cue cooldown. `shell_crushed` uses
`brick_hit` at pitch 1.18 unless it also produces `shell_break`, in which case
only the break cue plays. Status application is visual-only in the prototype.

Browsers may suspend audio until a gesture. Initialize SoundData at load, but
resume/play Sources only after the first pointer, touch, or key activation. Do
not emit a delayed backlog of cues after unlock.

## 13. Mute, reduced motion, and legibility

### Mute

- A 48×48 speaker control lives in the battle control region and settings.
- `M` toggles mute on keyboard.
- Mute sets the presentation master gain to zero; it does not pause or alter
  battle playback.
- Persist `muted` with `love.filesystem` as a boolean. Default is false.
- The icon has `SOUND ON`/`MUTED` text in its inspector and changes from three
  sound arcs to a crossed speaker; colour is not the only state.
- Result and UI cues obey mute. There is no forced sound on first launch.

### Reduced motion

Persist `reduced_motion` as a boolean. Default to the web platform preference
when the shell can pass `--reduced-motion`; otherwise default false and expose
the setting. A future web-shell change can read
`matchMedia("(prefers-reduced-motion: reduce)")` and append that argument beside
the existing `--touch` flag.

When enabled:

- card deal, drag settle, sling travel, camera nudge, hit stop, screen veils,
  particles, parallax, and result flecks are disabled;
- state changes use an 80 ms opacity crossfade and a 3 px static outline pulse;
- the active marble is shown at each canonical collision cell rather than
  tweening between cells;
- both commitment rings appear together, so volley semantics remain clear;
- event captions and optional audio continue at normal cadence;
- pause, step, replay, and speed controls remain available.

Reduced motion is not "skip battle." The same events, state, current actor, and
result remain visible.

### Legibility and input

- Body text contrast meets WCAG AA on its prescribed surfaces.
- No rules text is smaller than 16 px.
- Rarity, family, status, ownership, selection, and damage each use label or
  geometry in addition to colour.
- Critical actions contain text. Icons may accompany but never replace them.
- Pointer, touch, and keyboard share focus state and action functions.
- The current event is always present as text; animation is explanatory, not
  the only record of what happened.
- Pause/step controls remain in the battle slice because deterministic review
  is a product strength.

## 14. Runtime architecture contract

The presentation implementation should have these layers:

1. `art_tokens`: immutable values from `src/ui/art_tokens.lua`;
2. `primitives`: marble, brick, sling, card, stamp, and material functions;
3. `layout`: choose phone/desktop and return named rectangles;
4. `screen`: draft, formation, battle, and result composition;
5. `responses`: event-to-motion/particle/audio mapping;
6. `settings`: mute and reduced motion persistence.

`battle/` remains untouched. The battle screen accepts only the projected
presentation model and current canonical event. Draft/formation screens may
eventually produce setup data through a separate controller, but this document
defines no new rule or validation.

Cache:

- seven mineral pattern point sets;
- one 128×128 felt Canvas;
- fonts at the eight prescribed sizes;
- six SoundData buffers and small Source pools;
- optional static meshes/point lists for the sixteen behaviour sigils.

Do not cache one Canvas per marble or brick. The scene is small enough to draw
the primitive layers directly. Target at most 350 draw calls on phone and 500
on desktop with particles at cap.

## 15. Asset contracts

### `src/ui/art_tokens.lua`

- Runtime data, Lua 5.1 compatible, returns one immutable-by-convention table.
- No `love.*` call, file I/O, global mutation, external dependency, or battle
  require.
- Hex and normalized RGB are paired under every colour.
- Existing content IDs are keys: rarity, mineral, behaviour, collision, and
  release mappings must fail loudly when an unknown ID is rendered.
- Layout rectangles are canonical screenshot-review geometry.
- Audio recipes specify synthesis; they are not permission to fetch sounds.

### `docs/art-direction/phone-390x844.svg`

- Four 390×844 phone surfaces: draft, formation/order, dual-arena battle, result.
- Uses only authored SVG shapes and text; no linked resource.
- Coordinates match the Lua layout tokens.
- Reference and review artifact only; never package as a runtime sprite.

### `docs/art-direction/desktop-1280x800.svg`

- One 1280×800 dual-arena desktop reference.
- Shows horizontal facing, event spine, footer controls, material hierarchy, and
  lane/row orientation.
- Uses only authored SVG shapes and text; no linked resource.
- Reference and review artifact only; never package as a runtime sprite.

### Licensing

All three added assets are original project-authored source. They embed no
third-party font, image, sound, trademark, or remote URL. Runtime body lettering
comes from the LÖVE runtime already being distributed with the application;
display lettering is constructed in code. Procedural audio is generated from
the numeric recipes above.

## 16. Acceptance checklist

An implementation meets this bible when:

- `lua5.1 -e 'assert(loadfile("src/ui/art_tokens.lua"))'` passes;
- web still builds under love.js 11.4.1 and desktop under LÖVE 11.5;
- 390×844 screenshots match every named region without cropping or overlap;
- 1280×800 uses the authored landscape layout rather than a tall phone strip;
- every interactive phone target is at least 48×48 at the acceptance surface;
- rules remain 16 px or larger and no required text is ellipsized;
- a greyscale capture preserves rarity rank, brick behaviour, player ownership,
  selection, HP, durability, and status;
- battle visuals are a pure replay of the existing event sequence;
- visual randomness does not consume or change the battle RNG;
- phone stays within 48 live particles and desktop within 96;
- all sound is generated locally, obeys first-gesture unlock, and mutes
  immediately without changing playback;
- reduced motion has no positional tween, camera nudge, hit stop, particle, or
  screen veil;
- no new unlicensed or placeholder asset enters the build;
- no file under `battle/` changes as part of the art implementation.
