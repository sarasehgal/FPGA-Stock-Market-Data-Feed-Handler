#!/usr/bin/env python3
"""
dashboard.py - Live trading dashboard for the FPGA stock feed pipeline.

Sends a continuous stream of market data (quotes, trades, cancels, halts,
heartbeats) to the FPGA and displays real-time charts of:
  - Price history per symbol (line chart)
  - Trigger events (marked on chart)
  - Bid/Ask spread
  - Message & trigger counts
  - Round-trip latency

Supports 8 symbols: AAPL MSFT NVDA TSLA AMZN GOOG META NFLX

Usage:
  pip install scapy matplotlib
  python dashboard.py --iface "Ethernet"
  python dashboard.py --iface "Ethernet" --no-fpga   (demo mode, no hardware)
"""

import struct, time, sys, argparse, random, threading, os
from collections import defaultdict, deque
from datetime import datetime

try:
    import matplotlib
    matplotlib.use('TkAgg')
    import matplotlib.pyplot as plt
    from matplotlib.animation import FuncAnimation
    HAS_MPL = True
except ImportError:
    HAS_MPL = False

# ---------------------------------------------------------------------------
#  Protocol
# ---------------------------------------------------------------------------
ETHERTYPE_RX = 0x88B5
ETHERTYPE_TX = 0x0800
FPGA_SRC_MAC = "00:11:22:33:44:55"
DST_MAC      = "ff:ff:ff:ff:ff:ff"

MT_QUOTE  = 0x01
MT_TRADE  = 0x02
MT_CANCEL = 0x03
MT_HALT   = 0x04
MT_HB     = 0x05
MT_RESP   = 0xA1

# ---------------------------------------------------------------------------
#  Symbol universe (must match symbol_lut.v / trigger_engine.v)
# ---------------------------------------------------------------------------
SYMBOLS = {
    0:  ("AAPL", 120000),   1:  ("MSFT", 200000),   2:  ("NVDA", 900000),
    3:  ("TSLA", 500000),   4:  ("AMZN", 180000),   5:  ("GOOG", 170000),
    6:  ("META", 500000),   7:  ("NFLX", 650000),
}

# Starting prices (will random-walk)
START_PRICES = {
    "AAPL": 115000, "MSFT": 190000, "NVDA": 880000, "TSLA": 490000,
    "AMZN": 175000, "GOOG": 165000, "META": 490000, "NFLX": 640000,
}

SYM_NAMES = [SYMBOLS[i][0] for i in range(8)]
SYM_THRESHOLDS = {SYMBOLS[i][0]: SYMBOLS[i][1] for i in range(15)}

# ---------------------------------------------------------------------------
#  Frame building
# ---------------------------------------------------------------------------
def build_payload(msg_type, symbol_bytes, price, qty, seq, side):
    sym = symbol_bytes[:4].ljust(4, b'\x00')
    payload = struct.pack(">B4sIHHB", msg_type, sym, price, qty, seq, side)
    cksum = sum(payload) & 0xFF
    return payload + bytes([cksum])

def parse_response(raw):
    if len(raw) < 15:
        return None
    return {
        "type":   raw[0],
        "symbol": raw[1:5].decode("ascii", errors="replace"),
        "price":  struct.unpack(">I", raw[5:9])[0],
        "seq":    struct.unpack(">H", raw[11:13])[0],
        "reason": raw[13],
        "cksum_ok": (sum(raw[:14]) & 0xFF) == raw[14],
    }

# ---------------------------------------------------------------------------
#  Market data generator (random walk)
# ---------------------------------------------------------------------------
class MarketSimulator:
    def __init__(self):
        self.prices = dict(START_PRICES)
        self.seq = 0
        self.halted = set()

    def next_frame(self):
        self.seq += 1
        # 85% quote, 8% trade, 3% cancel, 2% halt, 1% HB, 1% unknown
        r = random.random()
        sym_name = random.choice(SYM_NAMES)
        sym_bytes = sym_name.encode("ascii")
        side = random.randint(0, 1)

        if r < 0.85:
            # Quote: random-walk the price
            delta = random.randint(-3000, 3500)  # slight upward bias
            self.prices[sym_name] = max(10000, self.prices[sym_name] + delta)
            price = self.prices[sym_name]
            qty = random.randint(10, 500)
            return MT_QUOTE, sym_bytes, price, qty, self.seq, side, sym_name

        elif r < 0.93:
            # Trade
            price = self.prices[sym_name] + random.randint(-1000, 1000)
            price = max(10000, price)
            qty = random.randint(1, 100)
            return MT_TRADE, sym_bytes, price, qty, self.seq, side, sym_name

        elif r < 0.96:
            # Cancel
            return MT_CANCEL, sym_bytes, 0, 0, self.seq, 0, sym_name

        elif r < 0.98:
            # Halt (pick a random symbol)
            self.halted.add(sym_name)
            return MT_HALT, sym_bytes, 0, 0, self.seq, 0, sym_name

        elif r < 0.99:
            # Heartbeat
            return MT_HB, sym_bytes, 0, 0, self.seq, 0, sym_name

        else:
            # Unknown
            return 0xBB, sym_bytes, random.randint(0, 999999), 1, self.seq, 0, sym_name

