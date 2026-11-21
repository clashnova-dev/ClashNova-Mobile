#!/usr/bin/env python3
import hashlib
import base64
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile
from PIL import Image

root = Path(__file__).resolve().parent.parent
version, code = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)', (root/'pubspec.yaml').read_text(), re.M).groups()
apk = root/'build/app/outputs/flutter-apk/app-release.apk'
sdk = Path(os.environ['ANDROID_HOME'])
tools = sdk/'build-tools'/os.environ['ANDROID_BUILD_TOOLS_VERSION'] if os.environ.get('ANDROID_BUILD_TOOLS_VERSION') else max((p for p in (sdk/'build-tools').iterdir() if re.fullmatch(r'\d+\.\d+\.\d+', p.name)), key=lambda p: tuple(int(x) for x in p.name.split('.')))
signature = subprocess.check_output([tools/'apksigner', 'verify', '--verbose', '--print-certs-pem', apk], text=True)
certificates = re.findall(r'-----BEGIN CERTIFICATE-----\s+(.*?)\s+-----END CERTIFICATE-----', signature, re.S)
assert len(certificates) == 1, 'Expected exactly one Android release signer'
certificate = hashlib.sha256(base64.b64decode(re.sub(r'\s+', '', certificates[0]), validate=True)).hexdigest()
assert certificate == (root/'android/release-certificate.sha256').read_text().strip()
# Pinning the certificate DER also pins the expected clashnova-dev identity.
badging = subprocess.check_output([tools/'aapt', 'dump', 'badging', apk], text=True)
assert "package: name='dev.airport.airport_mobile'" in badging
assert "versionName='"+version+"'" in badging and "versionCode='"+code+"'" in badging
assert "application-label:'ClashNova'" in badging
def pixels(image):
 image = image.convert('RGBA')
 data = bytearray(image.tobytes())
 for offset in range(0, len(data), 4):
  if data[offset+3] == 0:
   data[offset:offset+3] = b'\x00\x00\x00'
 return image.size, bytes(data)

icons = []
resources = root/'android/app/src/main/res'
for p in [*resources.glob('mipmap*/ic_launcher.png'), *resources.glob('drawable*/ic_launcher_foreground.png')]:
 with Image.open(p) as image:
  icons.append(pixels(image))
assert icons, 'Launcher icons missing from source'
found = False
with zipfile.ZipFile(apk) as z:
 for entry in z.namelist():
  if entry.startswith('res/') and entry.endswith(('.png','.webp')):
   with Image.open(io.BytesIO(z.read(entry))) as image:
    if pixels(image) in icons: found=True
 for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
  assert 'lib/'+abi+'/libbox.so' in z.namelist(), 'Missing VPN core: '+abi
assert found, 'Packaged launcher icon does not match ClashNova icon'
out=root/'release-artifacts'
out.mkdir(exist_ok=True)
dest=out/('ClashNova-Mobile_'+version+'_android.apk')
shutil.copyfile(apk,dest)
digest=hashlib.sha256(dest.read_bytes()).hexdigest()
metadata={'name':'ClashNova','version':version,'versionCode':int(code),'publisher':'clashnova-dev','certificateSHA256':certificate,'files':[{'file':dest.name,'sha256':digest}]}
(out/'package-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
(out/'SHA256SUMS').write_text(digest+'  '+dest.name+'\n')
print(json.dumps(metadata))
