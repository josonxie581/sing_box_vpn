"""AWS-specific installer invariants and generated CLI execution, isolated locally."""
import subprocess
import unittest

import secure_ss4_install_test as shared

SOURCE = (shared.ROOT / 'ss4.sh').read_text(encoding='utf-8')


class AWSTest(unittest.TestCase):
    setUp = shared.InstallerTest.setUp
    tearDown = shared.InstallerTest.tearDown
    run_bash = shared.InstallerTest.run_bash

    def test_aws_listener_and_service_user_preserved(self):
        generator = SOURCE.split('generate_config() {', 1)[1].split('\n# 新协议', 1)[0]
        self.assertNotIn('"listen": "$available_ip"', generator)
        self.assertEqual(generator.count('"listen": "0.0.0.0"'), 3)
        self.assertIn('User=$USERNAME', SOURCE)
        self.assertIn('ss -H -lnt "sport = :$port"', SOURCE)
        self.assertIn('sudo systemctl enable "$service_name"', SOURCE)

    def test_management_command_keeps_runtime_arguments(self):
        source_path = (shared.ROOT / 'ss4.sh').as_posix()
        body = f'source "{source_path}"\n' + r'''
sudo() {
    case "$1" in
        mkdir) return 0 ;;
        tee) command tee "$PWD/manager" ;;
        chmod) command chmod +x "$PWD/manager" ;;
        *) return 91 ;;
    esac
}
VMESS_PORT=20002 TUIC_PORT=20003 HY2_PORT=20001 SNELL_PORT=20004
NAIVE_PORT=20005 NAIVE_DOMAIN=proxy.example.com
create_quick_command
bash -n ./manager
cat > "$WORKDIR/keepalive.sh" <<'KEEP'
#!/bin/bash
printf '%s\n' "$@" > ../arguments
KEEP
chmod +x "$WORKDIR/keepalive.sh"
bash ./manager keep status sentinel
bash ./manager help
'''
        result = self.run_bash(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / 'arguments').read_text().splitlines(), ['status', 'sentinel'])
        self.assertIn('singbox', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
