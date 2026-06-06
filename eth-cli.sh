#!/bin/bash
# Geth CLI wrapper — runs geth attach commands inside the container
# Usage: ./eth-cli.sh <js expression>
docker compose exec -T geth geth attach --datadir /data/geth --exec "$@"
