import { Injectable, NotFoundException } from '@nestjs/common';
import * as fs from 'node:fs/promises';
import { existsSync } from 'node:fs';
import * as path from 'node:path';
import { parseNamedList } from '../common/utils/list.parser';

type LogSource = {
  name: string;
  kind: 'wallet' | 'chain' | 'system';
  path: string;
};

const runningInContainer = existsSync('/.dockerenv');
const HEALTH_SOURCE_PREFIX = 'health://';

@Injectable()
export class LogsService {
  listSources() {
    return this.getSources()
      .filter(
        (source) =>
          isHealthSource(source.path) || sourceExists(source.path),
      )
      .map((source) => ({
      name: source.name,
      kind: source.kind,
      path: source.path,
      }));
  }

  async tail(sourceName: string, limit = 120) {
    const source = this.getSources().find((item) => item.name === sourceName);
    if (!source) {
      throw new NotFoundException('Log source not found');
    }

    const resolvedPath = resolveReadablePath(source.path);

    const safeLimit = Math.min(Math.max(Number(limit) || 120, 1), 300);

    if (isHealthSource(source.path)) {
      return this.tailHealthSource(source, safeLimit);
    }

    try {
      const stat = await fs.stat(resolvedPath);
      const readSize = Math.min(stat.size, 256 * 1024);
      const handle = await fs.open(resolvedPath, 'r');
      const buffer = Buffer.alloc(readSize);
      try {
        await handle.read(
          buffer,
          0,
          readSize,
          Math.max(0, stat.size - readSize),
        );
        const content = buffer.toString('utf8');
        const lines = content.split(/\r?\n/).filter(Boolean).slice(-safeLimit);
        return {
          source: source.name,
          kind: source.kind,
          fileName: path.basename(resolvedPath),
          lines,
        };
      } finally {
        await handle.close();
      }
    } catch (error) {
      const detail =
        error instanceof Error ? error.message : 'Unable to read log source.';
      return {
        source: source.name,
        kind: source.kind,
        fileName: path.basename(resolvedPath),
        lines: [
          `[monitoring] ${detail}`,
          `[monitoring] path=${source.path}`,
          `[monitoring] resolved_path=${resolvedPath}`,
        ],
      };
    }
  }

  private async tailHealthSource(source: LogSource, limit: number) {
    const endpoint = decodeHealthSourcePath(source.path);
    if (!endpoint) {
      return {
        source: source.name,
        kind: source.kind,
        fileName: `${source.name}.health`,
        lines: ['[monitoring] Invalid health source definition.'],
      };
    }

    const startedAt = Date.now();
    try {
      const response = await fetch(endpoint, {
        signal: AbortSignal.timeout(3500),
      });
      const body = await response.text();
      const latencyMs = Date.now() - startedAt;
      const now = new Date().toISOString();

      const lines = [
        `[monitoring] ${now}`,
        `[monitoring] endpoint=${endpoint}`,
        `[monitoring] http_status=${response.status}`,
        `[monitoring] latency_ms=${latencyMs}`,
      ];

      if (body.trim()) {
        const compactBody = body.replace(/\s+/g, ' ').trim();
        lines.push(`[monitoring] payload=${compactBody}`);
      }

      return {
        source: source.name,
        kind: source.kind,
        fileName: `${source.name}.health`,
        lines: lines.slice(-limit),
      };
    } catch (error) {
      const detail =
        error instanceof Error ? error.message : 'Health probe failed.';
      return {
        source: source.name,
        kind: source.kind,
        fileName: `${source.name}.health`,
        lines: [
          `[monitoring] ${new Date().toISOString()}`,
          `[monitoring] endpoint=${endpoint}`,
          `[monitoring] ${detail}`,
        ],
      };
    }
  }

  private getSources(): LogSource[] {
    const configured = [
      ...parseNamedList(process.env.WALLET_LOG_SOURCES).map((item) => ({
        name: item.name,
        path: item.value,
        kind: 'wallet' as const,
      })),
      ...parseNamedList(process.env.CHAIN_LOG_SOURCES).map((item) => ({
        name: item.name,
        path: item.value,
        kind: 'chain' as const,
      })),
      ...parseNamedList(process.env.SYSTEM_LOG_SOURCES).map((item) => ({
        name: item.name,
        path: item.value,
        kind: 'system' as const,
      })),
    ];

    const monitoredServices = parseNamedList(
      process.env.MONITORED_SERVICE_ENDPOINTS,
    ).map((item) => ({
      name: item.name,
      path: encodeHealthSourcePath(item.value),
      kind: 'wallet' as const,
    }));

    const deduped = new Map<string, LogSource>();
    for (const source of [...configured, ...monitoredServices]) {
      if (!deduped.has(source.name)) {
        deduped.set(source.name, source);
      }
    }

    return [...deduped.values()];
  }
}

function isHealthSource(pathValue: string): boolean {
  return pathValue.startsWith(HEALTH_SOURCE_PREFIX);
}

function encodeHealthSourcePath(url: string): string {
  return `${HEALTH_SOURCE_PREFIX}${encodeURIComponent(url)}`;
}

function decodeHealthSourcePath(pathValue: string): string | null {
  if (!isHealthSource(pathValue)) {
    return null;
  }

  const encoded = pathValue.slice(HEALTH_SOURCE_PREFIX.length);
  if (!encoded) {
    return null;
  }

  try {
    return decodeURIComponent(encoded);
  } catch {
    return null;
  }
}

function resolveReadablePath(rawPath: string): string {
  if (!runningInContainer) {
    return rawPath;
  }

  if (!path.isAbsolute(rawPath)) {
    return rawPath;
  }

  // Host absolute paths like /home/<user>/Code/dacn_datn/... are not valid inside
  // the backend container; map them to the mounted workspace root.
  const marker = '/dacn_datn/';
  const markerIndex = rawPath.indexOf(marker);
  if (markerIndex >= 0) {
    const suffix = rawPath.slice(markerIndex + marker.length);
    return path.posix.join('/workspace', suffix);
  }

  return rawPath;
}

function sourceExists(rawPath: string): boolean {
  try {
    return existsSync(resolveReadablePath(rawPath));
  } catch {
    return false;
  }
}
