"""send_multi.py — Send all 8 symbols with random-walk prices near their thresholds."""
import struct, time, random
from scapy.all import Ether, Raw, sendp

IFACE = r'\Device\NPF_{696EC36D-E991-4A75-8002-E3C10A7430A6}'
SRC = 'd4:a2:cd:1c:a9:0b'

SYMBOLS = [
    (b'AAPL', 115000, 120000),   # start, threshold
    (b'MSFT', 195000, 200000),
    (b'NVDA', 880000, 900000),
    (b'TSLA', 490000, 500000),
    (b'AMZN', 175000, 180000),
    (b'GOOG', 165000, 170000),
    (b'META', 490000, 500000),
    (b'NFLX', 640000, 650000),
]

prices = {s[0]: s[1] for s in SYMBOLS}
seq = int(time.time()) & 0xFFFF

print(f'Sending all 8 symbols for 60s (seq start={seq})...')
end = time.time() + 60
total = 0
while time.time() < end:
    sym, start, thresh = random.choice(SYMBOLS)
    # Random walk with slight upward bias so symbols cross thresholds
    delta = random.randint(-2000, 2500)
    prices[sym] = max(10000, prices[sym] + delta)
    price = prices[sym]
    qty = random.randint(10, 500)
    side = random.randint(0, 1)
    seq = (seq + 1) & 0xFFFF
    if seq == 0: seq = 1

    payload = struct.pack('>B4sIHHB', 1, sym, price, qty, seq, side)
    payload += bytes([sum(payload) % 256])
    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src=SRC, type=0x88B5) / Raw(load=payload)
    sendp(pkt, iface=IFACE, verbose=False)
    total += 1
    if total % 500 == 0:
        status = ' '.join(f'{s[0].decode()}=${prices[s[0]]/10000:.0f}' for s in SYMBOLS)
        print(f'  [{total}] {status}')

print(f'Done. Sent {total} frames.')
