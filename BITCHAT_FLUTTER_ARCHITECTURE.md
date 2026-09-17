# Grid: Architecture Blueprint & Technical Specification (Flutter)

**Document Version:** 2.0.0 (Production Hardening & Verification)  
**Author:** Sushant Mishra (`sushantkumar6700@gmail.com`)  
**Target Platform:** Flutter (Android, iOS, macOS, Web)  
**Reference Protocol:** [permissionlesstech/bitchat](https://github.com/permissionlesstech/bitchat) (Protocol v2.0 / BLE Architecture v3)  

---

## 1. Executive Summary & Vision

Grid is a decentralized, peer-to-peer, dual-transport messaging platform engineered for secure, censorship-resistant communication operating in adversarial, partitioned, or zero-connectivity environments. Powered by the **BitChat mesh protocol** and **Nostr internet relay fallback**, it provides off-grid communication without reliance on telecommunication providers or centralized infrastructure.

Its architecture rests upon six foundational tenets:
1. **Zero Infrastructure & Zero Accounts:** No phone numbers, servers, registration, or accounts required. Identity is derived strictly from cryptographic key pairs.
2. **Dual Transport Harmony:** Ad-hoc local communication runs over a **Bluetooth Low Energy (BLE) multi-hop mesh network** (offline). Distant communication falls back seamlessly to **Nostr relays over WebSockets** (internet).
3. **End-to-End Encryption (E2EE) with Forward Secrecy:** Private sessions negotiate keys using the **Noise Protocol Framework (`Noise_XX_25519_ChaChaPoly_SHA256`)**.
4. **Controlled Flooding & Opportunistic Store-and-Forward:** Multi-hop mesh routing employs degree-dependent TTL clamping ($7 \to 5$), LRU deduplication (1,000 entries), fanout subsetting, randomized jitter (10–220ms), and opportunistic couriers (spray-and-wait).
5. **Hardened Privacy & Anti-DoS Protections:** Zero-exposure cryptographic phone commitments, token-bucket anti-vampire rate limiting, zero-trace SQLite database (`secure_delete = ON`), and forensic audio shredding.
6. **Ephemerality by Default & Panic Wipe:** Chat timelines reside in memory and local encrypted/sanitized storage. All cryptographic session keys and local data are instantly zeroized upon an emergency panic trigger.

---

## 2. Zero-Overhaul Extensibility Architecture

A primary architectural failure mode in peer-to-peer networking is creating tight coupling between the mesh radio, packet routing, and application features (which led upstream BitChat v2 to stall in an 8,000-line god-object).

To ensure that **any future protocol extension (e.g. voice streaming, group messaging, bulletin boards, Cashu ecash payments, or alternate transports like LoRa and LAN Wi-Fi Direct) can be dropped in without refactoring core routing or presentation**, this architecture enforces 7 modularity principles:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       FLUTTER PRESENTATION (Signal UI)                      │
│   Unified Conversation View  ·  Peer Directory  ·  Safety Numbers & Badges  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                    APPLICATION & STATE LAYER (Riverpod)                     │
│     AsyncNotifiers  ·  State Providers  ·  PanicWipeCoordinator             │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                     DOMAIN CORE: MODULAR PLUGIN ENGINE                      │
│                                                                             │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                 ProtocolFeatureRegistry (Open-Closed)                │  │
│   │  [PublicChatModule] [NoiseModule] [CourierModule] [FileTransfer]     │  │
│   │  [VoiceModule]      [GroupModule] [BoardModule]   [FutureModules...] │  │
│   └──────────────────────────────────▲───────────────────────────────────┘  │
│                                      │ Dispatches Inbound Payload           │
│   ┌──────────────────────────────────┴───────────────────────────────────┐  │
│   │                   MeshEngine (Pure Infrastructure)                   │  │
│   │  - Tolerant Decoder (Relays Unknown Packet Types Safely)             │  │
│   │  - Controlled Flooding (TTL Clamping 7->5, Deduplication LRU 1000)   │  │
│   │  - Randomized Jitter Scheduler (10-220ms) · Fanout Subsetting        │  │
│   │  - Split-Horizon Link Rule · Outbox State Machine                    │  │
│   └──────────────────────────────────▲───────────────────────────────────┘  │
│                                      │                                      │
│   ┌──────────────────────────────────┴───────────────────────────────────┐  │
│   │            MultiTransportRouter (Prioritized Arbitration)            │  │
│   │    BLE Mesh (Offline) ──▶ Local LAN (Wi-Fi) ──▶ Nostr Relay (Web)    │  │
│   └──────────────────────────────────▲───────────────────────────────────┘  │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                            PORTS & ADAPTERS LAYER                           │
│  TransportPort   CryptoPort   ConversationRepoPort   PowerPolicyPort        │
└─────────┬──────────────┬───────────────┬─────────────────────┬──────────────┘
          │              │               │                     │
          ▼              ▼               ▼                     ▼
   [Native BLE]     [Dart Crypto]  [Volatile RAM /        [Adaptive Duty]
   [Nostr WS]       (X25519/Ed)    Encrypted Cache]       (100% vs 25% sleep)
   [Future: LoRa]
```

### 2.1 The Protocol Feature Registry (Open-Closed Principle)
The `MeshEngine` is **pure networking infrastructure**. It knows how to encode headers, decrement TTL, deduplicate packets, and relay bytes over links. It has **zero knowledge** of private chat, files, or audio.

Whenever a packet is addressed to our local peer (or is a public broadcast), `MeshEngine` passes it to `ProtocolFeatureRegistry`:

```dart
abstract class ProtocolFeatureModule {
  String get moduleId;
  Set<MessageType> get handledMessageTypes;
  Future<void> initialize();
  Future<void> handleInbound(BitchatPacket packet, InboundContext context);
  Future<void> dispose();
}
```

*Adding a new feature later (e.g. push-to-talk voice, bulletin board, or Cashu ecash tokens) requires creating a single class implementing `ProtocolFeatureModule` and registering it at startup. **Zero edits to the mesh engine or routing logic.***

### 2.2 Tolerant Reader & Unknown Packet Relaying
If a nearby peer is running BitChat v2.5 with a new packet type (`0x30`), older nodes must **not crash, drop, or invalidate** the packet:
- `MessageType.unknown(int rawValue)` safely captures unallocated types.
- Relays inspect only the outer 14/16-byte binary header.
- The packet is deduplicated, TTL-decremented, jittered, and relayed across the mesh to its destination.
- TLV parsers ignore unknown tags gracefully without parse exceptions.

### 2.3 Pluggable Multi-Transport Pipeline
Instead of hardcoding binary `isBle` vs `isNostr` flags, the routing layer interacts with a unified `TransportPort`:

```dart
enum TransportMedium { bleMesh, localLan, nostrRelay, lora, custom }

abstract class TransportPort {
  TransportMedium get medium;
  Stream<TransportEvent> get events;
  Future<void> sendPacket(BitchatPacket packet, {String? targetPeerAddress});
  bool get isAvailable;
  int get priorityOrder; // 0 = Direct BLE, 1 = Local LAN, 2 = Nostr Internet
}
```
If we choose to add local Wi-Fi Direct, Multicast LAN UDP, or LoRa radio support in the future, we simply create a new adapter implementing `TransportPort` and register it in the router.

### 2.4 Configurable Storage & Ephemerality Strategy
- **Default Policy:** `VolatileMemoryConversationRepository` — Zero disk footprint. All message history lives in RAM ring buffers and vanishes on app kill or panic wipe.
- **Optional Policy:** `EncryptedDiskConversationRepository` — AES-GCM encrypted local store (key in Secure Enclave), allowing users who prefer message retention across restarts to opt-in, while maintaining instant cryptographic zeroization on panic.

### 2.5 Adaptive Power & Duty-Cycle Policies
BLE scanning causes rapid battery depletion if run at 100% duty cycle. The system includes an explicit `PowerPolicyCoordinator`:
- **Active Mode (App in foreground):** 100% scan, continuous advertising.
- **Balanced Mode (App idle in foreground):** Scan 15s, idle 15s.
- **Background Mode (App in background):** CoreBluetooth state restoration / Android background scan interval (scan 5s, idle 55s).

---

## 3. BitChat Protocol Wire Specifications (Under the Hood)

### 3.1 Wire Format & Binary Protocol

BitChat rejects heavy serialization formats (JSON, Protobuf) on the BLE mesh in favor of an optimized, big-endian binary packet format designed for constrained MTU limits (≤ 512 bytes):

#### Packet Wire Layout

```
Header (Fixed: 14 bytes for v1, 16 bytes for v2):
+--------+------+-----+-------------------+-------+------------------+
|Version | Type | TTL | Timestamp (UInt64)| Flags |  PayloadLength   |
| 1 byte |1 byte|1byte|      8 bytes      | 1 byte| 2 bytes (4 for v2|
+--------+------+-----+-------------------+-------+------------------+

Variable Section:
+----------+-----------------------+---------------------+-------------------+---------------------+
| SenderID | RecipientID (Optional)| Route (Optional)    | Payload (Variable)| Signature (Optional)|
| 8 bytes  | 8 bytes (flag 0x01)   | (flag 0x08)         | N bytes           | 64 bytes (flag 0x02)|
+----------+-----------------------+---------------------+-------------------+---------------------+
```

#### Flags Bitmask
* `0x01`: `hasRecipient` — Directed packet.
* `0x02`: `hasSignature` — Packet carries a 64-byte Ed25519 signature.
* `0x04`: `isCompressed` — Payload is compressed (zlib/deflate if > 256 bytes). Preceded by 2-byte uncompressed length.
* `0x08`: `hasRoute` — Source routing enabled (sequence of 8-byte intermediate peer IDs).
* `0x10`: `isRSR` — Reverse Source Route flag.

#### Packet Types (`MessageType`)
| Hex | Identifier | Description |
|---|---|---|
| `0x01` | `announce` | Peer presence announcement (TLV encoded: nickname, Noise key, Ed25519 key, neighbors, capabilities) |
| `0x02` | `message` | Broadcast public chat message (plain text) |
| `0x03` | `leave` | Graceful peer departure notice |
| `0x04` | `courierEnvelope` | Sealed store-and-forward bundle carried by intermediate nodes |
| `0x10` | `noiseHandshake` | Ephemeral Noise XX key exchange message |
| `0x11` | `noiseEncrypted` | E2EE ciphertext (padded to 256/512/1024/2048 bytes) |
| `0x20` | `fragment` | Packet fragment (8-byte frag ID, 2-byte index, 2-byte total) |
| `0x21` | `requestSync` | Gossip history synchronization request |
| `0x22` | `fileTransfer` | Large binary file chunk transfer |
| `0x23` | `boardPost` | Signed geohash bulletin board post |
| `0x24` | `prekeyBundle` | Gossiped one-time prekeys for asynchronous messaging |
| `0x25` | `groupMessage` | Group-encrypted message (group ID + ChaChaPoly ciphertext) |
| `0x26` / `0x27` | `ping` / `pong` | Directed latency/topology diagnostics |
| `0x28` | `nostrCarrier` | Nostr event ferried between mesh-only peer and gateway |
| `0x29` | `voiceFrame` | Live push-to-talk voice frame (signed broadcast) |
| `0x2C` | `announceV2` | Identity-free rotating peer ID presence |

#### Inner Noise Payload Types (Decrypted from `0x11`)
When an `0x11` (`noiseEncrypted`) payload is decrypted, its first byte reveals the real application payload:
* `0x01`: `privateMessage`
* `0x02`: `readReceipt`
* `0x03`: `delivered`
* `0x06`: `groupInvite`
* `0x07`: `groupKeyUpdate`
* `0x08`: `voiceFrame`
* `0x10` / `0x11`: `verifyChallenge` / `verifyResponse` (In-person QR verification)
* `0x12`: `vouch` (Web-of-trust attestation)
* `0x20`: `privateFile`
* `0x21`: `authenticatedPeerState`

### 3.2 Identity & Cryptographic Primitives

Each client generates two primary asymmetric key pairs:
1. **Curve25519 Key Pair:** Used for Noise Protocol Diffie-Hellman key exchange.
2. **Ed25519 Key Pair:** Used for signing public announcements, packets, and identity binding.

* **Peer ID:** The first 8 bytes of `SHA-256(Curve25519_Static_Public_Key)`. This 8-byte identifier is used in all mesh packet headers.
* **Signing Envelope:** Signatures are computed over the packet representation with `TTL = 0`, stripping the mutable TTL byte so relays can decrement TTL in transit without breaking the cryptographic signature.

### 3.3 Mesh Routing & Controlled Flooding Algorithm

To prevent broadcast storms while ensuring delivery across lossy radio links:
1. **TTL Clamping:** Packets originate with `TTL = 7`. Relays adaptively clamp TTL:
   - High density ($\ge 6$ active links): Cap broadcast TTL at $5$.
   - Low density ($\le 2$ active links): Relay at incoming TTL $- 1$.
2. **Deduplication LRU Seen-Set:** A cache of 1,000 recent packet identifiers with a 5-minute expiry. An incoming duplicate instantly cancels any pending relay.
3. **Randomized Relay Jitter:** Nodes delay relaying by a pseudo-random interval between $10\text{ ms}$ and $220\text{ ms}$ (wider window in dense topologies). This prevents simultaneous packet collisions over the 2.4 GHz ISM band and lets duplicate suppression take effect.
4. **Degree-Based Fanout Subsetting:** Broadcast traffic is forwarded to a deterministic, pseudo-random subset ($\approx \log_2(\text{degree})$) of connected peers, seeded by the packet ID.
5. **Split-Horizon Rule:** A packet is never relayed back out through the link on which it arrived.
6. **Directed Routing:** Packets with a target `recipientID` follow recorded source routes (derived from 1-hop neighbor lists in recent `announce` packets). If no route exists, they fall back to flooding with full fanout.

---

## 4. System Architecture & Codebase Layout

```
grid/
├── android/app/src/main/kotlin/com/bitchat/mesh/
│   ├── ble/
│   │   ├── BleAdvertiserManager.kt        # BLE Peripheral advertiser (GATT advertising)
│   │   ├── BleScannerManager.kt           # BLE Central scanner (Service UUID filtering)
│   │   ├── BleGattServerManager.kt        # GATT Server (accept writes, notify connected centrals)
│   │   ├── BleGattClientManager.kt        # Central connections (GATT client write & notify)
│   │   └── BleRadioCoordinator.kt         # Dual-role arbitration & peripheral connection pool
│   └── BlePlatformChannel.kt              # Flutter MethodChannel & EventChannel bridge
├── ios/Runner/BLE/                        # CoreBluetooth Central & Peripheral controllers
├── macos/Runner/MainFlutterWindow.swift   # macOS desktop CoreBluetooth & platform channels
├── lib/
│   ├── application/
│   │   └── bitchat_coordinator.dart       # Core application facade & state orchestrator
│   ├── core/
│   │   ├── constants/
│   │   │   ├── ble_constants.dart         # BLE UUIDs (Service, Characteristic, MTU limits)
│   │   │   └── protocol_constants.dart    # Limits, TTL caps, timeouts, jitter ranges
│   │   ├── error/
│   │   │   └── failure.dart               # Typed failure domain classes
│   │   └── utils/
│   │       ├── binary_reader.dart         # Big-endian byte-order binary stream parser
│   │       ├── binary_writer.dart         # Big-endian binary byte builder
│   │       ├── geohash.dart               # Morton Z-order curve spatial geohashing
│   │       └── message_padding.dart       # PKCS#7 bucket padding (256/512/1024/2048)
│   ├── domain/
│   │   ├── entities/
│   │   │   ├── bitchat_packet.dart        # Immutable 13/16-byte protocol wire packet
│   │   │   ├── chat_message.dart          # Chat message entity & delivery state
│   │   │   ├── peer_model.dart            # Peer identity, RSSI, commitments & safety numbers
│   │   │   └── courier_envelope.dart      # Store-and-forward sealed DTN bundle
│   │   ├── enums/
│   │   │   ├── message_type.dart          # Extensible wire packet types (with unknown fallback)
│   │   │   ├── noise_payload_type.dart    # Decrypted inner private payload discriminators
│   │   │   └── transport_medium.dart      # BLE Mesh, Nostr Relays, Local LAN, LoRa
│   │   ├── ports/
│   │   │   ├── transport_port.dart        # Abstract link transport interface
│   │   │   ├── crypto_port.dart           # Noise & digital signature port
│   │   │   └── power_policy_port.dart     # Adaptive duty-cycle interface
│   │   └── services/
│   │       ├── feature_registry.dart      # Open-Closed pluggable module coordinator
│   │       ├── mesh_engine.dart           # Controlled flooding, dedup, jitter, TTL clamping
│   │       ├── message_router.dart        # Dual-transport multi-medium arbitration
│   │       ├── seen_packet_cache.dart     # 1,000-entry LRU deduplication cache
│   │       ├── fragment_assembler.dart    # MTU slicing and reassembly buffer
│   │       ├── courier_service.dart       # Opportunistic DTN spray-and-wait outbox
│   │       ├── location_channel_service.dart # Ephemeral geohash room management
│   │       ├── noise_session_manager.dart # Noise_XX session handshake & ratchet state
│   │       ├── panic_zeroization_service.dart # Cryptographic RAM/disk wiping engine
│   │       └── [feature_modules]/         # Announcement, Chat, Courier, Noise, Voice
│   ├── infrastructure/
│   │   ├── adapters/
│   │   │   ├── native_ble_link_adapter.dart  # Production PlatformChannel BLE driver
│   │   │   ├── simulated_link_adapter.dart   # In-memory virtual mesh test radio
│   │   │   ├── nostr_relay_adapter.dart      # WebSocket Nostr client (NIP-01/04/44)
│   │   │   └── cryptography_adapter.dart     # Ed25519, X25519, ChaCha20-Poly1305 AEAD
│   │   ├── codecs/
│   │   │   ├── binary_protocol_codec.dart    # BitchatPacket wire serialization & CRC32
│   │   │   ├── announcement_codec.dart       # TLV Peer Announcement encoder/decoder
│   │   │   └── fragment_codec.dart           # Fragment payload chunking & headers
│   │   ├── database/
│   │   │   └── app_database.dart             # SQLite with PRAGMA secure_delete = ON
│   │   └── services/
│   │       ├── voice_service.dart            # 16 kHz AAC-LC audio recorder & player
│   │       └── local_storage_service.dart    # Encrypted settings & secure key storage
│   ├── presentation/
│   │   ├── state/
│   │   │   ├── timeline_notifier.dart        # Chat timeline & optimistic delivery state
│   │   │   ├── peers_notifier.dart           # Discovered mesh peer directory & RSSI
│   │   │   ├── channels_notifier.dart        # Ephemeral geohash channel subscriptions
│   │   │   ├── identity_state.dart           # Cryptographic identity & phone commitments
│   │   │   └── panic_controller.dart         # Emergency zeroization trigger
│   │   ├── theme/
│   │   │   └── app_theme.dart                # Minimalist monochrome Zinc-50 dark palette
│   │   ├── views/
│   │   │   ├── conversation_list_screen.dart # Thread list, Left Navigation Drawer, Mesh Radar
│   │   │   ├── chat_screen.dart              # E2EE thread, waveform player, terminal commands
│   │   │   ├── peer_directory_screen.dart    # Nearby peers, privacy phone search, QR sheet
│   │   │   └── safety_verification_dialog.dart# 60-digit safety numbers & QR scanner
│   │   └── widgets/                          # Message bubbles, waveforms, drawer, badges
│   └── main.dart
├── test/                                     # 209 automated unit, vector, & simulation tests
├── web/ & public/                            # Interactive client-side Web Mesh Simulator
└── docs/                                     # Archived delivery phases & historical logs
```

---

## 5. Signal UI Design Pattern & Minimalist Aesthetic

The UI combines **Signal's privacy-focused ergonomics** with a high-contrast **Minimalist Monochrome design system**:

1. **Responsive Shell & Navigation:**
   - **Left Navigation Drawer:** Smooth sliding drawer with quick navigation across `#mesh`, Geohashed local channels (`#geo-9q8y`), direct chats, live peer directory, and panic wipe trigger.
   - **Live Mesh Radar:** Top bar status indicator showing live BLE connection counts, active Nostr bridge status, and network topology density.
2. **Unified Conversation View:**
   - Visual transport badges distinguish direct BLE peer packets (Bluetooth icon) from Nostr internet fallback (Globe icon).
   - Verified safety checkmarks next to peers whose cryptographic identity has been confirmed via out-of-band QR verification.
3. **Interactive Audio Waveforms:**
   - Tactile 36-bar interactive audio player with variable speed controls (`1.0x`, `1.5x`, `2.0x`) and live recording amplitude metering.
4. **Terminal Slash Commands:**
   - Native command parser supports power-user CLI commands:
     - `/msg <peer> <text>`: Direct encrypted message.
     - `/who`: List active peers in mesh range.
     - `/ping <peer>`: Measure round-trip time across mesh hops.
     - `/join <channel>`: Enter a geohashed or custom channel.
     - `/phone <number>`: Compute and publish a cryptographic phone commitment.
     - `/clear`: Clear current chat display history.
     - `/panic`: Instant zeroization of private keys and session state.

---

## 6. Security Hardening, Anti-DoS & Forensic Protection

### 6.1 Noise_XX Forward-Secret E2EE & Ratchet State Machine
- **Handshake Protocol:** 1-on-1 private messaging negotiates ephemeral keys using `Noise_XX_25519_ChaChaPoly_SHA256`:
  $$\to e$$
  $$\leftarrow e, ee, s, es$$
  $$\to s, se$$
- **Replay Protection:** Incorporates a 1024-bit sliding window replay cache with 12-byte wire nonces and monotonic epoch counters.
- **Mutual Verification:** Generates symmetric 60-digit safety numbers from concatenated static public keys:
  $$\text{SafetyNumber} = \text{Format60}(\text{SHA-512}(K_A \mathbin{\Vert} K_B))$$

### 6.2 Privacy-Preserving Contact Discovery
To eliminate cleartext metadata leakage over public BLE broadcasts, Grid utilizes a **cryptographic commitment scheme** for phone number discovery:
- **Phone Commitment Hash:**
  $$\text{Commitment} = \text{SHA-256}(\text{"grid-phone-v1:"} \mathbin{\Vert} \text{NormalizedDigits})[0..8]$$
- **Zero-Exposure Querying:** Users search for contacts by entering phone numbers locally. The app hashes the search query using the identical domain-separated salt and matches the 8-byte commitment tag without ever transmitting or storing cleartext digits.

### 6.3 Anti-Vampire DoS Defense & Rate Limiting
- **Vampire Battery Attacks:** Malicious actors in physical proximity can exhaust smartphone batteries by flooding the 2.4 GHz spectrum with invalid cryptographic signatures or high-frequency packet bursts.
- **Token Bucket Limiter (`TokenBucketRateLimiter`):**
  - **Sustained Rate:** 10 packets/second per link.
  - **Burst Capacity:** 20 tokens.
  - **Pre-Validation Dropping:** Excess incoming packets are dropped immediately before expensive Ed25519 signature checks, Noise decryption, or mesh relaying.

### 6.4 Zero-Trace Storage & Forensic Shredding
- **SQLite Database Hardening:**
  - `PRAGMA secure_delete = ON;`: Overwrites deleted database rows with zero bytes to prevent forensic disk recovery.
  - `PRAGMA wal_checkpoint(TRUNCATE);`: Purges WAL freelists on shutdown or panic trigger.
- **Cryptographic Audio Shredding:** Prior to unlinking audio files from disk, the file is overwritten in-place with cryptographic random bytes (`Random.secure()`) followed by a pass of zero bytes.
- **Panic Zeroization:** The emergency panic controller instantly wipes private key material from volatile RAM (`X25519`, `Ed25519`), closes and deletes the SQLite database file, clears secure storage, and resets all Riverpod state providers.

### 6.5 Push-to-Talk (PTT) Voice Engine
- **Low-Bandwidth Compression:** 16 kHz AAC-LC compression tuned for high speech intelligibility over constrained BLE MTU limits.
- **Dynamic MTU Slicing:** Packets exceeding the radio MTU are transparently sliced into ordered chunks via `FragmentCodec` and reassembled by `FragmentAssembler` with an adaptive 30-second reassembly window.

---

## 7. Implementation Status, Verification & Test Coverage

All architectural phases of Grid have been fully realized in production code and verified against a comprehensive automated test suite.

> 📖 **Chronological Sprint History**: For detailed phase-by-phase delivery logs, architectural milestones, and historical test counts from Phase 1 through Phase 14, see **[docs/DELIVERY_PHASES.md](docs/DELIVERY_PHASES.md)**.

### Automated Verification Metrics

- **Automated Test Suite:** **209 / 209 tests passing** (`flutter test`)
- **Static Analysis:** **0 analyzer issues found** (`flutter analyze`)

### Verification Matrix by Architecture Layer

| Layer | Component | Verification Strategy | Test Status |
|---|---|---|:---:|
| **Wire Protocol** | `BinaryProtocolCodec`, `AnnouncementCodec`, `FragmentCodec` | Roundtrip binary vector serialization, endianness checks, unknown packet relaying | ✅ Verified |
| **Cryptography** | `CryptographyAdapter`, `NoiseSessionManager` | Official Noise test vectors, ChaCha20-Poly1305 AEAD, replay sliding window | ✅ Verified |
| **Mesh Engine** | `MeshEngine`, `SeenPacketCache`, `MessageRouter` | 10-node headless virtual mesh test, controlled flooding, jitter, loop suppression | ✅ Verified |
| **Store-and-Forward** | `CourierService`, `CourierModule` | Spray-and-wait DTN delivery upon simulated peer proximity | ✅ Verified |
| **Security & Privacy** | `TokenBucketRateLimiter`, Phone Commitments, Forensic Wipe | RF flood throttling, domain-separated commitment matching, disk shredding | ✅ Verified |
| **Audio Engine** | `VoiceService`, `VoiceMessageModule`, `WaveformPlayer` | AAC-LC compression, fragment reassembly, audio playback state | ✅ Verified |
| **Persistence** | `AppDatabase` (SQLite) | `PRAGMA secure_delete = ON` verification, table migrations, CRUD lifecycles | ✅ Verified |
| **Dual Transport** | Native BLE (`MethodChannel`) + Nostr WebSocket Relays | Platform channel message serialization, NIP-01/04/44 Nostr client tests | ✅ Verified |
