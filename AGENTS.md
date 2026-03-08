# AGENTS.md

This file provides guidance to Codex when working with this repository.

## Project Overview
- EVM is an Emacs/Evil multi-cursor package.
- The user tutorial lives in `tutorial/`.
- Current documentation work is focused on keeping `tutorial/` concise, practical, and EVM-specific.

## Read First
- `task_plan.md` — current plan and tutorial-refactor status
- `architecture.md` — package structure and planned tutorial architecture
- `features.md` — implemented behavior with examples

## Documentation Rules
- Keep tutorial text focused on EVM-specific behavior.
- Do not spend tutorial space teaching generic `evil-mode` or `evil-surround` usage beyond the EVM integration points.
- Move repeated tutorial boilerplate into a shared intro file instead of copying it across lessons.
- Prefer editing `tutorial/` for user-facing tutorial work.
- Do not mention planning history in user-facing tutorial text.

## Verification Commands
- `make test-batch`
- `make compile`

## Manual Verification for Tutorial Changes
- Open the edited `tutorial/*.txt` files in Emacs with `evil` and `evim` loaded.
- Run the key sequences described in the lesson text.
- Confirm that examples stay short, self-contained, and still work as manual regression tests.

## Notes
- `features.md` is the living source of truth for supported behavior.
- Tutorial refactor status lives in `task_plan.md`.
