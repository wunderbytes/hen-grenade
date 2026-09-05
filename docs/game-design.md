# Hen Grenade — Game Design Document

> Status: draft for review. Numbers marked **(tune)** are starting values to be balanced in playtesting, not commitments.
>
> **Theme is deliberately undecided.** The tone we are aiming for is light and playful — bright, cartoonish, nobody takes a loss personally — but no setting or character fiction is chosen yet. This document uses plain mechanical names (bombs, crates, players) so the rules stand on their own, and so a theme can be layered on later without rewriting the design. "Hen Grenade" is a working title. See §10.

## 1. Pitch

Hen Grenade is a local-multiplayer arena battler in the Bomberman tradition, played as a **timed deathmatch**. Two to four players share a wide arena, dropping fuse-lit bombs to blast apart crates, grab power-ups, and blow each other up. Death costs you a couple of seconds and some of your kit, not the round — you respawn and get straight back in. Two minutes, most kills wins.

## 2. Design pillars

1. **Couch-first.** Everything is designed around four people on one sofa looking at one screen. No accounts, no menus between rounds, no waiting for a lobby. Plug in a pad, press A, you are in.
2. **Readable at a glance.** With four players, twelve bombs, and a screen full of fire, a player must be able to tell in a quarter of a second where the blast will reach. Silhouette, colour, and telegraphing beat visual richness every time.
3. **Fair, then chaotic.** The core rules are strictly symmetric and deterministic. Chaos comes from power-ups and the scramble for a dead player's dropped kit, never from an unclear rule or a fuzzy hitbox.
4. **Nobody sits out.** You are never eliminated. A death costs about a second and a half, and the round always ends on the clock, so no one is ever watching other people play.
5. **Runs on the TV in the corner.** 60 FPS on a Raspberry Pi 400 is a design constraint, not just an engineering one — it caps our effects budget and pushes us toward crisp, high-contrast 2D art.

## 3. Core loop

```
Lobby (join with controller)
  └─> Match (best of 3, first to 2 round wins)
        └─> Round (fixed 2:00)
              ├─ move on grid, drop bombs, break crates, grab power-ups
              ├─ die -> drop part of your kit -> respawn after 1.5 s
              └─ clock hits 0:00: most points wins the round
        └─> Scoreboard (kills / deaths, 4 s, skippable)
  └─> Winner screen -> rematch (A) or back to lobby (B)
```

There is no elimination, no last-player-standing, and no stalemate to break: the clock always resolves the round.

## 4. The arena

The arena is **25 tiles wide × 15 tiles tall**, sized to fill a 16:9 screen with the whole playfield visible at once and the HUD living in the leftover margins.

- One-tile indestructible wall around the edge; playable interior is **23 × 13**.
- **Hard blocks** (indestructible pillars) sit at every interior tile where both coordinates are even — the classic Bomberman lattice, which is what makes blast lines readable at a glance.
- **Crates** (destructible soft blocks) fill **~70% (tune)** of the remaining interior, minus spawn clearances.
- Layouts are generated for one quadrant and mirrored four ways from a **per-round seed** shown on the scoreboard, so no corner is luckier than another and a good layout can be replayed.

**Why 15 rows and not 16.** The brief asked for 16 × 25; 15 rows was chosen and agreed instead, because the pillar lattice requires an **odd** interior in both axes. With 14 interior rows the bottom row of the lattice ends up as pillars pressed against the wall, the top and bottom halves stop mirroring, and the four corners stop being equivalent starting positions. 25 × 15 keeps the lattice and the four-way symmetry intact and still fills the widescreen properly: at a 640 × 360 internal resolution with 20 px tiles the arena is 500 × 300, leaving a 70 px HUD panel down each side and a 30 px band top and bottom for the round clock. The margins are the point — they are where the HUD lives, so nothing is wasted.

Arena dimensions live in a data file, not in code, so this is cheap to change after a playtest.

**A 23 × 13 interior is roughly twice the free area of a classic Bomberman battle arena, and that is the main balance risk in this design.** Four players in a space that size can spend a lot of time not meeting each other, which is poison for a deathmatch. The levers, in the order I would pull them: raise base movement speed (already done below), raise crate density so the early arena is a tight maze, then shrink the interior. Worth watching in the first four-player playtest.

