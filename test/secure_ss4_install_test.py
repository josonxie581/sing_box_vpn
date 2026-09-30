"""Isolated installer menu/process tests; never execute the full installer."""

import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "secure_ss4.sh").read_text(encoding="utf-8")
BASH = (r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt"
        else shutil.which("bash"))


def function(name):
    match = re.search(r"^" + name + r"\(\) \{\n.*?^\}", SOURCE, re.M | re.S)
    if not match:
        raise AssertionError(f"Missing function: {name}")
    return match.group()


COLORS = """
red() { printf '%s\\n' "$1"; }
green() { printf '%s\\n' "$1"; }
yellow() { printf '%s\\n' "$1"; }
purple() { printf '%s\\n' "$1"; }
"""


@unittest.skipUnless(BASH and Path(BASH).is_file(), "Bash is required")
class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="singbox install test ")
        self.base = Path(self.temporary.name)
        self.install = self.base / "sing-box"
        self.install.mkdir()
        self.trace = self.base / "trace"

    def tearDown(self):
        self.temporary.cleanup()

    def run_bash(self, body, input_text="", timeout=20):
        result = subprocess.run(
            [BASH, "-c", "set -e\n" + COLORS + function("setup_paths")
             + '\nsetup_paths\nUSERNAME="$(id -un)"\n' + body],
            cwd=self.base, input=input_text.encode("utf-8"), capture_output=True,
            timeout=timeout,
        )
        result.stdout = result.stdout.decode("utf-8")
        result.stderr = result.stderr.decode("utf-8")
        return result

    def run_init(self, input_text, extra=""):
        # Only rm/mkdir/chmod in the fresh temporary directory are real.
        # Process controls are stubbed, so menu tests cannot signal a process.
        body = """
curl() { :; }
pkill() { exit 97; }
kill() { exit 97; }
stop_existing_installation() {
    [[ -f "$WORKDIR/config.json" || -f "$WORKDIR/sing-box" || -f "$WORKDIR/keepalive.sh" ]]
    printf 'stop\\n' >> trace
}
rm() { printf 'remove\\n' >> trace; command rm "$@"; }
mkdir() { printf 'mkdir\\n' >> trace; command mkdir "$@"; }
""" + function("secure_init") + "\n" + extra + "\nsecure_init\necho CONTINUED\n"
        return self.run_bash(body, input_text)

    def existing_config(self):
        (self.install / "config.json").write_text("original config", encoding="utf-8")
        (self.install / "cert.pem").write_text("original certificate", encoding="utf-8")
        (self.install / "web").mkdir()
        (self.install / "web" / "node.txt").write_text("original node", encoding="utf-8")

    def snapshot(self):
        return {str(p.relative_to(self.install)): (p.read_bytes(), p.stat().st_mtime_ns)
                for p in self.install.rglob("*") if p.is_file()}

    def test_return_default_eof_and_invalid_input_preserve_installation(self):
        self.existing_config()
        original = self.snapshot()
        for choice in ("2\n", "\n", "", "wrong\n2\n", "wrong\n"):
            with self.subTest(choice=choice):
                result = self.run_init(choice)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("已返回", result.stdout)
                self.assertNotIn("CONTINUED", result.stdout)
                self.assertEqual(original, self.snapshot())
                self.assertFalse(self.trace.exists())

    def test_reinstall_stops_then_removes_and_recreates_directory(self):
        self.existing_config()
        for choice in ("1\n", "wrong\n1\n"):
            with self.subTest(choice=choice):
                result = self.run_init(choice)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("CONTINUED", result.stdout)
                self.assertEqual(self.trace.read_text().splitlines(), ["stop", "remove", "mkdir"])
                self.assertFalse((self.install / "config.json").exists())
                self.assertFalse((self.install / "cert.pem").exists())
                self.assertEqual(list((self.install / "web").iterdir()), [])
                self.trace.unlink()
                self.existing_config_after_reinstall()

    def existing_config_after_reinstall(self):
        (self.install / "config.json").write_text("old config", encoding="utf-8")
        (self.install / "cert.pem").write_text("old certificate", encoding="utf-8")
        (self.install / "web" / "node.txt").write_text("old node", encoding="utf-8")

    def test_partial_installations_offer_return(self):
        for name in ("sing-box", "keepalive.sh"):
            with self.subTest(name=name):
                marker = self.install / name
                marker.write_text("partial install", encoding="utf-8")
                result = self.run_init("2\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("检测到现有安装", result.stdout)
                self.assertTrue(marker.exists())
                self.assertFalse(self.trace.exists())
                marker.unlink()

    def test_new_installation_continues_without_deletion(self):
        marker = self.install / "unrelated.txt"
        marker.write_text("keep", encoding="utf-8")
        result = self.run_init("")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CONTINUED", result.stdout)
        self.assertNotIn("请选择", result.stdout)
        self.assertEqual(marker.read_text(), "keep")
        self.assertEqual(self.trace.read_text().splitlines(), ["mkdir"])

    def test_unexpected_path_and_missing_download_tools_preserve_files(self):
        self.existing_config()
        original = self.snapshot()
        for extra in (
            'WORKDIR="$(pwd -P)/./sing-box"',
            '''command() {
                if [[ "$1" == -v && ( "$2" == curl || "$2" == wget ) ]]; then
                    return 1
                fi
                builtin command "$@"
            }''',
            'stop_existing_installation() { exit 1; }',
        ):
            with self.subTest(extra=extra):
                result = self.run_init("1\n", extra)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertNotIn("CONTINUED", result.stdout)
                self.assertEqual(original, self.snapshot())
                self.assertFalse(self.trace.exists())

    def test_stop_orders_scripts_before_programs_and_skips_other_directories(self):
        body = """
systemctl() {
    if [[ "$1" == show ]]; then printf '%s\\n' "$WORKDIR";
    else printf 'systemctl %s\\n' "$*" >> trace; fi
}
pgrep() {
    if [[ "$4" == *keepalive* ]]; then printf '101\\n103\\n';
    else printf '102\\n104\\n'; fi
}
installation_process_dir() {
    case "$1" in
        101|102) printf '%s\\n' "$WORKDIR" ;;
        *) printf '%s\\n' "$(pwd -P)/another-install" ;;
    esac
}
kill() {
    [[ "$1" != -0 ]] || return 1
    printf 'kill %s\\n' "$*" >> trace
}
""" + function("stop_existing_installation") + "\nstop_existing_installation\n"
        result = self.run_bash(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.trace.read_text().splitlines(), [
            "systemctl stop sing-box-auto", "kill -TERM 101", "kill -TERM 102",
        ])

    def test_stuck_keepalive_is_killed_before_stopping_core(self):
        body = """
systemctl() { return 1; }
pgrep() {
    if [[ "$4" == *keepalive* ]]; then echo 101; else echo 102; fi
}
installation_process_dir() { printf '%s\\n' "$WORKDIR"; }
kill() {
    [[ "$1" != -0 ]] || return 0
    printf 'kill %s\\n' "$*" >> trace
}
sleep() { :; }
""" + function("stop_existing_installation") + "\nstop_existing_installation\n"
        result = self.run_bash(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.trace.read_text().splitlines(), [
            "kill -TERM 101", "kill -KILL 101", "kill -TERM 102", "kill -KILL 102",
        ])

    @unittest.skipUnless(sys.platform.startswith("linux"), "Requires Linux /proc")
    def test_real_processes_in_target_directory_stop_other_install_survives(self):
        other = self.base / "another-install"
        other.mkdir()
        processes = []
        try:
            for directory, name in ((self.install, "keepalive.sh"),
                                    (self.install, "sing-box"), (other, "sing-box")):
                program = directory / name
                program.write_text("#!/bin/bash\nwhile true; do sleep 30; done\n")
                processes.append(subprocess.Popen(
                    [BASH, str(program), "main"], cwd=directory, start_new_session=True,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                ))
            body = function("installation_process_dir") + "\n" + function(
                "stop_existing_installation") + "\nstop_existing_installation\n"
            result = self.run_bash(body)
            self.assertEqual(result.returncode, 0, result.stderr)
            for process in processes[:2]:
                process.wait(timeout=3)
            self.assertIsNone(processes[2].poll())
        finally:
            # Only process groups created above are ever signaled by this test.
            for process in processes:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
