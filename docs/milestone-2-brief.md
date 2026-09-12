# Milestone 2 — Build Brief

Everything needed to implement M2 without coming back to ask. Read [the roadmap](roadmap.md) for why M2 exists and [the technical design](technical-design.md) §4 for the input reasoning behind it; this document is the executable version, in the same spirit as the [M0](milestone-0-brief.md) and [M1](milestone-1-brief.md) briefs.

**M2 makes the game start like a game.** M1 left a match scene that claims two keyboard layouts on launch because there was nowhere else to decide who is playing. M2 builds that somewhere: a lobby where four people join with the device in their hands, a pause that survives a pad being yanked out of a hub, and a way back to the lobby that is not `Alt+F4`.

Nothing in M2 touches `src/sim/`. Not one line. The rule set was finished and pinned by a golden replay in M1, and if an M2 change makes `test_chains` fail, the change is wrong. What M2 adds sits **above** the sim (round lifecycle, menus) and **beside** it (slot assignment), never inside it.

The exit criterion — *four people on a Pi can start and finish a match without touching a keyboard* — is a hardware criterion. Most of this brief is about making that possible; the last section is about proving it.

---

## 1. Scope

**In scope**

1. **A pure, testable slot-assignment layer.** `DeviceBinder` decides which device drives which player slot — joins, leaves, bots, and the whole hot-plug reconnect dance — as a plain `RefCounted` with no `Node`, no autoload and no `Input` call, so it is unit-testable headless.
2. **`DeviceManager` reduced to an adapter.** Hardware enumeration, edge detection, and `InputSource` construction. Every decision it used to make inline moves into the binder.
3. **A menu input layer.** Menus need buttons the simulation never sees (Start, Y, X, Back). They do not go in `InputFrame`.
4. **The lobby screen.** Four slot cards — empty / human / bot — join, leave, add and drop bots, and start. No mode select; free-for-all is the only mode ([game design §7](game-design.md)).
5. **A round lifecycle in the match scene**: running, paused, waiting for a reconnect, round over. M1's implicit two-state "playing or finished" is not enough once a pause exists.
6. **Pause menu** — resume, restart round, quit to lobby — reachable from Start on any pad.
7. **The hot-plug pause and reconnect flow.** A bound pad disappearing mid-round pauses the match and says whose pad it was; getting it back resumes.
8. **Rematch and quit-to-lobby** from the round-end screen.
9. **A placeholder `BotSource`** so a bot slot is a real slot rather than a label. Real bots are M5.
10. **Tests** for everything above that can be tested without a scene tree, and a lobby entry in the CI scene smoke.

**Out of scope — do not build these**

Power-ups, kit loss, crate regeneration, **best-of-3 match scoring and the scoreboard screen** (all **M3**); real bot behaviour (**M5**); art, audio, animation, telegraphing, an options screen, control remapping, settings persistence (**M4/M6**).

Three borderline calls, resolved:

- **Best-of-3 stays in M3, and so does the scoreboard.** The roadmap puts "rematch flow" in M2 and "best-of-3 match scoring" in M3, and that split is right: a rematch is a lifecycle question (who owns the transition back into a round), match scoring is an economy question (what a round win is worth). M2 ships single rounds with a rematch that keeps the roster and rolls a fresh seed. The word "match" in the M2 exit criterion means "a round, start to finish, without a keyboard".
- **A bot slot is buildable now; a bot is not.** The lobby cannot honestly offer empty / human / bot with the third option greyed out until M5, and the roster, `active_slots`, and HUD paths for a non-human player are worth exercising early. So M2 ships a deliberately stupid placeholder: it wanders and never drops a bomb. It is labelled as a placeholder everywhere it appears, including on screen.
- **No options screen, and no remapping.** Both are M4 menu work. The keyboard layouts stay hardcoded as they were in M0, because on a Pi 400 the built-in keyboard is a first-class seat and its two layouts are part of the design (§4 of the technical design), not a placeholder for a remapping UI.

