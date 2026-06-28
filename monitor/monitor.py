"""
Vigilo — Network Threat Monitor
Detects ARP spoofing on the local network, automatically sends
corrective ARP to restore legitimate mappings, and reports the
threat to the Flask API in real time.
 
Also performs periodic network scans to discover real devices
and reports them to the dashboard for live radar display.
 
Run as root:
    sudo python3 monitor.py --interface eth0 --gateway 192.168.1.1 --api http://localhost:47823
"""
 
import time
import ipaddress
import threading
import requests
import argparse
import logging
from datetime import datetime
from scapy.all import (
    ARP, Ether, srp, sendp, sniff,
    get_if_hwaddr, get_if_addr, conf
)
 
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("vigilo")
 
# ── ARP table ──────────────────────────────────────────────────────────────────
arp_table: dict[str, str] = {}
reported: set[str] = set()
 
 
# ── Network helpers ────────────────────────────────────────────────────────────
 
def get_mac(ip: str, interface: str) -> str | None:
    """ARP request to resolve an IP to its real MAC address."""
    ans, _ = srp(
        Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=ip),
        timeout=2, iface=interface, verbose=False
    )
    return ans[0][1].hwsrc if ans else None
 
 
def get_subnet(interface: str) -> str:
    """
    Derive the subnet CIDR from the interface.
    Uses socket/fcntl (always available) instead of Scapy's
    get_if_netmask which was removed in recent Scapy versions.
    Falls back to /24 if detection fails.
    """
    import socket
    import struct
 
    try:
        import fcntl
        # SIOCGIFNETMASK — ioctl call to get interface netmask
        SIOCGIFNETMASK = 0x891b
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        netmask = socket.inet_ntoa(
            fcntl.ioctl(
                s.fileno(),
                SIOCGIFNETMASK,
                struct.pack("256s", interface[:15].encode())
            )[20:24]
        )
        s.close()
    except Exception:
        # Fallback to /24 — works for most home/office networks
        log.warning("Could not detect netmask — defaulting to /24")
        netmask = "255.255.255.0"
 
    ip      = get_if_addr(interface)
    network = ipaddress.IPv4Network(f"{ip}/{netmask}", strict=False)
    return str(network)
 
 
def get_own_ip(interface: str) -> str:
    """Return this machine's IP on the given interface."""
    return get_if_addr(interface)
 
 
def scan_network(subnet: str, interface: str) -> list[dict]:
    """
    ARP scan the entire subnet and return a list of
    discovered devices with their IP and MAC addresses.
    """
    log.info(f"Scanning subnet {subnet}...")
    ans, _ = srp(
        Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=subnet),
        timeout=5, iface=interface, verbose=False
    )
    devices = [
        {"ip": received.psrc, "mac": received.hwsrc}
        for _, received in ans
    ]
    log.info(f"Scan complete — {len(devices)} device(s) found")
    return devices
 
 
# ── API reporting ──────────────────────────────────────────────────────────────
 
def report_devices(api_url: str, devices: list[dict],
                   own_ip: str, gateway_ip: str) -> None:
    """POST discovered device list to the Flask API."""
    payload = {
        "devices":    devices,
        "own_ip":     own_ip,
        "gateway_ip": gateway_ip,
        "timestamp":  datetime.utcnow().isoformat()
    }
    try:
        requests.post(
            f"{api_url}/api/devices",
            json=payload, timeout=5
        )
        log.info(f"Device list reported — {len(devices)} device(s)")
    except requests.exceptions.ConnectionError:
        log.warning("API unreachable — device list not reported")
    except Exception as e:
        log.warning(f"Device report error: {e}")
 
 
def report_threat(api_url: str, attacker_mac: str, attacker_ip: str,
                  spoofed_ip: str, interface: str) -> None:
    """POST a threat event to the Flask API."""
    payload = {
        "attacker_mac": attacker_mac,
        "attacker_ip":  attacker_ip,
        "spoofed_ip":   spoofed_ip,
        "interface":    interface,
        "timestamp":    datetime.utcnow().isoformat(),
        "action":       "corrective_arp_broadcast",
        "status":       "neutralised"
    }
    try:
        response = requests.post(
            f"{api_url}/api/threat",
            json=payload, timeout=5
        )
        if response.status_code == 200:
            log.info(f"Threat reported — attacker: {attacker_mac}")
        else:
            log.warning(f"API returned {response.status_code}")
    except requests.exceptions.ConnectionError:
        log.warning("API unreachable — threat logged locally only")
 
 
