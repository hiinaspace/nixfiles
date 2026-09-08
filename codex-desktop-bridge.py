"""Adapt Electron's newline JSON RPC to Codex's Unix WebSocket transport."""
import asyncio
import os
import sys

from websockets.asyncio.client import unix_connect


async def bridge():
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
                await ws.send(line.decode().rstrip('\n'))

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
