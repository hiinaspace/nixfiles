"""Adapt Electron's newline JSON RPC to Codex's Unix WebSocket transport."""
import asyncio
import copy
import json
import os
import sys
import tomllib

from websockets.asyncio.client import unix_connect


THREAD_CONFIG_METHODS = {'thread/start', 'thread/resume', 'thread/fork'}


def merge_config(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge_config(target[key], value)
        else:
            target[key] = copy.deepcopy(value)


def launch_mcp_config(args):
    """Keep Desktop's MCP defaults local to this connection, not config.toml."""
    defaults = {}
    args = iter(args)
    for arg in args:
        if arg in ('-c', '--config'):
            override = next(args)
        elif arg.startswith('--config='):
            override = arg[len('--config='):]
        else:
            continue
        key, separator, value = override.partition('=')
        if not separator or not key.strip().startswith('mcp_servers.'):
            continue
        # Match the CLI's TOML-or-literal value handling.
        try:
            parsed = tomllib.loads('value=' + value)['value']
        except tomllib.TOMLDecodeError:
            parsed = value
        entry = {}
        cursor = entry
        parts = key.strip().split('.')
        for part in parts[:-1]:
            cursor = cursor.setdefault(part, {})
        cursor[parts[-1]] = parsed
        merge_config(defaults, entry)
    return defaults.get('mcp_servers', {})


def with_launch_mcp_config(message, defaults):
    if not defaults or message.get('method') not in THREAD_CONFIG_METHODS:
        return message
    message = copy.deepcopy(message)
    params = message.setdefault('params', {})
    config = params.get('config') or {}
    servers = copy.deepcopy(defaults)
    remaining = {}
    for key, value in config.items():
        if key == 'mcp_servers':
            if isinstance(value, dict):
                merge_config(servers, value)
            else:
                # Preserve an explicit replacement, including null.
                return message
        elif key.startswith('mcp_servers.'):
            entry = {}
            cursor = entry
            parts = key.split('.')[1:]
            for part in parts[:-1]:
                cursor = cursor.setdefault(part, {})
            cursor[parts[-1]] = value
            merge_config(servers, entry)
        else:
            remaining[key] = value
    # A single table avoids ordering conflicts between parent and dotted keys.
    params['config'] = {**remaining, 'mcp_servers': servers}
    return message


async def bridge():
    defaults = launch_mcp_config(sys.argv[1:])
    socket = os.environ['CODEX_DESKTOP_SOCKET']
    # systemd starts the server asynchronously during graphical login.
    for attempt in range(60):
        try:
            ws = await unix_connect(socket, uri='ws://localhost/',
                                    max_size=None, compression=None)
            break
        except (OSError, TimeoutError):
            if attempt == 59:
                raise
            await asyncio.sleep(0.5)
    try:
        reader = asyncio.StreamReader(limit=32 * 1024 * 1024)
        await asyncio.get_running_loop().connect_read_pipe(
            lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)

        async def send():
            while line := await reader.readline():
                message = with_launch_mcp_config(json.loads(line), defaults)
                await ws.send(json.dumps(message))

        async def receive():
            async for message in ws:
                if isinstance(message, bytes):
                    message = message.decode()
                print(message, flush=True)

        tasks = [asyncio.create_task(send()), asyncio.create_task(receive())]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    finally:
        await ws.close()


if __name__ == '__main__':
    if 'app-server' not in sys.argv[1:]:
        cli = os.environ['CODEX_DESKTOP_REAL_CLI']
        os.execv(cli, [cli, *sys.argv[1:]])
    asyncio.run(bridge())
