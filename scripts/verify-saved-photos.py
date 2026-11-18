from pathlib import Path
import sys, json, shutil, hashlib, subprocess
build=Path('build')
if not (build/'device.txt').exists(): sys.exit(0)
device=(build/'device.txt').read_text().strip()
media=Path.home()/'Library/Developer/CoreSimulator/Devices'/device/'data/Media/DCIM'
files={str(p):p for p in media.rglob('*') if p.is_file() and p.suffix.lower() in ('.jpg','.jpeg','.heic','.png')}
before=build/'photos-before.json'
if sys.argv[1]=='before':
 before.write_text(json.dumps(list(files)));sys.exit(0)
if not before.exists(): sys.exit(0)
new=set(files)-set(json.loads(before.read_text()))
out=build/'saved-photos';out.mkdir(exist_ok=True)
rows=[]
for i,name in enumerate(sorted(new)):
 p=files[name];target=out/(str(i+1)+'-'+p.name);shutil.copy2(p,target)
 rows.append({'file':target.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'dimensions':subprocess.check_output(['sips','-g','pixelWidth','-g','pixelHeight',str(p)]).decode().splitlines()[1:]})
(out/'verification.json').write_text(json.dumps({'newImageCount':len(rows),'images':rows},indent=2))
print('Actual saved image files:',len(rows))
