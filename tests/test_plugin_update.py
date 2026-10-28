"""bin/plugin-update against throwaway git repos: a remote with a newer
version, and an installed copy in every state an update has met."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "plugin-update")
IDENTITY = {"GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com"}


class PluginUpdateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = dict(os.environ, PLUGIN_UPDATE_QUIET="1", XDG_STATE_HOME=os.path.join(self.tmp, "state"),
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", **IDENTITY)
        self.remote = os.path.join(self.tmp, "remote")
        self.plugin = os.path.join(self.tmp, "plugin")
        os.makedirs(os.path.join(self.remote, "bin"))
        shutil.copy(SCRIPT, os.path.join(self.remote, "bin", "plugin-update"))
        self.write(self.remote, "manifest.json", json.dumps({"id": "io.example.test", "name": "Test", "version": "1.0.0"}))
        self.write(self.remote, "a.txt", "one\n")
        self.git(self.remote, "init", "--quiet", "--initial-branch=main")
        self.commit(self.remote, "First")
        self.git(self.tmp, "clone", "--quiet", self.remote, self.plugin)
        # The remote moves on: a new version with a new file.
        self.write(self.remote, "manifest.json", json.dumps({"id": "io.example.test", "name": "Test", "version": "1.1.0"}))
        self.write(self.remote, "b.txt", "two\n")
        self.commit(self.remote, "Second")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, root, name, text):
        with open(os.path.join(root, name), "w") as f:
            f.write(text)

    def git(self, root, *args):
        return subprocess.run(["git", "-C", root, *args], env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, root, message):
        self.git(root, "add", "-A")
        self.git(root, "commit", "--quiet", "-m", message)

    def run_update(self, *args):
        return subprocess.run(["python3", "-B", os.path.join(self.plugin, "bin", "plugin-update"), *args],
                              env=self.env, capture_output=True, text=True)

    def state(self):
        with open(os.path.join(self.tmp, "state", "test", "update.json")) as f:
            return json.load(f)

    def version(self):
        with open(os.path.join(self.plugin, "manifest.json")) as f:
            return json.load(f)["version"]

    def stashes(self):
        return [line for line in self.git(self.plugin, "stash", "list").splitlines() if line]

    def test_check_sees_the_newer_version(self):
        result = json.loads(self.run_update("check").stdout)
        self.assertTrue(result["available"])
        self.assertEqual((result["current"], result["latest"], result["notes"]), ("1.0.0", "1.1.0", ["Second"]))
        self.assertIsNone(result["error"])

    def test_clean_copy_updates(self):
        self.assertEqual(self.run_update("apply").returncode, 0)
        self.assertEqual(self.version(), "1.1.0")
        self.assertEqual(self.state()["state"], "done")
        self.assertEqual(self.state()["message"], "Updated to 1.1.0.")

    def test_new_files_already_copied_in_do_not_block_it(self):
        # What a development copy looks like: the update's files dropped in by hand.
        self.write(self.plugin, "b.txt", "two\n")
        self.write(self.plugin, "manifest.json", json.dumps({"id": "io.example.test", "name": "Test", "version": "1.1.0"}))
        self.assertEqual(self.run_update("apply").returncode, 0)
        self.assertEqual(self.version(), "1.1.0")
        self.assertEqual(self.stashes(), [], "edits that match the update are not kept")
        self.assertEqual(self.state()["message"], "Updated to 1.1.0.")

    def test_own_edits_are_kept_in_a_stash(self):
        self.write(self.plugin, "a.txt", "mine\n")
        self.write(self.plugin, "notes.txt", "scratch\n")
        self.assertEqual(self.run_update("apply").returncode, 0)
        self.assertEqual(self.version(), "1.1.0")
        self.assertEqual(len(self.stashes()), 1)
        self.assertIn("kept in git stash", self.state()["message"])

    def test_local_commits_are_left_to_git(self):
        self.write(self.plugin, "a.txt", "mine\n")
        self.commit(self.plugin, "Mine")
        self.assertIn("commits of its own", json.loads(self.run_update("check").stdout)["error"])
        self.assertEqual(self.run_update("apply").returncode, 1)
        self.assertEqual(self.state()["state"], "failed")
        self.assertEqual(self.git(self.plugin, "log", "-1", "--format=%s"), "Mine")

    def test_up_to_date_copy_says_so(self):
        self.git(self.plugin, "pull", "--quiet", "--ff-only")
        self.assertFalse(json.loads(self.run_update("check").stdout)["available"])
        self.assertEqual(self.run_update("apply").returncode, 0)
        self.assertEqual(self.state()["message"], "Already up to date.")


if __name__ == "__main__":
    unittest.main()
