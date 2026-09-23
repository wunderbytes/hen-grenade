# Milestone 3.6 — Build Brief

Everything needed to implement **lobby character customization** without coming back to ask. Read [the roadmap](roadmap.md) for where this sits (after Hen Grenade, before M4 art), [game design §8](game-design.md) for colour-as-identity, and [technical design §5 and A.11–A.12](technical-design.md) for the draw-call rules it has to obey. Same spirit as the [M0](milestone-0-brief.md)–[M3.5](milestone-3.5-brief.md) briefs.

**M3.6 is a presentation-on-programmer-art slice, not a rules milestone.** Theme is still open. The pieces are geometric shapes M4 can replace. Nothing lands in `src/sim/`, `InputFrame`, or replay fingerprints. Deathmatch golden *state* hashes must not move.

Players dress a hunter on the lobby card. That look draws in-match on hunters only. The Hen does not wear the outfit; it keeps a hen silhouette in the player’s main colour.

---

## 1. Scope

**In scope**

1. **Three cosmetic layers** on each seated player: head/hat, clothes, shoes/accessory. Each layer has its own option count (head 9, clothes 7, shoes 4), including “none” on hat and shoes.
2. **Lobby cycling** from the bound device: up/down selects the layer, left/right cycles the option. The device is still the cursor ([M2 brief §5](milestone-2-brief.md)).
3. **Lobby preview and in-match hunter drawing** from one painter. Slot colour stays the body fill.
4. **A clearer hen silhouette** (oval, comb, beak, tail, legs) in the same slot colour. No cosmetic layers on the Hen.
5. **Tests** for wrap, reset-on-leave, and tint. Scene smoke still green.

**Out of scope — do not build these**

Final art, animation, an options screen, settings persistence (**M4 / M6**); unlocks or a cosmetics economy (game design §9); unique-outfit enforcement; changing the sim, goldens, or `InputFrame`; D-pad for mode select; a shared lobby cursor.

Borderline calls, resolved:

- **Looks live on `PlayerSlot`, not `MatchState` or `Session`.** The roster already survives lobby ↔ match. The sim must not see a hat.
- **Leaving a seat resets the outfit.** The next person to sit there does not inherit a hat. A pad that vanishes *in a match* is reserved, not left: the look stays through reconnect.
- **Bots do not cycle.** They get a look derived from slot index (no RNG) so four placeholders are not identical.
- **Duplicates are allowed.** Colour is identity.
- **No hold-repeat** on customize edges. A sticky stick must not skip three hats.

---

## 2. What the sofa sees

Occupied lobby cards grow a small figure on the right of the card. That player’s device cycles their own look. Nobody navigates to a slot.

| | Select layer | Cycle option |
|---|---|---|
| **Pad** (bound only) | D-pad / left stick up-down | D-pad / left stick left-right |
| **WASD seat** | `W` / `S` | `A` / `D` |
| **Arrows seat** | up / down | left / right |

**LB / RB, Y / X, A / B, START** stay mode / bots / join / leave / begin ([M3.5 §5.1](milestone-3.5-brief.md)). Do not extend `DeviceManager.Menu` for this: those actions are aggregated across every device, which would make four people fight over one outfit.

`DeviceManager.menu_dir()` is the same trap (any pad’s stick, plus W/S). Customize is **per occupied human slot**, edge-detected from that slot’s pad or keyboard layout, and only while `join_enabled`.

Help lines grow one clause (`D-pad look`, `WASD / arrows look`). No extra Labels per layer (A.11). The selected layer is a tick on the preview.

HUD cards stay text-only. Colour plus the in-arena body is enough.

---

## 3. Catalog

Mechanical names, no theme fiction. Index 0 is the simplest look. Counts differ per layer; cycling wraps on that layer's own length.

| Layer | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| Head | `NONE` | `CAP` | `CONE` | `BALL` | `EARS` | `MOHAWK` | `PROP` | `BOW` | `ANTENNA` |
| Clothes | `TUNIC` | `VEST` | `OVERALLS` | `SASH` | `SKIRT` | `PLEATS` | `TUTU` | | |
| Shoes | `NONE` | `BOOTS` | `SNEAKERS` | `PACK` | | | | | |

Clothes always draw a body so the hunter stays a readable 14 × 14. Hat and shoes may be empty. Boots, sneakers, and the pack are drawn **outside** the body outline: a 1 px stroke is painted last and used to swallow anything that only occupied the bottom edge, and a downward-facing pack used to sit in the hat band.

**Main colour is the body fill:** `C.PLAYER_COLORS[slot]`. Overlays are darker/lighter of the *same* hue plus a black outline and a cream accent. Never a second player colour.

`CharacterArt` (`src/view/character_art.gd`) is the single painter the lobby preview and `EntityView` both call.

---

## 4. Drawing and the Pi budget

Hunters today are two rect passes (fill, then outline). Cosmetics stay **passes grouped by primitive** (A.12): all bodies, all clothing bands, all hats of a kind, all shoes, then all outlines — not hat+body+shoe per player.

The Hen path stays a **separate pass after hunters**, with **no cosmetic layers**. Programmer art: oval body, comb, beak in the facing direction, short tail, two stick legs; fill and outline in slot colour. There is one hen, so one extra polygon/circle pass is the budget (same rule as M3.5).

Facing pip stays on hunters and on the Hen.

---

## 5. What does not change

- Blast math, chains, scoring, kit, curses, pause, reconnect, replay file layout, input encoding, lobby mode chips.
- Deathmatch golden state hashes and traces.
- M4’s theme gate. These shapes are placeholders.

---

## 6. Tests

Headless, no scene tree for catalog/wrap/reset:

- Layer and option wrap; `PlayerSlot.clear()` / binder `leave()` reset to zeros.
- Reconnect (`device_removed` then `device_added`) **keeps** the look.
- `add_bot()` assigns a slot-index look, not all zeros on every bot.
- Tint helper, for every slot colour, is never equal to another slot’s palette colour.
- Existing suites stay green unmodified. **If a state hash or trace digest moves, stop — the sim was touched by mistake.**

Scene smoke: lobby still instantiates and draws; match hunters still draw. Do not add cosmetics to replay bytes. No new golden.

---

## 7. Suggested order of work

1. Docs + `PlayerSlot` fields + `CharacterArt` catalog, wrap, tint.
2. Binder: reset on leave, keep on reconnect, bot look on `add_bot`.
3. Per-slot customize edges on `DeviceManager`; lobby applies them and draws the preview.
4. `EntityView` batched hunters; hen silhouette upgrade.
5. Tests and smoke.

---

## 8. Exit criteria

1. Two seated humans can change hat, clothes, and shoes independently on the lobby cards, and those hunters draw that way in a round.
2. Slot colour is still the body; P2-as-hunter with a cap is still blue.
3. The living Hen is a hen silhouette in that player’s colour, not the hunter outfit.
4. Leave resets; quit-to-lobby keeps the roster *and* the looks of people still seated; reconnect mid-match keeps the look.
5. Sim suite green. Deathmatch goldens identical to M3.5. Scene smoke green.
