# Hen Grenade

A local-multiplayer, Bomberman-style arena battler for **Windows** and **Raspberry Pi**, built for four people on one couch with four gamepads.

> **Status: Milestone 3.6 in progress.** The hardware spike passed on a real Pi 400 (M0), the rule set exists and is unit-tested headless (M1), there is a lobby with four-player joining, hot-plug handling and a pause menu (M2), the economy is in (M3), the namesake **Hen Grenade** mode is playable from the lobby (M3.5), and seated players can dress a hunter (hat / clothes / shoes) on the lobby card (M3.6). Deathmatch is still the default. M3 still owes a four-person playtest. Final art, bots, and a theme decision are ahead — see the [roadmap](docs/roadmap.md).

## Playing it

Open the project in **Godot 4.7.2** and press play, or run an exported build. The
title card is a beat; it drops you into the lobby.

**In the lobby, join with your bomb button and leave with your action button.**
Two players minimum, four maximum, any mix of humans and (placeholder) bots.

| | Move | Join / bomb | Leave / action |
|---|---|---|---|
| **Gamepad** | D-pad or left stick | `A` | `B` |
| **Keyboard seat 1** | `W` `A` `S` `D` | `Space` | `Q` |
| **Keyboard seat 2** | arrow keys | `Right Ctrl` | `/` |

`Y` / `X` add and drop a bot (`B` / `N` on the keyboard). **LB / RB** (or `[` / `]`
on the keyboard) cycles **DEATHMATCH** and **HEN GRENADE**. Leaving the chips
alone stays deathmatch. Seated players cycle **hat / clothes / shoes** with the
D-pad (or `WASD` / arrow keys on the keyboard seats). Colour stays red / blue /
yellow / green. **`START` on a pad or `Enter` on the keyboard begins the round**.
So the shortest keyboard-only route from launch to playing is `Space`,
`Right Ctrl`, `Enter`.

In a round, `START` or `Esc` pauses — resume, restart, or quit to the lobby —
and unplugging a controller pauses the game until it comes back.

**A match is best of three** in deathmatch. Each round ends on the 2:00 clock, a
scoreboard shows the kills, deaths and the match tally for four seconds (`A`
skips it), and the next round starts itself. First to two round wins takes the
match; a drawn round takes it from nobody, so a level match plays a decider.

**HEN GRENADE** is one 5:00 round at half crate density. Collect the gold token
to become the Hen — slower, no bombs, a comb silhouette. Die and the token
drops; anyone can take it. Most seconds as the Hen wins. Rematch from the winner
screen starts a fresh 5:00 with the same roster.

On the winner screen, `A` / `Enter` starts a fresh match with the same players
and `B` / `Backspace` returns to the lobby.

**`B` is your ability button, and you have at most one ability.** Walking into a
bomb kicks it if you have Kick; `B` lobs the bomb under your feet two tiles if
you have Toss, or detonates everything you own if you have Remote. Picking up
one of Toss and Remote replaces the other.

Development routes: `F1` title, `F2` stress benchmark, `F3` input sandbox, `F4`
straight into a round with a stand-in roster, `F5` metrics overlay.

Every round is recorded to `user://replays/` as a seed plus an input log — about
29 KB for a full two-minute round, which is what makes "attach the replay to the
bug report" practical.

```bash
# Run the test suite headless (20 suites, 275 tests)
godot --headless --script res://tests/run_tests.gd

# Load and step every scene, the way CI does
godot --headless -- --smoke

# Peak draw calls for the match and stress scenes. Needs a real renderer —
# the headless dummy driver reports zero, so this refuses to run there.
godot --fixed-fps 60 -- --measure
```

Deploy
```
C:\tools\Godot_v4.7\Godot_v4.7.2-stable_win64_console.exe --headless --path "D:\repositories\hen-grenade" --export-release "Linux arm32"

scp build/linux-arm32/HenGrenade.arm32 build/linux-arm32/HenGrenade.pck malna@192.168.1.100:~/hen-grenade/

ssh malna@192.168.1.100 "chmod +x ~/hen-grenade/HenGrenade.arm32"
```

Running

```
./HenGrenade.arm32 --rendering-driver opengl3
```

## What it is

Two to four players share a wide arena, dropping fuse-lit bombs to blast apart crates, grab power-ups, and blow each other up. Dying costs you a second and a half and some of your kit, never the round, so nobody ever sits and watches. **Deathmatch** is two minutes, most kills wins. **Hen Grenade** is five minutes, one hunted player, most time as the Hen wins. No accounts, no online, no menus between rounds — plug in a controller, press A, play.

The tone is light and playful, but **the theme and the final title are deliberately still open** — the design is written theme-free so the decision can wait until art production starts. The namesake mode is in as of M3.5, still on programmer art.

## Planned targets

- **Windows** 10/11, x86_64
- **Raspberry Pi 400**, Raspberry Pi OS **32-bit (armhf)** — the target machine, 60 FPS at 720p
- Up to four USB gamepads (Logitech F310 class), hot-pluggable. Four pads need a powered USB hub on a Pi 400; **three pads plus the built-in keyboard** is a supported four-player setup with no extra hardware

## Documents

