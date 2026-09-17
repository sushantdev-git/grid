# Grid: Engineering Delivery History (Phases 1–14)

This document archives the chronological, test-driven development phases completed during the construction, hardening, and verification of **Grid**.

---

## 🛠 Engineering Methodology: Build-and-Test Incrementalism

We adhere strictly to an **incremental, verifiable engineering pattern**:
1. **Piece-by-Piece Construction:** We build one self-contained, high-cohesion module at a time.
2. **Immediate Verification:** Every module is accompanied by comprehensive automated tests (unit, property, or simulation).
3. **Commit & Push:** Once verified, changes are committed and pushed incrementally to the upstream repository.

---

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

- [x] **Phase 11: Minimal Monochrome Design System, Left Navigation Drawer & App Rebrand to Grid** *(Completed & Merged)*
  - **Monochrome Crisp Palette (`AppTheme`)**: High-contrast pure white/zinc-50 (`#FAFAFA`) accents with deep dark (`#09090B`) text and icon contrast.
  - **Left Navigation Drawer (`AppDrawer`)**: Clean branding header with live "Mesh Network Online" indicator, quick navigation to Messages, Peers radar (with live peer count badge), joined Channels, and pinned bottom Account Tab with user initial squircle avatar and one-tap metadata editing.
  - **Streamlined Conversation View**: Removed redundant floating action button to deliver an uncluttered viewport.
  - **Floating Capsule Composer**: Pill-shaped input with dynamic circular send button transitioning to pure white with upward arrow (`Icons.arrow_upward_rounded`) on text entry.
  - **Rebrand to Grid**: Unified application naming across platform manifests, UI headers, BLE local names, and storage namespaces.
  - **Verification:** 167/167 unit, widget, and integration tests passing; 0 analyzer issues.

- [x] **Phase 12: Offline Push-to-Talk (PTT) Audio Memos & SQLite Engine** *(Completed & Merged)*
  - Native audio capture with 16 kHz AAC-LC compression, live 30-sample normalized amplitude metering, and haptic feedback.
  - `VoiceFrameCodec`: TLV binary encoding for voice headers, duration, waveform samples, and AAC audio data.
  - Slicing and reassembly across BLE mesh via `FragmentCodec` and `FragmentAssembler`.
  - SQLite storage engine (`AppDatabase`) with ACID transactions, atomic schema upgrades, and zero-trace forensic deletion.
  - Interactive 36-bar tactile audio bubble player with variable playback speed (`1.0x` / `1.5x` / `2.0x`) and scrub controls.
  - **Verification:** 183/183 unit, widget, and integration tests passing; 0 analyzer issues.

- [x] **Phase 13: Neon Hexagonal Matrix Branding & App Landing Page** *(Completed & Merged)*
  - Replaced default Flutter placeholder icons with custom **Neon Hexagonal Matrix** across Android, iOS, macOS, and Web.
  - Modern app landing page inspired by Linear and Raycast in `public/` with responsive mobile drawer, 100% vector CSS phone mockup, touch-enabled interactive BLE mesh canvas simulator, and live audio waveform sandbox.
  - Zero external screenshots in git; Cloudflare Pages edge deployment ready.
  - **Verification:** 195/195 tests passing, 0 analyzer issues.

- [x] **Phase 14: Comprehensive Pre-Release Security Hardening & Cryptographic Audit Fixes** *(Completed & Merged)*
  - **Noise_XX Direct E2EE**: Connected `NoiseSessionManager` to 1-on-1 private messaging and Push-to-Talk voice notes with on-demand 3-way mutual authentication handshakes (`0x10`) and ChaCha20-Poly1305 wire encryption (`0x11`).
  - **Jitter & Reordering Resilience**: Inbound out-of-order encrypted packet buffering ensuring zero dropped messages during concurrent handshakes.
  - **Privacy-Preserving Phone Commitments (Solution 1)**: Replaced cleartext phone broadcasting with 8-byte domain-separated cryptographic commitments (`SHA-256("grid-phone-v1:" + digits)[0..8]`), paired with normalized hash-comparison search.
  - **Vampire Attack Defense**: `TokenBucketRateLimiter` on link inputs (10 pkts/sec, 20 burst capacity) dropping RF floods to protect against battery exhaustion.
  - **Storage Forensic Scrubbing**: Multi-pass random garbage overwrite (`Random.secure()`) followed by zero-fill before unlinking audio and JSON files; SQLite `PRAGMA secure_delete = ON;` and `PRAGMA wal_checkpoint(TRUNCATE);` checkpoints.
  - **Android Platform Hardening & OPSEC**: Blocked `adb backup` data extraction (`allowBackup="false"`) and defaulted to off-grid `bleOnly` radio silence (Nostr relays strictly opt-in).
  - **Verification:** 209/209 unit, widget, and integration tests passing; 0 analyzer issues.
