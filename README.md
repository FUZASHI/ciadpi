# ByeByeDPI

A cross-platform Flutter client for [ByeDPI](https://github.com/hufrea/byedpi) — a local SOCKS5 proxy that bypasses Deep Packet Inspection (DPI) based internet restrictions.

**Supported platforms:** Android, macOS, Windows

## Features

- 🛡️ One-click DPI bypass via animated connection orb
- 📋 9 curated presets for different regions and strategies
- ⚙️ Custom flags mode for manual `ciadpi` configuration
- 📡 Platform-aware proxy routing:
  - **Android:** VPN tunnel via `VpnService` + `tun2socks` (system-wide, no root)
  - **macOS:** Automatic Wi-Fi SOCKS5 proxy via `networksetup`
  - **Windows:** Proxy mode (browser-only) or **VPN mode** (all traffic via tun2socks)
- 📝 Real-time log viewer with color-coded output
- 🎨 Premium dark-mode UI with glassmorphism design
- 📱 Responsive layout — adapts to both mobile and desktop

## Presets

| Preset | Strategy | Best For |
|--------|----------|----------|
| ⚡ Default (ByeByeDPI) | `--oob 1 --udp-fake 1 --tlsrec -5+se` | Upstream default |
| 🇷🇺 Russia (Light) | `--disorder 1 --tlsrec 1+s` | Moderate DPI |
| 🇷🇺 Russia (Aggressive) | `--fake -1 --ttl 8` | Aggressive SNI blocking |
| 🇷🇺 Russia (Combined) | `--split 1+s --disorder 3+s --oob 1+s` | Maximum coverage |
| 🌍 Generic (Split) | `--split 3 --split 7` | Simple DPI |
| 🌍 Generic (Disorder) | `--disorder 1` | Stateful DPI |
| 🌍 Generic (TLS Record) | `--tlsrec 1+s` | TLS-aware DPI |
| 🌍 Generic (OOB) | `--oob 1+s` | DPI reassembly bypass |
| 🇹🇷 Turkey | `--disorder 1 --fake -1 --ttl 6` | Turkish ISPs |

## Platform Details

### Android
On Android, the app uses `VpnService` to create a local VPN tunnel. All device traffic is routed through a `tun2socks` tunnel into the local SOCKS5 proxy. No root required — users just need to approve the VPN permission dialog on first use. A persistent notification is shown while the VPN is active.

**Supported flags:** `--split`, `--disorder`, `--oob`, `--disoob`, `--fake`, `--ttl`, `--tlsrec`, `--mod-http`, `--auto`, `--timeout`, `--proto`, `--hosts`, `--drop-sack`

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

**Two routing modes:**
- **Proxy mode** (default) — sets system proxy via registry. Only affects browsers and apps that respect WinINET settings.
- **VPN mode** — uses [tun2socks](https://github.com/xjasonlyu/tun2socks) + [wintun](https://www.wintun.net/) to create a virtual TUN adapter that captures ALL system traffic (games, Discord, Telegram, etc.). Requires Administrator privileges.

## Building

### Prerequisites
- Flutter SDK (3.11+)
- Platform-specific tools:
  - **Android:** Android SDK with NDK 27+ installed
  - **macOS:** Xcode command line tools
  - **Windows:** Visual Studio 2022 with C++ desktop workload, plus MSYS2/MinGW for compiling ciadpi

### Android

1. **Clone the repo:**
   ```bash
   git clone <repo-url>
   cd ciadpi
   ```

2. **Build and run** (native code compiles automatically via CMake + ndk-build):
   ```bash
   flutter pub get
   flutter run -d <android-device>
   ```

   The build system automatically compiles:
   - `libbyedpi.so` — byedpi C proxy engine (via CMake)
   - `libhev-socks5-tunnel.so` — tun2socks VPN tunnel (via ndk-build)

### macOS

1. **Clone the repo:**
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

1. **Clone the repo:**
   ```bash
   git clone <repo-url>
   cd ciadpi
   ```

2. **Compile the byedpi binary** (in MSYS2 MinGW64 terminal):
   ```bash
   cd ByeByeDPI/app/src/main/cpp/byedpi
   make windows
   cp ciadpi.exe ../../../../../../assets/ciadpi.exe
   cd ../../../../../../
   ```

3. **Download VPN mode binaries (optional, for VPN mode):**
   - Download `tun2socks-windows-amd64.zip` from [tun2socks releases](https://github.com/xjasonlyu/tun2socks/releases)
   - Download `wintun.dll` from [wintun.net](https://www.wintun.net/)
   - Place both in the `assets/` folder:
     ```bash
     cp tun2socks.exe assets/tun2socks.exe
     cp wintun.dll assets/wintun.dll
     ```

4. **Run:**
   ```bash
   flutter pub get
   flutter run -d windows
   ```

   > **Note:** VPN mode requires running as Administrator. Right-click your terminal or the app → "Run as administrator".

### Building Release

```bash
# Android
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# macOS
flutter build macos --release
# Output: build/macos/Build/Products/Release/ciadpi.app

# Windows
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

## How It Works

### Desktop (macOS / Windows)
1. The app extracts the bundled binary (`ciadpi_mac` or `ciadpi.exe`) to the app's data directory
2. Launches it as a background process with the selected preset flags
3. Configures traffic routing:
   - **macOS:** Wi-Fi SOCKS proxy via `networksetup`
   - **Windows Proxy mode:** Internet Settings registry via `reg.exe` (browser-only)
   - **Windows VPN mode:** Launches `tun2socks` → creates wintun TUN adapter → configures split routes (0.0.0.0/1 + 128.0.0.0/1) → all traffic flows through TUN → SOCKS5 proxy
4. DPI bypass techniques are applied to outgoing packets
5. On disconnect, the proxy is killed, tun2socks is stopped, and system settings/routes are restored

### Android
1. The byedpi C engine runs in-process via JNI (`libbyedpi.so`)
2. A `VpnService` creates a TUN interface using Android's VPN API
3. `hev-socks5-tunnel` routes all traffic from the TUN into the local SOCKS5 proxy
4. DPI bypass techniques are applied to outgoing packets
5. On disconnect, the VPN tunnel is closed and the proxy stops

## Architecture

```
Flutter UI ─► ProxyManager
                   │
        ┌──────────┼──────────┐
        │          │          │
    [Android]   [macOS]   [Windows]
        │          │          │
  MethodChannel  Process   Process
        │          │          │
  VpnService    ciadpi     ciadpi.exe
   + JNI        binary     binary
        │          │          │
  libbyedpi.so     ├── TCP split/disorder
        +          ├── Fake packet injection
  tun2socks        ├── TLS record fragmentation
   (VPN)           └── OOB data injection
        │          │          │
  VPN tunnel   networksetup  ├── [Proxy] reg.exe
  (system-wide) (SOCKS proxy)└── [VPN] tun2socks
                                  + wintun TUN
                                  (system-wide)
```

## Project Structure

```
ciadpi/
├── lib/
│   ├── main.dart              # UI (responsive: desktop + mobile)
│   └── core/
│       ├── proxy_manager.dart  # Platform-aware proxy lifecycle
│       └── presets.dart        # DPI bypass presets
├── android/app/src/main/
│   ├── cpp/                    # CMake build for libbyedpi.so
│   │   ├── CMakeLists.txt
│   │   ├── native-lib.c        # JNI bridge
│   │   └── main.h
│   ├── jni/                    # ndk-build for tun2socks
│   │   ├── Android.mk
│   │   └── Application.mk
│   └── kotlin/.../ciadpi/
│       ├── MainActivity.kt     # MethodChannel bridge
│       ├── ByeDpiProxy.kt      # JNI wrapper for byedpi
│       ├── TProxyService.kt    # JNI wrapper for tun2socks
│       └── ByeDpiVpnService.kt # VPN service implementation
├── assets/
│   ├── ciadpi_mac              # Pre-compiled macOS binary
│   ├── ciadpi.exe              # Pre-compiled Windows binary
│   ├── tun2socks.exe           # Windows VPN mode (download separately)
│   └── wintun.dll              # Windows TUN driver (download separately)
└── ByeByeDPI/                  # Vendored byedpi C source code
    └── app/src/main/
        ├── cpp/byedpi/         # Core C engine sources
        └── jni/                # hev-socks5-tunnel sources
```

## Credits

- [ByeDPI](https://github.com/hufrea/byedpi) by hufrea — Core C proxy engine (vendored with macOS patches)
- [ByeByeDPI](https://github.com/romanvht/ByeByeDPI) by romanvht — Android client (inspiration + vendored native code)
- [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) by heiher — tun2socks implementation for Android VPN

## License

The `byedpi` core is licensed under MIT. See [ByeByeDPI/LICENSE](ByeByeDPI/LICENSE) for details.
