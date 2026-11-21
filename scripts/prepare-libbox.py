#!/usr/bin/env python3
"""Build reviewed libbox bindings; requires Go, Android SDK/NDK/JDK or Xcode.

The source archive is verified by Go's module checksum database and source.json.
Only the pinned native/go.mod and go.sum replace upstream dependency versions.
Artifacts are local build output, never fetched from an old binary release.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PINS = json.loads((ROOT / 'native/source.json').read_text())
OUT = ROOT / 'build/libbox'
PLUGIN = ROOT / 'third_party/sing_box'
TAGS = 'with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0'


def run(args, cwd, env):
    subprocess.run([str(x) for x in args], cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['android', 'apple'])
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    tools = OUT / 'tools'
    tools.mkdir(exist_ok=True)
    env = {**os.environ, 'GOTOOLCHAIN': PINS['toolchain'],
           'GOBIN': str(tools), 'PATH': str(tools) + os.pathsep + os.environ['PATH']}
    module = json.loads(subprocess.check_output(
        ['go', 'mod', 'download', '-json', f"{PINS['module']}@{PINS['version']}"],
        cwd=ROOT / 'native', env=env, text=True))
    if module['Sum'] != PINS['sum']:
        raise RuntimeError('sing-box source checksum mismatch')
    source = OUT / ('source-' + args.platform)
    if source.exists():
        for directory, _, _ in os.walk(source):
            Path(directory).chmod(0o755)
        shutil.rmtree(source)
    shutil.copytree(module['Dir'], source)
    for directory, _, _ in os.walk(source):
        Path(directory).chmod(0o755)
    for name in ['go.mod', 'go.sum']:
        (source / name).chmod(0o600)
        shutil.copyfile(ROOT / 'native' / name, source / name)
    for name in ['gomobile', 'gobind']:
        run(['go', 'install', f"github.com/sagernet/gomobile/cmd/{name}@{PINS['gomobile']}"], source, env)
    flags = f"-X github.com/sagernet/sing-box/constant.Version={PINS['version'].lstrip('v')} -s -w -buildid= -checklinkname=0"
    common = ['-trimpath', '-buildvcs=false', '-ldflags', flags]
    if args.platform == 'android':
        sdk = Path(env.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk')))
        ndks = sorted((sdk / 'ndk').glob('*'), key=lambda p: tuple(int(x) for x in p.name.split('.')))
        env['ANDROID_HOME'] = str(sdk)
        if not ndks and not env.get('ANDROID_NDK_HOME'):
            raise RuntimeError('Android NDK is missing; set ANDROID_NDK_HOME')
        env['ANDROID_NDK_HOME'] = env.get('ANDROID_NDK_HOME') or str(ndks[-1])
        if not env.get('JAVA_HOME'):
            studio = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home')
            java = shutil.which('java')
            if studio.exists():
                env['JAVA_HOME'] = str(studio)
            elif java and Path(java).resolve() != Path('/usr/bin/java'):
                env['JAVA_HOME'] = str(Path(java).resolve().parent.parent)
            else:
                env['JAVA_HOME'] = subprocess.check_output(
                    ['/usr/libexec/java_home', '-v', '17'], text=True).strip()
        artifact = OUT / 'libbox.aar'
        run([tools / 'gomobile', 'bind', '-o', artifact, '-target', 'android',
             '-androidapi', '26', '-javapkg=io.nekohasekai', '-libname=box',
             '-tags', TAGS, *common, './experimental/libbox'], source, env)
        (OUT / 'libbox.aar.sha256').write_text(hashlib.sha256(artifact.read_bytes()).hexdigest() + '\n')
    else:
        artifact = OUT / 'Libbox.xcframework'
        if artifact.exists():
            shutil.rmtree(artifact)
        run([tools / 'gomobile', 'bind', '-o', artifact, '-target', 'ios,iossimulator',
             '-libname=box', '-iosversion=15.0', '-tags-not-macos=with_low_memory',
             '-tags', TAGS + ',with_dhcp,grpcnotrace', *common, './experimental/libbox'], source, env)
        run(['bash', PLUGIN / 'scripts/flatten_xcframework.sh', artifact, '15.0'], source, env)
        destination = PLUGIN / 'ios/sing_box/Frameworks/Libbox.xcframework'
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(artifact, destination)
    record = {**PINS,
        'goModSHA256': hashlib.sha256((ROOT / 'native/go.mod').read_bytes()).hexdigest(),
        'goSumSHA256': hashlib.sha256((ROOT / 'native/go.sum').read_bytes()).hexdigest(),
        'sourceSHA256': hashlib.sha256((ROOT / 'native/source.json').read_bytes()).hexdigest()}
    (OUT / (args.platform + '-build.json')).write_text(json.dumps(record, indent=2) + '\n')
    (OUT / (args.platform + '-build.properties')).write_text(''.join(
        f'{key}={value}\n' for key, value in record.items()))
    if args.platform == 'apple':
        for name in ['go.mod', 'go.sum', 'source.json']:
            shutil.copyfile(ROOT / 'native' / name, artifact / ('Reviewed.' + name))
            shutil.copyfile(ROOT / 'native' / name, destination / ('Reviewed.' + name))
    print('Prepared reviewed native library:', args.platform)


if __name__ == '__main__':
    main()