def send_corrective_arp(target_ip: str, real_mac: str,
                        interface: str) -> None:
    """Broadcast a corrective ARP to restore legitimate mappings."""
    packet = (
        Ether(dst="ff:ff:ff:ff:ff:ff") /
        ARP(
            op=2, pdst="255.255.255.255",
            hwdst="ff:ff:ff:ff:ff:ff",
            psrc=target_ip, hwsrc=real_mac
        )
    )
    sendp(packet, iface=interface, count=5, inter=0.2, verbose=False)
    log.info(f"Corrective ARP sent: {target_ip} is at {real_mac}")
 
 
# ── Periodic device scanner ────────────────────────────────────────────────────
 
# Signal flag — set to True when network drops to exit cleanly
_stop_event = threading.Event()
 
 
def check_network_alive(interface: str) -> bool:
    """Return True if the interface still has a valid IP address."""
    try:
        ip = get_if_addr(interface)
        return ip not in ("", "0.0.0.0", None)
    except Exception:
        return False
 
 
def build_assessment(devices: list[dict], own_ip: str,
                     gateway_ip: str, subnet: str) -> dict:
    """
    Analyses the network scan and produces a plain-English assessment:
    a health score (0-100), a list of findings, and an action list.
    This is the Onboarding Assessment shown to the user on first run.
    """
    findings = []
    actions = []
    score = 100
 
    # Count devices that are not this machine and not the router
    other_devices = [
        d for d in devices
        if d["ip"] != own_ip and d["ip"] != gateway_ip
    ]
    total_devices = len(devices)
 
    # ── Finding 1: shared network (the big one) ──
    if len(other_devices) > 0:
        score -= 20
        findings.append({
            "level": "warning",
            "title": "Your network is shared with other devices",
            "detail": (
                f"Your device shares this network with {len(other_devices)} "
                f"other device(s). On a shared network, an intruder could "
                f"attempt to intercept your internet traffic, including your "
                f"login details for booking sites and email."
            ),
        })
        actions.append({
            "priority": 1,
            "text": "Set up a separate guest Wi-Fi network on your router so "
                    "visitors cannot share the same network as your business devices.",
        })
    else:
        findings.append({
            "level": "good",
            "title": "No other devices detected on your network",
            "detail": "Your device currently appears to be alone on this "
                      "network, which is the safest situation.",
        })
 
    # ── Finding 2: large network (bigger attack surface) ──
    if total_devices > 10:
        score -= 10
        findings.append({
            "level": "warning",
            "title": "Many devices are connected to your network",
            "detail": (
                f"There are {total_devices} devices on your network. The more "
                f"devices connected, the more opportunities an attacker has to "
                f"find a way in."
            ),
        })
        actions.append({
            "priority": 2,
            "text": "Review the devices on your network and disconnect any you "
                    "do not recognise.",
        })
 
    # ── Finding 3: unrecognised devices ──
    if len(other_devices) >= 3:
        score -= min(15, len(other_devices) * 3)
        findings.append({
            "level": "warning",
            "title": "Several devices could not be identified",
            "detail": (
                f"{len(other_devices)} devices on your network do not have a "
                f"recognised name. These could be guest phones and laptops, "
                f"but it is worth confirming you know what each one is."
            ),
        })
        actions.append({
            "priority": 3,
            "text": "Check the list of connected devices and make sure you "
                    "recognise each one.",
        })
 
    # ── Finding 4: gateway protection (always good once detected) ──
    if gateway_ip:
        findings.append({
            "level": "good",
            "title": "Vigilo is actively protecting your connection",
            "detail": "Vigilo has identified your router and is now watching "
                      "for any device trying to intercept your traffic. If an "
                      "attack happens, it will be blocked automatically.",
        })
 
    # Clamp the score
    score = max(0, min(100, score))
 
    # Overall status label
    if score >= 85:
        status = "good"
        summary = "Your network is in good shape. Vigilo is protecting you."
    elif score >= 60:
        status = "fair"
        summary = "Your network has a few things worth improving. See the actions below."
    else:
        status = "attention"
        summary = "Your network needs attention. Please review the actions below."
 
    return {
        "score": score,
        "status": status,
        "summary": summary,
        "findings": findings,
        "actions": sorted(actions, key=lambda a: a["priority"]),
        "device_count": total_devices,
        "subnet": subnet,
    }
 
 
