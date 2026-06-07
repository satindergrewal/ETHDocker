#!/bin/bash
# ETH Docker Stack — single command interface
# Usage: ./eth.sh <command>

set -euo pipefail
cd "$(dirname "$0")"

# Detect VPN mode and set compose command accordingly
if [ -f .vpn-mode ]; then
    DC="docker compose -f docker-compose.yml -f docker-compose.vpn.yml"
else
    DC="docker compose"
fi

# Enable optional profiles
PROFILES=""
[ -f .validator-mode ] && PROFILES="validator"
[ -f .explorer-mode ] && PROFILES="${PROFILES:+$PROFILES,}explorer"
[ -n "$PROFILES" ] && export COMPOSE_PROFILES="$PROFILES"

case "${1:-help}" in
    # Geth (Execution Layer)
    peers)
        $DC exec -T geth geth attach --datadir /data/geth --exec "JSON.stringify(admin.peers)" 2>/dev/null | python3 -c "
import sys,json
try:
    raw = sys.stdin.read().strip().strip('\"')
    peers = json.loads(raw.replace('\\\\','\\\\').encode().decode('unicode_escape'))
except:
    print('No peers or Geth not ready'); sys.exit()
if not peers:
    print('No peers connected'); sys.exit()
# Parse client name
def short_name(name):
    parts = name.split('/')
    client = parts[0] if parts else '?'
    version = parts[1] if len(parts)>1 else '?'
    return f'{client}/{version}'
# Header
print(f'Geth v1.17.3 — {len(peers)} peers')
print()
print(f'{\"dir\":<5} {\"client\":<35} {\"block\":>12}  {\"eth\":>4}  {\"address\":<25}')
print('-' * 90)
for p in sorted(peers, key=lambda x: x.get('network',{}).get('inbound',False)):
    d = 'in' if p.get('network',{}).get('inbound') else 'out'
    name = short_name(p.get('name','?'))
    eth = p.get('protocols',{}).get('eth',{})
    block = eth.get('latestBlock',0) if isinstance(eth,dict) else 0
    ver = eth.get('version','?') if isinstance(eth,dict) else '?'
    addr = p.get('network',{}).get('remoteAddress','?')
    # Trim port-only local addresses
    if ':' in addr:
        ip = addr.rsplit(':',1)[0]
    else:
        ip = addr
    print(f'{d:<5} {name:<35} {block:>12,}  {ver:>4}  {addr:<25}')
# Summary
inb = sum(1 for p in peers if p.get('network',{}).get('inbound'))
out = len(peers) - inb
print()
print(f'in: {inb}  out: {out}  total: {len(peers)}')
" 2>/dev/null || echo "Geth not reachable"
        ;;
    block)      $DC exec -T geth geth attach --datadir /data/geth --exec "eth.syncing || 'synced at block ' + eth.blockNumber" ;;
    log)        $DC logs -f geth ;;
    attach)     $DC exec geth geth attach --datadir /data/geth ;;
    rpc)        shift; curl -s -X POST -H "Content-Type: application/json" --data "$1" http://127.0.0.1:8545 | python3 -m json.tool 2>/dev/null || curl -s -X POST -H "Content-Type: application/json" --data "$1" http://127.0.0.1:8545 ;;

    # Sync progress and node summary
    info)
        python3 << 'PYEOF'
import json,subprocess,sys,os

def rpc(method, params=[]):
    try:
        r = subprocess.run(['curl','-s','-X','POST','-H','Content-Type: application/json',
            '--data',json.dumps({'jsonrpc':'2.0','method':method,'params':params,'id':1}),
            'http://127.0.0.1:8545'], capture_output=True, text=True, timeout=5)
        return json.loads(r.stdout).get('result')
    except: return None

