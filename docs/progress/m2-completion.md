# Milestone 2 — Completion Notes

> Status: **code complete and headless-verified; the hardware pass is still owed.** The lobby, the roster layer, the pause and hot-plug flows and the rematch path are all implemented, and 141 tests plus the golden replay are green with a clean scene smoke. What remains is the criterion the milestone actually exits on, and it cannot be faked: four people, four F310s through a powered hub, on the reference Pi 400, starting and finishing a round without touching a keyboard.

- **Date:** 2026-09-12
- **Brief:** [milestone-2-brief.md](../milestone-2-brief.md)
- **Previous:** [M1 completion notes](m1-completion.md)

## Implemented

1. **`DeviceBinder`** (`src/input/device_binder.gd`) — the whole roster decision layer, lifted out of the `DeviceManager` autoload into a plain `RefCounted` with no `Node`, no autoload and no `Input` call. Joins, leaves, bots, GUID reconnects, press-to-claim, seat reservations. **27 tests.**
2. **`PlayerSlot` grew an identity** — `kind` (empty / pad / keyboard / bot), pad GUID, pad name, device index, keyboard layout — and two predicates that carry the design: `is_occupied()` (what becomes `MatchState.active_slots`) and `is_awaiting_reconnect()` (what pauses a round).
3. **`DeviceManager` reduced to an adapter** — enumerate, edge-detect, delegate, construct sources, emit signals. It decides *that* something happened; the binder decides *what should happen*.
4. **A menu input layer** — `CONFIRM` / `BACK` / `START` / `ADD_BOT` / `REMOVE_BOT`, edge-detected once per physics frame, aggregated across every connected device. Nothing was added to `InputFrame`.
5. **The lobby** (`src/ui/lobby_scene.tscn`) — four cards, join / leave / add bot / drop bot / start, a two-player minimum, and the roster kept across rounds.
6. **A four-phase round lifecycle** in `MatchScene`: `RUNNING`, `PAUSED`, `RECONNECT`, `ROUND_OVER`. Only `RUNNING` calls `Sim.step()`.
7. **Pause menu and reconnect notice** (`src/ui/pause_overlay.gd`) over a frozen round, plus `MenuCursor` (`src/ui/menu_cursor.gd`, **10 tests**) for the selection.
8. **`BotSource`** (`src/bots/`) — the placeholder, fourth implementation of the M0 `InputSource` seam.
9. **Rematch and quit-to-lobby**, and the title card now routes to the lobby rather than straight into a round.
10. **CI**: the lobby joined the smoke list; the smoke now renders both overlay modes, self-checks the phase machine, and fails a scene that instantiated without a script.

## Verification performed

| Check | Result |
|---|---|
| `--headless --import --quit` | clean |
| Test suite | **12 suites, 141 tests, 0 failures**, exit 0 |
| Sim suites unchanged and still green | **104 of the 141**, plus the golden replay reproducing both its fingerprint and its trace digest |
| Scene smoke | match / lobby / sandbox / stress all load, step and draw clean; full 7200-tick round; both overlays drawn; phase machine self-check clean |
| Overlays inspected as images | pause menu and reconnect notice captured via `--write-movie` and read back — see A.16 |
| Lobby with a four-player roster | captured and correct: four tinted cards, `START to begin (4 players)` |

**The new smoke self-check was mutation-checked, not just run.** Making a reconnect resume the round instead of returning to the pause menu it interrupted was confirmed to print `FAIL a reconnect did not return to the pause menu` and exit non-zero. Without that, a green smoke would have meant nothing about the phase machine — which is the one M2 component that cannot be unit-tested, because it hangs off an autoload.

## Decisions taken during M2

- **Hot-plug has two policies, not one.** A pad lost *in the lobby* frees its seat; a pad lost *in a match* reserves it and pauses. The technical design only described the match case, and applying it in the lobby would have left seats held by controllers lying on the floor. §4 of the brief, and technical design §4 has been amended.
- **Joining is gated on the lobby; reconnecting is not.** `MatchState.active_slots` is frozen at round start, so a mid-round joiner would get a HUD card and no body. A reserved seat can still be claimed with a press mid-match, because that is a reconnect.
- **Identical pads are not guessed at.** Four F310s share one GUID. With two seats waiting on the same GUID the binder refuses to auto-rebind and the notice asks for a press; seats are then claimed in slot order. Matching on Godot's device *index* instead would be actively wrong — that index is reused, so a stale one can hand a seat to a different controller.
- **Menus read hardware, gameplay reads slots.** Any connected pad can confirm a rematch; only a bound device can move a player. Start and Back deliberately stay out of `InputFrame`, which is the replay format.
- **A bot slot ships, a bot does not.** The lobby could not honestly offer empty / human / bot with the third greyed out until M5, so `BotSource` is a labelled placeholder that wanders and never bombs. Worth recording for M5: **a bot does not have to be deterministic for replays to work** — `Replay` logs the frames the sim was given, not the reasons, so determinism is a constraint on `src/sim/` only.
- **The lobby has no "back".** It is the game's root screen (the title card is a 1.2 s beat that auto-advances into it), and giving it a `BACK` action would have collided with B-to-leave-your-seat. There is nowhere to go back to.
- **`ensure_keyboard_slots()` became `ensure_dev_roster()`** — two keyboard seats plus two bots, fired only when the roster is empty, which now means `F4`-straight-to-match or CI. M1's note said to delete the call from `start_round()`; it is gone from there, and CI got a better smoke out of it (a four-player round with two non-human sources instead of an empty arena).

