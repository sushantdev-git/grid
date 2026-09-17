# Grid: Feature Research & Roadmap

> Comprehensive feature proposals for **Grid**, a decentralized, peer-to-peer mesh & Nostr messenger.  
> Compiled based on analysis of the state-of-the-art in off-grid and privacy communication protocols (BitChat, Briar, Berty, Meshtastic, SimpleX, Signal, Keet).

---

## 🧭 Strategic Landscape & Design Philosophy

Grid is built on three core pillars:
1. **Zero-Infrastructure Sovereignty**: Fully functional without cellular coverage, internet, central servers, or accounts.
2. **Forensic Privacy & Plausible Deniability**: Zero metadata trails, strong forward secrecy (`Noise_XX`), and instant zeroization.
3. **Dual-Transport Continuity**: Seamlessly transitions between hyper-local Bluetooth Low Energy (BLE) mesh and global Nostr relay bridges.

The features below are organized into **five thematic tiers**, prioritized by utility, feasibility, and alignment with Grid’s minimalist aesthetic.

---

## 📋 Feature Catalog Matrix

| # | Feature | Category | Impact | Complexity | Recommended Next |
|---|---|---|---|---|---|
| **1** | **Off-Grid Push-to-Talk (PTT) Voice Notes** | Rich Media | 🟢 Very High | 🟡 Medium | ⭐ Top Pick |
| **2** | **Offline QR Code Fast Pairing & Safety Verification** | Privacy / UX | 🟢 Very High | 🟢 Low | ⭐ Top Pick |
| **3** | **Disappearing / Ephemeral Messages (Self-Destruct)** | Privacy / Security | 🟢 Very High | 🟢 Low | ⭐ Top Pick |
| **4** | **Delivery Receipts & Packet Hop Traceroute** | Network / Telemetry | 🟡 High | 🟢 Low | ⭐ Top Pick |
| **5** | **Local Wi-Fi / LAN Multicast Transport (mDNS/UDP)** | Transports | 🟢 Very High | 🟡 Medium | High Priority |
| **6** | **Emergency SOS Distress Beacon** | Safety / Crisis | 🟢 Very High | 🟢 Low | High Priority |
| **7** | **Offline Chunked Image & File Transfer** | Rich Media | 🟡 High | 🔴 High | Medium Term |
| **8** | **Duress PIN & Decoy Mode (Plausible Deniability)** | OpSec / Security | 🟢 Very High | 🟡 Medium | Medium Term |
| **9** | **Encrypted Database at Rest (SQLCipher / AES-GCM)** | OpSec / Security | 🟢 Very High | 🟡 Medium | Medium Term |
| **10** | **Epidemic Store-and-Forward (Mule / DTN Routing)** | Mesh Core | 🟢 Very High | 🔴 High | Medium Term |
| **11** | **Mesh Network Topology & Signal Heatmap** | UX / Telemetry | 🟡 High | 🟡 Medium | Fun & Useful |
| **12** | **Anti-Tracking Ephemeral MAC & Peer ID Rotation** | OpSec / Privacy | 🟡 High | 🟡 Medium | Privacy Focus |
| **13** | **LoRa Hardware Bridge (Meshtastic Companion)** | Transports | 🟢 Very High | 🔴 High | Long Term |
| **14** | **Mesh-to-Nostr Automatic Internet Gateway** | Nostr Bridge | 🟡 High | 🟡 Medium | Long Term |
| **15** | **Offline P2P Cashu / Bitcoin Ecash Tokens** | Micro-economy | 🟡 Medium | 🔴 High | Exploratory |

---

## 🚀 Detailed Feature Specifications

---

### Tier 1: Immediate High-Impact Features (Recommended Next)

#### 1. Off-Grid Push-to-Talk (PTT) Voice Notes
* **Why it matters**: In tactical, disaster, or low-light situations, typing on a phone keyboard is difficult. Voice notes give Grid true walkie-talkie utility off-grid.
* **How it works**:
  - Record ultra-low bitrate compressed audio using Opus, AMR-NB, or Codec2 (1.2 kbps to 8 kbps).
  - A 5-second voice snippet compresses down to **~1.5 KB**—small enough to chunk into 3–4 BLE packets with sliding-window reassembly.
  - Floating microphone capsule on the composer: tap or hold to record with live waveform feedback.
  - In-bubble minimal audio player with play/pause and progress scrub.
* **Architecture Touchpoints**:
  - Domain: `VoiceMessageCodec` plugin implementing `ProtocolFeatureModule`.
  - Infrastructure: Audio recorder & player with in-memory scrubbing.
  - UI: Micro-waveform visualizer matching AppTheme squircle cards.

#### 2. Offline QR Code Fast Pairing & In-Person Safety Verification
* **Why it matters**: Zero-RF contact exchange. Eliminates man-in-the-middle (MITM) risks by letting two nearby users physically pair their devices without sending identifying metadata over the air.
* **How it works**:
  - **Show QR**: Displays a high-density, animated/static QR code encoding the node's static Noise public key (`X25519`), signing public key (`Ed25519`), nickname, and optional phone number.
  - **Scan QR**: Built-in camera scanner reads the peer's QR, verifies the fingerprint safety number, marks the peer as `isVerified = true` with a green shield, and adds them to the directory.
  - Optional NFC tap-to-share between Android devices.