## 5. Player mechanics

### 5.1 Movement

- Speed is in **tiles per second**; base **3.5 t/s (tune)**, up from a classic-Bomberman-ish 3.0 to suit the larger arena. Power-ups step it by +0.6, capped at **6.0**.
- Movement is free along an axis but **snapped to the perpendicular lane** — you always walk down the middle of a corridor. This is the single most important feel decision in the genre.
- **Corner assist:** if a player pushes into a wall while a perpendicular opening is within **6 px (tune)**, they slide toward the opening instead of stopping. Without this the game feels like it is fighting you; with too much of it, it feels floaty.
- Players do not collide with each other. Player-vs-player collision in a tile game causes far more frustration (blocked in a corridor, shoved into a blast) than it adds.

### 5.2 Bombs

- Default loadout: **1 bomb, blast radius 1, fuse 2.5 s (tune)**.
- A bomb is dropped on the tile the player's centre occupies and is **solid to everyone except the player still standing on it** — you may step off your own bomb, but not back onto it.
- **Chain reaction:** a bomb caught in a blast detonates on the same tick.
- The blast is a plus-shape from the bomb's tile: it extends up to `radius` tiles in each direction, **stops at hard blocks**, and **destroys exactly one crate** before stopping in that direction. Flames persist **0.4 s (tune)** and kill any player whose centre tile they occupy.
- Every flame tile remembers **which player's bomb produced it**, including through chains. That owner gets the kill credit.

### 5.3 Death, respawn, and scoring

Death is a setback, not an exit.

- **One hit kills.** There is no health bar.
- On death you **drop part of your kit** (§6) and respawn after **1.5 s (tune)**.
- **Respawn placement:** the game picks, from the currently free tiles, the one that maximises distance from living players, live bombs, and flames, drawn from a set of ~10 designated respawn tiles spread across the arena. Corner spawns alone are not enough when players are dying every few seconds.
- **Spawn protection:** 2 s (tune) of invulnerability, clearly signalled by blinking. It ends early the moment you drop a bomb, so it cannot be used as an offensive shield.

Scoring within a round:

| Event | Score |
|---|---|
| Kill another player | **+1** to the bomb's owner |
| Die to your own bomb | **−1** to yourself |

The suicide penalty matters more than it looks: with a 1.5 s respawn, blowing yourself up is otherwise nearly free, and self-preservation has to stay a real consideration.

The round ends when the clock reaches **0:00** — always, with no overtime. Highest score wins the round; an equal top score is a draw and nobody takes the round. A match is **best of 3**, first to 2 round wins; if the match itself ends level, play a decider.

## 6. Power-ups

Dropped by destroyed crates at a **~30% (tune)** rate, weighted by the table below. A power-up caught in a later blast is destroyed, which creates real "grab it now" tension.

| Power-up | Effect | Weight | Cap |
|---|---|---|---|
| Extra Bomb | +1 concurrent bomb | high | 8 |
| Bigger Blast | +1 blast radius | high | 8 |
| Speed Up | +0.6 t/s | medium | 6.0 t/s |
| Kick | Walk into a bomb to slide it until it hits something | medium | on/off |
| Toss | Hold and release to lob your bomb two tiles over walls | low | on/off |
| Remote | Bombs no longer auto-fuse; press B to detonate all of yours | low | on/off |
| Jackpot | Blast radius jumps to max | rare | — |
| Dud (curse) | A timed debuff, 8 s: reversed controls, or forced constant bomb-dropping, or radius 1, or glued at max speed | low | — |

Design intent: Extra Bomb and Bigger Blast are the bread and butter, always meaningful, never game-ending on their own. Kick and Toss change how you think about space. Remote is the skill pick — highest ceiling, easiest way to blow yourself up. The Dud exists so that hoovering up every drop carries risk.

### 6.1 What you lose when you die

Starting rule **(tune)**: stacking upgrades (bombs, blast, speed) are **halved, rounded down**; ability power-ups (Kick, Toss, Remote) are **lost entirely**. Everything lost scatters as pickups on free tiles around where you died.

