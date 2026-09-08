import fcntl
import os
from pathlib import Path
import subprocess
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="port-bridge-installed-") as folder:
    env = dict(os.environ, XDG_CONFIG_HOME=folder)
    process = subprocess.Popen(["/usr/bin/port-bridge"], env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        time.sleep(1.5)
        assert process.poll() is None, process.communicate()
        with (Path(folder) / "port-bridge" / "app.lock").open("a") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                raise AssertionError("Installed app did not acquire its single-instance lock")
    finally:
        process.terminate()
        out, err = process.communicate(timeout=5)
    assert not err, err
print("Installed /usr/bin/port-bridge starts a Linux GUI and acquires the single-instance lock")
