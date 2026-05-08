# Overview

`git.smart.folder` is a nested Developer Dashboard command for disposable umbrella branch rebuilds.

## Command

```bash
dashboard git.smart.folder update [SMART_FOLDER_BRANCH]
```

The command always rebuilds from `origin/master`, never from the previous umbrella branch tip.

## Supported Branch Pattern

Given an umbrella branch like `STACK-11095`, the helper looks for numbered children such as:

- `STACK-11095-1`
- `STACK-11095-2`
- `STACK-11095-3`

Local child branches override matching `origin/*` child branches with the same numeric suffix.

## Conflict Rules

- add/add conflicts are auto-resolved with `--theirs`, meaning the later child branch version wins
- every other conflict type stops the rebuild for manual resolution

## Tagging

The command refreshes local marker tags after each child branch step:

- `SM-STACK-11095-1`
- `SM-STACK-11095-2`
- `SM-STACK-11095-3`

These tags mark the rebuilt smart-folder commits, not the original child branch commits.