This is the most important balance dial in the game and it will need real playtesting. Losing everything makes deaths brutal and the last minute unwinnable for anyone behind; losing nothing lets a strong player snowball unopposed for two minutes. Halving keeps a good player ahead while making each death bleed, and it turns the spot where someone died into a contested pile worth fighting over.

### 6.2 Keeping the arena stocked

A two-minute round with four players and growing blast radii strips the arena of crates in about a minute. Without a fix, the second half of every round is a bare box where nobody can rebuild after a death — the exact opposite of the comeback dynamic §6.1 is trying to create.

So crates **regenerate**: every **20 s (tune)** a small wave of crates drops onto random free tiles, with a short telegraphed landing animation. Hard rules — never on a tile occupied by a player, bomb, flame, or pickup; never adjacent to a living player; never in a way that leaves a player with no exit; and a cap on total crates so the arena cannot silt up.

If this proves fiddly in practice, the simpler fallback is to skip crate regeneration and instead drop a lone power-up onto a random free tile every 15 s. It solves the supply problem but not the "the arena has become an empty field" problem, so crates are the first choice.

## 7. Modes

**Free-for-all is the only mode.** Two to four players, any mix of humans and bots, timed deathmatch as described above.

Bots are a first-class feature, not a stretch goal: two-player sessions are the common case and a pair of bots makes them much better. Three difficulty levels (internally Easy / Normal / Hard) differing in reaction delay, escape-route search depth, and willingness to take aggressive trades.

Team play, and any other mode, is deferred (§9).

## 8. Presentation

- **Pixel art**, 20 × 20 px tiles, with 4-colour-plus-outline character palettes so the four players read instantly as red / blue / yellow / green even at a distance.
- Base render resolution **640 × 360**, integer-scaled to the display (×2 at 720p, ×3 at 1080p). Nearest-neighbour filtering, no sub-pixel camera movement.
- Layout: the 500 × 300 arena centred, a **70 px HUD panel down each side** carrying two player cards each (score, bombs, blast, speed, abilities, respawn countdown), and the **round clock** centred in the top band. The clock changes colour and ticks audibly for the last 10 seconds.
- The whole arena is always on screen. No camera work, no split screen.
- **Telegraphing is a rendering requirement:** bombs pulse faster as the fuse runs out, flames have a 3-frame anticipation, a bomb about to detonate tints the tiles its blast will cover, and respawning players blink for the duration of their spawn protection. Readability beats realism.
- Audio: short, punchy, mono-friendly SFX (TV speakers), one music loop per arena, distinct per-player death and kill stings. Music ducks under explosions.
- Accessibility: colourblind-safe player markers (a shape badge, not just hue), an option to disable screen shake and flashing, and remappable controls.

## 9. Explicit non-goals for 1.0

- **Online multiplayer.** The architecture keeps the door open (see the technical design), but shipping netcode is a separate project.
- **Team battle**, and every other mode besides free-for-all.
- **Per-match power-up presets** in the lobby. One balanced default rule set for now.
- Elimination-style rounds, a shrinking arena, or sudden death. The 2:00 clock is the only round-ending mechanism.
- Single-player campaign, story, unlocks, progression, or cosmetics economy.
- 3D, dynamic lighting, or anything else that spends the Pi's modest GPU budget on things that do not improve a two-minute round.
- More than four players. Four USB pads and one screen is the target living room.

## 10. Open design questions

1. **Theme and title.** Deliberately open. The tone is light and playful; the setting is not chosen. Mechanically nothing depends on it, but art production does, so this needs an answer **before Milestone 4** — everything up to and including the first real playtest can run on programmer art. Whatever we pick must survive the readability pillar: four instantly distinguishable player silhouettes and blast lines you can read at a glance.
2. **Does the 23 × 13 interior play too large for four players?** (§4) First playtest question, cheap to change.
3. **How much kit should a death cost?** (§6.1) Half is a starting guess, not a considered answer.
4. **Crate regeneration or periodic power-up drops?** (§6.2) Depends on whether regenerating crates feel like a fair part of the arena or like random interference.
5. **Is two minutes the right round length,** and is best-of-3 the right match length at ~6–7 minutes total?
