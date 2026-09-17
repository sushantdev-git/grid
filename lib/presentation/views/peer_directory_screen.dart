import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/bitchat_coordinator.dart';
import '../state/identity_state.dart';
import '../state/peers_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/three_d_scan_visualizer.dart';
import '../widgets/transport_badge.dart';
import 'chat_screen.dart';
import 'safety_verification_dialog.dart';
import '../models/peer_model.dart';

/// Screen listing active discovered mesh peers with signal meters, hop counts, and safety statuses.
/// Supports live search by nickname, phone number, or peer ID prefix.
class PeerDirectoryScreen extends ConsumerStatefulWidget {
  const PeerDirectoryScreen({super.key});

  @override
  ConsumerState<PeerDirectoryScreen> createState() => _PeerDirectoryScreenState();
}

class _PeerDirectoryScreenState extends ConsumerState<PeerDirectoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _isScanning = false;
  Timer? _scanTimer;
  Timer? _scanBurstTimer;

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanBurstTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    final coordinator = ref.read(bitchatCoordinatorProvider);
    if (coordinator != null) {
      if (!coordinator.isStarted) {
        await coordinator.start();
      }
      await coordinator.startScan();
    }

    // Broadcast presence burst periodically every 1.5 seconds during scan
    _scanBurstTimer?.cancel();
    _scanBurstTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      ref.read(bitchatCoordinatorProvider)?.broadcastPresence();
    });

    // Conclude scan automatically after 10 seconds
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 10), () {
      _stopScan(showNotification: true);
    });
  }

  void _stopScan({bool showNotification = false}) {
    _scanTimer?.cancel();
    _scanBurstTimer?.cancel();
    if (!mounted) return;
    final wasScanning = _isScanning;
    setState(() => _isScanning = false);

    if (wasScanning && showNotification) {
      final peerCount = ref.read(peersProvider).allPeers.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            peerCount > 0
                ? 'Scan complete. Discovered $peerCount mesh ${peerCount == 1 ? 'peer' : 'peers'}.'
                : 'Scan complete. No new peers detected in range.',
          ),
          backgroundColor: AppTheme.darkCardElevated,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isPhoneMatch(dynamic peer) {
    if (_query.isEmpty) return false;
    if (peer is PeerModel) {
      return peer.matchesPhoneCommitment(_query);
    }
    return false;
  }


  /// Returns true if the peer matches the current search query.
  /// Matches on nickname prefix, phone number (digits-only substring), or peer ID prefix.
  bool _matches(peer) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    // 1. Nickname (case-insensitive prefix)
    if (peer.nickname.toLowerCase().contains(q)) return true;
    // 2. Peer ID (prefix)
    if (peer.peerId.toLowerCase().startsWith(q)) return true;
    // 3. Phone number — compare digits only so "+91 98765" matches "9198765"
    if (_isPhoneMatch(peer)) return true;
    return false;
  }

    void _copyId(BuildContext context, String id) {
      Clipboard.setData(ClipboardData(text: id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Peer ID copied to clipboard'),
          backgroundColor: AppTheme.darkCardElevated,
          duration: Duration(seconds: 2),
        ),
      );
    }

    @override
    Widget build(BuildContext context) {
      final identity = ref.watch(identityProvider);
      final peersState = ref.watch(peersProvider);
      final allPeers = peersState.allPeers;
      final filtered = allPeers.where(_matches).toList();

      // Format peer ID as groups of 4: C0E6 4DED E5F6 0718
      String formatId(String hex) {
        final upper = hex.toUpperCase();
        final buf = StringBuffer();
        for (int i = 0; i < upper.length; i++) {
          if (i > 0 && i % 4 == 0) buf.write(' ');
          buf.write(upper[i]);
        }
        return buf.toString();
      }

      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovered Peers', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (_isScanning)
              TextButton.icon(
                onPressed: () => _stopScan(showNotification: true),
                icon: const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.verifiedGreen,
                  ),
                ),
                label: const Text(
                  'Scanning',
                  style: TextStyle(
                    color: AppTheme.verifiedGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.radar, color: AppTheme.textPrimary),
                tooltip: 'Scan for peers',
                onPressed: _startScan,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── Your Identity Card ──────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: AppTheme.squircleLarge,
                border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryAccent,
                      borderRadius: AppTheme.squircleMedium,
                    ),
                    child: Center(
                      child: Text(
                        identity.nickname.isNotEmpty ? identity.nickname[0].toUpperCase() : '?',
                        style: const TextStyle(color: AppTheme.onPrimaryAccent, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                identity.nickname,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accentSubtle,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                              ),
                            ),
                          ],
                      ),
                      const SizedBox(height: 6),
                      // Formatted peer ID with copy button
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatId(identity.peerIdHex),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _copyId(context, identity.peerIdHex),
                            child: const Tooltip(
                              message: 'Copy peer ID',
                              child: Icon(Icons.copy, size: 14, color: AppTheme.textMuted),
                            ),
                          ),
                        ],
                      ),
                      // Phone number (if set)
                      if (identity.phoneNumber != null && identity.phoneNumber!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 13, color: AppTheme.textSecondary),
                            const SizedBox(width: 5),
                            Text(
                              identity.phoneNumber!,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Edit profile button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.textSecondary),
                  tooltip: 'Edit profile',
                  onPressed: () => EditProfileSheet.show(context),
                ),
              ],
            ),
          ),

          // ── 3D Pulsating Scan Visualizer (while scanning) ───────────────
          if (_isScanning)
            ThreeDScanVisualizer(
              peerCount: filtered.length,
              onStopScan: () => _stopScan(showNotification: true),
            ),

          // ── Search Bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or peer ID…',
                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: AppTheme.darkCard,
                border: const OutlineInputBorder(
                  borderRadius: AppTheme.pill,
                  borderSide: BorderSide(color: AppTheme.darkBorderSubtle),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: AppTheme.pill,
                  borderSide: BorderSide(color: AppTheme.darkBorderSubtle),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: AppTheme.pill,
                  borderSide: BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                ),
              ),
            ),
          ),

          // ── Nearby Nodes ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'NEARBY NODES IN RADIO RANGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  Text(
                    '${filtered.length} of ${allPeers.length}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),

          if (allPeers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radar_outlined, size: 44, color: AppTheme.textMuted),
                    const SizedBox(height: 12),
                    const Text(
                      'No mesh peers discovered yet.\nPeers within Bluetooth Low Energy radio range (~30m) or Nostr internet relays will appear here automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
                    ),
                    if (!_isScanning) ...[
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.sensors, size: 16, color: AppTheme.onPrimaryAccent),
                        label: const Text(
                          'Scan for Nearby Peers',
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.onPrimaryAccent),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: AppTheme.onPrimaryAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: const RoundedRectangleBorder(borderRadius: AppTheme.pill),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Center(
                child: Text(
                  'No peers match "$_query"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
                ),
              ),
            )
          else
            ...filtered.map((peer) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: AppTheme.squircleMedium,
                    border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                  ),
                  child: Icon(
                    peer.isDirectNeighbor ? Icons.bluetooth : Icons.router,
                    color: AppTheme.bleMeshBlue,
                    size: 20,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      peer.nickname,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (peer.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 15, color: AppTheme.verifiedGreen),
                    ],
                    const SizedBox(width: 8),
                    TransportBadge(medium: peer.medium, isCompact: true),
                  ],
                ),
                subtitle: Text(
                  _isPhoneMatch(peer)
                      ? 'Phone match'
                      : (peer.isDirectNeighbor ? 'Nearby' : '${peer.hops}-hop relay'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _isPhoneMatch(peer) ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    peer.isVerified ? Icons.verified_user : Icons.shield_outlined,
                    color: peer.isVerified ? AppTheme.verifiedGreen : AppTheme.textSecondary,
                  ),
                  tooltip: 'Safety Numbers',
                  onPressed: () => SafetyVerificationSheet.show(context, peer.peerId),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(channelOrPeerId: peer.peerId),
                    ),
                  );
                },
              );
            }),
        ],
      ),
    );
  }
}
