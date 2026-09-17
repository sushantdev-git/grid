import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'transport_badge.dart';
import 'voice_bubble_content.dart';

/// Position of a message within a grouped consecutive cluster from the same sender.
enum BubblePosition {
  single,
  first,
  middle,
  last,
}

/// Minimalist chat bubble supporting adaptive corner clustering,
/// E2EE lock indicators, transport badges, and delivery states.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final BubblePosition position;
  final bool showHeader;

  const MessageBubble({
    super.key,
    required this.message,
    this.position = BubblePosition.single,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _buildSystemBubble(context);
    }

    final isOutgoing = message.isOutgoing;
    final bubbleColor = isOutgoing ? AppTheme.outgoingBubble : AppTheme.incomingBubble;
    final align = isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final borderRadius = _computeBorderRadius(isOutgoing);

    final timeString =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    final verticalPadding = (position == BubblePosition.middle || position == BubblePosition.last) ? 1.5 : 3.5;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
              border: Border.all(
                color: AppTheme.darkBorderSubtle,
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isOutgoing && showHeader) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.senderNickname,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      TransportBadge(medium: message.medium, isCompact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (message.isVoice)
                  VoiceBubbleContent(message: message)
                else
                  Text(
                    message.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEncrypted) ...[
                      const Icon(Icons.lock, size: 11, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      timeString,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    if (isOutgoing) ...[
                      const SizedBox(width: 4),
                      _buildDeliveryIcon(message.deliveryStatus),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BorderRadius _computeBorderRadius(bool isOutgoing) {
    const double large = 18.0;
    const double small = 4.0;

    if (isOutgoing) {
      switch (position) {
        case BubblePosition.single:
          return const BorderRadius.only(
            topLeft: Radius.circular(large),
            topRight: Radius.circular(large),
            bottomLeft: Radius.circular(large),
            bottomRight: Radius.circular(small),
          );
        case BubblePosition.first:
          return const BorderRadius.only(
            topLeft: Radius.circular(large),
            topRight: Radius.circular(large),
            bottomLeft: Radius.circular(large),
            bottomRight: Radius.circular(small),
          );
        case BubblePosition.middle:
          return const BorderRadius.only(
            topLeft: Radius.circular(large),
            topRight: Radius.circular(small),
            bottomLeft: Radius.circular(large),
            bottomRight: Radius.circular(small),
          );
        case BubblePosition.last:
          return const BorderRadius.only(
            topLeft: Radius.circular(large),
            topRight: Radius.circular(small),
            bottomLeft: Radius.circular(large),
            bottomRight: Radius.circular(large),
          );
      }
    } else {
      switch (position) {
        case BubblePosition.single:
          return const BorderRadius.only(
            topLeft: Radius.circular(large),
            topRight: Radius.circular(large),
            bottomLeft: Radius.circular(small),
            bottomRight: Radius.circular(large),
          );
        case BubblePosition.first:
          return const BorderRadius.only(
            topLeft: Radius.circular(large),
            topRight: Radius.circular(large),
            bottomLeft: Radius.circular(small),
            bottomRight: Radius.circular(large),
          );
        case BubblePosition.middle:
          return const BorderRadius.only(
            topLeft: Radius.circular(small),
            topRight: Radius.circular(large),
            bottomLeft: Radius.circular(small),
            bottomRight: Radius.circular(large),
          );
        case BubblePosition.last:
          return const BorderRadius.only(
            topLeft: Radius.circular(small),
            topRight: Radius.circular(large),
            bottomLeft: Radius.circular(large),
            bottomRight: Radius.circular(large),
          );
      }
    }
  }

  Widget _buildSystemBubble(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.systemBubble,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.darkBorderSubtle),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryIcon(MessageDeliveryStatus status) {
    switch (status) {
      case MessageDeliveryStatus.sending:
        return const Icon(Icons.access_time, size: 12, color: AppTheme.textMuted);
      case MessageDeliveryStatus.sent:
        return const Icon(Icons.done, size: 13, color: AppTheme.textSecondary);
      case MessageDeliveryStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: AppTheme.textPrimary);
      case MessageDeliveryStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: AppTheme.panicRed);
    }
  }
}
