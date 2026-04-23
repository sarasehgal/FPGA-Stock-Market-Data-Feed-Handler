"""send_multi.py — Send all 8 symbols with all message types and random-walk prices."""
import struct, time, random
from scapy.all import Ether, Raw, sendp

IFACE = r'\Device\NPF_{696EC36D-E991-4A75-8002-E3C10A7430A6}'
SRC = 'd4:a2:cd:1c:a9:0b'

# msg_type constants
MT_QUOTE  = 0x01
MT_TRADE  = 0x02
MT_CANCEL = 0x03
MT_HALT   = 0x04
MT_HB     = 0x05

SYMBOLS = [
    (b'AAPL', 115000, 120000),
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
halted = set()

print(f'Sending all 8 symbols, all msg types, 60s (seq start={seq})...')
end = time.time() + 60
total = 0
while time.time() < end:
    sym, start, thresh = random.choice(SYMBOLS)
    seq = (seq + 1) & 0xFFFF
    if seq == 0: seq = 1

    # Message type distribution: 80% quote, 10% trade, 4% cancel, 3% halt, 3% heartbeat
    r = random.random()
    if r < 0.80:
        mt = MT_QUOTE
        # Random walk with slight upward bias
        delta = random.randint(-2000, 2500)
        prices[sym] = max(10000, prices[sym] + delta)
        price = prices[sym]
        qty = random.randint(10, 500)
        side = random.randint(0, 1)
    elif r < 0.90:
        mt = MT_TRADE
        price = prices[sym] + random.randint(-1000, 1000)
        price = max(10000, price)
        qty = random.randint(1, 200)
        side = random.randint(0, 1)
    elif r < 0.94:
        mt = MT_CANCEL
        price, qty, side = 0, 0, 0
    elif r < 0.97:
        mt = MT_HALT
        halted.add(sym)
        price, qty, side = 0, 0, 0
    else:
        mt = MT_HB
        price, qty, side = 0, 0, 0

    payload = struct.pack('>B4sIHHB', mt, sym, price, qty, seq, side)
    payload += bytes([sum(payload) % 256])
    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src=SRC, type=0x88B5) / Raw(load=payload)
    sendp(pkt, iface=IFACE, verbose=False)
    total += 1
    if total % 500 == 0:
        status = ' '.join(f'{s[0].decode()}=${prices[s[0]]/10000:.0f}' for s in SYMBOLS)
        h = ','.join(s.decode() for s in halted) if halted else 'none'
        print(f'  [{total}] {status}  halted={h}')

print(f'Done. Sent {total} frames.')
