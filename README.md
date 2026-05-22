# ByeByeDPI

A cross-platform Flutter client for [ByeDPI](https://github.com/hufrea/byedpi) — a local SOCKS5 proxy that bypasses Deep Packet Inspection (DPI) based internet restrictions.

**Supported platforms:** macOS, Windows

This is **not** a VPN. It does not encrypt traffic or hide your IP. It runs a local proxy that manipulates TCP packets to confuse DPI middleboxes.

## Features

- 🛡️ One-click DPI bypass via animated connection orb
- 📋 8 curated presets for different regions and strategies
- ⚙️ Custom flags mode for manual `ciadpi` configuration
- 📡 Automatic system SOCKS5 proxy configuration (macOS Wi-Fi / Windows registry)
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

## Platform Compatibility

### macOS
Most `byedpi` features work natively. The following are **not supported** (Linux-only):
- `--md5sig` — TCP MD5 Signature
- `--drop-sack` — SACK packet filtering
- `--transparent` — Transparent proxy mode

Fake packet injection (`--fake`) is supported via a custom macOS `send_fake()` implementation using TTL-based packet expiration.

### Windows
All `byedpi` features work natively, including:
- `--fake` — via `TransmitFile` API
- `--md5sig`, `--drop-sack` — fully supported

Only `--transparent` (Linux TPROXY) is not available.

## Building

### Prerequisites
- Flutter SDK (3.11+)
- Platform-specific tools:
  - **macOS:** Xcode command line tools
  - **Windows:** Visual Studio 2022 with C++ desktop workload, plus MSYS2/MinGW for compiling ciadpi

### macOS

1. **Clone with submodules:**
   ```bash
   git clone <repo-url>
   cd ciadpi
   ```

2. **Compile the byedpi binary:**
   ```bash
   cd ByeByeDPI/app/src/main/cpp/byedpi
   make
   cp ciadpi ../../../../../../assets/ciadpi_mac
   cd ../../../../../../
   ```

3. **Run:**
   ```bash
   flutter pub get
   flutter run -d macos
   ```

### Windows

1. **Clone with submodules:**
   ```bash
   git clone --recurse-submodules <repo-url>
   cd ciadpi
   ```

2. **Compile the byedpi binary** (in MSYS2 MinGW64 terminal):
   ```bash
   cd ByeByeDPI/app/src/main/cpp/byedpi
   make windows
   cp ciadpi.exe ../../../../../../assets/ciadpi.exe
   cd ../../../../../../
   ```

3. **Run:**
   ```bash
   flutter pub get
   flutter run -d windows
   ```

### Building Release

```bash
# macOS
flutter build macos --release
# Output: build/macos/Build/Products/Release/ciadpi.app

# Windows
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

## How It Works

1. The app extracts the bundled binary (`ciadpi_mac` or `ciadpi.exe`) to the app's data directory
2. Launches it as a background process with the selected preset flags
3. Configures system proxy:
   - **macOS:** Wi-Fi SOCKS proxy via `networksetup`
   - **Windows:** Internet Settings registry via `reg.exe`
4. All traffic is routed through the local proxy, which applies DPI bypass techniques
5. On disconnect, the proxy is killed and system settings are restored

## Architecture

```
Flutter UI ─► ProxyManager ─► ciadpi binary (SOCKS5 proxy)
                  │                    │
                  │                    ├── TCP split/disorder
                  │                    ├── Fake packet injection
                  │                    ├── TLS record fragmentation
                  │                    └── OOB data injection
                  │
                  ├── [macOS] networksetup (Wi-Fi SOCKS proxy)
                  └── [Windows] reg.exe (Internet Settings proxy)
```

## Credits

- [ByeDPI](https://github.com/hufrea/byedpi) by hufrea — Core C proxy engine (vendored with macOS patches)
- [ByeByeDPI](https://github.com/romanvht/ByeByeDPI) by romanvht — Android client (inspiration)

## License

The `byedpi` core is licensed under MIT. See [ByeByeDPI/LICENSE](ByeByeDPI/LICENSE) for details.
