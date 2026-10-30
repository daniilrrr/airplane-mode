#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELLS = ('/bin/bash', '/bin/zsh')
STUB = r'''
import os, pathlib, signal, sys, time
case = pathlib.Path(os.environ['CASE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
def alive():
    try:
        os.kill(int((case / 'server.pid').read_text()), 0)
        return (case / 'ready').exists()
    except (FileNotFoundError, ProcessLookupError):
        return False
if name == 'ollama':
    if args[0] == 'serve':
        (case / 'server.pid').write_text(str(os.getpid()))
        if os.environ.get('START_FAIL') == '1':
            sys.exit(7)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, lambda *_: sys.exit(0))
        (case / 'ready').touch()
        while True:
            time.sleep(.02)
    elif args[0] == 'launch':
        (case / 'client.pid').write_text(str(os.getpid()))
        (case / 'owner.pid').write_text(str(os.getppid()))
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, lambda sig, _: sys.exit(128 + sig))
        (case / 'launched').touch()
        if os.environ.get('BLOCK_CLIENT') == '1':
            while True:
                time.sleep(.02)
        sys.exit(int(os.environ.get('LAUNCH_FAIL', '0')))
    elif args[0] == 'show':
        sys.exit(int(os.environ.get('MISSING', '0')))
    elif args[0] == 'pull':
        sys.exit(int(os.environ.get('PULL_FAIL', '0')))
elif name == 'curl':
    if any(a.endswith('/api/tags') for a in args):
        sys.exit(0 if alive() and os.environ.get('NEVER_READY') != '1' else 1)
    if any(a.endswith('/api/generate') for a in args):
        print('{"done":false}' if os.environ.get('BAD_RESPONSE') == '1' else '{"done":true,"response":"hello"}')
    else:
        sys.exit(1)
elif name == 'opencode':
    print('opencode v2.2.3')
elif name == 'uname':
    print('Darwin')
elif name == 'sleep':
    time.sleep(.02)
elif name == 'mktemp':
    result = __import__('subprocess').run(['/usr/bin/mktemp', *args], capture_output=True, text=True)
    with (case / 'tempfiles').open('a') as output:
        output.write(result.stdout)
    sys.stdout.write(result.stdout)
    sys.exit(result.returncode)
'''


