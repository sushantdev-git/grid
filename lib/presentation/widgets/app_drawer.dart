import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/channels_notifier.dart';
import '../state/identity_state.dart';
import '../state/mesh_traffic_notifier.dart';
import '../state/panic_controller.dart';
import '../state/peers_notifier.dart';
import '../theme/app_theme.dart';
import '../views/chat_screen.dart';
import '../views/mesh_traffic_screen.dart';
import '../views/peer_directory_screen.dart';
import 'edit_profile_sheet.dart';

/// Minimalist left navigation drawer providing primary section navigation
/// (Messages, Peers, Channels) and a pinned bottom Account Tab for editing metadata.
class AppDrawer extends ConsumerWidget {
  final VoidCallback? onOpenEditProfile;
  final VoidCallback? onPanicWipe;
  final VoidCallback? onNavigateToPeers;
  final ValueChanged<String>? onNavigateToChannel;

  const AppDrawer({
    super.key,
    this.onOpenEditProfile,
    this.onPanicWipe,
    this.onNavigateToPeers,
    this.onNavigateToChannel,
  });

  void _handleOpenProfile(BuildContext context) {
    Navigator.of(context).pop(); // Close drawer first
    if (onOpenEditProfile != null) {
      onOpenEditProfile!();
    } else {
      EditProfileSheet.show(context);
    }
  }

  void _handleNavigateToPeers(BuildContext context) {
    Navigator.of(context).pop(); // Close drawer first
    if (onNavigateToPeers != null) {
      onNavigateToPeers!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PeerDirectoryScreen()),
      );
    }
  }

  void _handleNavigateToTraffic(BuildContext context) {
    Navigator.of(context).pop(); // Close drawer first
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MeshTrafficScreen()),
    );
  }

  void _handleNavigateToChannel(BuildContext context, String channel) {
    Navigator.of(context).pop(); // Close drawer first
    if (onNavigateToChannel != null) {
      onNavigateToChannel!(channel);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(channelOrPeerId: channel)),
      );
    }
  }

  void _handlePanicWipe(BuildContext context, WidgetRef ref) {
    Navigator.of(context).pop(); // Close drawer first
    if (onPanicWipe != null) {
      onPanicWipe!();
    } else {
      _showDefaultPanicDialog(context, ref);
    }
  }

  void _showDefaultPanicDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCardElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTheme.squircleLarge,
          side: BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.panicRed, size: 24),
            SizedBox(width: 8),
            Text('Emergency Panic Wipe', style: TextStyle(color: AppTheme.panicRed, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will instantaneously zeroize and delete all in-memory message feeds, wipe active peer sessions, and regenerate a fresh ephemeral cryptographic identity.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.panicRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(panicControllerProvider).executePanicWipe();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Panic wipe completed: all keys and timelines zeroized.'),
                    backgroundColor: AppTheme.panicRed,
                  ),
                );
              }
            },
            child: const Text('Execute Wipe'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider);
    final peersState = ref.watch(peersProvider);
    final channelsState = ref.watch(channelsProvider);
    final channels = channelsState.joinedChannels.toList()..sort();

    final peerIdShort = identity.peerIdHex.isNotEmpty
        ? (identity.peerIdHex.length >= 8 ? identity.peerIdHex.substring(0, 8) : identity.peerIdHex)
        : 'Unknown';

    final secondaryInfo = (identity.phoneNumber != null && identity.phoneNumber!.isNotEmpty)
        ? identity.phoneNumber!
        : 'ID: $peerIdShort';

    return Drawer(
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
        side: BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Top Branding
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.darkCardElevated,
                      borderRadius: AppTheme.squircleMedium,
                      border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                    ),
                    child: const Icon(
                      Icons.hub_outlined,
                      size: 20,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Grid',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.verifiedGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Flexible(
                              child: Text(
                                'Mesh Network Online',
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.darkBorderSubtle, height: 1, thickness: 0.8),

            // Navigation List Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // Messages Section
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: AppTheme.darkCardElevated,
                    leading: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.textPrimary, size: 20),
                    title: const Text(
                      'Messages',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 4),

                  // Discovered Peers Section
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.radar_rounded, color: AppTheme.textSecondary, size: 20),
                    title: const Text(
                      'Peers',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCardElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                      ),
                      child: Text(
                        '${peersState.allPeers.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    onTap: () => _handleNavigateToPeers(context),
                  ),
                  const SizedBox(height: 4),

                  // Mesh Traffic Inspector Section
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.troubleshoot_rounded, color: AppTheme.textSecondary, size: 20),
                    title: const Text(
                      'Traffic Inspector',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    trailing: Consumer(
                      builder: (context, ref, _) {
                        final traffic = ref.watch(meshTrafficProvider);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCardElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                          ),
                          child: Text(
                            '${traffic.entries.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        );
                      },
                    ),
                    onTap: () => _handleNavigateToTraffic(context),
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: AppTheme.darkBorderSubtle, height: 1, thickness: 0.8),
                  const SizedBox(height: 8),

                  // Channels Header
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      'CHANNELS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),

                  // Channel Quick Links
                  ...channels.map((ch) {
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      leading: const Icon(Icons.tag_rounded, size: 18, color: AppTheme.textSecondary),
                      title: Text(
                        ch,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      onTap: () => _handleNavigateToChannel(context, ch),
                    );
                  }),
                ],
              ),
            ),

            const Divider(color: AppTheme.darkBorderSubtle, height: 1, thickness: 0.8),

            // Pinned Bottom Account Tab
            Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: AppTheme.darkCardElevated,
                borderRadius: AppTheme.squircleLarge,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _handleOpenProfile(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.squircleLarge,
                      border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                    ),
                    child: Row(
                      children: [
                        // Squircle Avatar with user initial
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryAccent,
                            borderRadius: AppTheme.squircleMedium,
                          ),
                          child: Center(
                            child: Text(
                              identity.nickname.isNotEmpty ? identity.nickname[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppTheme.onPrimaryAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Display name & phone number / peer ID
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      identity.nickname,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit_outlined, size: 12, color: AppTheme.textMuted),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                secondaryInfo,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Emergency panic button or quick settings
                        IconButton(
                          icon: const Icon(Icons.emergency_outlined, color: AppTheme.panicRed, size: 20),
                          tooltip: 'Emergency Panic Wipe',
                          onPressed: () => _handlePanicWipe(context, ref),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
