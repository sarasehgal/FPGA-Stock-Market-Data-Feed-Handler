#!/usr/bin/env python3
"""
send_frames.py - Send test frames to the FPGA and verify responses.

Two modes:
  --test     : Send the original 8 verification frames, check responses (default)
  --stream N : Continuously stream N random frames across all 15 symbols

Usage:
  python send_frames.py --iface "Ethernet" --test
  python send_frames.py --iface "Ethernet" --stream 100
  python send_frames.py --dry-run --test
"""

import struct, time, sys, argparse, random
from collections import namedtuple

try:
    from scapy.all import Ether, Raw, sendp, sniff, get_if_list, get_if_hwaddr
except ImportError:
    print("ERROR: scapy not installed.  Run:  pip install scapy")
    sys.exit(1)

ETHERTYPE_RX = 0x88B5
ETHERTYPE_TX = 0x0800
FPGA_SRC_MAC = "00:11:22:33:44:55"
DST_MAC      = "ff:ff:ff:ff:ff:ff"
MT_QUOTE  = 0x01; MT_TRADE = 0x02; MT_CANCEL = 0x03
MT_HALT   = 0x04; MT_HB    = 0x05; MT_RESP   = 0xA1

# All 8 symbols (must match symbol_lut.v)
ALL_SYMBOLS = [
    b"AAPL", b"MSFT", b"NVDA", b"TSLA", b"AMZN", b"GOOG", b"META", b"NFLX",
]

Frame = namedtuple("Frame", "name msg_type symbol price qty seq side expect_trigger")

# Original 8 verification frames
TEST_FRAMES = [
    Frame("Quote AAPL bid",      MT_QUOTE,  b"AAPL", 123456,  100, 42, 0, True ),
    Frame("Trade MSFT ask",      MT_TRADE,  b"MSFT", 223344,  250, 43, 1, True ),
    Frame("Cancel AAPL bid",     MT_CANCEL, b"AAPL",      0,    0, 44, 0, False),
    Frame("Halt NVDA",           MT_HALT,   b"NVDA",      0,    0, 45, 0, False),
    Frame("Quote NVDA (halted)", MT_QUOTE,  b"NVDA", 998877,   75, 46, 0, False),
    Frame("Heartbeat",           MT_HB,     b"AAPL",      0,    0, 47, 0, False),
    Frame("Unknown 0xAB",        0xAB,      b"AAPL", 999999,    1, 48, 0, False),
    Frame("Quote TSLA bid",      MT_QUOTE,  b"TSLA", 555555,   10, 49, 0, True ),
]

def build_payload(msg_type, symbol, price, qty, seq, side):
    sym = symbol[:4].ljust(4, b'\x00')
    payload = struct.pack(">B4sIHHB", msg_type, sym, price, qty, seq, side)
    return payload + bytes([sum(payload) & 0xFF])

def parse_response(raw):
    if len(raw) < 15: return None
    return {
        "type": raw[0], "symbol": raw[1:5].decode("ascii", errors="replace"),
        "price": struct.unpack(">I", raw[5:9])[0],
        "seq": struct.unpack(">H", raw[11:13])[0], "reason": raw[13],
        "cksum_ok": (sum(raw[:14]) & 0xFF) == raw[14],
    }

def run_test(iface, src_mac, dry_run):
    """Send 8 verification frames and check 3 trigger responses."""
    packets = []
    for f in TEST_FRAMES:
        payload = build_payload(f.msg_type, f.symbol, f.price, f.qty, f.seq, f.side)
        pkt = Ether(dst=DST_MAC, src=src_mac, type=ETHERTYPE_RX) / Raw(load=payload)
        packets.append((f, pkt, payload))

    if dry_run:
        print("-- DRY RUN: 8 test frame payloads --")
        for f, _, payload in packets:
            trig = " [TRIGGER]" if f.expect_trigger else ""
            print(f"  seq={f.seq:3d} {f.name:25s} {payload.hex()}{trig}")
        return

    print("-- Sending 8 test frames --\n")
    send_times = {}
    for f, pkt, _ in packets:
        trig = " [EXPECT TRIGGER]" if f.expect_trigger else ""
        print(f"  [{f.seq:3d}] {f.name:25s}  type=0x{f.msg_type:02X}  "
              f"price={f.price:>7d}{trig}")
        send_times[f.seq] = time.perf_counter()
        sendp(pkt, iface=iface, verbose=False)
        time.sleep(0.05)

    print(f"\n-- Listening for responses (3 seconds) --\n")
    captured = sniff(iface=iface, timeout=3,
                     lfilter=lambda p: (p.haslayer(Ether)
                         and p[Ether].src.lower() == FPGA_SRC_MAC
                         and p[Ether].type == ETHERTYPE_TX))

    print(f"  Captured {len(captured)} response(s)\n")
    reason_map = {1: "BID", 2: "ASK"}

    for i, pkt in enumerate(captured):
        raw = bytes(pkt[Raw].load) if pkt.haslayer(Raw) else b""
        r = parse_response(raw)
        if not r: continue
        lat = (time.perf_counter() - send_times.get(r["seq"], time.perf_counter())) * 1000
        print(f"  Response {i}: {r['symbol'].strip():4s}  "
              f"${r['price']/10000:.2f}  reason={reason_map.get(r['reason'],'?')}  "
              f"seq={r['seq']}  ck={'OK' if r['cksum_ok'] else 'FAIL'}  "
              f"lat={lat:.1f}ms")

    expected = [
        {"symbol": "AAPL", "price": 123456, "seq": 42, "reason": 1},
        {"symbol": "MSFT", "price": 223344, "seq": 43, "reason": 2},
        {"symbol": "TSLA", "price": 555555, "seq": 49, "reason": 1},
    ]
    ok = len(captured) == 3
    if ok:
        for pkt, exp in zip(captured, expected):
            raw = bytes(pkt[Raw].load) if pkt.haslayer(Raw) else b""
            r = parse_response(raw)
            if not r or r["symbol"].strip() != exp["symbol"] or r["price"] != exp["price"]:
                ok = False
    print(f"\n  {'PASS' if ok else 'FAIL'}: {len(captured)}/3 responses "
          f"{'verified' if ok else '(check above)'}")