def geth_js(expr):
    try:
        r = subprocess.run(['docker','compose','exec','-T','geth','geth','attach',
            '--datadir','/data/geth','--exec',expr],
            capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except: return None

def beacon(path):
    try:
        r = subprocess.run(['curl','-s','http://127.0.0.1:5052'+path],
            capture_output=True, text=True, timeout=5)
        return json.loads(r.stdout)
    except: return None

h = lambda x: int(x,16) if x and x!='0x' else 0

# === Geth ===
print('=== Geth (Execution) ===')
syncing = rpc('eth_syncing')
block_num = rpc('eth_blockNumber')
chain_id = rpc('eth_chainId')
gas_price = rpc('eth_gasPrice')

# Get version and peers via IPC (admin API not on HTTP)
version_raw = geth_js('admin.nodeInfo.name')
peers_raw = geth_js('JSON.stringify({total: admin.peers.length, inb: admin.peers.filter(function(p){return p.network.inbound}).length})')

# Chain info
chain = {1:'mainnet',11155111:'sepolia',17000:'holesky'}.get(h(chain_id),'chain '+str(h(chain_id))) if chain_id else '?'
version = '?'
if version_raw:
    parts = version_raw.strip('"').split('/')
    version = parts[1] if len(parts)>1 else version_raw

print('  Chain: '+chain)
print('  Version: '+version)

# Sync
if syncing == False:
    block = h(block_num) if block_num else 0
    print('  Block: {:,}'.format(block))
    print('  Sync: 100%')
elif syncing:
    current = h(syncing.get('currentBlock','0x0'))
    highest = h(syncing.get('highestBlock','0x0'))
    accounts = h(syncing.get('syncedAccounts','0x0'))
    storage = h(syncing.get('syncedStorage','0x0'))
    bytecodes = h(syncing.get('syncedBytecodes','0x0'))
    healed = h(syncing.get('healedTrienodes','0x0'))
    healing = h(syncing.get('healingTrienodes','0x0'))
    tx_remaining = h(syncing.get('txIndexRemainingBlocks','0x0'))
    if highest > 0 and current >= highest:
        print('  Block: {:,}'.format(current))
        print('  Sync: 100%')
        if tx_remaining > 0:
            # Get TX index rate from logs
            try:
                r = subprocess.run(['docker','compose','logs','--tail','10','geth'],
                    capture_output=True, text=True, timeout=10)
                import re
                for line in reversed(r.stdout.splitlines()):
                    if 'Indexing transactions' in line:
                        done = re.search(r'blocks=([\d,]+)', line)
                        elapsed = re.search(r'elapsed=(\S+)', line)
                        if done and elapsed:
                            done_n = int(done.group(1).replace(',',''))
                            el_str = elapsed.group(1)
                            # Parse elapsed like "16m35.528s" or "1h2m3s"
                            secs = 0
                            hm = re.findall(r'(\d+\.?\d*)([hms])', el_str)
                            for val, unit in hm:
                                if unit == 'h': secs += float(val) * 3600
                                elif unit == 'm': secs += float(val) * 60
                                elif unit == 's': secs += float(val)
                            if done_n > 0 and secs > 0:
                                rate = done_n / secs
                                eta_secs = int(tx_remaining / rate)
                                eta_m, eta_s = divmod(eta_secs, 60)
                                eta_h, eta_m = divmod(eta_m, 60)
                                if eta_h > 0:
                                    eta_str = '{}h{}m'.format(eta_h, eta_m)
                                else:
                                    eta_str = '{}m{}s'.format(eta_m, eta_s)
                                print('  TX index: {:,} blocks remaining  ETA: {}'.format(tx_remaining, eta_str))
                            else:
                                print('  TX index: {:,} blocks remaining'.format(tx_remaining))
                        else:
                            print('  TX index: {:,} blocks remaining'.format(tx_remaining))
                        break
                else:
                    print('  TX index: {:,} blocks remaining'.format(tx_remaining))
            except:
                print('  TX index: {:,} blocks remaining'.format(tx_remaining))
    elif highest > 0:
        pct = current/highest*100
        print('  Block: {:,} / {:,}'.format(current, highest))
        print('  Sync: {:.2f}%'.format(pct))
        # Get ETAs from logs (different formats for snap vs archive sync)
        try:
            r = subprocess.run(['docker','compose','logs','--tail','20','geth'],
                capture_output=True, text=True, timeout=10)
            import re
            found_eta = False
            for line in reversed(r.stdout.splitlines()):
                if 'chain download in progress' in line:
                    eta = re.search(r'eta=(\S+)', line)
                    if eta:
                        print('  ETA (chain): '+eta.group(1))
                    found_eta = True
                    break
            if not found_eta:
                # Archive sync — estimate ETA from block import rate
                imports = []
                for line in r.stdout.splitlines():
                    if 'Imported new chain segment' in line:
                        num = re.search(r'number=([\d,]+)', line)
                        ts = re.search(r'\[([^\]]+)\]', line)
                        if num and ts:
                            imports.append((int(num.group(1).replace(',','')), ts.group(1)))
                if len(imports) >= 2:
                    from datetime import datetime
                    try:
                        t0 = datetime.strptime(imports[0][1], '%m-%d|%H:%M:%S.%f')
                        t1 = datetime.strptime(imports[-1][1], '%m-%d|%H:%M:%S.%f')
                        secs = (t1 - t0).total_seconds()
                        blocks_done = imports[-1][0] - imports[0][0]
                        if secs > 0 and blocks_done > 0:
                            rate = blocks_done / secs
                            remaining = highest - current
                            eta_secs = int(remaining / rate)
                            eta_h, rem = divmod(eta_secs, 3600)
                            eta_m, _ = divmod(rem, 60)
                            if eta_h >= 24:
                                eta_d = eta_h // 24
                                eta_h = eta_h % 24
                                print('  ETA: {}d {}h {}m  ({:.0f} blocks/sec)'.format(eta_d, eta_h, eta_m, rate))
                            else:
                                print('  ETA: {}h {}m  ({:.0f} blocks/sec)'.format(eta_h, eta_m, rate))
                    except:
                        pass
            for line in reversed(r.stdout.splitlines()):
                if 'state download in progress' in line:
                    st_pct = re.search(r'synced=([\d.]+%)', line)
                    eta = re.search(r'eta=(\S+)', line)
                    if st_pct and eta:
                        print('  State: {}  ETA: {}'.format(st_pct.group(1), eta.group(1)))
                    break
                elif 'state healing in progress' in line:
                    pending = re.search(r'pending=(\d+)', line)
                    if pending:
                        print('  State: healing ({:,} pending)'.format(int(pending.group(1))))
                    else:
                        print('  State: healing')
                    break
        except:
            pass
    elif accounts > 0 or storage > 0:
        print('  Phase: Snap sync (downloading state)')
        print('  Accounts: {:,}  Storage: {:,}  Bytecodes: {:,}'.format(accounts, storage, bytecodes))
        if healed > 0 or healing > 0:
            print('  Healing: {:,} done, {:,} pending'.format(healed, healing))
    else:
        # Check logs for header download progress
        try:
            r = subprocess.run(['docker','compose','logs','--tail','50','geth'],
                capture_output=True, text=True, timeout=10)
            for line in reversed(r.stdout.splitlines()):
                if 'Syncing beacon headers' in line:
                    import re
                    dl = re.search(r'downloaded=([\d,]+)', line)
                    left = re.search(r'left=([\d,]+)', line)
                    eta = re.search(r'eta=(\S+)', line)
                    if dl and left:
                        d_num = int(dl.group(1).replace(',',''))
                        l_num = int(left.group(1).replace(',',''))
                        total = d_num + l_num
                        pct = d_num/total*100 if total>0 else 0
                        print('  Phase: Downloading headers')
                        print('  Headers: {:,} / {:,}'.format(d_num, total))
                        print('  Sync: {:.2f}%'.format(pct))
                        if eta:
                            print('  ETA: '+eta.group(1))
                    break
            else:
                print('  Phase: Starting (finding headers)')
        except:
            print('  Phase: Starting (downloading headers)')
else:
    print('  Sync: not reachable')

# Peers
try:
    pd = json.loads(peers_raw.strip('"').replace('\\"','"'))
    total = pd['total']
    inb = pd['inb']
    out = total - inb
    print('  Peers: in {}, out {}, total {}'.format(inb, out, total))
except:
    print('  Peers: ?')

# Gas price
if gas_price:
    gwei = h(gas_price) / 1e9
    print('  Gas price: {:.2f} gwei'.format(gwei))

print()

# === Lighthouse ===
print('=== Lighthouse (Consensus) ===')
lh_sync = beacon('/eth/v1/node/syncing')
lh_version = beacon('/eth/v1/node/version')
lh_peers = beacon('/eth/v1/node/peer_count')
lh_finality = beacon('/eth/v1/beacon/states/head/finality_checkpoints')

if lh_version and 'data' in lh_version:
    print('  Version: '+lh_version['data']['version'])

if lh_sync and 'data' in lh_sync:
    d = lh_sync['data']
    head = int(d['head_slot'])
    dist = int(d['sync_distance'])
    target = head + dist
    el = 'online' if not d.get('el_offline') else 'OFFLINE'
    if dist <= 64:
        print('  Slot: {:,}'.format(head))
        print('  Sync: 100%')
    else:
        pct = (head/target*100) if target > 0 else 0
        print('  Slot: {:,} / {:,}'.format(head, target))
        print('  Sync: {:.2f}%'.format(pct))
        print('  Remaining: {:,} slots'.format(dist))
        # Get ETA from logs
        try:
            r = subprocess.run(['docker','compose','logs','--tail','5','lighthouse'],
                capture_output=True, text=True, timeout=10)
            import re
            for line in reversed(r.stdout.splitlines()):
                if 'est_time' in line:
                    eta = re.search(r'est_time:\s*"([^"]+)"', line)
                    speed = re.search(r'speed:\s*"([^"]+)"', line)
                    if eta:
                        print('  ETA: '+eta.group(1))
                    if speed:
                        print('  Speed: '+speed.group(1))
                    break
        except:
            pass
    print('  Execution layer: '+el)
else:
    print('  Sync: not reachable')

if lh_peers and 'data' in lh_peers:
    d = lh_peers['data']
    print('  Peers: connected {}, connecting {}'.format(d['connected'], d['connecting']))

if lh_finality and 'data' in lh_finality:
    fin = lh_finality['data']
    epoch = fin.get('finalized',{}).get('epoch','?')
    print('  Finalized epoch: '+str(epoch))

print()

# === Ready status ===
geth_synced = (syncing == False) or (syncing and highest > 0 and current >= highest)
lh_synced = lh_sync and 'data' in lh_sync and int(lh_sync['data'].get('sync_distance','1')) <= 64
el_online = lh_sync and 'data' in lh_sync and not lh_sync['data'].get('el_offline')

if geth_synced and lh_synced and el_online:
    print('READY — Node is fully synced and accepting connections')
    print('  JSON-RPC:  http://127.0.0.1:8545')
    print('  WebSocket: ws://127.0.0.1:8546')
    print('  Beacon:    http://127.0.0.1:5052')
    print('  Metamask:  http://127.0.0.1:8545  Chain ID: 1')
else:
    reasons = []
    if not geth_synced: reasons.append('Geth syncing')
    if not lh_synced: reasons.append('Lighthouse syncing')
    if not el_online: reasons.append('Execution layer offline')
    print('NOT READY — '+', '.join(reasons))

print()

# === Mode ===
vpn = 'ON' if os.path.exists('.vpn-mode') else 'OFF'
val = 'ON' if os.path.exists('.validator-mode') else 'OFF'
print('VPN: {}  Validator: {}'.format(vpn, val))
PYEOF
        ;;

    # Lighthouse (Consensus Layer)
    beacon)     curl -s http://127.0.0.1:5052/eth/v1/node/syncing | python3 -m json.tool 2>/dev/null || curl -s http://127.0.0.1:5052/eth/v1/node/syncing ;;
    beaconpeers)
        curl -s "http://127.0.0.1:5052/eth/v1/node/peers?state=connected" 2>/dev/null | python3 -c "
