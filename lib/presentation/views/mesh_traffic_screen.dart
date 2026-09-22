import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/bitchat_coordinator.dart';
import '../../domain/entities/mesh_traffic_entry.dart';
import '../state/mesh_traffic_notifier.dart';
import '../state/peers_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/transport_badge.dart';

/// Interactive telemetry console displaying live mesh packet forwarding,
/// anonymous hop distances, rate-limiting drop events, and active traceroute probes.
class MeshTrafficScreen extends ConsumerStatefulWidget {
  const MeshTrafficScreen({super.key});

  @override
  ConsumerState<MeshTrafficScreen> createState() => _MeshTrafficScreenState();
}

class _MeshTrafficScreenState extends ConsumerState<MeshTrafficScreen> {
  void _openTracerouteDialog() {
    final peersState = ref.read(peersProvider);
    final peers = peersState.allPeers;
    final textCtrl = TextEditingController();
    String? selectedPeerId = peers.isNotEmpty ? peers.first.peerId : null;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.darkCardElevated,
              shape: const RoundedRectangleBorder(
                borderRadius: AppTheme.squircleLarge,
                side: BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
              ),
              title: const Row(
                children: [
                  Icon(Icons.alt_route_rounded, color: AppTheme.bleMeshBlue, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Diagnostic Traceroute',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Transmit an active multi-hop ping probe to measure exact hop count and roundtrip latency to a target mesh node.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  if (peers.isNotEmpty) ...[
                    const Text(
                      'DISCOVERED PEERS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedPeerId,
                          isExpanded: true,
                          dropdownColor: AppTheme.darkCardElevated,
                          items: peers.map((p) {
                            return DropdownMenuItem<String>(
                              value: p.peerId,
                              child: Text(
                                '${p.nickname} (${p.shortPeerId})',
                                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedPeerId = val;
                                textCtrl.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text('— OR ENTER PEER ID HEX —', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: textCtrl,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontFamily: 'Courier'),
                    decoration: InputDecoration(
                      hintText: 'e.g. 7f3a8b2c...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.darkCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
                      ),
                    ),
                    onChanged: (val) {
                      if (val.trim().isNotEmpty && selectedPeerId != null) {
                        setDialogState(() => selectedPeerId = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    foregroundColor: AppTheme.onPrimaryAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final targetRaw = textCtrl.text.trim().isNotEmpty ? textCtrl.text.trim() : (selectedPeerId ?? '');
                    final cleanHex = targetRaw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
                    if (cleanHex.isEmpty) return;

                    Navigator.pop(dialogCtx);
                    final targetBytes = Uint8List.fromList(
                      List.generate(
                        cleanHex.length ~/ 2,
                        (i) => int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16),
                      ),
                    );

                    final coordinator = ref.read(bitchatCoordinatorProvider);
                    if (coordinator != null) {
                      await coordinator.sendTraceProbe(recipientId: targetBytes);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('🔍 Traceroute probe dispatched to @${cleanHex.substring(0, cleanHex.length.clamp(0, 8))}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Send Probe'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final traffic = ref.watch(meshTrafficProvider);
    final notifier = ref.read(meshTrafficProvider.notifier);
    final entries = traffic.filteredEntries;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Traffic Inspector',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: traffic.isPaused ? Colors.amber : AppTheme.verifiedGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  traffic.isPaused ? 'PAUSED' : 'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: traffic.isPaused ? Colors.amber : AppTheme.verifiedGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Traceroute Probe',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.alt_route_rounded, size: 20, color: AppTheme.textPrimary),
            onPressed: _openTracerouteDialog,
          ),
          IconButton(
            tooltip: traffic.isPaused ? 'Resume Feed' : 'Pause Feed',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              traffic.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
              color: AppTheme.textPrimary,
            ),
            onPressed: () => notifier.togglePause(),
          ),
          IconButton(
            tooltip: 'Clear Feed',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.textSecondary),
            onPressed: () => notifier.clear(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Top Metrics Bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricTile('TOTAL', '${traffic.totalCount}', AppTheme.textPrimary),
                _buildDivider(),
                _buildMetricTile('RELAYED', '${traffic.relayedCount}', AppTheme.bleMeshBlue),
                _buildDivider(),
                _buildMetricTile('INBOUND', '${traffic.inboundCount}', AppTheme.verifiedGreen),
                _buildDivider(),
                _buildMetricTile('DROPPED', '${traffic.droppedCount}', AppTheme.panicRed),
              ],
            ),
          ),

          // Filter Chips Horizontal Scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'All (${traffic.totalCount})',
                  isSelected: traffic.filter == MeshTrafficFilter.all,
                  onSelected: () => notifier.setFilter(MeshTrafficFilter.all),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Relayed (${traffic.relayedCount})',
                  isSelected: traffic.filter == MeshTrafficFilter.relayed,
                  onSelected: () => notifier.setFilter(MeshTrafficFilter.relayed),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Inbound (${traffic.inboundCount})',
                  isSelected: traffic.filter == MeshTrafficFilter.inbound,
                  onSelected: () => notifier.setFilter(MeshTrafficFilter.inbound),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Outbound (${traffic.outboundCount})',
                  isSelected: traffic.filter == MeshTrafficFilter.outbound,
                  onSelected: () => notifier.setFilter(MeshTrafficFilter.outbound),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Dropped (${traffic.droppedCount})',
                  isSelected: traffic.filter == MeshTrafficFilter.dropped,
                  onSelected: () => notifier.setFilter(MeshTrafficFilter.dropped),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Main Packet Stream List
          Expanded(
            child: entries.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _buildEntryCard(entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'Courier',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      color: AppTheme.darkBorderSubtle,
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAccent : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : AppTheme.darkBorderSubtle,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppTheme.onPrimaryAccent : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard(MeshTrafficEntry entry) {
    Color dirColor;
    IconData dirIcon;
    String dirLabel;

    switch (entry.direction) {
      case MeshTrafficDirection.inbound:
        dirColor = AppTheme.verifiedGreen;
        dirIcon = Icons.arrow_downward_rounded;
        dirLabel = 'IN';
        break;
      case MeshTrafficDirection.outbound:
        dirColor = AppTheme.primaryAccent;
        dirIcon = Icons.arrow_upward_rounded;
        dirLabel = 'OUT';
        break;
      case MeshTrafficDirection.relayed:
        dirColor = AppTheme.bleMeshBlue;
        dirIcon = Icons.sync_alt_rounded;
        dirLabel = 'RELAY';
        break;
      case MeshTrafficDirection.dropped:
        dirColor = AppTheme.panicRed;
        dirIcon = Icons.block_rounded;
        dirLabel = 'DROP';
        break;
    }

    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}.${(entry.timestamp.millisecond ~/ 100)}';

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.direction == MeshTrafficDirection.dropped
              ? AppTheme.panicRed.withValues(alpha: 0.25)
              : AppTheme.darkBorderSubtle,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Direction pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dirColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: dirColor.withValues(alpha: 0.3), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(dirIcon, size: 10, color: dirColor),
                    const SizedBox(width: 3),
                    Text(
                      dirLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: dirColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Message Type Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.darkCardElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.6),
                ),
                child: Text(
                  entry.type.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Hop Counter
              Text(
                '${entry.hops}h (ttl ${entry.ttl})',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                ),
              ),

              const Spacer(),

              // Timestamp
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Routing line: @sender -> @recipient or broadcast
          Row(
            children: [
              Text(
                '@${entry.shortSenderId}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded, size: 11, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                entry.recipientId != null ? '@${entry.shortRecipientId}' : 'broadcast',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: entry.recipientId != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontFamily: 'Courier',
                ),
              ),
              const Spacer(),
              TransportBadge(medium: entry.medium, isCompact: true),
              const SizedBox(width: 6),
              Text(
                '${entry.payloadLength}B',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),

          if (entry.summary.isNotEmpty || entry.dropReason != null) ...[
            const SizedBox(height: 6),
            Text(
              entry.dropReason != null
                  ? '⚠️ Dropped: ${entry.dropReason}'
                  : entry.summary,
              style: TextStyle(
                fontSize: 11,
                color: entry.dropReason != null ? AppTheme.panicRed : AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.radar_rounded, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 12),
          Text(
            'Listening for Mesh Telemetry...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Packets traversing the BLE mesh radio, relays, and diagnostic pings will stream here in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
