# Single-Generator Capacity Scenarios

These scenarios are designed for one load-generator machine.
They benchmark capacity with progressive concurrency while keeping the same request flow.

## Scenario ladder

- `01-capacity-0100-users.env`: 100 total users (80 wallet, 15 monitoring, 5 chain probes)
- `02-capacity-0250-users.env`: 250 total users (200 wallet, 40 monitoring, 10 chain probes)
- `03-capacity-0500-users.env`: 500 total users (400 wallet, 80 monitoring, 20 chain probes)
- `04-capacity-0800-users.env`: 800 total users (640 wallet, 128 monitoring, 32 chain probes)
- `05-capacity-1200-users.env`: 1200 total users (960 wallet, 192 monitoring, 48 chain probes)
- `06-capacity-1600-users.env`: 1600 total users (1280 wallet, 256 monitoring, 64 chain probes)

## Variables

Each file can override:

- `WALLET_USERS`, `WALLET_RAMP`, `WALLET_LOOPS`
- `MONITOR_USERS`, `MONITOR_RAMP`, `MONITOR_LOOPS`
- `CHAIN_PROBE_USERS`, `CHAIN_PROBE_RAMP`, `CHAIN_PROBE_LOOPS`
- `MAX_P95_MS`, `MAX_ERROR_PCT`

Run order is lexical by filename, so keep naming format `NN-name.env`.
