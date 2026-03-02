---
name: docs-sync-and-commit
description: Check documentation consistency against workspace changes and perform a standard git commit workflow. Use when the user asks to "检查并更新文档后提交", "整理文档并 commit", or any request that bundles doc sync + git commit for the current phase.
---

# Docs Sync and Commit

Run this workflow to enforce a simple rule: if code/data changes, docs should be updated before commit.

## Workflow

1. Run pre-check mode first:
```bash
skills/docs-sync-and-commit/scripts/run.sh --no-commit
```

2. If pre-check fails with doc sync error:
- Update at least one relevant doc file (`README.md`, `docs/*.md`, or other `*.md`).
- Re-run pre-check.

3. Commit with explicit message:
```bash
skills/docs-sync-and-commit/scripts/run.sh -m "feat|fix|docs|chore: summary"
```

## Commit Message Policy

- Use `feat:` for new gameplay/features.
- Use `fix:` for bug fixes.
- Use `docs:` for documentation-only changes.
- Use `chore:` for maintenance or mixed refactors.

## Options

- `--no-commit`: check only.
- `--allow-no-doc`: bypass doc-change requirement when intentionally committing non-doc-only work.
- `-m/--message`: set commit message.

## Resource

- Script entry: `skills/docs-sync-and-commit/scripts/run.sh`
