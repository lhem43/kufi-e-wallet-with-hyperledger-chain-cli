import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { existsSync } from 'node:fs';

type NamedEndpoint = {
  name: string;
  value: string;
};

const runningInContainer = existsSync('/.dockerenv');

@Injectable()
export class ChainObserverService {
  constructor(private readonly configService: ConfigService) {}

  async collect() {
    const gatewayUrl = this.configService.get<string>(
      'CHAIN_GATEWAY_HEALTH_URL',
    );
    const nodeEndpoints = await this.resolveNodeEndpoints();

    const [gatewayResult, nodes] = await Promise.all([
      gatewayUrl
        ? this.pingGateway(gatewayUrl)
        : Promise.resolve({
            status: 'unknown' as const,
            fabricStatus: 'unconfigured',
          }),
      Promise.all(
        nodeEndpoints.map((endpoint) => this.collectNodeStatus(endpoint)),
      ),
    ]);

    nodes.sort((left, right) => {
      const severityDiff =
        statusWeight(right.status) - statusWeight(left.status);
      if (severityDiff !== 0) {
        return severityDiff;
      }

      if (right.pendingRequests !== left.pendingRequests) {
        return right.pendingRequests - left.pendingRequests;
      }

      return left.orgName.localeCompare(right.orgName);
    });

    const activeNodes = nodes.filter(
      (node) => node.status !== 'critical',
    ).length;
    const peerCounts = nodes
      .filter((node) => node.status !== 'critical')
      .map((node) => node.knownPeers);
    const peerSpread =
      peerCounts.length > 0
        ? Math.max(...peerCounts) - Math.min(...peerCounts)
        : 0;

    const anomalies: Array<{
      code: string;
      severity: 'warning' | 'critical';
      message: string;
    }> = [];

    if (nodes.length > 0 && activeNodes < nodes.length) {
      anomalies.push({
        code: 'chain_nodes_down',
        severity: 'critical',
        message: `${nodes.length - activeNodes} Kufi chain node(s) are unreachable.`,
      });
    }

    if (
      gatewayUrl &&
      gatewayResult.fabricStatus !== 'connected' &&
      gatewayResult.fabricStatus !== 'ok'
    ) {
      anomalies.push({
        code: 'fabric_disconnected',
        severity: 'critical',
        message: 'Fabric gateway is not connected to the network.',
      });
    }

    if (peerSpread > 1) {
      anomalies.push({
        code: 'peer_topology_drift',
        severity: 'warning',
        message: 'Known peer counts are inconsistent across chain nodes.',
      });
    }

    const pendingGovernanceRequests = nodes
      .filter((node) => node.pendingRequests > 0)
      .reduce((total, node) => total + node.pendingRequests, 0);

    if (pendingGovernanceRequests > 0) {
      anomalies.push({
        code: 'pending_governance_requests',
        severity: 'warning',
        message: `${pendingGovernanceRequests} chain governance request(s) are still pending review.`,
      });
    }

    return {
      gatewayStatus: gatewayResult.status,
      fabricStatus: gatewayResult.fabricStatus,
      activeNodes,
      configuredNodes: nodes.length,
      nodes,
      anomalies,
    };
  }

  private async resolveNodeEndpoints(): Promise<NamedEndpoint[]> {
    const configuredBootstrap = this.normalizeHttpUrl(
      this.configService.get<string>('CHAIN_BOOTSTRAP_MGMT_URL'),
    );
    const defaultBootstrap = this.defaultBootstrapMgmtUrl();
    const bootstrapCandidates = [
      ...new Set([configuredBootstrap, defaultBootstrap]),
    ].filter((url): url is string => Boolean(url));

    for (const bootstrapUrl of bootstrapCandidates) {
      const discovered = await this.discoverNodeEndpoints(bootstrapUrl);
      if (discovered.length > 0) {
        return discovered;
      }
    }

    return [];
  }

  private defaultBootstrapMgmtUrl(): string | null {
    return null;
  }

