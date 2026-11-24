#!/usr/bin/env bash
# Instala apigeecli (fijar version con APIGEECLI_VERSION) para runners de GitHub Actions.
set -euo pipefail
VERSION=${APIGEECLI_VERSION:-}
if [[ -n "$VERSION" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh" | APIGEECLI_VERSION="$VERSION" sh -
else
  curl -fsSL "https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh" | sh -
fi
echo "$HOME/.apigeecli/bin" >> "${GITHUB_PATH:-/dev/null}"
"$HOME/.apigeecli/bin/apigeecli" --version || true
