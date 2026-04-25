# ByeByeDPI macOS

A macOS Flutter client for [ByeDPI](https://github.com/hufrea/byedpi) — a local SOCKS5 proxy that bypasses Deep Packet Inspection (DPI) based internet restrictions.

This is **not** a VPN. It does not encrypt traffic or hide your IP. It runs a local proxy that manipulates TCP packets to confuse DPI middleboxes.

## Features

- 🛡️ One-click DPI bypass via animated connection orb
- 📋 8 curated presets for different regions and strategies
- ⚙️ Custom flags mode for manual `ciadpi` configuration
- 📡 Automatic macOS Wi-Fi SOCKS5 proxy configuration
- 📝 Real-time log viewer with color-coded output
- 🎨 Premium dark-mode UI with glassmorphism design

## Presets

| Preset | Strategy | Best For |
|--------|----------|----------|
| 🇷🇺 Russia (Light) | `--disorder 1 --tlsrec 1+s` | Moderate DPI |
| 🇷🇺 Russia (Aggressive) | `--fake -1 --ttl 8` | Aggressive SNI blocking |
| 🇷🇺 Russia (Combined) | `--split 1+s --disorder 3+s --oob 1+s` | Maximum coverage |
| 🌍 Generic (Split) | `--split 3 --split 7` | Simple DPI |
| 🌍 Generic (Disorder) | `--disorder 1` | Stateful DPI |
| 🌍 Generic (TLS Record) | `--tlsrec 1+s` | TLS-aware DPI |
| 🌍 Generic (OOB) | `--oob 1+s` | DPI reassembly bypass |
| 🇹🇷 Turkey | `--disorder 1 --fake -1 --ttl 6` | Turkish ISPs |

## macOS Compatibility

Most `byedpi` features work natively on macOS. The following are **not supported** (Linux-only):
- `--md5sig` — TCP MD5 Signature
- `--drop-sack` — SACK packet filtering
- `--transparent` — Transparent proxy mode

Fake packet injection (`--fake`) is supported via a custom macOS `send_fake()` implementation using TTL-based packet expiration.

## Building

### Prerequisites
- Flutter SDK (3.11+)
- Xcode command line tools
- macOS 10.15+

### Steps

1. **Clone with submodules:**
   ```bash
   git clone --recurse-submodules <repo-url>
   cd ciadpi
   ```

2. **Compile the byedpi binary:**
   ```bash
   cd ByeByeDPI/app/src/main/cpp/byedpi
   make
   cp ciadpi ../../../../../../assets/ciadpi_mac
   cd ../../../../../../
   ```

3. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

4. **Run:**
   ```bash
   flutter run -d macos
   ```

## How It Works

1. The app extracts the bundled `ciadpi_mac` binary to `~/Library/Application Support/`
2. Launches it as a background process with the selected preset flags
3. Configures macOS Wi-Fi network interface to use `127.0.0.1:1080` as SOCKS5 proxy
4. All system traffic is routed through the local proxy, which applies DPI bypass techniques
5. On disconnect, the proxy is killed and system proxy settings are restored

## Architecture

```
Flutter UI ─► ProxyManager ─► ciadpi_mac (SOCKS5 proxy)
                  │                    │
                  │                    ├── TCP split/disorder
                  │                    ├── Fake packet injection
                  │                    ├── TLS record fragmentation
                  │                    └── OOB data injection
                  │
                  └── networksetup (macOS system proxy)
```

## Credits

- [ByeDPI](https://github.com/hufrea/byedpi) by hufrea — Core C proxy engine
- [ByeByeDPI](https://github.com/romanvht/ByeByeDPI) by romanvht — Android client (inspiration)

## License

The `byedpi` core is licensed under MIT. See [ByeByeDPI/LICENSE](ByeByeDPI/LICENSE) for details.
