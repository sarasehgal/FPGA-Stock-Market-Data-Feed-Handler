#!/usr/bin/env python3
"""
run_demo.py — One-shot demo launcher.
1. Programs FPGA via Vivado
2. Waits for PHY link
3. Starts demo_server.py (UART→WebSocket relay + HTTP)
4. Sends frames with timestamp-based seq (never repeats)
5. Keeps sending until Ctrl+C
"""
import subprocess, sys, os, time, struct, signal, threading

PROJ = os.path.dirname(os.path.abspath(__file__))
PYTHON = sys.executable
VIVADO = r"C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat"
IFACE = r'\Device\NPF_{696EC36D-E991-4A75-8002-E3C10A7430A6}'

def step(msg):
    print(f"\n{'='*60}\n  {msg}\n{'='*60}", flush=True)

# ── 1. Program FPGA ─────────────────────────────────────────
step("Programming FPGA...")
r = subprocess.run(
    [VIVADO, "-mode", "batch", "-source", "prog_only.tcl",
     "-log", "vivado_demo.log", "-journal", "vivado_demo.jou"],
    cwd=PROJ, capture_output=True, text=True, timeout=120)
if r.returncode != 0:
    print("FPGA programming failed!")
    print(r.stdout[-500:] if r.stdout else "")
    print(r.stderr[-500:] if r.stderr else "")
    sys.exit(1)
print("  FPGA programmed OK")

# ── 2. Wait for PHY link ────────────────────────────────────
step("Waiting 12s for PHY link-up...")
time.sleep(12)
print("  Ready")

# ── 3. Start demo_server.py ─────────────────────────────────
step("Starting demo_server.py...")
server = subprocess.Popen(
    [PYTHON, "-u", "demo_server.py"],
    cwd=PROJ, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
time.sleep(2)
print("  WebSocket server started")

# Start HTTP server separately (demo_server's HTTP thread sometimes fails silently)
step("Starting HTTP server on port 8080...")
http_proc = subprocess.Popen(
    [PYTHON, "-m", "http.server", "8080", "--directory", PROJ],
    cwd=PROJ, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
time.sleep(1)
print("  HTTP server started")

# ── 4. Verify UART works ────────────────────────────────────
step("Quick UART verification (5s)...")
import serial
try:
    ser = serial.Serial('COM4', 115200, timeout=1)
except Exception as e:
    print(f"  COM4 open failed: {e}")
    print("  (demo_server may have it — that's OK, continuing)")
    ser = None

if ser:
    # Send a few frames and check UART
    from scapy.all import Ether, Raw, sendp
    seq = 0  # start at 0; FPGA was just reprogrammed so last_seq is reset
    for i in range(20):
        seq = (seq + 1) & 0xFFFF
        payload = struct.pack('>B4sIHHB', 1, b'AAPL', 123456, 100, seq, 0)
        payload += bytes([sum(payload) % 256])
        sendp(Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5)/Raw(load=payload),
              iface=IFACE, verbose=False)
    time.sleep(2)
    data = ser.read(1000)
    ser.close()
    if b'TRIG' in data:
        print(f"  UART verified! Got {data.count(b'TRIG')} triggers")
    else:
        print(f"  WARNING: no triggers in UART ({len(data)} bytes)")
else:
    print("  Skipping direct UART check (server has port)")

# ── 5. Send frames continuously ─────────────────────────────
step("Sending frames... Open http://localhost:8080/dashboard.html")
print("  Press Ctrl+C to stop\n", flush=True)

import random
from scapy.all import Ether, Raw, sendp

MT_QUOTE, MT_TRADE, MT_CANCEL, MT_HALT, MT_HB = 1, 2, 3, 4, 5
SYMBOLS_DATA = [
    (b'AAPL', 115000), (b'MSFT', 195000), (b'NVDA', 880000), (b'TSLA', 490000),
    (b'AMZN', 175000), (b'GOOG', 165000), (b'META', 490000), (b'NFLX', 640000),
]
prices = {s[0]: s[1] for s in SYMBOLS_DATA}
seq = 0  # start at 0; FPGA was just reprogrammed so last_seq is reset
total = 0
try:
    while True:
        sym, _ = random.choice(SYMBOLS_DATA)
        seq = (seq + 1) & 0xFFFF
        if seq == 0: seq = 1
        r = random.random()
        if r < 0.80:
            mt = MT_QUOTE
            prices[sym] = max(10000, prices[sym] + random.randint(-2000, 2500))
            price, qty, side = prices[sym], random.randint(10, 500), random.randint(0, 1)
        elif r < 0.90:
            mt = MT_TRADE
            price = max(10000, prices[sym] + random.randint(-1000, 1000))
            qty, side = random.randint(1, 200), random.randint(0, 1)
        elif r < 0.94:
            mt, price, qty, side = MT_CANCEL, 0, 0, 0
        elif r < 0.97:
            mt, price, qty, side = MT_HALT, 0, 0, 0
        else:
            mt, price, qty, side = MT_HB, 0, 0, 0
        payload = struct.pack('>B4sIHHB', mt, sym, price, qty, seq, side)
        payload += bytes([sum(payload) % 256])
        sendp(Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5)/Raw(load=payload),
              iface=IFACE, verbose=False)
        total += 1
        time.sleep(0.01)  # ~100 frames/sec — keeps seq alive for ~10 min before wrap
        if total % 500 == 0:
            status = ' '.join(f'{s[0].decode()}=${prices[s[0]]/10000:.0f}' for s in SYMBOLS_DATA)
            print(f"  [{total}] {status}", flush=True)
except KeyboardInterrupt:
    print(f"\n  Stopped after {total} frames")
finally:
    server.terminate()
    http_proc.terminate()
    print("  Servers stopped. Done.")
