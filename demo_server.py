#!/usr/bin/env python3
"""demo_server.py — FPGA trigger relay: UART → WebSocket + HTTP."""
import asyncio, json, time, threading, argparse, http.server, functools, os
from collections import deque
import serial
import websockets

# ── Shared state ─────────────────────────────────────────────────────
trigger_queue = deque(maxlen=5000)  # thread-safe append from UART reader
write_idx = 0  # monotonic counter of total messages added

# ── UART reader thread ──────────────────────────────────────────────
def uart_reader(port, baud):
    global write_idx
    ser = serial.Serial(port, baud, timeout=1)
    print(f"[UART] Opened {port} at {baud}", flush=True)
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
                    trigger_queue.append(msg)
                    write_idx += 1

def parse_trigger(line):
    try:
        parts = line.split(":")
        if len(parts) < 4:
            return None
        sym = parts[1]
        price = int(parts[2], 16)
        reason_code = parts[3]
        latency_cycles = int(parts[4], 16) if len(parts) > 4 else 0
        latency_ns = latency_cycles * 10
        reason_map = {"T":"THRESH","t":"THRESH","E":"EMA","e":"EMA","S":"SPREAD"}
        side_map = {"T":"bid","t":"ask","E":"bid","e":"ask","S":"spread"}
        return {
            "sym": sym, "price": price,
            "side": side_map.get(reason_code, "bid"),
            "reason": reason_map.get(reason_code, "THRESH"),
            "lat_ns": latency_ns,
            "ts": int(time.time() * 1000),
        }
    except Exception:
        return None

# ── WebSocket handler — each client polls the shared deque ───────────
async def ws_handler(ws):
    remote = ws.remote_address
    print(f"[WS] Client connected: {remote}", flush=True)

    # Send last 20 from history
    items = list(trigger_queue)
    for msg in items[-20:]:
        try:
            await ws.send(json.dumps(msg))
        except Exception:
            return

    # Track where this client is in the stream
    seen = write_idx

    try:
        while True:
            current_idx = write_idx
            if current_idx > seen:
                # New messages available — send them
                items = list(trigger_queue)
                # Send the last (current_idx - seen) items, capped to avoid huge bursts
                n_new = min(current_idx - seen, 50)
                for msg in items[-n_new:]:
                    await ws.send(json.dumps(msg))
                seen = current_idx
            await asyncio.sleep(0.1)  # 100ms poll — fast enough for live feel
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        print(f"[WS] Client disconnected: {remote}", flush=True)

# ── Main ─────────────────────────────────────────────────────────────
async def main_async(args):
    # UART reader thread
    threading.Thread(target=uart_reader, args=(args.port, args.baud), daemon=True).start()

    # WebSocket server
    print(f"[WS] Listening on ws://localhost:{args.ws_port}", flush=True)
    print(f"\n  Dashboard: http://localhost:{args.http_port}/dashboard.html\n", flush=True)

    async with websockets.serve(ws_handler, "localhost", args.ws_port):
        await asyncio.Future()  # run forever

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM4")
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
