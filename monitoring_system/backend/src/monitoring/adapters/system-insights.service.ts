import { Injectable } from '@nestjs/common';
import * as os from 'node:os';
import si from 'systeminformation';

@Injectable()
export class SystemInsightsService {
  async collect() {
    const [load, memory, disks, networkStats] = await Promise.all([
      si.currentLoad(),
      si.mem(),
      si.fsSize(),
      si.networkStats(),
    ]);

    const totalDisk = disks.reduce((acc, disk) => acc + disk.size, 0);
    const usedDisk = disks.reduce((acc, disk) => acc + disk.used, 0);
    const totalRxSec = networkStats.reduce((acc, item) => acc + item.rx_sec, 0);
    const totalTxSec = networkStats.reduce((acc, item) => acc + item.tx_sec, 0);

    return {
      cpuPercent: round(load.currentLoad),
      memoryPercent: round((memory.active / memory.total) * 100),
      memoryUsedGb: round(memory.active / 1024 ** 3),
      memoryTotalGb: round(memory.total / 1024 ** 3),
      diskPercent: totalDisk === 0 ? 0 : round((usedDisk / totalDisk) * 100),
      diskUsedGb: round(usedDisk / 1024 ** 3),
      diskTotalGb: round(totalDisk / 1024 ** 3),
      networkRxMbps: round((totalRxSec * 8) / 1_000_000),
      networkTxMbps: round((totalTxSec * 8) / 1_000_000),
      loadAverage1m: round(os.loadavg()[0] ?? 0),
      uptimeHours: round(os.uptime() / 3600),
    };
  }
}

function round(value: number) {
  return Number(value.toFixed(2));
}