def run_stream(iface, src_mac, count):
    """Stream N random frames across all 8 symbols."""
    prices = {s.decode(): p for s, p in zip(ALL_SYMBOLS, [
        115000,190000,880000,490000,175000,165000,490000,640000])}

    print(f"-- Streaming {count} frames across 15 symbols --\n")
    send_times = {}
    responses = []

    # Start sniffer
    import threading
    def rx_handler(pkt):
        if not pkt.haslayer(Ether): return
        if pkt[Ether].src.lower() != FPGA_SRC_MAC: return
        if pkt[Ether].type != ETHERTYPE_TX: return
        raw = bytes(pkt[Raw].load) if pkt.haslayer(Raw) else b""
        r = parse_response(raw)
        if r and r["type"] == MT_RESP:
            lat = (time.perf_counter() - send_times.get(r["seq"], time.perf_counter()))*1000
            responses.append((r, lat))
            reason_s = "BID" if r["reason"] == 1 else "ASK"
            print(f"  >>> TRIGGER {r['symbol'].strip():4s} ${r['price']/10000:.2f} "
                  f"{reason_s} seq={r['seq']} lat={lat:.1f}ms")

    sniffer = threading.Thread(target=lambda: sniff(
        iface=iface, prn=rx_handler, store=False, timeout=count*0.1+5), daemon=True)
    sniffer.start()

    for seq in range(1, count + 1):
        sym_b = random.choice(ALL_SYMBOLS)
        sym_s = sym_b.decode()

        r = random.random()
        if r < 0.80:
            mt, side = MT_QUOTE, random.randint(0, 1)
            prices[sym_s] = max(10000, prices[sym_s] + random.randint(-3000, 3500))
            price = prices[sym_s]
            qty = random.randint(10, 500)
        elif r < 0.90:
            mt, side = MT_TRADE, random.randint(0, 1)
            price = max(10000, prices[sym_s] + random.randint(-1000, 1000))
            qty = random.randint(1, 100)
        elif r < 0.95:
            mt, side, price, qty = MT_CANCEL, 0, 0, 0
        elif r < 0.98:
            mt, side, price, qty = MT_HB, 0, 0, 0
        else:
            mt, side, price, qty = 0xBB, 0, 0, 0

        payload = build_payload(mt, sym_b, price, qty, seq, side)
        pkt = Ether(dst=DST_MAC, src=src_mac, type=ETHERTYPE_RX) / Raw(load=payload)
        send_times[seq] = time.perf_counter()
        sendp(pkt, iface=iface, verbose=False)
        time.sleep(random.uniform(0.02, 0.06))

    time.sleep(2)  # wait for last responses
    print(f"\n-- Summary --")
    print(f"  Sent: {count}  Triggers: {len(responses)}")
    if responses:
        lats = [lat for _, lat in responses]
        print(f"  Latency: min={min(lats):.1f}ms avg={sum(lats)/len(lats):.1f}ms "
              f"max={max(lats):.1f}ms")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iface", default=r'\Device\NPF_{696EC36D-E991-4A75-8002-E3C10A7430A6}')  # Realtek PCIe GbE → FPGA PHY
    parser.add_argument("--list-ifaces", action="store_true")
    parser.add_argument("--src-mac", default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--test", action="store_true", help="Run 8-frame verification")
    parser.add_argument("--stream", type=int, metavar="N",
                        help="Stream N random frames continuously")
    args = parser.parse_args()

    if args.list_ifaces:
        for i in get_if_list(): print(f"  {i}")
        sys.exit(0)

    if not args.dry_run and args.iface is None:
        print("Specify --iface.  Use --list-ifaces to see options.")
        sys.exit(1)

    src_mac = args.src_mac
    if not src_mac and args.iface:
        try: src_mac = get_if_hwaddr(args.iface)
        except: src_mac = "de:ad:be:ef:ca:fe"

    if args.stream:
        run_stream(args.iface, src_mac, args.stream)
    else:
        run_test(args.iface, src_mac, args.dry_run)

if __name__ == "__main__":
    main()
