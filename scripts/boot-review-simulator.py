"""Create a fresh simulator; bound startup so hosted-runtime hangs are diagnosable."""
import json
import subprocess
from pathlib import Path

def run(*args, timeout=120):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()

runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j'))['runtimes']
runtime = max((r for r in runtimes if r.get('isAvailable') and r['name'].startswith('iOS 26')),
              key=lambda r: tuple(int(v) for v in r['version'].split('.')))
device = run('xcrun', 'simctl', 'create', 'Shallpick Review',
             'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', runtime['identifier'])
print(f"Device: {device}; runtime: {runtime['name']}", flush=True)
Path('build/device.txt').write_text(device)
run('xcrun', 'simctl', 'boot', device)
print(run('xcrun', 'simctl', 'bootstatus', device, '-b', timeout=240), flush=True)