## Fixed along the way

- **The scene smoke was reporting `OK` for a scene that did not compile.** A parse error in the lobby script produced a node with no script attached, which `instantiate()` reports as success. Exit code 0; only CI's stderr grep was catching it. The smoke now fails any scene whose root has no script. See technical design **A.15** — and note this was a live blind spot for all of M1, not a new one.
- **Join-and-instantly-leave.** The leave check runs after the join check in the same `_physics_process`, so a player holding B while pressing A took a seat and gave it up on the same frame. Leave edges are now seeded at the moment a seat is bound — the same "track always, act on edges only" rule the rest of the file follows, applied at the moment tracking starts.
- **`BACK` on the pause menu no longer abandons the round.** It closes the menu; quitting is the explicit third item. B is the in-round action button and four people are holding pads, which makes a stray press likely enough that it should not cost everyone the round. The reconnect notice keeps `BACK` as its escape hatch, because there is no menu there to back out of.
- **An overlay that is never drawn.** The smoke called `show_menu()` then awaited a single process frame, which slipped past the queued redraw, so the pause menu was never actually rendered in a run whose comment claimed it was. Two awaits. Found by looking at the captured frames rather than at the code. **A.16.**

## Deferred / still owed

- **The hardware pass, which is the exit criterion.** Four F310s through a powered hub on the Pi 400; the three-pads-plus-built-in-keyboard configuration; unplug-and-replug of one pad mid-round; unplug of one of two *identical* pads (the ambiguous path, which is the interesting one). Tracked in [m0-pi400.md](../measurements/m0-pi400.md).
- **The M1 and M2 performance rows** in the same file, still waiting on the M0 numbers being transcribed in the first place. Nothing in M2 should cost frame time — the lobby is 8 rects and 14 Labels with a shadow on exactly one of them, and the overlays only draw while a round is frozen — but "should" is not a measurement.
- **Best-of-3, the scoreboard screen, and draw handling** are M3, per the roadmap. A round-end screen that offers a rematch is as far as M2 goes.
- **Rumble, remapping, options, settings persistence** — M4/M6.

## Open, not worth blocking on

- **One script resource is reported still in use at process exit** (`input_frame.gd`, refcount 1), with an `ERROR: 1 resources still in use at exit` line on stderr that did not appear before M2. It is not a runtime leak: it is a GDScript *class* resource, which lives for the process anyway, and the count does not grow with runtime. It reproduces with a script that does nothing at all, so it happens at load time, before any M2 code runs, and it survives removing the obvious suspects. CI is unaffected (the grep patterns are `SCRIPT ERROR`, `Parse Error`, `Cannot call method`) and exit codes are unaffected. Recorded here rather than guessed at in the Appendix, because a wrong explanation in the lessons file is worse than a known unknown.

## Notes for M3

- **Match scoring wants an owner above the round.** `MatchScene` now owns the round lifecycle, which was the right move for M2, but best-of-3 needs something that survives a scene change — round wins, the match seed, who is still seated. The roster already survives (`DeviceManager` is an autoload); the match record does not.
- `PlayerSlot.card_lines()` is where a lobby card's text comes from. A bot difficulty selector in M5 belongs there and in `DeviceBinder`, not in the lobby scene.
- The pause menu is a fixed three-item list. M3's scoreboard and M4's options screen both want `MenuCursor` with more items and probably a shared panel; `pause_overlay.gd` is the thing to generalise, and it is ~100 lines.
- **Do not add a field to `InputFrame`.** M3 adds Kick, Toss and Remote, all of which are already expressible: `action` exists, packs into the byte, and is not read by any rule yet. If a fourth button ever does become genuinely necessary, the replay format's `HGR1` magic has to move with it or every committed replay silently misreads.
