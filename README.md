# git

## Description

`git` is a Developer Dashboard skill that adds a nested smart-folder rebuild helper for stacked Git ticket branches.

## Value

It gives the user a repeatable way to rebuild a disposable umbrella branch from `origin/master` while replaying numbered child branches in order and refreshing local marker tags for each step in the stack.

## Problem It Solves

When stacked ticket work is split across branches such as `STACK-11095-1`, `STACK-11095-2`, and `STACK-11095-3`, the umbrella branch is easy to stale or rebuild incorrectly by hand. The user needs one command that can reset the derived umbrella branch, reapply the child commits in the intended order, and stop before any push.

## What It Does To Solve It

The skill exposes `dashboard git.smart.folder update [SMART_FOLDER_BRANCH]`. The helper validates the repository state, resolves the umbrella branch name, fetches remote refs, discovers matching local and remote child branches, recreates the umbrella branch from `origin/master`, cherry-picks the child ranges in numeric order, auto-resolves add/add conflicts by taking the later child version, refreshes local `SM-*` tags, and prints a clear no-push completion message.

When the helper has to continue after an auto-resolved add/add conflict, it forces a non-interactive Git editor setting so `update` does not stall behind `vim` or another editor prompt.

## Developer Dashboard Feature Added

This skill adds:

- the nested dotted command usage `dashboard git.smart.folder`
- a Perl implementation module for smart-folder rebuild logic
- a disposable-repo test suite for stacked branch rebuild behavior
- a worked example script for local or installed DD usage

## Layout

- `skills/smart/cli/folder` nested CLI entrypoint
- `lib/Git/Smart/Folder.pm` smart-folder implementation
- `examples/rebuild-smart-folder.sh` example wrapper script
- `docs/` skill-local documentation
- `t/` skill-local tests
- `.env` skill-local version metadata
- `Changes` skill-local changelog

## Installation

Install the skill through Developer Dashboard from a git repository:

```bash
dashboard skills install <git-url-to-git-skill>
```

Example:

```bash
dashboard skills install git@github.mf:manif3station/git.git
```

## CLI Usage

Direct local development:

```bash
perl skills/smart/cli/folder update STACK-11095
```

Installed DD usage:

```bash
dashboard git.smart.folder update STACK-11095
```

Implicit branch resolution while already checked out on the umbrella branch:

```bash
dashboard git.smart.folder update
```

Expected output includes:

- the resolved smart folder branch name
- the discovered child branches in numeric order
- progress lines while child branches are applied or skipped
- refreshed `SM-*` tag lines
- a final message that no push was performed

## Practical Examples

Normal case, rebuild an explicit umbrella branch:

```bash
dashboard git.smart.folder update STACK-11095
```

Normal case, rebuild from the current umbrella branch:

```bash
git checkout STACK-11095
dashboard git.smart.folder update
```

Normal case, run the shipped example wrapper:

```bash
./examples/rebuild-smart-folder.sh STACK-11095
```

## Edge Cases

- if the command runs outside a Git work tree, it fails clearly
- if the working tree is dirty, it refuses to rebuild
- if `HEAD` is detached and no explicit umbrella name is supplied, it fails clearly
- if the current branch is a child branch such as `STACK-11095-2`, implicit resolution is rejected
- if the current branch is `master` or `main`, implicit resolution is rejected
- if no matching child branches exist, the rebuild fails clearly
- if a child branch adds no commits beyond its base, it is skipped and its marker tag is refreshed at the current rebuilt `HEAD`
- if a conflict is not an add/add conflict, the helper stops for manual resolution
- if Git editor settings would normally open an editor during `cherry-pick --continue`, the helper suppresses that prompt so the auto-resolved path stays non-interactive
- if a cherry-pick is already in progress on the disposable smart-folder branch, the helper aborts that state and rebuilds from scratch
- if a cherry-pick is already in progress on some other branch, the helper still refuses to take over that state
- the rebuild deletes and recreates only the named local smart-folder branch; it does not delete child branches or unrelated branches

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`

## License

`git` is released under the MIT License.

See [LICENSE](LICENSE).