* **Architecture Touchpoints**:
  - Presentation: `QrPairingSheet` with `mobile_scanner` or `qr_flutter`.
  - State: `PeersNotifier.markVerified(peerId, true)` persisted directly in `AppDatabase`.

#### 3. Disappearing / Ephemeral Messages (Self-Destruct Timer)
* **Why it matters**: Prevents chats from accumulating on devices that might be confiscated, inspected, or lost.
* **How it works**:
  - User can toggle timer per channel or per private conversation: **Off**, **30 seconds**, **5 minutes**, **1 hour**, **24 hours**.
  - Messages display a subtle countdown indicator / ring.
  - When the timer fires:
    1. Message row is deleted from the local SQLite `messages` table and vacuumed.
    2. An ephemeral wire packet `MessageType.retract` or tombstone is broadcast to notify the recipient node to scrub their copy.
* **Architecture Touchpoints**:
  - Database: Add `expires_at` column to `messages` table in `AppDatabase`.
  - Application: Background cleanup timer executing `DELETE FROM messages WHERE expires_at < ?`.

#### 4. Delivery Receipts & Hop Traceroute Visualizer
* **Why it matters**: In an asynchronous mesh network, users want to know if their message actually hopped across nodes and reached the destination peer.
* **How it works**:
  - State progression: `Sending` (clock) ➔ `Relayed via N hops` (routing node icon) ➔ `Delivered` (single check) ➔ `Read` (double check).
  - Long-pressing any message reveals a **"Packet Telemetry"** bottom sheet:
    - Transport medium used (BLE Mesh, Nostr Relay, Local LAN).
    - Hop count and latency ($ms$).
    - Packet relay trace showing intermediate node IDs and signal strengths (RSSI).
* **Architecture Touchpoints**:
  - Wire Codec: Lightweight 16-byte ACK packet (`MessageType.ack`).
  - Presentation: Interactive packet traceroute modal.

---

### Tier 2: Transports & Network Expansion

#### 5. Local Wi-Fi / LAN Multicast Transport (UDP Broadcast / mDNS)
* **Why it matters**: Bluetooth Low Energy is limited in throughput (~1-2 Mbps) and payload size. When multiple devices are on the same local Wi-Fi router or a phone's portable hotspot (even with **NO internet connection / during ISP shutdown**), local Wi-Fi multicast enables 50–100 Mbps transfers with sub-10ms latency.
* **How it works**:
  - Implement a new `LanMulticastAdapter` conforming to `TransportPort`.
  - Discovers peers via mDNS / Bonjour service `_grid._udp` and broadcasts packets via UDP multicast (`239.255.0.1:4242`).
  - Works simultaneously alongside BLE and Nostr in `MessageRouter`.
* **Architecture Touchpoints**:
  - Hexagonal Port: Plug into `TransportPort` without modifying `MeshEngine`.

#### 6. Emergency SOS Distress Beacon
* **Why it matters**: Mesh networks are critical during earthquakes, floods, outages, or backcountry emergencies where normal cellular towers fail.
* **How it works**:
  - One-tap or 5-press hardware power button SOS activation.
  - Floods the mesh with a high-priority emergency packet (`MessageType.emergency`).
  - Contains optional GPS coordinates, altitude, battery percentage, timestamp, and short medical/distress note.
  - When received by any nearby device:
    - Vibrates and plays a distinctive alert tone (even if phone is in silent mode).
    - Displays a prominent red Emergency Banner with distance, bearing, and geohash.
    - Nodes automatically relay SOS beacons with infinite priority and maximum TTL.
* **Architecture Touchpoints**:
  - Wire protocol: `MessageType.emergency` packet with highest relay priority in `MeshEngine`.

#### 7. Epidemic Store-and-Forward (Data Mule / Delay-Tolerant Networking)
* **Why it matters**: Currently, if Peer A and Peer C are never within direct range at the same time, messages cannot be delivered. Store-and-forward enables Peer B (who walks between them) to act as a physical "data mule".
* **How it works**:
  - Messages destined for an offline peer are wrapped in an encrypted bundle (recipient public key).
  - Intermediate nodes carry these bundles in an encrypted transit vault (`bundles` table in SQLite) with a strict TTL (e.g. 72 hours).
  - When a node detects presence announcements for the destination peer, it flushes the bundle.
* **Architecture Touchpoints**:
  - Storage: New `bundles` table in `AppDatabase` with quota management (e.g. 50 MB max vault).

---

### Tier 3: Tactical Privacy & Plausible Deniability (OpSec)

#### 8. Duress PIN & Decoy Mode (Plausible Deniability)
* **Why it matters**: In hostile environments (police stops, border crossings, device theft), a user may be physically forced to unlock their app.
* **How it works**:
  - User sets two PINs: **Real PIN** and **Duress PIN**.
  - Entering the **Real PIN** opens the actual account with real messages and keys.
  - Entering the **Duress PIN** opens an isolated, realistic **Decoy Workspace** populated with fake innocuous channels (`#weather`, `#sports`) and empty DMs.
  - The real database remains fully hidden with zero UI indication that a decoy is running.