def running(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
    return bool(result.stdout.strip()) and not result.stdout.lstrip().startswith('Z')


def wait_for(predicate, message, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.02)
    raise AssertionError(message)


class Lifecycle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='airplane-lifecycle-')
        cls.directory = Path(cls.temporary.name)
        cls.bin = cls.directory / 'bin'
        cls.bin.mkdir()
        for name in ('ollama', 'curl', 'opencode', 'uname', 'sleep', 'mktemp'):
            executable = cls.bin / name
            executable.write_text(f'#!{sys.executable}\n' + STUB)
            executable.chmod(0o755)
        cls.block = cls.directory / 'ollama.sh'
        with cls.block.open('w') as output:
            subprocess.run(['/bin/bash', '-c', '. "$1"; ENGINE=ollama; SELECTED_MODEL="$DEFAULT_MODEL"; write_launcher_block',
                            'emit', str(ROOT / 'src/airplane-mode.sh')], stdout=output, check=True)
        for shell in SHELLS:
            if not Path(shell).exists():
                raise RuntimeError(f'Required verification shell missing: {shell}')

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(dir=self.directory))
        self.env = dict(os.environ, CASE=str(self.case), HOME=str(self.case),
                        TMPDIR=str(self.case), PATH=f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin')
        for name in ('START_FAIL', 'BLOCK_CLIENT', 'LAUNCH_FAIL', 'MISSING', 'PULL_FAIL', 'BAD_RESPONSE', 'NEVER_READY'):
            self.env.pop(name, None)
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for filename in ('server.pid', 'client.pid'):
            path = self.case / filename
            if path.exists():
                pid = int(path.read_text())
                try:
                    if running(pid):
                        os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for process in self.processes:
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=3)

    def start(self, shell, command='airplane-mode', setup=False, **variables):
        self.env.update({key: str(value) for key, value in variables.items()})
        argv = [shell, str(ROOT / 'src/airplane-mode.sh')] if setup else [shell, '-c', '. "$1"; ' + command, 'test', str(self.block)]
        process = subprocess.Popen(argv, env=self.env, start_new_session=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.processes.append(process)
        return process

    def finish(self, process, expected=0, setup=False):
        output, _ = process.communicate('yes\n1\n' if setup else None, timeout=10)
        self.assertEqual(process.returncode, expected, output)
        return output

    def assert_stopped(self):
        path = self.case / 'server.pid'
        self.assertTrue(path.exists(), 'The test must have started a persistent server')
        pid = int(path.read_text())
        wait_for(lambda: not running(pid), f'launcher returned but owned Ollama {pid} is still running')

    def test_owned_exit(self):
        for shell in SHELLS:
            for variables, expected, command in (({}, 0, 'airplane-mode'),
                                                  ({'LAUNCH_FAIL': 37}, 37, 'airplane-mode'),
                                                  ({'MISSING': 1}, 1, 'airplane-mode'),
                                                  ({'NEVER_READY': 1}, 1, 'airplane-mode'),
                                                  ({'START_FAIL': 1}, 1, 'airplane-mode'),
                                                  ({}, 0, '_airplane_smoke'),
                                                  ({'BAD_RESPONSE': 1}, 255, '_airplane_smoke')):
                with self.subTest(shell=shell, command=command, variables=variables):
                    self.finish(self.start(shell, command, **variables), expected)
                    self.assert_stopped()
                self.tearDown()
                self.setUp()

    def test_borrowed_server(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                server = subprocess.Popen([str(self.bin / 'ollama'), 'serve'], env=self.env, start_new_session=True)
                self.processes.append(server)
                wait_for(lambda: (self.case / 'ready').exists(), 'External server did not start')
                pid = int((self.case / 'server.pid').read_text())
                self.finish(self.start(shell))
                self.assertTrue(running(pid), 'Launcher killed a borrowed server')
                self.finish(self.start(shell, '_airplane_smoke'))
                self.assertTrue(running(pid), 'Smoke check killed a borrowed server')
            self.tearDown()
            self.setUp()

    def test_terminal_signals(self):
        for shell in SHELLS:
            for sig in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
                with self.subTest(shell=shell, signal=sig):
                    process = self.start(shell, BLOCK_CLIENT=1)
                    wait_for(lambda: (self.case / 'launched').exists(), 'Client did not start')
                    self.assertTrue(running(int((self.case / 'server.pid').read_text())))
                    os.killpg(process.pid, sig)
                    output, _ = process.communicate(timeout=5)
                    self.assert_stopped()
                    self.assertNotEqual(process.returncode, 0, output)
                    self.assertFalse(running(int((self.case / 'client.pid').read_text())), 'Client survived terminal signal')
                self.tearDown()
                self.setUp()

    def test_caller_state(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                command = '''
[ -z "${ZSH_VERSION:-}" ] || setopt localtraps localoptions
trap 'printf caller-exit' EXIT
trap ':' HUP INT TERM
before=$(trap)
caller_flags=$-
_airplane_ollama_pid=caller-owned-value
airplane-mode || exit
[ "$(trap)" = "$before" ] || exit 41
[ "$-" = "$caller_flags" ] || exit 42
[ "$_airplane_ollama_pid" = caller-owned-value ] || exit 43
'''
                output = self.finish(self.start(shell, command))
                self.assertEqual(output.count('caller-exit'), 1, output)
                self.assert_stopped()
            self.tearDown()
            self.setUp()

    def test_setup_cleanup(self):
        for variables, expected in (({}, 0), ({'MISSING': 1, 'PULL_FAIL': 9}, 9), ({'BAD_RESPONSE': 1}, 255)):
            with self.subTest(variables=variables):
                self.finish(self.start('/bin/bash', setup=True, **variables), expected, setup=True)
                self.assert_stopped()
                paths = (self.case / 'tempfiles').read_text().splitlines()
                self.assertTrue(paths, 'Setup must exercise temporary-file cleanup')
                self.assertTrue(all(not Path(path).exists() for path in paths), f'Setup left temporary files: {paths}')
            self.tearDown()
            self.setUp()


if __name__ == '__main__':
    unittest.main(verbosity=2)
