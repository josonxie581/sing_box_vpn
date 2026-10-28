#!/usr/bin/python3
"""Stream a strict, secret-free Linux runtime snapshot for Gsou.

Installed as a root-owned forced SSH command for the unprivileged
``gsou-monitor`` account. It accepts no arguments or input and exposes only
aggregate operating-system counters.
"""

from __future__ import annotations

import json
import os
import sys
import time

VERSION = 1
INTERVAL_SECONDS = 5.0


def default_interface() -> str:
    with open("/proc/net/route", encoding="ascii") as routes:
        next(routes, None)
        for line in routes:
            fields = line.split()
            if len(fields) >= 4 and fields[1] == "00000000":
                return fields[0]
    raise RuntimeError("default interface unavailable")


def cpu_times() -> tuple[int, int]:
    with open("/proc/stat", encoding="ascii") as stat:
        fields = stat.readline().split()
    if not fields or fields[0] != "cpu" or len(fields) < 6:
        raise RuntimeError("cpu counters unavailable")
    values = [int(value) for value in fields[1:]]
    return sum(values), values[3] + values[4]


def memory_bytes() -> tuple[int, int]:
    values: dict[str, int] = {}
    with open("/proc/meminfo", encoding="ascii") as meminfo:
        for line in meminfo:
            key, raw = line.split(":", 1)
            fields = raw.split()
            if fields:
                values[key] = int(fields[0]) * 1024
    return values["MemTotal"], values["MemAvailable"]


def network_bytes(interface: str) -> tuple[int, int]:
    with open("/proc/net/dev", encoding="ascii") as devices:
        for line in devices:
            if ":" not in line:
                continue
            name, raw = line.split(":", 1)
            if name.strip() != interface:
                continue
            fields = raw.split()
            return int(fields[0]), int(fields[8])
    raise RuntimeError("network counters unavailable")


def disk_bytes() -> tuple[int, int]:
    stat = os.statvfs("/")
    return stat.f_blocks * stat.f_frsize, stat.f_bavail * stat.f_frsize


def uptime_seconds() -> int:
    with open("/proc/uptime", encoding="ascii") as uptime:
        return int(float(uptime.read().split()[0]))


def main() -> int:
    interface = default_interface()
    previous_total, previous_idle = cpu_times()
    previous_rx, previous_tx = network_bytes(interface)
    previous_time = time.monotonic()
    time.sleep(1.0)
    while True:
        current_time = time.monotonic()
        total, idle = cpu_times()
        rx, tx = network_bytes(interface)
        elapsed = max(current_time - previous_time, 0.001)
        total_delta = max(total - previous_total, 1)
        idle_delta = min(max(idle - previous_idle, 0), total_delta)
        memory_total, memory_available = memory_bytes()
        disk_total, disk_available = disk_bytes()
        sample = {
            "version": VERSION,
            "cpuPercent": round((total_delta - idle_delta) * 100 / total_delta, 2),
            "memoryTotalBytes": memory_total,
            "memoryAvailableBytes": memory_available,
            "diskTotalBytes": disk_total,
            "diskAvailableBytes": disk_available,
            "load1": round(os.getloadavg()[0], 2),
            "uptimeSeconds": uptime_seconds(),
            "rxBytesPerSecond": round(max(rx - previous_rx, 0) / elapsed, 2),
            "txBytesPerSecond": round(max(tx - previous_tx, 0) / elapsed, 2),
            "networkInterface": interface,
        }
        sys.stdout.write(json.dumps(sample, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        previous_total, previous_idle = total, idle
        previous_rx, previous_tx = rx, tx
        previous_time = current_time
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        raise SystemExit(0)
