import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'transport_badge.dart';

/// Modal bottom sheet displaying delivery confirmation, hop telemetry,
/// and cryptographic security details for a specific chat message.
class MessageDetailsSheet extends StatelessWidget {
  final ChatMessage message;

  const MessageDetailsSheet({
    super.key,
    required this.message,
  });

  /// Displays the modal sheet for the given [message].
  static Future<void> show(BuildContext context, ChatMessage message) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkCardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MessageDetailsSheet(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final isDelivered = message.deliveryStatus == MessageDeliveryStatus.delivered;
    final hopCount = message.hops;

    String hopDescription;
    if (isOutgoing) {
      hopDescription = 'Originated locally (initial TTL: 7)';
    } else if (hopCount == 0) {
      hopDescription = 'Direct link transmission (0 hops)';
    } else if (hopCount == 1) {
      hopDescription = '1-Hop Direct Neighbor';
    } else {
      hopDescription = '$hopCount-Hop Mesh Relay Route';
    }

    final formattedTimestamp =
        '${message.timestamp.year}-${message.timestamp.month.toString().padLeft(2, '0')}-${message.timestamp.day.toString().padLeft(2, '0')} '
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}:${message.timestamp.second.toString().padLeft(2, '0')}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.primaryAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Message Telemetry',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Section 1: Delivery Status Card
            _buildCard(
              icon: isOutgoing
                  ? (isDelivered ? Icons.done_all : Icons.check)
                  : Icons.mark_email_read_outlined,
              iconColor: (isOutgoing && isDelivered) ? AppTheme.verifiedGreen : AppTheme.primaryAccent,
              title: isOutgoing ? 'Delivery Confirmation' : 'Inbound Receipt',
              subtitle: isOutgoing
                  ? (isDelivered
                      ? 'Delivered (E2EE ACK received from recipient)'
                      : 'Sent (Awaiting cryptographic delivery ACK)')
                  : 'Received and verified on local node',
              extra: Row(
                children: [
                  Text(
                    formattedTimestamp,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier',
                    ),
                  ),
                  const Spacer(),
                  if (isOutgoing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isDelivered ? AppTheme.verifiedGreen : AppTheme.textSecondary)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (isDelivered ? AppTheme.verifiedGreen : AppTheme.textSecondary)
                              .withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isDelivered ? 'DELIVERED' : 'SENT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isDelivered ? AppTheme.verifiedGreen : AppTheme.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Section 2: Mesh Distance & Hops Card
            _buildCard(
              icon: Icons.alt_route_rounded,
              iconColor: AppTheme.bleMeshBlue,
              title: 'Hop Distance Telemetry',
              subtitle: hopDescription,
              extra: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isOutgoing
                          ? 'Zero intermediate relay exposure'
                          : 'Mathematical hop counter (7 - TTL). Intermediate identities masked.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Section 3: Cryptographic Security Card
            _buildCard(
              icon: message.isEncrypted ? Icons.lock_outline : Icons.public,
              iconColor: message.isEncrypted ? AppTheme.verifiedGreen : AppTheme.textSecondary,
              title: message.isEncrypted ? 'Noise_XX E2EE' : 'Public Channel',
              subtitle: message.isEncrypted
                  ? 'ChaCha20-Poly1305 with forward secrecy & verified safety key'
                  : 'Cleartext broadcast across local mesh flood domain',
              extra: null,
            ),
            const SizedBox(height: 10),

            // Section 4: Transport & Identifier Card
            _buildCard(
              icon: Icons.fingerprint,
              iconColor: AppTheme.nostrPurple,
              title: 'Transport & Fingerprint',
              subtitle: 'Message ID: ${message.id}',
              extra: Row(
                children: [
                  TransportBadge(medium: message.medium, isCompact: false),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message ID copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 12, color: AppTheme.textSecondary),
                        SizedBox(width: 4),
                        Text(
                          'Copy ID',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? extra,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.darkBorderSubtle,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
          if (extra != null) ...[
            const SizedBox(height: 8),
            extra,
          ],
        ],
      ),
    );
  }
}