# ---------------------------------------------------------------------------
#  Dashboard state
# ---------------------------------------------------------------------------
class DashboardState:
    def __init__(self):
        self.lock = threading.Lock()
        self.price_history = defaultdict(lambda: deque(maxlen=200))
        self.time_axis     = defaultdict(lambda: deque(maxlen=200))
        self.triggers      = []          # (time, symbol, price, reason)
        self.msg_count     = 0
        self.trig_count    = 0
        self.latencies     = deque(maxlen=100)
        self.last_prices   = dict(START_PRICES)
        self.halted        = set()
        self.log_lines     = deque(maxlen=30)
        self.start_time    = time.time()

    def add_price(self, sym, price):
        with self.lock:
            t = time.time() - self.start_time
            self.price_history[sym].append(price / 10000.0)  # convert to dollars
            self.time_axis[sym].append(t)
            self.last_prices[sym] = price
            self.msg_count += 1

    def add_trigger(self, sym, price, reason, latency_ms):
        with self.lock:
            t = time.time() - self.start_time
            self.triggers.append((t, sym, price / 10000.0, reason))
            self.trig_count += 1
            self.latencies.append(latency_ms)
            reason_s = "BID" if reason == 1 else "ASK"
            self.log_lines.append(
                f"[{datetime.now().strftime('%H:%M:%S')}] TRIGGER {sym.strip()} "
                f"${price/10000:.2f} {reason_s} lat={latency_ms:.1f}ms")

    def add_log(self, msg):
        with self.lock:
            self.log_lines.append(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

state = DashboardState()

# ---------------------------------------------------------------------------
#  Network I/O (runs in background thread)
# ---------------------------------------------------------------------------
def network_loop(iface, no_fpga=False):
    sim = MarketSimulator()

    if not no_fpga:
        from scapy.all import Ether, Raw, sendp, sniff, get_if_hwaddr
        try:
            src_mac = get_if_hwaddr(iface)
        except Exception:
            src_mac = "de:ad:be:ef:ca:fe"

        # Start sniffer in background
        def rx_handler(pkt):
            if not pkt.haslayer(Ether):
                return
            eth = pkt[Ether]
            if eth.src.lower() != FPGA_SRC_MAC.lower():
                return
            if eth.type != ETHERTYPE_TX:
                return
            raw = bytes(pkt[Raw].load) if pkt.haslayer(Raw) else b""
            resp = parse_response(raw)
            if resp and resp["type"] == MT_RESP:
                seq = resp["seq"]
                lat = send_times.get(seq, time.perf_counter())
                latency_ms = (time.perf_counter() - lat) * 1000
                state.add_trigger(resp["symbol"], resp["price"],
                                  resp["reason"], latency_ms)

        send_times = {}
        sniffer = threading.Thread(target=lambda: sniff(
            iface=iface, prn=rx_handler, store=False), daemon=True)
        sniffer.start()
        state.add_log(f"Connected to {iface}")

    state.add_log(f"Streaming 15 symbols {'(demo mode)' if no_fpga else 'to FPGA'}")

    while True:
        mt, sym_b, price, qty, seq, side, sym_name = sim.next_frame()

        # Update dashboard state for all message types with prices
        if mt in (MT_QUOTE, MT_TRADE) and price > 0:
            state.add_price(sym_name, price)

        if mt == MT_HALT:
            state.halted.add(sym_name)
            state.add_log(f"HALT {sym_name.strip()}")

        if not no_fpga:
            payload = build_payload(mt, sym_b, price, qty, seq, side)
            pkt = Ether(dst=DST_MAC, src=src_mac, type=ETHERTYPE_RX) / Raw(load=payload)
            send_times[seq] = time.perf_counter()
            try:
                sendp(pkt, iface=iface, verbose=False)
            except Exception as e:
                state.add_log(f"Send error: {e}")
        else:
            # Demo mode: simulate triggers locally
            state.msg_count += 1
            threshold = SYM_THRESHOLDS.get(sym_name, 0xFFFFFFFF)
            if mt in (MT_QUOTE, MT_TRADE) and price >= threshold:
                if sym_name not in sim.halted:
                    lat = random.uniform(0.05, 0.3)
                    reason = 2 if side else 1
                    state.add_trigger(sym_name, price, reason, lat)

        time.sleep(random.uniform(0.02, 0.08))  # 15-50 msgs/sec

# ---------------------------------------------------------------------------
#  Matplotlib live dashboard
# ---------------------------------------------------------------------------
def run_dashboard():
    if not HAS_MPL:
        print("ERROR: matplotlib not installed. Run: pip install matplotlib")
        sys.exit(1)

    fig = plt.figure(figsize=(16, 9), facecolor='#1a1a2e')
    fig.canvas.manager.set_window_title('FPGA Stock Feed - Live Dashboard')

    # Layout: 2x2 grid
    ax_prices  = fig.add_subplot(2, 2, 1)  # price chart
    ax_triggers = fig.add_subplot(2, 2, 2)  # trigger log
    ax_stats   = fig.add_subplot(2, 2, 3)  # latency + stats
    ax_spread  = fig.add_subplot(2, 2, 4)  # current prices bar chart

    colors = plt.cm.tab20(range(15))
    dark_bg = '#16213e'

    for ax in [ax_prices, ax_triggers, ax_stats, ax_spread]:
        ax.set_facecolor(dark_bg)
        ax.tick_params(colors='white', labelsize=8)
        for spine in ax.spines.values():
            spine.set_color('#555')

    def update(frame_num):
        with state.lock:
            # --- Price chart ---
            ax_prices.clear()
            ax_prices.set_facecolor(dark_bg)
            ax_prices.set_title('Live Prices ($/share)', color='white', fontsize=11)
            ax_prices.set_xlabel('Time (s)', color='#aaa', fontsize=8)
            ax_prices.set_ylabel('Price ($)', color='#aaa', fontsize=8)

            shown = 0
            for i, sym in enumerate(SYM_NAMES):
                if sym in state.price_history and len(state.price_history[sym]) > 1:
                    ax_prices.plot(list(state.time_axis[sym]),
                                  list(state.price_history[sym]),
                                  color=colors[i], linewidth=1.2,
                                  label=sym.strip(), alpha=0.9)
                    shown += 1
            if shown > 0:
                ax_prices.legend(loc='upper left', fontsize=6, ncol=3,
                                 facecolor='#1a1a2e', edgecolor='#555',
                                 labelcolor='white')

            # Mark triggers on price chart
            for t, sym, price, reason in state.triggers[-20:]:
                ax_prices.axvline(x=t, color='red', alpha=0.3, linewidth=0.5)

            ax_prices.tick_params(colors='white', labelsize=8)

            # --- Trigger log ---
            ax_triggers.clear()
            ax_triggers.set_facecolor(dark_bg)
            ax_triggers.set_title(f'Trigger Alerts ({state.trig_count} total)',
                                  color='#ff6b6b', fontsize=11)
            ax_triggers.axis('off')

            log_text = '\n'.join(list(state.log_lines)[-15:])
            ax_triggers.text(0.02, 0.98, log_text, transform=ax_triggers.transAxes,
                            fontsize=8, color='#00ff88', family='monospace',
                            verticalalignment='top')

            # --- Stats / Latency ---
            ax_stats.clear()
            ax_stats.set_facecolor(dark_bg)
            ax_stats.set_title('System Stats', color='white', fontsize=11)
            ax_stats.axis('off')

            avg_lat = (sum(state.latencies) / len(state.latencies)
                       if state.latencies else 0)
            min_lat = min(state.latencies) if state.latencies else 0
            max_lat = max(state.latencies) if state.latencies else 0

            elapsed = time.time() - state.start_time
            rate = state.msg_count / max(elapsed, 0.1)

            stats = (
                f"Messages sent    : {state.msg_count:,}\n"
                f"Triggers fired   : {state.trig_count}\n"
                f"Message rate     : {rate:.1f} msg/s\n"
                f"Elapsed time     : {elapsed:.0f}s\n"
                f"\n"
                f"Latency (ms):\n"
                f"  Min  : {min_lat:.2f}\n"
                f"  Avg  : {avg_lat:.2f}\n"
                f"  Max  : {max_lat:.2f}\n"
                f"\n"
                f"Halted symbols   : {', '.join(s.strip() for s in state.halted) or 'none'}\n"
                f"Active symbols   : {len(state.price_history)}/8"
            )
            ax_stats.text(0.05, 0.95, stats, transform=ax_stats.transAxes,
                         fontsize=9, color='white', family='monospace',
                         verticalalignment='top')

            # --- Current prices bar chart ---
            ax_spread.clear()
            ax_spread.set_facecolor(dark_bg)
            ax_spread.set_title('Current Prices vs Thresholds', color='white', fontsize=11)

            syms_with_data = [(s, state.last_prices.get(s, 0))
                              for s in SYM_NAMES if s in state.last_prices]
            if syms_with_data:
                names = [s.strip() for s, _ in syms_with_data]
                prices_d = [p / 10000.0 for _, p in syms_with_data]
                thresholds_d = [SYM_THRESHOLDS.get(s, 0) / 10000.0
                                for s, _ in syms_with_data]

                x = range(len(names))
                bar_colors = ['#00ff88' if p >= t else '#4a90d9'
                              for p, t in zip(prices_d, thresholds_d)]
                ax_spread.barh(names, prices_d, color=bar_colors, alpha=0.8, height=0.6)

                # Threshold markers
                for i, t in enumerate(thresholds_d):
                    ax_spread.plot(t, i, '|', color='red', markersize=15, markeredgewidth=2)

                ax_spread.tick_params(colors='white', labelsize=7)
                ax_spread.set_xlabel('Price ($)', color='#aaa', fontsize=8)

        fig.tight_layout(pad=1.5)
        return []

    ani = FuncAnimation(fig, update, interval=500, blit=False, cache_frame_data=False)
    plt.show()

# ---------------------------------------------------------------------------
#  Terminal-only dashboard (no matplotlib)
# ---------------------------------------------------------------------------
def run_terminal_dashboard():
    while True:
        os.system('cls' if os.name == 'nt' else 'clear')
        with state.lock:
            elapsed = time.time() - state.start_time
            rate = state.msg_count / max(elapsed, 0.1)

            print("=" * 70)
            print("  FPGA STOCK FEED - LIVE DASHBOARD")
            print("=" * 70)
            print(f"  Messages: {state.msg_count:,}  |  Triggers: {state.trig_count}"
                  f"  |  Rate: {rate:.0f} msg/s  |  Time: {elapsed:.0f}s")
            print("-" * 70)

            # Current prices
            print("  SYMBOL  PRICE      THRESHOLD  STATUS")
            print("  " + "-" * 50)
            for sym in SYM_NAMES:
                p = state.last_prices.get(sym, 0)
                t = SYM_THRESHOLDS.get(sym, 0)
                price_s = f"${p/10000:>8.2f}"
                thresh_s = f"${t/10000:>8.2f}"
                if sym in state.halted:
                    status = "HALTED"
                elif p >= t:
                    status = ">>> ALERT <<<"
                else:
                    status = ""
                print(f"  {sym}  {price_s}  {thresh_s}  {status}")

            print("-" * 70)
            print("  Recent triggers:")
            for line in list(state.log_lines)[-8:]:
                print(f"  {line}")

        time.sleep(1)

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="FPGA Stock Feed Live Dashboard")
    parser.add_argument("--iface", default=None, help="Network interface")
    parser.add_argument("--no-fpga", action="store_true",
                        help="Demo mode - simulate triggers locally")
    parser.add_argument("--terminal", action="store_true",
                        help="Use terminal display instead of matplotlib")
    parser.add_argument("--list-ifaces", action="store_true")
    args = parser.parse_args()

    if args.list_ifaces:
        from scapy.all import get_if_list
        for i in get_if_list():
            print(f"  {i}")
        sys.exit(0)

    if not args.no_fpga and args.iface is None:
        print("Specify --iface <name> or use --no-fpga for demo mode")
        sys.exit(1)

    # Start network thread
    net_thread = threading.Thread(
        target=network_loop, args=(args.iface, args.no_fpga), daemon=True)
    net_thread.start()

    # Run dashboard
    if args.terminal or not HAS_MPL:
        run_terminal_dashboard()
    else:
        run_dashboard()

if __name__ == "__main__":
    main()
