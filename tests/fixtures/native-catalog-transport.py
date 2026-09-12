"""Constructed inert IPC replacements; never contact a real shell."""
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader('catalog_helper', str(Path(__file__).parent / 'catalog/manager/shibumi-native-catalog'))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)


def require(value, message):
    if not value:
        raise AssertionError(message)


def command(code):
    return ['/usr/bin/python3', '-I', '-S', '-c', code]


def must_refuse(code, diagnostic):
    try:
        helper.collect(command(code))
    except helper.Refused:
        return
    raise AssertionError(diagnostic)


require(helper.MAX_OUTPUT == 262144 and helper.MAX_ERROR == 8192 and helper.DEADLINE == 3,
    'production acquisition bounds changed')
for size in (0, 262143, 262144):
    require(len(helper.collect(command(f'import sys;sys.stdout.buffer.write(b"x"*{size})'))) == size,
        'stdout boundary refused')
for size in (8191, 8192):
    require(helper.collect(command(f'import sys;sys.stderr.buffer.write(b"x"*{size});print("[]")')) == b'[]\n',
        'stderr boundary refused')
must_refuse('import sys;sys.stdout.buffer.write(b"x"*262145)', 'stdout acquisition overbound accepted')
must_refuse('import sys;sys.stderr.buffer.write(b"x"*8193)', 'stderr acquisition overbound accepted')
must_refuse('import sys;print("[]");sys.exit(1)', 'IPC failure accepted')
started = time.monotonic()
must_refuse('import time;time.sleep(15)', 'hung IPC accepted')
require(time.monotonic() - started < 4.5, 'owned deadline was not enforced')

# A leader exits while an inert descendant retains the pipes. Reader timeout
# must kill the still-reserved process group, not reap/reuse the leader PID first.
pidfile = Path('descendant.pid').absolute()
code = f'''import os,time
pid=os.fork()
if pid == 0:
    with open({str(pidfile)!r}, 'w') as out: out.write(str(os.getpid()))
    time.sleep(15)
else:
    os._exit(0)
'''
must_refuse(code, 'descendant pipe escaped deadline')
pid = int(pidfile.read_text())
for _ in range(100):
    try:
        state = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[0]
        if state == 'Z': break
    except FileNotFoundError:
        break
    time.sleep(.01)
else:
    raise AssertionError('owned descendant survived cleanup')

collect = helper.collect
shell_process_identity = helper.shell_process_identity
stdout = sys.stdout
arguments = sys.argv
fixture_shell = (Path('fixture-shell') / 'shell').absolute()
(fixture_shell / 'plugins/widget').mkdir(parents=True)
manifest = {"schemaVersion": 1, "id": "fixture.widget", "name": "Fixture Widget",
    "version": "1.2.3", "author": "Fixture Author", "description": "Search metadata",
    "tags": ["searchable"], "kinds": ["bar-widget"],
    "entryPoints": {"barWidget": "Widget.qml"},
    "barWidget": {"displayName": "Fixture Widget", "description": "Widget metadata",
        "category": "Fixture", "semanticCapabilities": ["fixture"],
        "defaultSection": "left", "allowMultiple": False}}
(fixture_shell / 'plugins/widget/manifest.json').write_text(json.dumps(manifest))
class Capture:
    def __init__(self): self.buffer = io.BytesIO()

def invoke(raw):
    expected = ['/usr/bin/quickshell', 'ipc', '--pid', '4242',
                'call', '--', 'shell', 'listPlugins']
    def replacement(argv, *, group_owner=False):
        require(argv == expected and group_owner is False,
                'non-read-only or wrong-instance command')
        return raw
    def identity(pid, directory):
        require(pid == 4242 and directory == str(fixture_shell),
                'wrong shell process identity arguments')
        return 99
    helper.collect = replacement  # Complete inert override; no native fallback.
    helper.shell_process_identity = identity
    sys.argv = ['helper', '--shell', str(fixture_shell), '--pid', '4242']
    capture = Capture()
    sys.stdout = capture
    try:
        helper.main()
        return capture.buffer.getvalue()
    finally:
        sys.stdout = stdout
        sys.argv = arguments
        helper.collect = collect
        helper.shell_process_identity = shell_process_identity

