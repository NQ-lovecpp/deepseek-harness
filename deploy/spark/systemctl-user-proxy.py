#!/usr/bin/env python3
"""Loopback-only, token-authenticated allowlist for chen user-systemd commands."""

import hmac
import json
import os
import socketserver
import subprocess

MAX_REQUEST_BYTES = 16 * 1024
MAX_RESPONSE_BYTES = 512 * 1024
ALLOWED_ACTIONS = {
    'cat', 'daemon-reload', 'disable', 'enable', 'is-active', 'is-enabled',
    'list-timers', 'list-unit-files', 'list-units', 'reload', 'reset-failed',
    'restart', 'show', 'start', 'status', 'stop', 'try-restart',
}
REJECTED_OPTIONS = {'--global', '--host', '--machine', '--root', '--runtime'}


def response(code: int, stdout: str = '', stderr: str = '') -> bytes:
    return (json.dumps({'code': code, 'stdout': stdout[-MAX_RESPONSE_BYTES:], 'stderr': stderr[-MAX_RESPONSE_BYTES:]}) + '\n').encode()


def action_of(args: list[str]) -> str | None:
    for argument in args:
        if not argument.startswith('-'):
            return argument
    return None


def is_allowed(args: object) -> bool:
    if not isinstance(args, list) or not args or len(args) > 64 or not all(isinstance(argument, str) for argument in args):
        return False
    if any(argument == '--user' or argument.split('=', 1)[0] in REJECTED_OPTIONS for argument in args):
        return False
    return action_of(args) in ALLOWED_ACTIONS


class Handler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        raw = self.rfile.readline(MAX_REQUEST_BYTES + 1)
        if not raw or len(raw) > MAX_REQUEST_BYTES:
            self.wfile.write(response(2, stderr='Invalid host systemctl proxy request.\n'))
            return
        try:
            request = json.loads(raw)
            token = request['token']
            args = request['args']
        except (KeyError, TypeError, json.JSONDecodeError):
            self.wfile.write(response(2, stderr='Invalid host systemctl proxy request.\n'))
            return
        with open(os.environ['SYSTEMCTL_PROXY_TOKEN_FILE'], encoding='utf-8') as token_file:
            expected = token_file.read().strip()
        if not isinstance(token, str) or not hmac.compare_digest(token, expected):
            self.wfile.write(response(1, stderr='Host systemctl proxy authentication failed.\n'))
            return
        if not is_allowed(args):
            self.wfile.write(response(2, stderr='That systemctl --user operation is not allowed by the host proxy.\n'))
            return
        try:
            completed = subprocess.run(
                ['/usr/bin/systemctl', '--user', '--no-pager', *args],
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
        except subprocess.TimeoutExpired:
            self.wfile.write(response(124, stderr='Host systemctl proxy timed out after 60 seconds.\n'))
            return
        self.wfile.write(response(completed.returncode, completed.stdout, completed.stderr))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


if __name__ == '__main__':
    address = os.environ.get('SYSTEMCTL_PROXY_ADDRESS', '127.0.0.1')
    port = int(os.environ.get('SYSTEMCTL_PROXY_PORT', '8892'))
    with Server((address, port), Handler) as server:
        server.serve_forever()
