# Hen Grenade — Roadmap

Milestones are ordered by risk, not by how satisfying they are to demo. The two things that can genuinely sink this project — a **Raspberry Pi 400** holding 60 FPS, and four controllers behaving on two operating systems — are proven in Milestone 0, before any gameplay is written.

**Milestone 0 needs a physical Pi 400 on the desk.** It is the target machine, its GPU is half a Pi 5's, and nothing about the plan can be validated without one.

Each milestone ends in something runnable on **both** targets. Estimates assume one developer working part-time; treat them as relative sizes, not dates.

---

## M0 — Hardware spike and skeleton *(~1 week)*

**The goal is to be wrong early.** Nothing here is gameplay. Implementation-level detail — project settings, skeleton architecture, input contracts, the benchmark scene composition, and the measurement protocol — is in the [Milestone 0 build brief](milestone-0-brief.md).

- Godot 4.6.3 pinned in `.godot-version`; empty project with the repo layout from the technical design.
- A throwaway scene at the real 640 × 360 base resolution with the full 25 × 15 tilemap, four coloured squares moving around it, and a frame-time overlay.
- **A deliberate worst-case stress scene**, not a hello-world: every crate on screen, a large chain reaction, four squares moving, a regeneration wave landing. Whatever the Pi 400 does here is the honest number.
- **Export to Windows x86_64 and Linux arm64 and run both**, with the Pi 400 as the reference machine.
- **Measure the stress scene at 720p, 1080p and 4K output** to find out how much the final upscale blit actually costs on this GPU, and confirm the borderless-720p-window default behaves. Cheap check now, expensive surprise later.
- **Four Logitech F310s connected at once**, on Windows and on the Pi 400 through a powered hub, all four squares moving independently; unplug and replug one.
- **The three-pads-plus-built-in-keyboard configuration**, which is the only four-player setup a stock Pi 400 supports without extra hardware.
- GitHub Actions running headless Godot and building both artifacts.

**Exit criteria:** 60 FPS on the Pi 400 in the *stress* scene, not the empty one; four pads read simultaneously on both OSes; three pads plus keyboard working; hot-plug detected. If the frame target fails, we revisit the ADR now rather than in month three — this is the milestone whose entire purpose is to catch that.

---

## M1 — Core simulation *(~2 weeks)*

The rule set, headless and tested, with programmer-art rendering on top.

- Fixed 60 Hz sim loop, fixed-point positions, seeded PRNG, `step(state, inputs) -> events`.
- Arena generation (mirrored, seeded, spawn clearances), movement with lane snapping and corner assist.
- Bombs: placement, own-bomb pass-off, fuse, plus-shaped blast, hard block and crate interaction, chain reactions, death.
- Flame ownership through chains, kill credit, and the suicide penalty.
- The 2:00 integer round clock, death → respawn cycle, respawn tile selection, spawn protection.
- GUT unit tests covering blast propagation, chain reactions, and kill credit; replay record + playback harness.

**Exit criteria:** two keyboard players can play a complete, correct two-minute round with respawns and a score; the sim test suite is green headless in CI.

---

## M2 — Players, controllers, and the lobby *(~1.5 weeks)*

- Device manager: press-A-to-join, slot binding by GUID, keyboard slots, hot-plug pause and reconnect flow.
- Lobby screen: four slots, each empty / human / bot, and start. No mode select — free-for-all is the only mode.
- Four-player round working end to end on real hardware.
- Pause menu, quit-to-lobby, rematch flow.

**Exit criteria:** four people on a Pi can start and finish a match without touching a keyboard.

---

## M3 — Power-ups, economy, and match flow *(~2 weeks)*

- Power-up drops, the full table, caps.
- Kick, Toss, Remote, and the Dud curse variants.
- **Kit loss on death** — halve stacking upgrades, lose abilities, scatter the remainder as pickups.
- **Crate regeneration**, with its exclusion rules and the never-seal-a-player-in guarantee.
- Draw handling, best-of-3 match scoring, kills/deaths scoreboard.
- All tuning moved into `.tres` balance resources.

**Exit criteria:** a full best-of-3 match plays start to finish and is *fun* in a real playtest with four people. This is the first honest go/no-go on the design, and specifically the first real answer to three open questions: whether the 23 × 13 interior plays too large, how much a death should cost, and whether crate regeneration feels fair or feels like interference.

---

## M4 — Presentation *(~3 weeks, the long pole)*