---

## 2. The slot model

Four slots, fixed for the life of the process, index-stable. Index 0 is P1, and P1 is red, in the lobby, in the HUD, and in `MatchState.players[0]`. Nothing anywhere renumbers slots.

`PlayerSlot` grows from "a slot with a source" into "a slot with a source and the identity of whatever is driving it":

| Field | Meaning |
|---|---|
| `index` | 0–3, never changes |
| `kind` | `EMPTY` / `PAD` / `KEYBOARD` / `BOT` |
| `source` | the `InputSource`, or `null` |
| `connected` | `false` only for a `PAD` slot whose pad has vanished |
| `pad_device`, `pad_guid`, `pad_name` | pad identity; `pad_device` is `-1` while disconnected |
| `kb_layout` | which `KeyboardSource.Layout` claimed this slot |

Two predicates carry the whole design:

- `is_occupied()` — `kind != EMPTY and connected`. This is what the match scene turns into `MatchState`'s `active_slots`, and what the lobby counts to decide whether it can start.
- `is_awaiting_reconnect()` — `kind == PAD and not connected`. A seat being held for someone whose pad fell out. This is what pauses a round.

**Why `pad_device` is cleared on disconnect and `pad_guid` is not.** Godot's device index is a slot in its own table and **gets reused**: unplug pad 2, plug in a different pad, and the new one can be device 2. Matching a returning pad on a stale index would hand P2's seat to a stranger's controller. The GUID identifies the *model*, which is the best any of this can do — see §4.

### 2.1 `DeviceBinder` — the part worth testing

The flakiest logic in this project is not the simulation, which is pinned by a golden replay; it is what happens when four identical F310s share one GUID and the third one falls out of a hub mid-round. That logic was written inline in M0's `DeviceManager`, which is an autoload, and autoloads cannot be reached from a `--script` test process at all ([Appendix A.2](technical-design.md)). It was therefore completely untested.

So it moves out, whole, into `src/input/device_binder.gd`: a plain `RefCounted` that owns `Array[PlayerSlot]` and exposes the decisions as functions. Constructing a `GamepadSource` or a `KeyboardSource` touches no hardware — only `poll()` does — so the binder can build real sources and a test can assert on the resulting roster without ever reading a device.

```
join_pad(device_id, guid, name) -> int      # first free slot, or -1
join_keyboard(layout) -> int
add_bot() -> int
leave(slot) -> bool
device_added(device_id, guid, name) -> int  # unambiguous GUID rebind only, else -1
device_removed(device_id) -> int            # reserve the seat, return it
claim_awaiting(device_id, guid, name) -> int# press-to-claim a reserved seat
release_awaiting() -> Array[int]            # free reserved seats (lobby policy, §4)
```

The binder never decides *when* any of this happens. That is `DeviceManager`'s job, and the difference between the two is the difference between "what should happen if a pad with this GUID appears" and "a pad with this GUID just appeared".

---

## 3. Join, leave, and menu input

### 3.1 Gameplay input is unchanged

`InputFrame` stays exactly as it is: direction, bomb, action, packed into one byte. It is the replay format, it is what bots emit in M5, and it is the only thing the sim ever sees. **Nothing in M2 adds a field to it.** Start and Back are not gameplay, and a pause that the simulation could observe would be a determinism bug waiting to happen.

### 3.2 The one rule players have to learn

> **Join with your bomb button. Leave with your action button.**

That is uniform across every device, and it falls out of the `InputSource` seam rather than being four special cases:

| | Join | Leave | Move |
|---|---|---|---|
| Gamepad | **A** | **B** | D-pad / left stick |
| Keyboard, WASD seat | **Space** | **Q** | `W` `A` `S` `D` |
| Keyboard, arrows seat | **Right Ctrl** | **`/`** | arrow keys |

Leave is only live in the lobby, because B is the action button in a round — that is what Toss and Remote will be bound to in M3, and a player pressing it mid-round must not lose their seat.