* **Architecture Touchpoints**:
  - Presentation: App lock gate in `main.dart`.
  - Database: Dual database files (`grid.db` vs `grid_decoy.db`).

#### 9. Full Database Encryption at Rest (SQLCipher / AES-GCM)
* **Why it matters**: If an attacker gets physical access to the device or performs an `adb pull / forensic extraction`, they cannot read the SQLite database without the encryption key.
* **How it works**:
  - Encrypt `grid.db` pages with AES-256 using SQLCipher or an application-level envelope key.
  - Encryption key is derived from user PIN/Passphrase using **Argon2id** and protected by Android Keystore / Apple Secure Enclave biometrics.
  - On Panic Wipe, the key in Keystore is scrubbed instantly, rendering the disk payload mathematically unrecoverable.

#### 10. Ephemeral MAC & Peer ID Anti-Tracking Rotation
* **Why it matters**: Static BLE identifiers allow adversary RF sniffing devices (e.g. in metro stations or protest zones) to track a user's physical movement.
* **How it works**:
  - Periodically (every 15–60 minutes or upon network change) rotate the local ephemeral peer ID and BLE advertisement payload.
  - Known contacts track updates through a cryptographic hash chain derived from the initial Noise handshake, while external passive sniffers see a completely new random node.

---

### Tier 4: Visualization & UX Polish

#### 11. Mesh Topology Network Map & Signal Heatmap
* **Why it matters**: Visualizing the mesh network is engaging and helps users understand their coverage, find relay nodes, and test radio distance.
* **How it works**:
  - Expand the existing Three.js 3D visualizer into a full interactive **Mesh Graph View**:
    - Nodes represented as interconnected 3D spheres with live pulsing signals.
    - Line thickness and colors based on signal strength (RSSI: Green > -70 dBm, Yellow > -85 dBm, Red > -95 dBm).
    - Shows multi-hop paths connecting your node to remote nodes.
  - Optional 2D Map View plotting geohash-tagged nodes on an offline vector map (OpenStreetMap).

#### 12. Adaptive Battery & Radio Duty-Cycling Profiles
* **Why it matters**: Continuous BLE scanning and advertising can drain smartphone batteries over extended periods.
* **How it works**:
  - Allow users to select battery profiles:
    - **Active / Tactical**: 100% duty cycle, immediate packet relay, maximum responsiveness (events, emergencies).
    - **Balanced (Default)**: Adaptive scanning (5s scan / 10s sleep), wakes up upon packet reception.
    - **Ultra Battery Saver**: Scans for 3s every 60s. Extends battery life to several days off-grid.
    - **Stealth / Silent Node**: Listen-only mode. Does not advertise presence or transmit packets, completely silent on the RF spectrum.

---

### Tier 5: External Hardware & Nostr Ecosystem

#### 13. LoRa Radio Companion Support (Meshtastic Integration)
* **Why it matters**: Bluetooth range is typically 20–50 meters. LoRa (Long Range 915/868/433 MHz) radios achieve **5 to 15+ kilometers** line-of-sight with tiny battery consumption.
* **How it works**:
  - Connect Grid via BLE to inexpensive (\$20–\$30) portable LoRa hardware (e.g. Heltec V3, LilyGO T-Beam, Seeed T1000).
  - Grid acts as the rich messaging client and routes packets through the long-range LoRa mesh.

#### 14. Automated Mesh-to-Nostr Gateway
* **Why it matters**: If 50 devices are in a subway or disaster area without cellular service, but **one device** near an exit gets 4G or Wi-Fi, that single device automatically relays messages between the offline mesh and global Nostr relays.
* **How it works**:
  - Node detecting internet connectivity advertises `gateway_capability = true` in its presence beacon.
  - Other mesh nodes route external/global messages towards the gateway node for Nostr publishing.

#### 15. Offline P2P Ecash / Lightning Micro-Payments (Cashu)
* **Why it matters**: Send bearer e-cash tokens (Cashu / Fedimint) peer-to-peer over the Bluetooth mesh without internet.
* **How it works**:
  - Cashu tokens are self-contained cryptographic strings.
  - Grid recognizes token strings in chat and renders an interactive **Ecash Gift Card** bubble.
  - Recipient claims the token offline; it syncs with the mint whenever internet is regained.

---

## 🎯 Recommended Next Steps

To build momentum while maximizing immediate user delight and tactical capability, here is the suggested immediate roadmap:

1. **Feature 1 (Off-Grid PTT Voice Memos)**: Transforms Grid from text-only into a versatile off-grid walkie-talkie.
2. **Feature 2 (Offline QR Code Pairing)**: Essential for frictionless in-person contact exchange and safety verification.
3. **Feature 3 (Disappearing Messages)**: High privacy value, clean implementation with existing SQLite architecture.
4. **Feature 4 (Delivery Receipts & Packet Traceroute)**: Immediate UX satisfaction, shows users how mesh routing actually works.
