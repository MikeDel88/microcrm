#!/usr/bin/env bash
# Démarre ou arrête la stack ELK.
# Usage : ./elk.sh up | down
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE=(sudo docker compose --env-file .env.elk -f compose.elk.yml)

case "${1:-}" in
  up)   exec "${COMPOSE[@]}" up -d ;;
  down) exec "${COMPOSE[@]}" down ;;
  *)
    echo "Usage : $0 up | down" >&2
    exit 1
    ;;
esac