### 3.3 Menu input

Menus read hardware directly and do not care about slots: **any** connected pad can confirm a rematch, including one that never joined. This is a deliberate difference from gameplay input, where a device that has not claimed a slot can do nothing at all.

| Menu action | Pad | Keyboard |
|---|---|---|
| `CONFIRM` | A | `Space`, `Enter` |
| `BACK` | B, Back | `Backspace` |
| `START` | Start | `Escape`, `Enter` |
| `ADD_BOT` | Y | `B` |
| `REMOVE_BOT` | X | `N` |
| `UP` / `DOWN` | D-pad, left stick | `W`/`S`, arrows |

`Enter` is deliberately both `START` and `CONFIRM`. `START` means "begin the match" in the lobby and "pause" in a round, and `Escape` is only the obvious key for the second of those — a keyboard player being told to press Escape to start a game is a wart. The two readings never collide because the pause menu checks `CONFIRM` first (so `Enter` chooses the highlighted item) and **the lobby never reads `CONFIRM` at all** — which it must not, since `Space` is the WASD seat's join key and a third player sitting down must not start the match out from under the two already seated.

All of it is **edge-detected once per physics frame inside `DeviceManager`**, which as an autoload is added to the tree before the current scene and therefore always computes its edges before any menu reads them. A menu asks `DeviceManager.menu_pressed(...)`; no menu polls `Input` itself, so no two menus can disagree about what a press means.

**Edges are tracked whether or not the action is allowed.** Pressing `Space` on the title screen advances to the lobby; if the lobby only started tracking that key on arrival it would see a held key as a fresh press and auto-join the WASD seat. Track always, act only when enabled — the same reason M1's tick counters needed exact tests rather than "eventually".

---

## 4. Hot-plug: two policies, one mechanism

The technical design says an unplugged pad pauses the match. That is the right behaviour **in a match** and the wrong behaviour in a lobby, where nobody is mid-round and a pad on the floor is just a pad on the floor. So:

| A bound pad disappears… | What happens |
|---|---|
| **in the lobby** | its seat is **freed**. `kind` back to `EMPTY`. Someone else can take it. |
| **in a match** | its seat is **reserved** (`is_awaiting_reconnect()`), and the round pauses. |

`DeviceManager` owns that choice — the same `binder.device_removed()` mechanism either way, followed by `binder.leave()` in the lobby case. Entering the lobby also releases any seat still reserved from a match that was quit while paused, so a roster can never arrive at the lobby with a ghost in it.

**Reconnect, in order of preference:**

1. **GUID match, unambiguous.** Exactly one seat is waiting for this GUID: rebind it silently and resume. This is the common case — one pad fell out of the hub.
2. **GUID match, ambiguous.** Two or more seats are waiting for the *same* GUID, which is exactly what four identical F310s produce. There is no way to tell them apart, so we do not guess: the notice asks each player to press A, and the seats are claimed in slot order as they press.
3. **A pad with an unknown GUID appears mid-match.** Nothing happens. It cannot join a running round, because `MatchState.active_slots` was frozen at round start.

Press-to-claim for a **reserved** seat works even in a match, where joining is disabled. That is the whole point: a reconnect is not a join.

**And there is always a way out.** If the pad is genuinely dead, `BACK` from the reconnect notice quits to the lobby. A party game that can be soft-locked by a loose USB plug is worse than one with no hot-plug handling at all.

---

## 5. The lobby

One scene, `src/ui/lobby_scene.tscn`, at the real 640 × 360.

```
                        HEN GRENADE
                     press A to join

  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
  │ P1         │ │ P2         │ │ P3         │ │ P4         │
  │            │ │            │ │            │ │            │
  │ Pad 0      │ │ Keyboard   │ │ BOT        │ │ press A    │
  │ F310       │ │ WASD       │ │ placeholder│ │ to join    │
  └────────────┘ └────────────┘ └────────────┘ └────────────┘

  A join   B leave   Y add bot   X drop bot   START begin
  keyboard: Space / Right Ctrl join, Q / slash leave
                    START to begin  ·  2 players minimum
```

