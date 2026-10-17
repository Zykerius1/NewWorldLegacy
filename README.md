# New World Life

A text-first Roblox life simulator in the spirit of *BitLife*, set in a New World of
tiered magic, adventurer guilds, and powers that predate the current age.

You are born a nobody — a race, a family, a village — and age up year by year. Every
year brings events; every choice moves your stats, your money, your reputation, and
your odds of seeing another year.

> **Status: design phase.** No game code yet. This repository currently contains the
> project scaffolding only. Implementation begins once the design brief is locked.

---

## Repository layout

```
default.project.json   Rojo project file — maps src/ into the Roblox DataModel
src/
  shared/              Modules and data used by both client and server (event tables, config, types)
  server/              Server-side logic (game state, stat resolution, saving)
  client/              Client-side UI (the screens the player actually sees)
```

`src/` is the source of truth. Place files are **build artifacts** and are gitignored —
never hand-edit a `.rbxlx` and expect it to survive; Rojo builds the place from `src/`.

---

## First-time setup

1. **Roblox Studio** — install if you haven't.
2. **Rojo CLI** — download the release binary for your OS from the Rojo GitHub releases
   page and put it on your `PATH`. Verify with `rojo --version`.
3. **Rojo Studio plugin** — in Studio, open the Toolbox, search **Rojo**, install the
   plugin by `rojo-rbx`.

## Daily workflow

From the repository root:

```bash
git pull
rojo serve
```

Leave `rojo serve` running. In Studio, open a blank baseplate place, click the **Rojo**
plugin, and hit **Connect**. Rojo watches `src/` and live-syncs it into the open place.

To pick up new changes later, `git pull` again — Rojo notices the files changed and
re-syncs automatically. No rebuild, no re-import.

### Building a place file without Studio sync

```bash
rojo build -o build/NewWorldLife.rbxlx
```

The `build/` directory is gitignored.

---

## Conventions

- All work happens on a feature branch, merged via pull request.
- Pull the default branch before starting new work so you branch from current code.
- **All code lives in `src/`.** Anything in `build/` is disposable.

## License

Proprietary. All rights reserved. See [LICENSE](LICENSE).