import sys,json
try:
    data = json.load(sys.stdin)['data']
except:
    print('Lighthouse not reachable'); sys.exit()
if not data:
    print('No peers connected'); sys.exit()
# Extract IP from multiaddr: /ip4/1.2.3.4/...
def parse_addr(ma):
    parts = (ma or '').split('/')
    ip = '?'
    proto = '?'
    for i,p in enumerate(parts):
        if p == 'ip4' and i+1 < len(parts): ip = parts[i+1]
        if p == 'ip6' and i+1 < len(parts): ip = parts[i+1]
        if p in ('tcp','udp') and i+1 < len(parts): proto = f'{p}/{parts[i+1]}'
        if p == 'quic-v1': proto = 'quic'
    return ip, proto
inb = sum(1 for p in data if p.get('direction')=='inbound')
out = len(data) - inb
print(f'Lighthouse v8.1.3 — {len(data)} peers')
print()
print(f'{\"dir\":<5} {\"transport\":<10} {\"peer_id\":<20} {\"address\":<25}')
print('-' * 65)
for p in sorted(data, key=lambda x: x.get('direction','')=='inbound'):
    d = 'in' if p.get('direction')=='inbound' else 'out'
    pid = p.get('peer_id','?')[:18] + '..'
    ip, proto = parse_addr(p.get('last_seen_p2p_address',''))
    print(f'{d:<5} {proto:<10} {pid:<20} {ip:<25}')
