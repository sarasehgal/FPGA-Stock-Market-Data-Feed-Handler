#!/usr/bin/env python3
"""
demo_server.py — FPGA trigger relay server.

Reads triggers from FPGA via COM4 UART at 115200 baud,
broadcasts each as JSON over WebSocket to connected dashboards.

Usage:
    python demo_server.py
    python demo_server.py --port COM5 --ws-port 8765 --http-port 8080
"""
import asyncio
import json
import time
import threading
import argparse
import http.server
import functools
from collections import deque

import serial
import websockets

# ── Globals ──────────────────────────────────────────────────────────
clients = set()
history = deque(maxlen=200)
stats = {"total": 0, "start": time.time()}

# ── UART reader (runs in background thread) ──────────────────────────
def uart_reader(port, baud, loop):
    ser = serial.Serial(port, baud, timeout=1)
    print(f"[UART] Opened {port} at {baud}")
    buf = b""
    while True:
        chunk = ser.read(256)
        if not chunk:
            continue
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            text = line.rstrip(b"\r").decode("ascii", errors="replace")
            if text.startswith("TRIG:"):
                msg = parse_trigger(text)
                if msg:
                    stats["total"] += 1
                    history.append(msg)
                    asyncio.run_coroutine_threadsafe(broadcast(msg), loop)

def parse_trigger(line):
    """Parse 'TRIG:AAPL:0x0001E240:b:008E' → dict"""
    try:
        parts = line.split(":")
        if len(parts) < 4:
            return None
        sym = parts[1]
        price = int(parts[2], 16)
        reason_code = parts[3]
        latency_cycles = int(parts[4], 16) if len(parts) > 4 else 0
        latency_ns = latency_cycles * 10  # 100 MHz = 10ns per cycle
        # Reason codes: T=bid_thresh, t=ask_thresh, E=ema_bid, e=ema_ask, S=spread
        reason_map = {"T":"THRESH","t":"THRESH","E":"EMA","e":"EMA","S":"SPREAD","b":"THRESH","a":"THRESH"}
        side_map = {"T":"bid","t":"ask","E":"bid","e":"ask","S":"spread","b":"bid","a":"ask"}
        return {
            "sym": sym,
            "price": price,
            "side": side_map.get(reason_code, "?"),
            "reason": reason_map.get(reason_code, "?"),
            "reason_code": reason_code,
            "lat_ns": latency_ns,
            "lat_cycles": latency_cycles,
            "ts": int(time.time() * 1000),
        }
    except Exception:
        return None

# ── WebSocket server ─────────────────────────────────────────────────
async def broadcast(msg):
    if not clients:
        return
    data = json.dumps(msg)
    dead = set()
    for ws in clients:
        try:
            await ws.send(data)
        except websockets.exceptions.ConnectionClosed:
            dead.add(ws)
    clients -= dead

async def ws_handler(ws):
    clients.add(ws)
    remote = ws.remote_address
    print(f"[WS] Client connected: {remote}")
    # Send recent history on connect
    for msg in list(history)[-20:]:
        try:
            await ws.send(json.dumps(msg))
        except Exception:
            break
    try:
        async for _ in ws:
            pass  # ignore client messages
    finally:
        clients.discard(ws)
        print(f"[WS] Client disconnected: {remote}")

# ── HTTP server for dashboard.html ───────────────────────────────────
def run_http(directory, port):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
    httpd = http.server.HTTPServer(("", port), handler)
    print(f"[HTTP] Serving {directory} on http://localhost:{port}")
    httpd.serve_forever()

# ── Main ─────────────────────────────────────────────────────────────
async def main_async(args):
    loop = asyncio.get_event_loop()

    # Start UART reader thread
    uart_thread = threading.Thread(
        target=uart_reader, args=(args.port, args.baud, loop), daemon=True)
    uart_thread.start()

    # Start HTTP server thread
    import os
    http_dir = os.path.dirname(os.path.abspath(__file__))
    http_thread = threading.Thread(
        target=run_http, args=(http_dir, args.http_port), daemon=True)
    http_thread.start()

    # Start WebSocket server
    print(f"[WS] Listening on ws://localhost:{args.ws_port}")
    async with websockets.serve(ws_handler, "localhost", args.ws_port):
        print(f"\n  Dashboard: http://localhost:{args.http_port}/dashboard.html\n")
        await asyncio.Future()  # run forever

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM4", help="Serial port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--ws-port", type=int, default=8765)
    ap.add_argument("--http-port", type=int, default=8080)
    args = ap.parse_args()

    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        print("\nShutdown.")

if __name__ == "__main__":
    main()
