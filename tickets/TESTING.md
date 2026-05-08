# TESTING

## Commands

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc "apt-get update && apt-get install -y git >/tmp/git-apt.log && cd /workspace/skills/git && prove -lr t"
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc "apt-get update && apt-get install -y git >/tmp/git-apt.log && rm -rf /workspace/cover_db/git-smart-folder && cd /workspace/skills/git && HARNESS_PERL_SWITCHES=-MDevel::Cover=-db,/workspace/cover_db/git-smart-folder prove -lr t >/tmp/git-skill-prove.log && cover -ignore '^t/' -report text /workspace/cover_db/git-smart-folder"
```

## Latest Result

2026-05-08

- `prove -lr t`: pass
- implementation coverage: `lib/Git/Smart/Folder.pm` reached `100.0` statement coverage and `100.0` subroutine coverage
- disposable smart-folder cherry-pick cleanup was verified to auto-abort only the named local smart-folder branch rebuild path while keeping child branches intact
