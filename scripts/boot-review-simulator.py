import json, subprocess
from pathlib import Path
def run(*args,timeout=120):
    return subprocess.check_output(args,text=True,timeout=timeout).strip()
sdk=run('xcrun','--sdk','iphonesimulator','--show-sdk-version')
runtimes=json.loads(run('xcrun','simctl','list','runtimes','-j'))['runtimes']
runtime=next(r for r in runtimes if r.get('isAvailable') and r['version'].split('.')[:2]==sdk.split('.')[:2])
device=run('xcrun','simctl','create','Shallpick Section2','com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro',runtime['identifier'])
Path('build/device.txt').write_text(device)
print('SDK:',sdk,'runtime:',runtime['name'],'device:',device,flush=True)
run('xcrun','simctl','boot',device)
subprocess.run(['open','-a','Simulator','--args','-CurrentDeviceUDID',device],check=False)
print(run('xcrun','simctl','bootstatus',device,'-b',timeout=300),flush=True)
