"""Read-only owned PID/start-time checks BEFORE the test cgroup is drained."""
import json
import os
from pathlib import Path
import time

base = Path(os.environ['CATALOG_PID_DIR'])
files = list(base.glob('*.json'))
expected = {'hard', 'destroy'} if os.environ.get('CATALOG_MASKED_SIGNALS') == '1' else {'cancel', 'owner', 'hard', 'destroy'}
if not len(expected) <= len(files) <= 12 or {path.name.split('-', 1)[0] for path in files} != expected:
    raise AssertionError('actual command did not construct its expected inert process trees')
records = []
for path in files:
    if path.stat().st_size > 4096:
        raise AssertionError('oversized fixture record')
    records.extend(json.loads(path.read_text()))


def alive(record):
    try:
        value = Path(f'/proc/{record["pid"]}/stat').read_text().rsplit(')', 1)[1].split()
        return value[19] == record['start'] and value[0] != 'Z'
    except FileNotFoundError:
        return False


deadline = time.monotonic() + .75
while any(alive(record) for record in records) and time.monotonic() < deadline:
    time.sleep(.01)
if any(alive(record) for record in records):
    raise AssertionError('custodian descendant survived cancellation')
print('actual command process trees drained before cgroup cleanup')