require(invoke(b'[]\n') == b'[]', 'valid empty public helper output changed')
native_row = [{"id": "fixture.widget", "name": "Fixture Widget", "kinds": ["bar-widget"],
    "enabled": False, "active": False, "canDisable": True,
    "firstParty": True, "clonedFrom": ""}]
native_payload = json.dumps(native_row, separators=(",", ":")).encode()
enriched = json.loads(invoke(native_payload))[0]
require(enriched["description"] == "Search metadata"
    and enriched["author"] == "Fixture Author"
    and enriched["tags"] == ["searchable"]
    and enriched["barWidget"]["defaultSection"] == "left",
    'package metadata/defaultSection was not retained')

manifest_path = fixture_shell / 'plugins/widget/manifest.json'
duplicate_directory = fixture_shell / 'plugins/duplicate'
duplicate_directory.mkdir()
(duplicate_directory / 'manifest.json').write_text(json.dumps(manifest))
try:
    invoke(native_payload)
except helper.Refused:
    pass
else:
    raise AssertionError('duplicate manifest identity accepted')
(duplicate_directory / 'manifest.json').unlink()
duplicate_directory.rmdir()

manifest_backup = manifest_path.with_suffix('.backup')
manifest_path.rename(manifest_backup)
manifest_path.symlink_to(manifest_backup.name)
try:
    invoke(native_payload)
except (helper.Refused, OSError):
    pass
else:
    raise AssertionError('symlinked manifest metadata accepted')
manifest_path.unlink()
manifest_backup.rename(manifest_path)

saved_probe_limit = helper.MAX_MANIFEST_PROBES
helper.MAX_MANIFEST_PROBES = 0
try:
    invoke(native_payload)
except helper.Refused:
    pass
else:
    raise AssertionError('manifest enumeration bound was not enforced')
finally:
    helper.MAX_MANIFEST_PROBES = saved_probe_limit

saved_manifest_total = helper.MAX_MANIFEST_TOTAL
helper.MAX_MANIFEST_TOTAL = 1
try:
    invoke(native_payload)
except helper.Refused:
    pass
else:
    raise AssertionError('aggregate manifest byte bound was not enforced')
finally:
    helper.MAX_MANIFEST_TOTAL = saved_manifest_total

race_path = Path('manifest-race.json').absolute()
race_path.write_bytes(b'x' * 20000)
original_read = helper.os.read
race_triggered = False
def racing_read(descriptor, size):
    global race_triggered
    data = original_read(descriptor, size)
    if data and not race_triggered:
        race_triggered = True
        race_path.write_bytes(b'y' * 20000)
    return data
helper.os.read = racing_read
try:
    helper.read_regular(race_path)
except helper.Refused:
    pass
else:
    raise AssertionError('manifest replacement during read accepted')
finally:
    helper.os.read = original_read
    race_path.unlink()

duplicate_id_payload = native_payload.replace(
    b'"id":"fixture.widget"', b'"id":"decoy","id":"fixture.widget"', 1)
for raw, diagnostic in ((duplicate_id_payload, 'duplicate JSON key accepted'),
    (b'\xef\xbb\xbf[]', 'BOM accepted'), (b'["\xff"]', 'invalid UTF8 accepted'),
    (b'{}', 'non-array accepted'), (b'[NaN]', 'nonfinite token accepted'),
    (b'[1e309]', 'overflow accepted'), (b'[' + b'{},' * 512 + b'{}]', '513 helper rows accepted')):
    try:
        invoke(raw)
    except (helper.Refused, UnicodeError, ValueError):
        continue
    raise AssertionError(diagnostic)
print('bounded native catalog transport passed; inert IPC only')
