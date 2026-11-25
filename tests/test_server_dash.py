"""bin/server-dash against a stand-in ssh and keyring: no server is touched.

The fake ssh answers `-O check` and `-O exit` as a live master would, and
runs whatever the probe or action sends through a local `sh`, so these
tests see what the server would be asked and what the script does with the
answer.
"""

import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "server-dash")

FAKE_SSH = r"""#!/bin/bash
# Skip the options; the master is always up.
args=("$@")
for a in "${args[@]}"; do [[ $a == check || $a == exit ]] && exit 0; done
cmd=""
i=0
while (( i < ${#args[@]} )); do
  a=${args[$i]}
  case "$a" in
    -p|-o) i=$((i + 2)); continue ;;
    -*) i=$((i + 1)); continue ;;
  esac
  i=$((i + 1))
  cmd="${args[*]:$i}"
  break
done
printf '%s\n' "$cmd" >> "$FAKE_LOG"
case "${FAKE_MODE:-}" in
  hang) sleep 60; exit 0 ;;
  sudo-refused) echo "sudo: a password is required" >&2; exit 1 ;;
  dropped) exit 255 ;;
esac
exit 0
"""


class ServerDashTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        bindir = os.path.join(self.dir, "bin")
        os.mkdir(bindir)
        with open(os.path.join(bindir, "ssh"), "w") as f:
            f.write(FAKE_SSH)
        with open(os.path.join(bindir, "secret-tool"), "w") as f:
            f.write("#!/bin/sh\nexit 1\n")
        for name in ("ssh", "secret-tool"):
            os.chmod(os.path.join(bindir, name), 0o755)
        self.log = os.path.join(self.dir, "log")
        self.env = dict(os.environ, PATH=bindir + ":" + os.environ["PATH"], FAKE_LOG=self.log,
                        XDG_STATE_HOME=self.dir, XDG_RUNTIME_DIR=self.dir)

    def run_dash(self, *args, mode="", timeout=20):
        env = dict(self.env, FAKE_MODE=mode)
        return subprocess.run(["bash", SCRIPT, *args], env=env, capture_output=True, text=True, timeout=timeout)

    def sent(self):
        with open(self.log) as f:
            return f.read()

    def test_a_hung_probe_ends_on_term(self):
        # A wedged server must not hold the probe past the panel's watchdog:
        # TERM reaches it while ssh is still waiting.
        env = dict(self.env, FAKE_MODE="hang")
        proc = subprocess.Popen(["bash", SCRIPT, "probe", "user@host", "22"], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1)
        start = time.time()
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=5)
        self.assertLess(time.time() - start, 3)
        self.assertEqual(proc.returncode, 143)

    def test_slow_parts_of_the_probe_have_a_time_limit(self):
        self.run_dash("probe", "user@host", "22")
        # The probe script goes over stdin; the fake ssh logs the command line
        # only, so check the script itself.
        with open(SCRIPT) as f:
            text = f.read()
        for part in ("t df -P", "t ps -eo", "t docker ps", "t sudo -n docker ps", "t systemctl list-units"):
            self.assertTrue(part in text, part + " has a time limit")

    def test_reboot_refused_by_sudo_fails(self):
        # No password saved here, so the panel can say what would help.
        r = self.run_dash("action", "user@host", "22", "reboot", mode="sudo-refused")
        self.assertEqual(r.returncode, 1)
        self.assertIn("@@ERROR\nsudo\nsudo needs a password; save one in Settings", r.stdout)

    def test_reboot_that_drops_the_session_succeeds(self):
        for mode in ("", "dropped"):
            r = self.run_dash("action", "user@host", "22", "poweroff", mode=mode)
            self.assertEqual(r.returncode, 0, mode)
            self.assertNotIn("@@ERROR", r.stdout)

    def test_unit_names_are_quoted(self):
        r = self.run_dash("action", "user@host", "22", "unit-restart", "-weird\\name@1.service")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("systemctl restart -- -weird\\\\name@1.service", self.sent())

    def test_bad_unit_names_never_reach_the_server(self):
        r = self.run_dash("action", "user@host", "22", "unit-restart", "a;reboot")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.exists(self.log))


if __name__ == "__main__":
    unittest.main()