  private async discoverNodeEndpoints(
    bootstrapMgmtUrl: string,
  ): Promise<NamedEndpoint[]> {
    try {
      const [bootstrapStatusPayload, peersPayload] = await Promise.all([
        this.fetchJson(`${bootstrapMgmtUrl}/api/status`),
        this.fetchJson(`${bootstrapMgmtUrl}/api/peers`),
      ]);
      const bootstrapStatus = bootstrapStatusPayload as Record<string, unknown>;

      const endpointMap = new Map<string, string>();
      const peers = Array.isArray(peersPayload)
        ? (peersPayload as Array<Record<string, unknown>>)
        : [];

      for (const peer of peers) {
        const mgmtAddr = this.normalizeHttpUrl(readString(peer.mgmt_addr));
        if (!mgmtAddr) {
          continue;
        }
        const peerName =
          slugifyName(readString(peer.org_name)) ||
          slugifyName(readString(peer.msp_id)) ||
          'peer';
        endpointMap.set(peerName, mgmtAddr);
      }

      const ordererMgmtFromStatus = this.normalizeHttpUrl(
        readString(bootstrapStatus.orderer_mgmt_addr),
      );
      const ordererMgmtUrl =
        ordererMgmtFromStatus ??
        this.deriveOrdererMgmtUrl(readString(bootstrapStatus.orderer));
      if (ordererMgmtUrl) {
        endpointMap.set('orderer', ordererMgmtUrl);
      }

      return [...endpointMap.entries()]
        .map(([name, value]) => ({ name, value }))
        .sort((left, right) => left.name.localeCompare(right.name));
    } catch {
      return [];
    }
  }

  private deriveOrdererMgmtUrl(ordererAddr: string | null): string | null {
    if (!ordererAddr) {
      return null;
    }

    const [host] = ordererAddr.split(':');
    if (!host) {
      return null;
    }

    return this.normalizeHttpUrl(`http://${host}:9500`);
  }

  private normalizeHttpUrl(urlLike?: string | null): string | null {
    const trimmed = urlLike?.trim();
    if (!trimmed) {
      return null;
    }

    try {
      const url = new URL(trimmed);
      if (!['http:', 'https:'].includes(url.protocol)) {
        return null;
      }

      if (
        runningInContainer &&
        (url.hostname === '127.0.0.1' || url.hostname === 'localhost')
      ) {
        url.hostname = 'host.docker.internal';
      }

      return `${url.origin}${url.pathname}`.replace(/\/$/, '');
    } catch {
      return null;
    }
  }

  private async fetchJson(url: string): Promise<unknown> {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(2500),
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    return (await response.json()) as unknown;
  }

  private async collectNodeStatus(endpoint: NamedEndpoint) {
    const startedAt = Date.now();
    const inferredRole = inferRoleFromEndpoint(endpoint);
    try {
      const payload = (await this.fetchJson(
        `${endpoint.value}/api/status`,
      )) as Record<string, unknown>;
      const pendingRequests = Number(payload.pending_requests ?? 0);
      const status =
        pendingRequests > 0 ? ('warning' as const) : ('healthy' as const);
      return {
        name: endpoint.name,
        url: endpoint.value,
        status,
        role: readString(payload.role) ?? inferredRole,
        orgName: readString(payload.org_name) ?? endpoint.name,
        mspId: readString(payload.msp_id) ?? 'unknown',
        knownPeers: Number(payload.known_peers ?? 0),
        pendingRequests,
        latencyMs: Date.now() - startedAt,
        lastCheckedAt: new Date().toISOString(),
        detail:
          pendingRequests > 0
            ? `${pendingRequests} governance request(s) are still pending.`
            : null,
      };
    } catch (error) {
      return {
        name: endpoint.name,
        url: endpoint.value,
        status: 'critical' as const,
        role: inferredRole,
        orgName: endpoint.name,
        mspId: 'unknown',
        knownPeers: 0,
        pendingRequests: 0,
        latencyMs: null,
        lastCheckedAt: new Date().toISOString(),
        detail:
          error instanceof Error ? error.message : 'Chain node is unreachable.',
      };
    }
  }

  private async pingGateway(url: string) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(2500),
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const payload = (await response.json()) as Record<string, unknown>;
      const fabricStatus =
        readString(payload.fabric_status) ??
        readString(payload.fabricStatus) ??
        readString(payload.status) ??
        'unknown';
      return {
        status:
          fabricStatus === 'connected' || fabricStatus === 'ok'
            ? ('healthy' as const)
            : ('warning' as const),
        fabricStatus,
      };
    } catch {
      return {
        status: 'critical' as const,
        fabricStatus: 'unreachable',
      };
    }
  }
}

function inferRoleFromEndpoint(endpoint: NamedEndpoint): string {
  const loweredName = endpoint.name.toLowerCase();
  if (loweredName.includes('orderer')) {
    return 'orderer';
  }

  try {
    const url = new URL(endpoint.value);
    if (url.port === '9500') {
      return 'orderer';
    }
  } catch {
    return 'unknown';
  }

  return 'unknown';
}

function readString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function slugifyName(value: string | null): string {
  if (!value) {
    return '';
  }

  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function statusWeight(status: 'healthy' | 'warning' | 'critical' | 'unknown') {
  switch (status) {
    case 'critical':
      return 3;
    case 'warning':
      return 2;
    case 'unknown':
      return 1;
    case 'healthy':
    default:
      return 0;
  }
}
