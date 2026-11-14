#!/usr/bin/env python3
"""Verify a process's tray item through the desktop's actual watcher registry."""
import shlex
import subprocess
import sys


def busctl(*arguments):
    return shlex.split(subprocess.check_output(
        ["busctl", "--user", "--no-pager", *arguments], text=True, timeout=5,
    ))


def main():
    expected_pid = int(sys.argv[1])
    watcher = busctl(
        "get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems",
    )
    if len(watcher) < 2 or watcher[0] != "as" or int(watcher[1]) != len(watcher[2:]):
        raise SystemExit(f"Unexpected tray registry: {watcher}")
    for item in watcher[2:]:
        service, separator, suffix = item.partition("/")
        path = "/" + suffix if separator else "/StatusNotifierItem"
        owner = busctl(
            "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", service,
        )
        if owner != ["u", str(expected_pid)]:
            continue
        status = busctl("get-property", service, path, "org.kde.StatusNotifierItem", "Status")
        if status != ["s", "Active"]:
            raise SystemExit(f"Gsou tray item is not active: {status}")
        print(f"Tray registered with desktop watcher: PID {expected_pid}, {item}, Active")
        return
    raise SystemExit("Desktop watcher has no tray item owned by Gsou")


if __name__ == "__main__":
    main()
