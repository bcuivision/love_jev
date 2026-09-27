#!/usr/bin/env python3
"""Run the Mac backend and deliver its connection settings to a development iPhone."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / '.build' / 'local-server'
PID_FILE = STATE / 'server.pid'
NODE = shutil.which('node')


def environment():
    values = {}
    for line in (ROOT / 'server' / '.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key] = value.strip().strip('\"').strip("'")
    return values


def health():
    port = int(environment().get('PORT', '8787'))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f'http://127.0.0.1:{port}/health', timeout=2) as response:
            return json.load(response)
    except (OSError, ValueError):
        return None


def managed_pid():
    if not PID_FILE.exists():
        return None
    try:
        pid = int(PID_FILE.read_text())
        command = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
        if str(ROOT / 'server' / 'src' / 'index.ts') in command:
            return pid
    except (ValueError, OSError):
        pass
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['start', 'stop', 'status', 'configure-iphone'])
    parser.add_argument('--device', help='Connected iPhone identifier from xcrun devicectl list devices')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    if args.action == 'start':
        if managed_pid():
            print(json.dumps({'running': True, 'health': health()}, ensure_ascii=False))
            return
        if health() is not None:
            raise SystemExit('Another service already uses this port; it was left running.')
        if not NODE:
            raise SystemExit('Node.js is required.')
        log_path = STATE / 'server.log'
        with log_path.open('ab') as log:
            os.chmod(log_path, 0o600)
            process = subprocess.Popen([NODE, '--env-file=.env', str(ROOT / 'server' / 'src' / 'index.ts')],
                cwd=ROOT / 'server', stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        PID_FILE.write_text(str(process.pid))
        for _ in range(30):
            if process.poll() is not None:
                raise SystemExit('Backend failed to start. Check .build/local-server/server.log.')
            result = health()
            if result:
                print(json.dumps({'running': True, 'pid': process.pid, 'health': result}, ensure_ascii=False))
                return
            time.sleep(0.2)
        raise SystemExit('Backend started but health check has not completed.')
    elif args.action == 'stop':
        pid = managed_pid()
        if pid:
            os.kill(pid, signal.SIGTERM)
            PID_FILE.unlink(missing_ok=True)
        print('Stopped managed local backend.' if pid else 'No managed backend is running.')
    elif args.action == 'status':
        print(json.dumps({'running': managed_pid() is not None, 'health': health()}, ensure_ascii=False))
    else:
        if not args.device:
            raise SystemExit('--device is required.')
        values = environment()
        token = values.get('APP_ACCESS_TOKEN', '')
        if len(token) < 24:
            raise SystemExit('APP_ACCESS_TOKEN is missing or too short.')
        host = socket.gethostname()
        if not host.endswith('.local'):
            host = subprocess.check_output(['scutil', '--get', 'LocalHostName'], text=True).strip() + '.local'
        endpoint = f'http://{host}:{int(values.get("PORT", "8787"))}'
        with tempfile.TemporaryDirectory(prefix='lianaiba-connection-') as folder:
            connection = Path(folder) / 'local-service.json'
            connection.write_text(json.dumps({'endpoint': endpoint, 'accessToken': token}))
            connection.chmod(0o600)
            subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'to', '--device', args.device,
                '--domain-type', 'appDataContainer', '--domain-identifier', 'com.jevdemo.lianaiba',
                '--source', str(connection), '--destination', 'Documents/local-service.json', '--timeout', '20'], check=True)
        print(f'Connection delivered: {endpoint}. Relaunch 恋爱吧 to import it; analysis consent is unchanged.')


if __name__ == '__main__':
    main()
