# ETHDocker

Self-contained Ethereum node stack. Geth (execution) + Lighthouse (consensus) with optional VPN support.

No third-party images for core components — Geth and Lighthouse built from official binaries with SHA256 verification. Multi-arch (amd64/arm64).

## Quick Start

```bash
# Generate the shared secret for Geth <-> Lighthouse auth
openssl rand -hex 32 > jwt-secret

# Start the stack
./eth.sh up
```

Wait for sync. Add to Metamask: `http://127.0.0.1:8545`, Chain ID `1`.

## Architecture

| Container | Default | Purpose |
|-----------|---------|---------|
| `eth-geth` | Yes | Execution layer — transactions, JSON-RPC, state |
| `eth-lighthouse` | Yes | Consensus layer — beacon chain, proof-of-stake |
| `eth-validator` | No | Validator client — staking (signs attestations/proposals) |
| `eth-vpn` | No | WireGuard VPN tunnel (hides your IP from peers) |
| `eth-vpn-proxy` | No | SOCKS5 proxy through VPN |

Geth and Lighthouse authenticate via shared JWT secret on the Engine API (port 8551, Docker-internal only).

Note: Geth has no native Tor/.onion support (unlike Bitcoin Core), so Tor is not included for P2P. VPN is the privacy tool here. A future Tor hidden service for remote RPC access is planned.

## Ports (localhost only)

| Port | Service |
|------|---------|
| 127.0.0.1:8545 | Geth JSON-RPC (HTTP) — Metamask connects here |
| 127.0.0.1:8546 | Geth WebSocket RPC |
| 127.0.0.1:5052 | Lighthouse Beacon API |

No P2P ports exposed to host.

## Commands

```
./eth.sh <command>

Geth (Execution):
  info        Sync progress, peers, gas price — full dashboard
  peers       Geth peer table (client, block, direction)
  block       Sync progress / latest block
  log         Tail Geth logs
  attach      Interactive Geth JS console
  rpc <json>  Raw JSON-RPC call to localhost:8545

Lighthouse (Consensus):
  beacon      Beacon chain sync status
  beaconpeers Lighthouse peer table
  beaconlog   Tail Lighthouse logs
  finality    Finalization checkpoints

Validator (Staking):
  validator <on|off>  Toggle validator client
  vallog      Tail validator logs
  valstatus   Validator status

VPN:
Explorer:
  explorer <on|off>  Toggle Blockscout explorer
  explorerlog Tail explorer logs

VPN:
  vpn <on|off>  Toggle VPN (requires vpn/wg0.conf)
  vpnlog      Tail VPN logs
  myip        Check exit IP (verify VPN is working)
  speedtest   Run speedtest through VPN
  mode        Show current status (VPN/Validator/Explorer/sync mode)

Stack:
  up          Start all containers
  down        Stop all containers
  nuke        Stop and remove all images
  status      Container status
  logs        Tail all logs
  update      Update images
```

## Sync

Two modes controlled by `.env`:

| Mode | .env sample | Geth size | Use case |
|------|-------------|-----------|----------|
| **Snap** | `.env.snap.sample` | ~800GB | Wallets, Metamask, transactions |
| **Archive** | `.env.archive.sample` | ~2TB+ | Block explorer, historical queries, debug/trace |

```bash
# Snap sync (default — lightweight)
cp .env.snap.sample .env

# Archive sync (full history — for explorer)
cp .env.archive.sample .env
```

- **Lighthouse**: Checkpoint sync from a public beacon API (syncs in minutes, then backfills)

Monitor both with `./eth.sh info`.

## Validator (Staking)

The validator client is off by default. It uses Docker Compose profiles — the container doesn't exist until you enable it.

```bash
# 1. Make sure Geth and Lighthouse are fully synced first
./eth.sh info

# 2. Set your fee recipient address in docker-compose.yml
#    Find: --suggested-fee-recipient=0x0000000000000000000000000000000000000000
#    Replace with your actual Ethereum address

# 3. Import your validator keys into ./data/validator/
#    (key import depends on how you generated them — see Lighthouse docs)

# 4. Enable the validator
./eth.sh validator on

# 5. Monitor
./eth.sh vallog
./eth.sh valstatus

# Disable when needed
./eth.sh validator off
```

**Important**: Never run the same validator keys on two machines simultaneously — this will get you slashed.

## Explorer (Blockscout)

Self-hosted block explorer. Requires archive mode for full history.

```bash
# 1. Set up archive mode
cp .env.archive.sample .env
# Edit .env to set your data paths

# 2. Start the stack and wait for sync
./eth.sh up

# 3. Enable the explorer
./eth.sh explorer on

# Access at http://127.0.0.1:4000
```

The explorer indexes blocks as Geth syncs. On a fresh archive sync this takes days.

## VPN Setup

```bash
# Place your WireGuard config
cp your-wireguard-config.conf vpn/wg0.conf

# Enable VPN
./eth.sh vpn on

# Verify your exit IP
./eth.sh myip
```

All P2P traffic routes through the VPN tunnel. Peers see the VPN exit IP, not yours.

## System Requirements

### Minimum
- **CPU**: 4 cores
- **RAM**: 16GB
- **Storage**: 1.5TB NVMe SSD (800GB Geth snap sync + 200GB Lighthouse + headroom)
- **OS**: Linux (amd64 or arm64), Docker Engine 24+
- **Network**: Unmetered connection recommended (initial sync pulls ~1TB)

### Recommended
- **CPU**: 8+ cores
- **RAM**: 32GB (Geth and Lighthouse both benefit from extra RAM for caching)
- **Storage**: 2TB+ NVMe SSD (leaves room for state growth and pruning headroom)

### Notes
- SATA SSDs will work but sync significantly slower — NVMe strongly preferred
- HDD will not work (random I/O too slow for state trie access)
- Initial sync takes 12-48 hours depending on hardware and network
- After sync, reduce `--cache=4096` to `--cache=1024` in docker-compose.yml to free RAM
- Not recommended for laptops — use dedicated server or desktop

## Updating

```bash
# Rebuild all local images with current versions
./eth.sh update

# Update Geth to a specific version (update SHA256 checksums in Dockerfile first)
./update.sh --geth 1.17.4 abc12345

# Update Lighthouse to a specific version
./update.sh --lighthouse 8.2.0
```

## Security

- All RPC ports bound to 127.0.0.1 only
- JWT authentication between Geth and Lighthouse (Engine API)
- Config files and JWT secret gitignored
- No third-party images for execution/consensus
- SHA256 verification of all downloaded binaries
- Validator keys stored in gitignored `data/validator/` directory
