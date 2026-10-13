#!/usr/bin/env bash
# Points this clone's Git at the versioned hooks in .githooks/.
# Run from anywhere inside the repository.
set -euo pipefail

main() {
  local root
  if ! root="$(git rev-parse --show-toplevel)"; then
    echo "setup-hooks: not inside a Git work tree." >&2
    exit 1
  fi

  local hooks_dir="$root/.githooks"
  if [[ ! -d "$hooks_dir" ]]; then
    echo "setup-hooks: $hooks_dir not found; nothing to set up." >&2
    exit 1
  fi

  find "$hooks_dir" -maxdepth 1 -type f -exec chmod +x {} +
  git -C "$root" config core.hooksPath .githooks

  echo "Made the files in .githooks/ executable."
  echo "Set core.hooksPath to .githooks for $root."
  echo
  echo "Notes:"
  echo "- This setting is local to this clone. Run this script again on a new clone,"
  echo "  or call it from a \`prepare\` script if the project has a package.json."
  echo "- To commit the executable bit, run:"
  echo "    git update-index --chmod=+x .githooks/<hook>"
  echo "- \`git commit --no-verify\` and \`git push --no-verify\` bypass these hooks,"
  echo "  so CI must repeat the same checks."
}

main "$@"
