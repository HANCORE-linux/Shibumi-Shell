"""Inert, fully replaced IPC leaf for actual QProcess/custodian tests."""
import json
import os
from pathlib import Path
import sys
import time

mode = sys.argv[1]
base = Path(os.environ['CATALOG_PID_DIR'])
if mode == 'happy':
    print('[]')
    raise SystemExit(0)
if mode == 'failure':
    print('[]')
    raise SystemExit(1)
if mode not in ('cancel', 'owner', 'hard', 'destroy'):
    raise SystemExit(2)


def identity(pid):
    value = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return {'pid': pid, 'start': value[19]}


parent = os.getpid()
group = os.getpgrp()
if os.fork() == 0:
    record = [identity(group), identity(parent), identity(os.getpid())]
    with (base / f'{mode}-{os.getpid()}.json').open('x') as stream:
        json.dump(record, stream)
    (base / 'ready').write_text(mode)
    time.sleep(20)
    os._exit(0)
time.sleep(20)