def report_assessment(api_url: str, assessment: dict) -> None:
    """POST the onboarding assessment to the API."""
    try:
        requests.post(f"{api_url}/api/assessment", json=assessment, timeout=5)
        log.info(f"Assessment reported - health score: {assessment['score']}")
    except requests.exceptions.ConnectionError:
        log.warning("API unreachable - assessment not reported")
    except Exception as e:
        log.warning(f"Assessment report error: {e}")
 
 
def device_scan_loop(interface: str, gateway_ip: str,
                     api_url: str, interval: int = 30) -> None:
    """
    Background thread — scans the network every `interval` seconds
    and reports real devices to the dashboard.
    On the first scan, also builds and reports the Onboarding Assessment.
    Exits cleanly when _stop_event is set (network drop detected).
    """
    own_ip = get_own_ip(interface)
    log.info(f"Device scanner started — scanning every {interval}s")
    first_scan = True
 
    while not _stop_event.is_set():
        try:
            # Check network is still alive before scanning
            if not check_network_alive(interface):
                log.warning("Network interface lost — stopping scanner")
                _stop_event.set()
                break
 
            subnet  = get_subnet(interface)
            devices = scan_network(subnet, interface)
            report_devices(api_url, devices, own_ip, gateway_ip)
 
            # On the very first scan, build the onboarding assessment
            if first_scan:
                assessment = build_assessment(devices, own_ip, gateway_ip, subnet)
                report_assessment(api_url, assessment)
                first_scan = False
 
            # Seed ARP table with discovered devices
            for device in devices:
                if device["ip"] not in arp_table:
                    arp_table[device["ip"]] = device["mac"]
 
        except Exception as e:
            log.warning(f"Device scan error: {e}")
 
        # Sleep in small chunks so stop_event is checked frequently
        for _ in range(interval):
            if _stop_event.is_set():
                break
            time.sleep(1)
 
 
# ── ARP packet handler ─────────────────────────────────────────────────────────
 
def handle_packet(packet, interface: str, gateway_ip: str,
                  api_url: str) -> None:
    """Inspect each ARP packet for spoofing."""
    if not packet.haslayer(ARP):
        return
 
    arp = packet[ARP]
    if arp.op != 2:  # Only ARP replies
        return
 
    sender_ip  = arp.psrc
    sender_mac = arp.hwsrc
 
    # Skip own interface
    try:
        if sender_mac == get_if_hwaddr(interface):
            return
    except Exception:
        pass
 
    # First time seeing this IP — record as legitimate
    if sender_ip not in arp_table:
        arp_table[sender_ip] = sender_mac
        log.debug(f"ARP table: {sender_ip} → {sender_mac}")
        return
 
    # Check for MAC mismatch
    known_mac = arp_table[sender_ip]
    if sender_mac == known_mac:
        return
 
    # ARP spoof detected
    log.warning(
        f"ARP SPOOF DETECTED — {sender_ip} "
        f"claimed by {sender_mac} (known: {known_mac})"
    )
 
    if sender_mac in reported:
        return
    reported.add(sender_mac)
 
    real_mac = get_mac(sender_ip, interface) or known_mac
    send_corrective_arp(sender_ip, real_mac, interface)
    report_threat(
        api_url=api_url,
        attacker_mac=sender_mac,
        attacker_ip=arp.psrc,
        spoofed_ip=sender_ip,
        interface=interface
    )
 
 
# ── Entry point ────────────────────────────────────────────────────────────────
 
def resolve_interface(requested: str) -> str:
    """
    Resolve the correct network interface name.
    Works across Linux (eth0, wlo1) and Windows (GUID-based names).
    If the requested interface exists, use it. Otherwise auto-detect
    the interface that has the default route.
    """
    from scapy.all import get_if_list, conf
 
    available = get_if_list()
 
    # If a valid interface was explicitly requested, use it
    if requested and requested in available:
        return requested
 
    # Try Scapy's own idea of the default route interface
    try:
        if conf.iface and str(conf.iface) in [str(i) for i in available]:
            log.info(f"Auto-detected interface: {conf.iface}")
            return str(conf.iface)
    except Exception:
        pass
 
    # Fall back to conf.iface directly (Scapy resolves the best one)
    try:
        detected = str(conf.iface)
        log.info(f"Using Scapy default interface: {detected}")
        return detected
    except Exception:
        pass
 
    # Last resort - first non-loopback interface
    for iface in available:
        if "loopback" not in iface.lower() and "lo" != iface.lower():
            log.warning(f"Falling back to interface: {iface}")
            return iface
 
    return requested or "eth0"
 
 
