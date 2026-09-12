#!/bin/sh
# Enable this repo's secret protection. Run once per clone.
#
# Git does not clone hook or filter configuration, so a fresh clone has
# neither until this runs. Both are needed: the filter keeps secrets out of
# commits transparently, the hook refuses the commit if the filter is absent.
set -e
cd "$(dirname "$0")/.."

git config filter.strip-config-secrets.clean "scripts/strip-config-secrets.py"
git config filter.strip-config-secrets.smudge cat
git config core.hooksPath scripts/git-hooks

echo "Enabled:"
echo "  clean filter  -> config/config.json is committed with sessionSecret removed"
echo "  pre-commit    -> blocks any commit carrying a live secret"
