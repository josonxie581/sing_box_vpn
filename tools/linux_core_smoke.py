#!/usr/bin/env python3
"""Exercise the Linux C ABI and SOCKS forwarding without a remote VPN server.

The optional TUN check refuses the initial network namespace. Run it through
`unshare --net`, with loopback and a dummy default interface already configured.
"""
import argparse
import ctypes
import http.server
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def read_exact(sock, count):
    result = b""
    while len(result) < count:
        chunk = sock.recv(count - len(result))
        if not chunk:
            raise RuntimeError("Unexpected SOCKS EOF")
        result += chunk
    return result


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        payload = b"gsou-linux-core-smoke-ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass


def forward_request(proxy_port, server_port):
    with socket.create_connection(("127.0.0.1", proxy_port), timeout=5) as sock:
        sock.sendall(b"\x05\x01\x00")
        assert read_exact(sock, 2) == b"\x05\x00", "SOCKS handshake failed"
        sock.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + struct.pack("!H", server_port))
        header = read_exact(sock, 4)
        assert header[:2] == b"\x05\x00", f"SOCKS connect failed: {header!r}"
        size = {1: 4, 4: 16}.get(header[3])
        if size is None:
            assert header[3] == 3
            size = read_exact(sock, 1)[0]
        read_exact(sock, size + 2)
        sock.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
        response = b""
        while chunk := sock.recv(4096):
            response += chunk
        assert b"gsou-linux-core-smoke-ok" in response, response


def tun_request():
    # A benchmark-only destination is routed by the TUN inbound to the
    # loopback test server. This requires actual transparent TCP interception.
    with socket.create_connection(("198.18.0.2", 18080), timeout=5) as sock:
        sock.sendall(b"GET / HTTP/1.0\r\nHost: tun-test\r\n\r\n")
        response = b""
        while chunk := sock.recv(4096):
            response += chunk
        assert b"gsou-linux-core-smoke-ok" in response, response


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("library", type=Path)
    parser.add_argument("--tun", action="store_true")
    args = parser.parse_args()
    library_path = args.library.resolve(strict=True)
    if args.tun:
        if os.geteuid() != 0:
            raise SystemExit("TUN smoke test requires root in an isolated namespace")
        if os.readlink("/proc/self/ns/net") == os.readlink("/proc/1/ns/net"):
            raise SystemExit("Refusing TUN changes in the host network namespace")
    core = ctypes.CDLL(str(library_path))
    core.InitSingBox.restype = ctypes.c_ssize_t
    core.StartSingBox.argtypes = [ctypes.c_char_p]
    core.StartSingBox.restype = ctypes.c_ssize_t
    core.StopSingBox.restype = ctypes.c_ssize_t
    core.IsRunning.restype = ctypes.c_ssize_t
    core.SbGetLastError.restype = ctypes.c_void_p
    core.FreeCString.argtypes = [ctypes.c_void_p]
    core.Cleanup.restype = None

    def last_error():
        pointer = core.SbGetLastError()
        if not pointer:
            return ""
        try:
            return ctypes.string_at(pointer).decode("utf-8", errors="replace")
        finally:
            core.FreeCString(pointer)

    def net_state():
        return tuple(subprocess.check_output(command, text=True) for command in [
            ["ip", "-j", "rule", "show"],
            ["ip", "-j", "route", "show", "table", "all"],
            ["nft", "list", "tables"],
        ])

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    previous_directory = os.getcwd()
    try:
        with tempfile.TemporaryDirectory(prefix="gsou-core-smoke-") as directory:
            os.chdir(directory)
            assert core.InitSingBox() == 0, last_error()
            for cycle in range(2):
                port = free_port()
                config = {
                    "log": {"disabled": True},
                    "inbounds": [{"type": "mixed", "tag": "mixed", "listen": "127.0.0.1", "listen_port": port}],
                    "outbounds": [{"type": "direct", "tag": "direct"}],
                    "route": {"final": "direct", "auto_detect_interface": args.tun},
                }
                before = net_state() if args.tun else None
                if args.tun:
                    config["route"]["rules"] = [{
                        "inbound": ["tun-in"], "action": "route", "outbound": "direct",
                        "override_address": "127.0.0.1", "override_port": server.server_port,
                    }]
                    config["inbounds"].append({
                        "type": "tun", "tag": "tun-in", "interface_name": "gsou-tun",
                        "address": ["172.19.0.1/30"], "mtu": 1400, "stack": "mixed",
                        "auto_route": True, "auto_redirect": True,
                    })
                assert core.StartSingBox(json.dumps(config).encode()) == 0, last_error()
                try:
                    assert core.IsRunning() == 1
                    if args.tun:
                        subprocess.run(["ip", "link", "show", "gsou-tun"], check=True, stdout=subprocess.DEVNULL)
                    forward_request(port, server.server_port)
                    if args.tun:
                        tun_request()
                finally:
                    assert core.StopSingBox() == 0, last_error()
                assert core.IsRunning() == 0
                with socket.socket() as probe:
                    assert probe.connect_ex(("127.0.0.1", port)) != 0, "Proxy listener leaked"
                if args.tun:
                    assert subprocess.run(["ip", "link", "show", "gsou-tun"], capture_output=True).returncode != 0
                    assert net_state() == before, "TUN left routing or nftables state behind"
                path = "SOCKS + transparent TUN" if args.tun else "SOCKS"
                print(f"Cycle {cycle + 1}: core start, {path} HTTP forwarding, stop and cleanup passed")
            core.Cleanup()
            os.chdir(previous_directory)
    finally:
        os.chdir(previous_directory)
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
