#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

branch="$(git rev-parse --abbrev-ref HEAD)"
push_remote="$(git remote get-url --push origin 2>/dev/null || true)"

if [[ -z "${push_remote}" ]]; then
  echo "origin push remote is not configured" >&2
  exit 1
fi

if [[ "${push_remote}" == *"github.com/p0deje/Maccy"* ]]; then
  echo "origin push remote still points to upstream Maccy: ${push_remote}" >&2
  echo "set origin to your MaccyLite fork before pushing" >&2
  exit 1
fi

if [[ "${branch}" != "master" ]]; then
  echo "current branch is ${branch}; expected master for MaccyLite delivery" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is not clean" >&2
  exit 1
fi

echo "git delivery safety check passed"
