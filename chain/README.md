# KufiChain CLI

`chain/` contains the KufiChain runtime and CLI used to provision and run Fabric orderer/peer nodes for the consortium network.

## Platform Support

- Linux: fully supported.
- macOS: supported (Docker Desktop required).
- Windows: use WSL2 (Ubuntu recommended) for runtime commands.

## Prerequisites

- Docker Engine 24+ and Docker Compose v2.
- Go 1.21+.
- Bash, `curl`, and `jq`.
- Hyperledger Fabric binaries (installed automatically by `install-prereq.sh`).

## Install Prerequisites

Run from `chain/`:

```bash
chmod +x install-prereq.sh
./install-prereq.sh
```

This script installs Docker, Docker Compose, Go, Fabric binaries, and required helpers.
On macOS, Docker Desktop must be installed manually first, then re-run the script.
It also restores Go dependencies for `chain`, `chaincode/payment`, and `chaincode/governance`.

## Build CLI

Linux/macOS/WSL2:

```bash
go build -o kufichain ./cmd/kufichain
```

Windows PowerShell (native build only):

```powershell
go build -o kufichain.exe ./cmd/kufichain
```

For runtime commands on Windows, use WSL2 shell and the Linux commands below.

## Restore Go Dependencies (Manual Fallback)

`install-prereq.sh` already runs this automatically.
Run manually only when you need to refresh dependencies:

```bash
# CLI and internal services
go mod download
go mod verify

# Chaincode modules
cd chaincode/payment && go mod download && go mod verify
cd ../governance && go mod download && go mod verify
```

## Global Flag

- `--data-dir <path>`: custom node state directory (default: `.kufichain`).
- Use different directories to run multiple local nodes.
- Equivalent format is also accepted: `--data-dir=<path>`.

Examples:

```bash
./kufichain setup --data-dir .orderer
./kufichain setup --data-dir .peer-techcombank
```

## Command Reference

### `setup`

Interactive node initialization.

- Prompts role selection: `Orderer` or `Peer`.
- If node config already exists, it offers:
  - run existing node
  - reset and re-initialize

Linux/macOS/WSL2:

```bash
./kufichain setup [--data-dir <path>]
```

### `join`

Peer join shortcut (same core flow as `setup` -> peer).

Required:

- `--bootstrap <host:port>`: orderer management API address.
  `http://` is optional (the CLI auto-adds it when omitted).

Optional flags:

- `--org <name>`: organization/bank name.
- `--host <public-ip-or-hostname>`: this node external address.
- `--peer-port <port>`: default `7051`.
- `--couchdb-port <port>`: default `5984`.
- `--gateway-port <port>`: default `8080`.
- `--ops-port <port>`: default `9444`.
- `--mgmt-port <port>`: default `9500`.
- `--yes`: skip confirmation prompt (automation mode).

Automation note:

- For non-interactive join, pass both `--org` and `--host`.
- If both are omitted, CLI falls back to interactive prompts.

Interactive join:

```bash
./kufichain join --bootstrap 203.0.113.40:9500
```

Non-interactive automation join:

```bash
./kufichain join \
  --bootstrap 203.0.113.40:9500 \
  --org Techcombank \
  --host 203.0.113.50 \
  --peer-port 7051 \
  --couchdb-port 5984 \
  --gateway-port 8080 \
  --ops-port 9444 \
  --mgmt-port 9500 \
  --data-dir .peer-techcombank \
  --yes
```

### `run`

Starts node services and attaches to the interactive dashboard.

- Starts Docker services for the node.
- Starts management API.
- For peer role: ensures channel join, deploys chaincode, starts gateway.

```bash
./kufichain run [--data-dir <path>]
```

Dashboard commands while running:

- `a <request-number>` or `approve <request-number>`
- `r <request-number>` or `reject <request-number>`
- `p` or `peers`
- `s` or `status`
- `l` or `list`
- `log` or `logs` (peer nodes only)
- `q` or `quit` (detach, keep services running)
- `stop` (stop services and exit)

### `status`

Prints detailed current node status.

```bash
./kufichain status [--data-dir <path>]
```

### `stop`

Stops this node's chaincode container (peer role) and Docker services.

```bash
./kufichain stop [--data-dir <path>]
```

### `help`

Show command usage summary.

```bash
./kufichain help
./kufichain -h
./kufichain --help
```

## Typical Flows

### Role 1: Orderer Node

1. Initialize orderer:

```bash
./kufichain setup --data-dir .orderer
```

2. Start orderer:

```bash
./kufichain run --data-dir .orderer
```

During setup, provide:

- public host/IP
- channel name
- orderer port (default `7050`)
- orderer admin port (default `7053`)
- ops port (default `9443`)
- management API port (default `9500`)

### Role 2: Peer Node

1. Join network:

```bash
./kufichain join --bootstrap <orderer-host:9500> --data-dir .peer-yourorg
```

2. Start peer:

```bash
./kufichain run --data-dir .peer-yourorg
```

## Utility Scripts

- `scripts/deploy-node.sh`: remote deployment helper.
- `tools/bench_throughput.sh`: chain gateway throughput check helper.
