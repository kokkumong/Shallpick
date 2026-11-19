"""Boot an iPhone using a runtime supported by the selected Xcode."""
import json, subprocess
from pathlib import Path

def run(*args, timeout=120):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()

runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j'))['runtimes']
sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
print('Selected simulator SDK:', sdk, flush=True)
print('Available iOS runtimes:', [(r['name'], r.get('isAvailable')) for r in runtimes if r['name'].startswith('iOS')], flush=True)
compatible = [r for r in runtimes if r.get('isAvailable') and r['version'].split('.')[:2] == sdk.split('.')[:2]]
if not compatible:
    raise RuntimeError('No simulator runtime matching selected SDK ' + sdk)
runtime = compatible[0]
device = run('xcrun', 'simctl', 'create', 'Shallpick Review', 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', runtime['identifier'])
print(f"Device: {device}; runtime: {runtime['name']}", flush=True)
Path('build/device.txt').write_text(device)
run('xcrun', 'simctl', 'boot', device)
subprocess.run(['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', device], check=False)
print(run('xcrun', 'simctl', 'bootstatus', device, '-b', timeout=300), flush=True)