| Document | What it answers |
|---|---|
| [Game design](docs/game-design.md) | What the game is: rules, arena, power-ups, modes, feel, non-goals |
| [Technical design](docs/technical-design.md) | How it is built: simulation architecture, input, Pi performance budget, repo layout, testing |
| [Roadmap](docs/roadmap.md) | Milestones M0–M6, exit criteria, and the risk register |
| [Milestone 0 build brief](docs/milestone-0-brief.md) | The executable spec for the first milestone: project settings, skeleton architecture, input contracts, the benchmark scene, and the measurement protocol |
| [Milestone 1 build brief](docs/milestone-1-brief.md) | The executable spec for the simulation layer: the determinism contract, arena generation, movement, blasts and chains, respawn, replays, and the test plan |
| [Milestone 2 build brief](docs/milestone-2-brief.md) | The executable spec for players and controllers: the slot model, join and menu input, the two hot-plug policies, the lobby, and the round lifecycle |
| [Milestone 3 build brief](docs/milestone-3-brief.md) | The executable spec for the economy: the power-up table, the three abilities and the curse, kit loss on death, crate regeneration, best-of-3, and the PRNG draw-count rules that keep all of it deterministic |
| [Milestone 3.5 build brief](docs/milestone-3.5-brief.md) | The executable spec for the namesake mode: lobby select, the Hen token, Hen constraints, time-as-Hen scoring, and the determinism rules that keep deathmatch goldens still |
| [Milestone 3.6 build brief](docs/milestone-3.6-brief.md) | The executable spec for lobby dress-up: three cosmetic layers, per-device cycling, colour-locked hunter drawing, and a hen silhouette that does not wear the outfit |
| [M0 completion notes](docs/progress/m0-completion.md) | What was implemented for M0 and the hardware pass result |
| [M1 completion notes](docs/progress/m1-completion.md) | What was implemented for M1, what was verified, the rule decisions taken, and what is still owed |
| [M2 completion notes](docs/progress/m2-completion.md) | What was implemented for M2, the input decisions taken, and the hardware checks still owed |
| [M3 completion notes](docs/progress/m3-completion.md) | What was implemented for M3, the design calls taken, and the playtest that is the real exit criterion |
| [M3.5 completion notes](docs/progress/m3.5-completion.md) | What was implemented for Hen Grenade mode, and that deathmatch goldens did not move |
| [Pi 400 measurements](docs/measurements/m0-pi400.md) | The performance protocol and the running record every milestone appends to |
| [ADR 0001 — Engine choice](docs/decisions/0001-engine-choice.md) | Why Godot 4.7 over LÖVE, pygame, SDL, and Bevy |

## The short version of the plan

- **Engine: Godot 4.7.2, GDScript, 2D.** It is the only candidate that ships official Windows x86_64 *and* Linux arm32 export templates from one project, and its SDL-backed gamepad layer handles the four-controller requirement without custom code.
- **A 25 × 15 arena at a 640 × 360 internal resolution**, integer-scaled ×2 to 720p and ×3 to 1080p, with the HUD in the side margins — the whole playfield on screen at once, filling a 16:9 display.
- **Gameplay runs in a pure, deterministic 60 Hz simulation** outside the scene tree, with rendering as a read-only view on top. That makes the rules unit-testable headless, gives us replays for bug reports and regression tests, makes bots and humans interchangeable, and leaves online play possible later without a rewrite.
- **Milestone 0 was a hardware spike, not a feature.** Four F310s and 60 FPS on a real Pi 400 — measured on a deliberate worst-case scene, not a hello-world — were proven before a single gameplay rule was written. The Pi 400's GPU is the biggest risk in the project, so it got tested first, and the engine choice was written to be reversible at exactly that point. It passed; Godot stays.
- **Milestone 2 is about the ten seconds before the game starts**, which is where a couch game is won or lost: you press A on the pad in your hand and you are in. The interesting engineering is not the lobby, it is the roster layer under it — joins, leaves, GUID reconnects and the four-identical-controllers case all live in a pure class with no `Node` and no `Input` in sight, so the flakiest logic in the project finally has a test suite instead of a hardware anecdote.
- **Milestone 1 is the rule set, and it is testable rather than watchable.** Bombs, chains, kill credit, respawn and the round clock all live in `src/sim/` as a pure function of state and input, covered by headless tests and golden replays that must reproduce committed state fingerprints. The programmer-art rendering on top is the last thing built, deliberately: if the rules are wrong, watching squares move around will not tell you.
- **Milestone 3 is the first honest go/no-go on the design.** It adds the economy the game needs to be a game — drops, Kick, Toss, Remote, the Dud curse, half your kit scattered on the floor where you died, crates growing back, best of three — and then it gets played by four people who say whether any of it works. Every number behind it is a field in a `.tres`, because "does a death cost too much" is a playtest question and not a code question. The engineering care went where determinism could quietly break: the number of random draws a destroyed crate costs is a constant, and there is a test that asserts it.
- **Milestone 3.5 is the namesake mode, on programmer art, before M4.** Deathmatch stays the default and its golden *state* hashes did not move. Hen Grenade is five minutes, half the crates, one token, one hunted player who cannot bomb and moves at half speed, and the winner is whoever spent the most seconds as that player.
