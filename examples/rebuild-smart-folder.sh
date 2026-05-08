#!/usr/bin/env bash
set -eu

branch="${1:-}"

if [ -n "$branch" ]; then
  exec dashboard git.smart.folder update "$branch"
fi

exec dashboard git.smart.folder update