- A card is tinted with its player colour when occupied and left dark when empty, because "which square am I" is answered here, before the round, and the four colours are the only identity the programmer art has.
- **Start needs two occupied slots** (`C.MIN_PLAYERS`). The design is 2–4 players; a one-player round has nothing in it.
- Bots fill the **first free slot** and drop from the **last** bot slot, so `Y` `Y` `X` is predictable without a cursor. There is no per-slot cursor in the lobby at all — a player's device *is* their cursor, which is the whole reason press-A-to-join exists.
- The lobby keeps the roster it arrives with. Coming back from a round, the same four people are still seated and `START` plays again.

Draw-call discipline applies here as much as in the arena ([Appendix A.11, A.12](technical-design.md)): card fills in one pass and outlines in another, and no drop shadows on text that sits on a flat background.

---

## 6. The round lifecycle

`MatchScene` gains an explicit phase, because "is the round over" cannot express "paused because P3's pad fell out".

```
                 ┌──────────────── START ─────────────────┐
                 ▼                                        │
   ┌─────────┐ pad lost  ┌───────────┐              ┌───────────┐
   │ RUNNING │──────────►│ RECONNECT │              │  PAUSED   │
   │         │◄──────────│           │              │           │
   └────┬────┘ rebound   └─────┬─────┘              └──┬──┬──┬──┘
        │ clock hits 0:00      │ BACK                  │  │  │
        ▼                      ▼         "Quit to lobby"│  │  │
   ┌────────────┐         quit to lobby ◄───────────────┘  │  │
   │ ROUND_OVER │◄────────────────── "Restart round" ──────┘  │
   └──┬──────┬──┘                     START / BACK / "Resume"─┘
      │      └── BACK ──► quit to lobby
      └── CONFIRM ──► rematch (same roster, fresh seed)
```

Rules that keep this honest:

- **Only `RUNNING` calls `Sim.step()`.** Pausing does not slow the sim down or skip ticks; it stops calling it. The sim has no idea a pause exists, which is the only way it stays deterministic.
- **A paused round records nothing.** `replay.record()` is called from the same place as `Sim.step()`, so a replay is exactly the ticks the sim was given, with no pause gaps to reproduce.
- `RECONNECT` outranks `PAUSED`: a pad falling out while the pause menu is open shows the reconnect notice, and the menu comes back when the pad does.
- **`BACK` closes the pause menu; it does not quit.** B is the in-round action button, four people are holding pads, and abandoning everyone's round on one stray press is too much to hang off a reflex. Quitting is the explicit third menu item. The reconnect notice is the exception, because there is no menu there to back out of — and it is the one place a player might genuinely need out.
- **Restarting or quitting from a pause abandons the round's replay.** A replay is written at a clean round end. Writing a half-round replay whose last input is "someone pressed Start" is a file nobody will ever be glad to have.

---

## 7. Bots — what M2 actually ships

`BotSource` is the fourth implementation of the M0 `InputSource` seam, and the whole point of the seam is that adding it changes nothing else. It:

- picks a cardinal direction from a seeded `SimRng`, holds it for 20–70 ticks, and picks again;
- **never drops a bomb**, so it cannot take a kill, take a suicide penalty, or make a scoreboard look meaningful;
- is labelled `Bot (placeholder)` in the lobby and the sandbox legend.

Two notes for M5. First, this thing is not a bot and is not the beginning of one — M5 starts from a danger map, not from this file. Second, and more interestingly: **a bot does not have to be deterministic for replays to work.** `Replay` records the `InputFrame`s the sim was *given*, not the reasons for them, so even a bot reading the system clock would replay perfectly. Determinism is a requirement on `src/sim/`, not on anything upstream of it. The placeholder is seeded anyway, because a wanderer that does the same thing twice is easier to debug than one that does not.

