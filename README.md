# Grid: Decentralized Peer-to-Peer Mesh & Nostr Messenger

> A censorship-resistant, zero-infrastructure, end-to-end encrypted mobile chat application built with **Flutter**, powered by the **BitChat** mesh protocol and **Nostr** internet fallback.

[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](http://unlicense.org/)
[![Protocol: BitChat v2.0](https://img.shields.io/badge/protocol-BitChat%20v2.0-orange)](https://github.com/permissionlesstech/bitchat)
[![Architecture: Clean%20%2F%20Hexagonal](https://img.shields.io/badge/architecture-Hexagonal%20Ports%20%26%20Adapters-green)](BITCHAT_FLUTTER_ARCHITECTURE.md)
[![State: Riverpod](https://img.shields.io/badge/state-Riverpod-blue)](https://riverpod.dev)
[![Design: Minimal%20Monochrome](https://img.shields.io/badge/Design-Minimal%20Monochrome-lightgrey)](#-minimal-monochrome-design-system)
[![Cloudflare Pages: Ready](https://img.shields.io/badge/Cloudflare_Pages-Ready-f38020?logo=cloudflare)](public/CLOUDFLARE_PAGES_SETUP.md)

---

## 🌟 Vision & Key Capabilities

- **Zero Accounts & Zero Central Servers:** Cryptographic key pairs serve as the sole user identity. No servers, registration, or metadata silos.
- **Dual Transport Architecture:**
  - **Offline BLE Mesh Network:** Direct peer-to-peer and multi-hop mesh communication over Bluetooth Low Energy when disconnected from the internet.
  - **Nostr Relay Fallback:** Bridges separated meshes and reaches remote mutual favorites across the global internet via Nostr WebSocket relays.
- **Minimalist Monochrome UI:** Clean, distraction-free aesthetic with high-contrast Zinc tones, floating capsule composer, continuous squircle cards, and a standard Left Navigation Drawer.
- **End-to-End Encryption with Forward Secrecy:** Private chats are secured using the **Noise Protocol Framework (`Noise_XX_25519_ChaChaPoly_SHA256`)**.
- **Controlled Flooding Mesh Routing:** Multi-hop message delivery capped by degree-based TTL clamping ($7 \to 5$), 1000-entry LRU deduplication, randomized relay jitter ($10\text{--}220\text{ ms}$), split-horizon filtering, and degree-adaptive fanout.
- **Store-and-Forward Couriers:** Delay-Tolerant Networking (DTN) for delivering messages across isolated network partitions through physical encounters.
- **Instant Panic Wipe:** Physical zeroization of private keys, memory scrubbing, and disk storage wipe with zero confirmation dialog delay in emergencies.
- **Production Static Landing Page:** A self-contained, zero-dependency product showcase in [`public/`](public/) with interactive real-time BLE mesh canvas simulation, live audio waveform player, and packet wire inspector—ready for 1-click hosting on **Cloudflare Pages**.

---

## 🌐 Static Landing Page & Cloudflare Pages Hosting

Grid includes an ultra-premium, dark-mode product showcase in the [`public/`](public/) directory ready to host on **Cloudflare Pages** by connecting this repository:
1. **Connect Repo:** On [Cloudflare Dashboard](https://dash.cloudflare.com/), go to **Workers & Pages > Create application > Pages > Connect to Git** and select this repo.
2. **Build Settings:** Set **Build output directory** to `public` (leave **Build command** empty).
3. **Deploy:** Instant edge CDN deployment with pre-configured security headers (`public/_headers`) and routing (`public/_redirects`). See [CLOUDFLARE_PAGES_SETUP.md](public/CLOUDFLARE_PAGES_SETUP.md) for full instructions.

## 🏛 Architecture Overview

Detailed architectural design and protocol reverse-engineering are documented in:
👉 **[BITCHAT_FLUTTER_ARCHITECTURE.md](BITCHAT_FLUTTER_ARCHITECTURE.md)**

### Zero-Overhaul Extensibility & Plugin Architecture
To prevent architectural stalling, Grid employs an **Open-Closed Plugin Pattern**:
- **Pure Infrastructure Mesh Engine:** The core `MeshEngine` handles only low-level networking (flooding, deduplication LRU, TTL clamping, randomized jitter, and link relaying). It has **zero knowledge** of specific message types or features.
- **Protocol Feature Registry:** High-level features (Public Chat, Noise E2EE, Couriers, Files, Voice, Groups, Bulletin Boards) are self-contained `ProtocolFeatureModule` plugins that register dynamically. New features are added without modifying the core mesh engine.
- **Tolerant Wire Codec:** Unknown future packet types (`MessageType.unknown`) are forwarded across the mesh safely without crashing or dropping packets.
- **Pluggable Multi-Transport Pipeline:** Abstract `TransportPort` allows seamlessly adding new transports (e.g. Local LAN Wi-Fi Direct, LoRa radios, WebRTC) alongside BLE Mesh and Nostr.
- **Configurable Ephemerality:** Clean repository port supporting both default volatile in-memory storage (zero disk trace) and optional encrypted local persistence with secure zeroization.

```
┌────────────────────────────────────────────────────────┐
│             FLUTTER PRESENTATION (Minimalist UI)       │
│     Chat Screen, Left Navigation Drawer, Peer Radar    │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│                 APPLICATION LAYER (Riverpod)           │
│        TimelineState, PeerState, ChannelState          │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│          DOMAIN CORE: MODULAR PLUGIN ENGINE            │
│  ┌──────────────────────────────────────────────────┐  │
│  │ ProtocolFeatureRegistry (Chat, Noise, Couriers)  │  │
│  └────────────────────────▲─────────────────────────┘  │
│                           │ Dispatches Inbound Payload │
│  ┌────────────────────────┴─────────────────────────┐  │
│  │ MeshEngine (Flooding, Dedup, Jitter, TTL Clamp)  │  │
│  └────────────────────────▲─────────────────────────┘  │
│                           │                            │
│  ┌────────────────────────┴─────────────────────────┐  │
│  │ MultiTransportRouter (BLE Mesh -> LAN -> Nostr)  │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│                 PORTS & ADAPTERS LAYER                 │
│  TransportPort   CryptoPort   StoragePort   PowerPort  │
└────────────┬───────────────────────┬───────────────────┘
             │                       │
     ┌───────┴───────┐       ┌───────┴───────┐
     ▼               ▼       ▼               ▼
[Native BLE]  [Simulated] [Dart Crypto] [Nostr WS]
(iOS/Android)  (Headless)  (X25519/Ed)   (Relays)
```

---

## 🛠 Engineering Methodology: Build-and-Test Incrementalism

We adhere strictly to an **incremental, verifiable engineering pattern**:
1. **Piece-by-Piece Construction:** We build one self-contained, high-cohesion module at a time.
2. **Immediate Verification:** Every module is accompanied by comprehensive automated tests (unit, property, or simulation).
3. **Commit & Push:** Once verified, changes are committed and pushed incrementally to the upstream repository.

### Delivery Phases

  - [x] **Phase 1: Pure Dart Wire Protocol & Codecs** *(Completed & Merged)*
    - `BinaryReader` & `BinaryWriter`: Big-endian integer and byte slice read/write with bounds checking.
    - `MessageType`: Wire packet enumeration matching BitChat v2.0 with forward-compatible `unknown(rawValue)` fallback.
    - `MessagePadding`: PKCS#7 message padding toward `{256, 512, 1024, 2048}`-byte buckets.
    - `BitchatPacket`: Immutable packet model (v1 14-byte & v2 16-byte headers, flag bitmasks, `copyForSigning()` invariant).
    - `BinaryProtocolCodec`: Full wire serialization/deserialization engine with automatic zlib payload compression.
    - `AnnouncementCodec`: TLV presence encoder/decoder with resilient unknown tag skipping.
    - `FragmentCodec`: Large packet MTU slicing into 469-byte fragments and reassembly.
    - **Verification:** 15/15 unit tests passing, 0 analyzer issues.
  - [x] **Phase 2: Cryptographic Engine & Identity Subsystem** *(Completed & Merged)*
    - `IdentityKeyPair`: Dual Curve25519 (X25519) + Ed25519 keys, persistent 8-byte peer ID (`SHA-256(noisePublicKey)[0..8]`), and symmetric 60-digit safety numbers.
    - `CryptoPort` & `CryptographyAdapter`: Abstract port & concrete adapter using `package:cryptography` for unforgeable canonical packet signing (`TTL=0`) and tamper-evident verification.
    - `NoiseCipherState`: ChaCha20-Poly1305 AEAD with BitChat 12-byte nonce layout, extracted 4-byte big-endian wire nonces, and 1024-bit sliding-window replay protection.
    - `NoiseSymmetricState`: Complete Noise Protocol framework SymmetricState abstraction (HKDF-SHA256, `mixHash`, `mixKey`, `mixKeyAndHash`, `encryptAndHash`, `decryptAndHash`, `split`).
    - `NoiseHandshakeState`: 3-step `Noise_XX_25519_ChaChaPoly_SHA256` mutual authentication state machine (`-> e`, `<- e, ee, s, es`, `-> s, se`) with forward secrecy and static key encryption.
    - `NoiseSessionManager` & `NoiseSession`: State management for peer E2EE sessions, in-flight handshake timeout management, automatic PKCS#7 message padding, and instant panic session wipe.
    - `NoisePayloadType`: Forward-compatible enumeration for inner decrypted 0x11 payloads (`privateMessage`, `readReceipt`, `groupInvite`, `verifyChallenge`, etc.).
    - **Verification:** 28/28 unit tests passing across protocol and crypto suites, 0 analyzer issues.
  - [x] **Phase 3: Mesh Routing Engine & Multi-Node Simulation** *(Completed & Merged)*
    - `SeenPacketCache`: High-performance 1,000-entry LRU cache with 5-minute TTL and immediate duplicate suppression.
    - `ProtocolFeatureRegistry` & `ProtocolFeatureModule`: Dynamic decoupled feature registration preserving the Open-Closed Principle (zero feature knowledge in core mesh).
    - `MeshEngine`: BitChat controlled flooding with adaptive TTL clamping ($7 \to 5$ when peer density $\ge 6$), randomized relay jitter ($10\text{--}220\text{ ms}$), split-horizon filtering, and degree-based fanout subsetting.
    - `TransportPort` & `TransportMedium`: Transport abstraction supporting BLE, Nostr, Wi-Fi LAN, and simulated virtual radio links.
    - `SimulatedMeshNetwork` & `SimulatedLinkAdapter`: Headless multi-node virtual radio environment with configurable propagation latency, packet loss, and topology builders (line, full mesh, ring).
    - **Verification:** 38/38 unit tests passing across all suites including 10-node linear chain and circular ring deduplication simulations; 0 analyzer issues.
  - [x] **Phase 4: Native BLE Dual-Role Radio Bridge** *(Completed & Merged)*
    - `BleConstants`: BitChat Service UUID (`0xFDC7`), Characteristic UUID (`0x2A06`), target MTU 512, platform channel identifiers.
    - `PowerPolicyPort` & `BlePowerMode`: Adaptive duty cycle modes: `active` (100% continuous), `balanced` (15s on / 15s off), and `background` (5s on / 55s off).
    - `NativeBleLinkAdapter`: Concrete `TransportPort` bridging Dart mesh routing with native dual-role radio controllers via Flutter MethodChannel and EventChannel.
    - **iOS CoreBluetooth Dual-Role (`ios/Runner/BLE/`):**
      - `BLEPeripheralController`: `CBPeripheralManager` & GATT Server advertising BitChat service and hosting packet characteristic.
      - `BLECentralController`: `CBCentralManager` & Scanner discovering BitChat peers, subscribing to notifications, and transmitting packets.
      - `BLERadioCoordinator`: Dual-role coordinator managing both Central and Peripheral links with adaptive duty-cycling.
      - `BlePlatformChannel`: Platform channel message and event stream handlers.
      - Background modes: `bluetooth-central`, `bluetooth-peripheral`.
    - **Android BLE Dual-Role (`android/app/src/main/kotlin/com/bitchat/mesh/dec_chat/ble/`):**
      - `BleAdvertiserManager`: `BluetoothLeAdvertiser` with low-latency settings.
      - `BleGattServerManager`: `BluetoothGattServer` handling incoming writes and client subscriptions.
      - `BleScannerManager`: `BluetoothLeScanner` with service UUID scan filters and "Grid" name matching.
      - `BleGattClientManager`: Client connections, MTU 512 negotiation, notifications, and packet transmission.
      - `BleRadioCoordinator`: Dual-role coordinator and duty-cycle scheduling.
      - `BlePlatformChannel`: MethodChannel and EventChannel bridge.
      - Permissions: `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`.
    - **Verification:** 46/46 unit tests passing across all suites including platform channel bridge test suite; 0 analyzer issues.
  - [x] **Phase 5: Nostr Dual-Transport & Location Channels** *(Completed & Merged)*
    - `Geohash`: Pure Dart Morton Z-order curve spatial indexing encoder, decoder, 8-neighbor adjacency calculator, and location channel validation (`#9q8yy`).
    - `NostrKind`: Protocol event enumeration covering NIP-01, NIP-04, NIP-28, and custom ephemeral BitChat mesh (20000) & geohash (20001) carriers.
    - `NostrEvent`: NIP-01 data model, canonical serialization `[0, pubkey, created_at, kind, tags, content]`, SHA-256 event ID verification, and transparent BitChat packet wrapping/unwrapping.
    - `NostrRelayAdapter`: Concrete `TransportPort` managing multi-relay WebSocket connections, automatic reconnection with backoff, NIP-01 subscription framing (`REQ`, `CLOSE`), echo suppression, and geohash channel subscriptions.
    - `LocationChannelService`: Spatial channel manager resolving GPS coordinates to geohash channels and computing 9-cell boundary neighborhood coverage.
    - `MessageRouter`: Dual-transport coordinator implementing `TransportPort`, providing policy switching (`adaptive`, `bleOnly`, `nostrOnly`, `dual`), cross-medium deduplication via `SeenPacketCache`, and proximity-directed BLE-to-Nostr fallback.
    - **Verification:** 78/78 unit tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 6: Riverpod Application State & Domain Core** *(Completed & Merged)*
    - `ChatMessage` & `PeerModel`: Immutable presentation models with transport badges, delivery checkmarks, and symmetric 60-digit safety numbers.
    - `ChatCommand`: Command parser supporting BitChat power commands (`/msg`, `/who`, `/slap`, `/ping`, `/join`, `/clear`, `/panic`).
    - **Riverpod Application State:**
      - `IdentityNotifier`: Manages local key pairs, nickname, and peer ID.
      - `PeersNotifier`: Tracks active/discovered peers, RSSI signal indicators, hop count, and safety verification status.
      - `ChannelsNotifier`: Manages joined channels (`#mesh`, `#general`, `#9q8yy`).
      - `TimelineNotifier`: Ephemeral in-memory timeline buffer with packet dispatching and feature module routing.
      - `PanicController`: Instant zeroization and session wipe.
    - **Verification:** 109/109 unit and widget tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 7: Store-and-Forward Couriers, Panic Wipe & Field Polish** *(Completed & Merged)*
    - `CourierEnvelope`: Compact binary wire serialization for sealed DTN envelopes, hop budgeting, and expiration checking.
    - `CourierService`: Store-and-forward Delay-Tolerant Networking (DTN) outbox with spray-and-wait routing, data-muling across partitioned networks, direct encounter delivery, and capacity eviction.
    - `CourierModule`: Protocol feature module integrating `MessageType.courierEnvelope` (`0x04`) into `ProtocolFeatureRegistry` and `MeshEngine`.
    - `PanicZeroizationService`: In-place memory scrubbing (`scrubBytes`), courier outbox wipe, Noise session cipher state destruction, deduplication cache clearing, and radio shutdown.
    - `BitchatCoordinator`: Master application coordinator tying together identity, Noise encryption, controlled mesh flooding, courier DTN, and panic zeroization.
    - `End-to-End Integration Suite`: Verification of direct 1-hop delivery, multi-node mobile data muling across network partitions, and panic zeroization.
    - **Verification:** 123/123 unit and integration tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 8: Native macOS Desktop BLE, Live Peer Discovery & Dual-Transport Hardening** *(Completed & Merged)*
    - `AnnouncementModule`: Protocol module capturing `MessageType.announce` packets and registering peers with nicknames, cryptographic public keys, and symmetric safety numbers into `peersProvider`.
    - `ChatMessageModule`: Protocol module routing `MessageType.message` packets into `timelineProvider` for real-time conversation updates.
    - Native macOS CoreBluetooth peripheral/central integration with dynamic state management.
    - **Verification:** 130/130 unit and integration tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 9: Persistent Cryptographic Identity, Thread Unification & Zero-Trace Local Storage** *(Completed & Merged)*
    - Deterministic key recovery from 32-byte seed retaining identical `peerId` across restarts.
    - Decoupled persistent local storage subsystem managing `identity.json`, `peers.json`, and `conversations.json` with write-through memory caching and file disk buffer overwriting (`wipeAll()`).
    - **Verification:** 140/140 unit and integration tests passing; 0 analyzer issues.
  - [x] **Phase 10: Editable Profile, Phone Number Discovery & Peer Search** *(Completed & Merged)*
    - Broadcast phone number via optional TLV tag `0x07` in `AnnouncementCodec`.
    - Edit Profile sheet for display name and phone number with live persistence.
    - Real-time search in `PeerDirectoryScreen` filtering peers by nickname, formatted phone number, or peer ID prefix.
    - Slash commands: `/nick <name>` and `/phone <number>` (or `/phone clear`).
    - **Verification:** 163/163 unit and widget tests passing; 0 analyzer issues.
  - [x] **Phase 11: Minimal Monochrome Design System, Left Navigation Drawer & App Rebrand to Grid** *(Completed)*
    - **Monochrome Crisp Palette (`AppTheme`)**: High-contrast pure white/zinc-50 (`#FAFAFA`) accents with deep dark (`#09090B`) text and icon contrast.
    - **Left Navigation Drawer (`AppDrawer`)**: Clean branding header with live "Mesh Network Online" indicator, quick navigation to Messages, Peers radar (with live peer count badge), joined Channels, and pinned bottom Account Tab with user initial squircle avatar and one-tap metadata editing.
    - **Streamlined Conversation View**: Removed redundant floating action button to deliver an uncluttered viewport.
    - **Floating Capsule Composer**: Pill-shaped input with dynamic circular send button transitioning to pure white with upward arrow (`Icons.arrow_upward_rounded`) on text entry.
    - **Rebrand to Grid**: Unified application naming across platform manifests, UI headers, BLE local names, and storage namespaces.
    - **Verification:** 167/167 unit, widget, and integration tests passing; 0 analyzer issues.

---

## 📦 Repository & Local Environment

- **Git Remote:** `https://github.com/sushantdev-git/grid.git` (formerly `dec-chat.git`)
- **Default Branch:** `main`
- **Active Feature Branch:** `feat/rebrand-to-grid`
- **Author:** Sushant Mishra (`sushantkumar6700@gmail.com`)

### Environment & Toolchain
- **Flutter SDK:** `3.47.4 • channel stable`
- **Dart SDK:** `3.13.3 • macos_arm64`
- **Run Tests:**
  ```bash
  flutter test
  ```
- **Analyze Code:**
  ```bash
  flutter analyze
  ```

---

## 📄 License

This project is dedicated to the public domain under the [Unlicense](http://unlicense.org/).