def resolve_gateway(requested: str, interface: str) -> str:
    """
    Resolve the default gateway IP address.
    If one was provided, use it. Otherwise auto-detect it from the
    system routing table. Works on both Windows and Linux.
    """
    if requested:
        return requested
 
    # Try Scapy's routing table first (cross-platform)
    try:
        from scapy.all import conf
        gw = conf.route.route("0.0.0.0")[2]
        if gw and gw != "0.0.0.0":
            log.info(f"Auto-detected gateway: {gw}")
            return gw
    except Exception:
        pass
 
    # Linux fallback - parse `ip route`
    try:
        import subprocess
        out = subprocess.check_output(
            ["ip", "route"], stderr=subprocess.DEVNULL
        ).decode()
        for line in out.splitlines():
            if line.startswith("default"):
                parts = line.split()
                gw = parts[parts.index("via") + 1]
                log.info(f"Auto-detected gateway (ip route): {gw}")
                return gw
    except Exception:
        pass
 
    log.warning("Could not auto-detect gateway")
    return ""
 
 
def main():
    parser = argparse.ArgumentParser(description="Vigilo Network Monitor")
    parser.add_argument("--interface", default="")
    parser.add_argument("--gateway",   default="")
    parser.add_argument("--api",       default="http://localhost:47823")
    parser.add_argument("--scan-interval", type=int, default=30,
                        help="Seconds between network scans (default: 30)")
    args = parser.parse_args()
 
    conf.verb = 0
 
    # Resolve the network interface. On Windows the interface is not
    # named "eth0" - Scapy uses a different naming. If no interface is
    # given, or the given one does not exist, auto-detect the active one.
    args.interface = resolve_interface(args.interface)
 
    # Resolve the gateway. If not provided, auto-detect from routing table.
    args.gateway = resolve_gateway(args.gateway, args.interface)
 
    if not args.gateway:
        log.warning("No gateway available yet - waiting for network...")
        # Wait for a network to appear rather than crashing
        import time as _t
        for _ in range(60):
            if _stop_event.is_set():
                return
            _t.sleep(2)
            args.gateway = resolve_gateway("", args.interface)
            if args.gateway:
                args.interface = resolve_interface("")
                break
        if not args.gateway:
            log.error("No network detected after waiting. Exiting.")
            return
 
    log.info(f"Vigilo monitor starting on {args.interface}")
    log.info(f"Gateway : {args.gateway}")
    log.info(f"API     : {args.api}")
 
    # Resolve and seed gateway MAC
    log.info("Resolving gateway MAC address...")
    gateway_mac = get_mac(args.gateway, args.interface)
    if gateway_mac:
        arp_table[args.gateway] = gateway_mac
        log.info(f"Gateway verified: {args.gateway} -> {gateway_mac}")
    else:
        log.warning("Could not resolve gateway MAC - proceeding without seed")
 
    # Start background device scanner thread
    scanner = threading.Thread(
        target=device_scan_loop,
        args=(args.interface, args.gateway, args.api, args.scan_interval),
        daemon=True
    )
    scanner.start()
 
    log.info("Monitoring for ARP spoofing... (Ctrl+C to stop)")
 
    def stop_filter(pkt):
        """Stop sniffing if network drops or stop event is set."""
        if _stop_event.is_set():
            return True
        if not check_network_alive(args.interface):
            log.warning("Network dropped — stopping monitor")
            _stop_event.set()
            return True
        return False
 
    sniff(
        iface=args.interface,
        filter="arp",
        prn=lambda pkt: handle_packet(
            pkt, args.interface, args.gateway, args.api
        ),
        stop_filter=stop_filter,
        store=False
    )
 
    log.info("Monitor stopped — network change detected")
 
 
if __name__ == "__main__":
    main()
 