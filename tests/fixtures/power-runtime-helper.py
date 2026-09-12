"""Inert private-fixture power helper. Never calls a platform service."""
from pathlib import Path
import sys
import time

root = Path(sys.argv[1])
kind = sys.argv[2]
if kind not in ('profiles', 'activeProfile', 'battery', 'setProfile'):
    raise SystemExit(1)
with (root / 'trace').open('a') as stream:
    stream.write(kind + '\n')
if kind == 'profiles':
    active = (root / 'profile').read_text().strip()
    for profile in ('power-saver', 'balanced', 'performance'):
        print(profile + '\t' + ('1' if profile == active else '0'))
elif kind == 'activeProfile':
    print('s "' + (root / 'profile').read_text().strip() + '"')
elif kind == 'battery':
    print('battery-id\tBATfixture\nhealth\t96%\nsize\t50Wh')
else:
    if len(sys.argv) != 4 or sys.argv[3] not in ('power-saver', 'balanced', 'performance'):
        raise SystemExit(1)
    if sys.argv[3] == 'power-saver':
        (root / 'barrier').write_text('ready')
        time.sleep(1)
    (root / 'profile').write_text(sys.argv[3] + '\n')