**Entry gate: the theme has to be decided before this milestone starts.** It is intentionally open through M0–M3 (light and playful is the only constraint so far) because nothing before this point depends on it — programmer art carries us all the way through the first real playtest. Nothing in M4 can start without it.

- Final tileset and four character sheets with animations (idle, walk ×4, drop, death).
- Blast, smoke, pickup, and death effects within the Pi budget.
- HUD side panels and the round clock; telegraphing pass (fuse pulse, blast preview tint, spawn-protection blink); screen shake with an off switch.
- SFX bank, one music track per arena, ducking.
- Menus: title, lobby, options (audio, video, remapping, accessibility), scoreboard, winner screen.

**Note:** art is the schedule risk, not code. Decide early whether we commission pixel art, use a licensed pack (Kenney and similar), or keep a deliberately minimal geometric style — and record the licence for every asset in `assets/`.

**Exit criteria:** a stranger can sit down, understand what is happening, and play.

---

## M5 — Bots *(~2 weeks)*

- Danger map (tiles that will be on fire, and when) as the shared foundation.
- Behaviours: flee blast, path to power-up, break crates toward an opening, hunt an opponent, and go for a dropped kit after a kill.
- Three difficulties via reaction delay, search depth, and aggression.
- Four-bot soak test: 200 headless rounds, no crashes, no player stuck unable to respawn, sane score spread.

**Exit criteria:** two humans plus two Normal-difficulty bots is a good game.

---

## M6 — Polish and release *(~2 weeks)*

- Balance pass driven by playtest data; tune the numbers, not the code.
- Settings persistence, first-run controller setup guide, in-game credits.
- Packaging: Windows zip, Pi `.tar.gz` with `.desktop` and optional kiosk autostart script.
- `README` and a real Pi 400 setup guide: the F310 X/D switch, the `usbhid.quirks` line, the powered hub for four pads, the three-pads-plus-keyboard alternative, and setting the display to 1080p.
- Tagged 1.0 release built by CI.

---

## Post-1.0 candidates

Online multiplayer (the architecture is ready for lockstep or rollback), team battle and other modes, per-match power-up presets, additional arenas and tilesets, a map editor, replay viewer UI, eight players.

---

## Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| **Pi 400 cannot hold 60 FPS** | **High — the biggest single risk** | Its VideoCore VI is roughly half a Pi 5's GPU, so the positive Godot-on-Pi reports do not transfer, and Godot 4 tilemap games *have* been reported at single digits on this GPU. Hard ban on 2D lights (the documented culprit), 640 × 360 internal resolution, output capped at 1080p, Compatibility renderer, strict draw-call and particle budget, and an M0 exit criterion measured on a worst-case scene. Fallback if it still fails: drop to LÖVE per ADR 0001 |
| User plugs the Pi 400 into a 4K TV and gets a 4K desktop | Medium | `viewport` stretch mode keeps scene cost fixed at 640 × 360 so only the final blit scales; default to a borderless 720p window; kiosk installer sets the mode via `xrandr`; measured at all three output resolutions in M0 |
| Four controllers flaky on Pi 400 (power, enumeration, only three ports) | High | Proven in M0; powered hub is mandatory for four pads and says so in the setup guide; three-pads-plus-built-in-keyboard supported as a first-class alternative; X-mode documented; hot-plug handled as a first-class state |
| Arena plays too large — four players rarely meet | Medium | Grid size is a data file, not code; speed and crate density are the first levers; answered at the M3 playtest |
| Respawn deathmatch balance swings wildly (kit loss, spawn camping) | Medium | Spawn protection and the suicide penalty are in from M1; kit-loss fraction is a single tunable; bot soak test flags degenerate score spreads |
| Accidental non-determinism creeps into the sim | Medium | Golden replay tests in CI from M1; fixed-point positions; single seeded PRNG; no `delta` in sim code |
| Art production stalls the project | Medium | Programmer art through M3; theme and art sourcing strategy both settled before M4 starts; the game must be fun before it is pretty |
| Theme stays undecided past M3 and blocks M4 | Medium | Treated as an explicit M4 entry gate rather than a background question; mechanics are written theme-free so the decision stays cheap right up to that point |
| Game is balanced but not fun | Medium | M3 exits on a real four-player playtest, early enough to change direction cheaply |
| Godot arm64 export gotchas (texture import formats) | Low | Known issue, settings documented in the technical design, exercised in M0 CI |
| Scope creep toward online play | Low | Explicit non-goal; architecture already leaves the door open, so there is no cost to saying "later" |