---

## 8. Tests

Everything that can be tested headless, must be. The line is not "input is untestable" — it is `Input` and `Node` that are untestable in a `--script` process, and the binder is neither.

**`tests/unit/test_device_binder.gd`** — the suite that would have caught the bugs M0 shipped:

- Join fills slot 0, then 1, then 2, then 3; a fifth pad gets `-1` and changes nothing.
- One pad cannot hold two seats; one keyboard layout cannot be claimed twice.
- `leave()` frees the seat, and the freed seat is the next one a join takes.
- Bots take the first free slot; dropping a bot takes the last bot slot and never a human's.
- A disconnect reserves the seat: `is_occupied()` goes false, `is_awaiting_reconnect()` goes true, and the seat is not offered to a joining pad.
- **A returning pad with the same GUID gets its own seat back**, and its `pad_device` is the *new* device id.
- **Two identical pads, both disconnected, then one returns:** it is *not* auto-bound (ambiguous), and press-to-claim gives it the lower-numbered waiting seat.
- A reused device id does not resurrect a stale binding.
- `can_start()` is false at zero and one occupied slots and true at two.
- `release_awaiting()` frees reserved seats and leaves occupied ones alone.

**`tests/unit/test_menu_cursor.gd`** — navigation wraps both ways, a held direction does not repeat, and releasing and pressing again does.

**What stays untested, and why.** `DeviceManager` itself: it is an autoload that reads `Input`, and both halves of that are unreachable from a `--script` process. That is exactly why it is now thin enough to read in one sitting, and why the hard decisions moved out of it. The remaining verification for it is the CI scene smoke and the hardware pass.

## 9. CI

Add the lobby to the smoke scene list. It is a scene with a `_draw` and per-frame input reads, which is precisely the shape of thing [Appendix A.1](technical-design.md) says `--import` will not check and A.13 says a zero exit code will not either.

The match scene is smoked directly, without a lobby in front of it, so it needs a roster from somewhere. M1's `ensure_keyboard_slots()` call comes out of `start_round()` — it is the thing the lobby exists to replace — and is replaced by a dev fallback that only fires when the roster is empty: **two keyboard seats and two bots**. That keeps `F4`-straight-to-match working for development, and it means CI smokes a four-player round with two non-human sources in it rather than an empty arena.

## 10. Exit criteria

1. **Four people on a Pi 400 start and finish a round without touching a keyboard.** Four F310s through a powered hub, all four joining in the lobby, Start, a full two minutes, rematch.
2. **The three-pads-plus-built-in-keyboard configuration does the same thing**, since it is the only four-player setup a stock Pi 400 supports (technical design §4).
3. **A pad unplugged mid-round pauses the game, names the player, and resumes when it comes back.** Tested both ways: unplug and replug the same pad, and unplug one of two identical pads.
4. The pause menu resumes, restarts, and quits to lobby; quit-to-lobby keeps the roster; rematch keeps the roster and changes the layout.
5. **The sim test suite is still green and the golden replay still reproduces.** M2 must not be able to change a rule, and this is how we know it did not.
6. Scene smoke green, including the lobby, on Windows and in CI.

## 11. Suggested order of work

1. `PlayerSlot` grows its identity fields; `DeviceBinder` lifted out of `DeviceManager` wholesale.
2. `test_device_binder.gd` — before the adapter is rewritten, while the behaviour is still fresh.
3. `DeviceManager` rewritten as an adapter: enumerate, edge-detect, delegate, construct sources, emit signals.
4. Menu input layer, `MenuCursor`, and `test_menu_cursor.gd`.
5. `BotSource`.
6. Lobby scene.
7. `MatchScene` phases, pause overlay, reconnect notice, rematch, quit-to-lobby.
8. Title routes to the lobby; sandbox keeps working; smoke list updated.
9. Full headless pass, then the hardware pass on Windows and the Pi 400.