print()
print(f'in: {inb}  out: {out}  total: {len(data)}')
" 2>/dev/null || echo "Lighthouse not reachable"
        ;;
    beaconlog)  $DC logs -f lighthouse ;;
    finality)   curl -s http://127.0.0.1:5052/eth/v1/beacon/states/head/finality_checkpoints | python3 -m json.tool 2>/dev/null || curl -s http://127.0.0.1:5052/eth/v1/beacon/states/head/finality_checkpoints ;;

    # Validator
    vallog)     $DC logs -f validator ;;
    valstatus)  $DC exec -T validator lighthouse vc --datadir /data/validator --network mainnet validator-list 2>/dev/null || echo "Validator not running. Enable with: ./eth.sh validator on" ;;
    validator)
        shift
        case "${1:-}" in
            on)
                touch .validator-mode
                export COMPOSE_PROFILES="validator"
                echo "Enabling validator client..."
                $DC up -d validator
                echo "Validator ON. Import keys to ./data/validator/ before it can attest."
                echo ""
                echo "IMPORTANT: Set your fee recipient address in docker-compose.yml"
                echo "  --suggested-fee-recipient=0xYOUR_ADDRESS"
                ;;
            off)
                echo "Stopping validator client..."
                $DC stop validator
                $DC rm -f validator
                rm -f .validator-mode
                echo "Validator OFF."
                ;;
            *)
                echo "Usage: ./eth.sh validator <on|off>"
                echo "  on   = Start validator client (requires imported keys)"
                echo "  off  = Stop validator client"
                echo ""
                echo -n "Status: "
                [ -f .validator-mode ] && echo "ON" || echo "OFF"
                ;;
        esac
        ;;

    # Explorer
    explorer)
        shift
        case "${1:-}" in
            on)
                touch .explorer-mode
                PROFILES="explorer"
                [ -f .validator-mode ] && PROFILES="validator,$PROFILES"
                export COMPOSE_PROFILES="$PROFILES"
                echo "Starting Blockscout explorer..."
                $DC up -d explorer-db explorer-redis explorer
                echo "Explorer ON. Access at http://127.0.0.1:4000"
                echo ""
                echo "NOTE: Explorer works best with archive mode (GETH_SYNCMODE=full, GETH_GCMODE=archive)"
                ;;
            off)
                echo "Stopping explorer..."
                $DC stop explorer explorer-redis explorer-db
                $DC rm -f explorer explorer-redis explorer-db
                rm -f .explorer-mode
                echo "Explorer OFF."
                ;;
            *)
                echo "Usage: ./eth.sh explorer <on|off>"
                echo "  on   = Start Blockscout explorer"
                echo "  off  = Stop explorer"
                echo ""
                echo -n "Status: "
                [ -f .explorer-mode ] && echo "ON — http://127.0.0.1:4000" || echo "OFF"
                ;;
        esac
        ;;
    explorerlog) $DC logs -f explorer ;;

    # VPN
    vpnlog)     $DC logs -f vpn ;;
    vpn)        shift; ./toggle-vpn.sh "$@" ;;
    myip)
        echo "Checking exit IP..."
        echo ""
        if [ -f .vpn-mode ]; then
            echo "VPN:"
            $DC exec -T vpn sh -c "wget -qO- https://ipinfo.io 2>/dev/null" || echo "  no internet"
            echo ""
        fi
        echo "Host:"
        curl -s https://ipinfo.io 2>/dev/null || echo "  check failed"
        echo ""
        ;;

    speedtest)
        if [ -f .vpn-mode ]; then
            echo "Running speedtest through VPN..."
            $DC exec -T vpn sh -c "which speedtest-cli >/dev/null 2>&1 || apk add --no-cache -q speedtest-cli >/dev/null 2>&1; speedtest-cli --simple"
        else
            echo "No VPN active. Running speedtest from host..."
            which speedtest-cli >/dev/null 2>&1 && speedtest-cli --simple || echo "Install speedtest-cli to run speedtest"
        fi
        ;;

    # Stack
    up)         $DC up -d ;;
    down)       $DC down ;;
    nuke)       $DC down --rmi all ;;
    status)     $DC ps ;;
    logs)       $DC logs -f ;;
    update)     shift; ./update.sh "$@" ;;
    mode)
        echo -n "VPN: "
        [ -f .vpn-mode ] && echo "ON" || echo "OFF"
        echo -n "Validator: "
        [ -f .validator-mode ] && echo "ON" || echo "OFF"
        echo -n "Explorer: "
        [ -f .explorer-mode ] && echo "ON — http://127.0.0.1:4000" || echo "OFF"
        echo -n "Sync mode: "
        grep -q "GETH_GCMODE=archive" .env 2>/dev/null && echo "archive" || echo "snap"
        ;;

    help|*)
        echo "ETH Docker Stack"
        echo ""
        echo "Geth (Execution):"
        echo "  info        Sync progress, peers, gas price — full dashboard"
        echo "  peers       Geth peer table (client, block, direction)"
        echo "  block       Sync progress / latest block"
        echo "  log         Tail Geth logs"
        echo "  attach      Interactive Geth JS console"
        echo "  rpc <json>  Raw JSON-RPC call to localhost:8545"
        echo ""
        echo "Lighthouse (Consensus):"
        echo "  beacon      Beacon chain sync status"
        echo "  beaconpeers Lighthouse peer table"
        echo "  beaconlog   Tail Lighthouse logs"
        echo "  finality    Finalization checkpoints"
        echo ""
        echo "Validator (Staking):"
        echo "  validator <on|off>  Toggle validator client"
        echo "  vallog      Tail validator logs"
        echo "  valstatus   Validator status"
        echo ""
        echo "Explorer:"
        echo "  explorer <on|off>  Toggle Blockscout explorer"
        echo "  explorerlog Tail explorer logs"
        echo ""
        echo "VPN:"
        echo "  vpn <on|off>  Toggle VPN (requires vpn/wg0.conf)"
        echo "  vpnlog      Tail VPN logs"
        echo "  myip        Check exit IP (verify VPN is working)"
        echo "  speedtest   Run speedtest through VPN"
        echo "  mode        Show current status (VPN/Validator/Explorer/sync mode)"
        echo ""
        echo "Stack:"
        echo "  up          Start all containers"
        echo "  down        Stop all containers"
        echo "  nuke        Stop and remove all images"
        echo "  status      Container status"
        echo "  logs        Tail all logs"
        echo "  update      Update images"
        ;;
esac
