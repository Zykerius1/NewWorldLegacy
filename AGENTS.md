# New World Legacy — working notes for agents

A text-first Roblox life simulator (BitLife-like) with turn-based tactical combat,
set in the *Overlord* New World. Server-authoritative state; the client renders
whole screens from a view model.

## Layout

| Path | What it is |
|---|---|
| `src/server/GameState.lua` | The whole simulation: character, ageing, events, stats, death, combat entry |
| `src/server/Main.server.lua` | Wiring, `pushState`, server-side warnings |
| `src/server/Combat.lua` | Turn-based combat engine (telegraph, brace, damage) |
| `src/shared/Events.lua` | All 30+ authored events, in tiers |
| `src/shared/Config.lua` | Every tunable number |
| `src/client/Main.client.lua` | Screen construction and `render(view)` |
| `src/client/UiKit.lua` | `create`, `label`, `panel`, `button`, `clear`, `ensureStack` |
| `tools/gen_*.py` | Headless harness generators (see below) |

## Verify before you say it works

```
python3 tools/gen_harness.py       && luau /tmp/harness.luau        # whole lives, events, death
python3 tools/gen_combat_bench.py  && luau /tmp/combatbench2.luau   # combat win rates by play style
python3 tools/gen_card_harness.py  && luau /tmp/card_harness.luau   # every card has a pressable button
rojo build default.project.json -o /tmp/out.rbxl                    # the place builds
```

The generators print only a "wrote …" line; run the generated file to see results.
`luau-analyze` always reports `Unknown global 'script'` / `Color3` / `UDim2` on
Roblox modules — expected, not a defect.

## Conventions that have already cost us bugs

- **`UiKit.clear(parent)` preserves structural children** (`UIListLayout`, `UIPadding`,
  `UICorner`, …). Anything else parented under a frame you clear is gone — including
  frames you built once at startup and expect to reuse. Build reusable containers
  inside the render function, after the clear.
- A card with no visible button is the worst bug this game can have. If you touch
  `renderCard`, run the card harness.
- `ScreenGui.IgnoreGuiInset = true`, with the AGE and HEALTH readouts at the far
  right of the top strip, clear of Roblox's own top-left controls.
- The game runs with `Players.CharacterAutoLoads = false` and the Roblox health and
  backpack UI off. Do not re-enable them; there is no ground in the place.

## Process

Feature branch → PR against `main` → the team lead reviews and merges.
See `/home/team/shared/WORKFLOW.md` for the git and `gh` token details.
