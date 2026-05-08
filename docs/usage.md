# Usage

## Local Development

Run the nested CLI directly from the skill repo:

```bash
perl skills/smart/cli/folder update STACK-11095
```

## Installed Developer Dashboard Usage

```bash
dashboard git.smart.folder update STACK-11095
```

When already checked out on the umbrella branch:

```bash
dashboard git.smart.folder update
```

## Example Output Shape

```text
Smart folder branch: STACK-11095
Child branches discovered:
  STACK-11095-1 -> STACK-11095-1
  STACK-11095-2 -> origin/STACK-11095-2
Applying STACK-11095-1 (1 commit(s))
Refreshed tag SM-STACK-11095-1 at <sha>
Applying STACK-11095-2 (2 commit(s))
Refreshed tag SM-STACK-11095-2 at <sha>
Rebuilt STACK-11095 on top of origin/master.
No push was performed.
```

## Example Script

The skill ships an example wrapper:

```bash
./examples/rebuild-smart-folder.sh STACK-11095
```

If no branch name is supplied, the example wrapper forwards to the implicit branch resolution logic in `dashboard git.smart.folder update`.
