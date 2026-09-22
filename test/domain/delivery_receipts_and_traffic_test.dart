import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/entities/mesh_traffic_entry.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/domain/services/diagnostics_module.dart';
import 'package:grid/domain/services/feature_registry.dart';
import 'package:grid/presentation/models/chat_message.dart';
import 'package:grid/presentation/state/mesh_traffic_notifier.dart';
import 'package:grid/presentation/state/timeline_notifier.dart';
import 'package:grid/presentation/utils/chat_command.dart';

void main() {
  group('ChatMessage & Delivery Receipt Telemetry', () {
    test('ChatMessage models hops and delivery status properly', () {
      final msg = ChatMessage(
        id: 'msg_1',
        senderId: 'alice_id',
        senderNickname: 'Alice',
        content: 'Hello Mesh',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        isOutgoing: true,
        isEncrypted: true,
        medium: TransportMedium.bleMesh,
        channelOrPeerId: 'bob_id',
        deliveryStatus: MessageDeliveryStatus.sent,
        hops: 2,
      );

      expect(msg.hops, 2);
      expect(msg.deliveryStatus, MessageDeliveryStatus.sent);

      final json = msg.toJson();
      expect(json['hops'], 2);
      expect(json['deliveryStatus'], 'sent');

      final restored = ChatMessage.fromJson(json);
      expect(restored.hops, 2);
      expect(restored.deliveryStatus, MessageDeliveryStatus.sent);

      final delivered = restored.copyWith(deliveryStatus: MessageDeliveryStatus.delivered);
      expect(delivered.deliveryStatus, MessageDeliveryStatus.delivered);
      expect(delivered.hops, 2);
    });

    test('TimelineNotifier marks message delivered on E2EE receipt', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(timelineProvider.notifier);

      final sentMsg = ChatMessage(
        id: 'msg_test_ack',
        senderId: 'self',
        senderNickname: 'Self',
        content: 'Testing ACK',
        timestamp: DateTime.now(),
        isOutgoing: true,
        isEncrypted: true,
        medium: TransportMedium.bleMesh,
        channelOrPeerId: 'bob_hex',
        deliveryStatus: MessageDeliveryStatus.sent,
      );

      notifier.addMessage(sentMsg);

      final initial = notifier.state.getMessages('bob_hex');
      expect(initial.length, 1);
      expect(initial.first.deliveryStatus, MessageDeliveryStatus.sent);

      // Simulates receiving E2EE delivery confirmation
      notifier.markDelivered('bob_hex', 'msg_test_ack');

      final updated = notifier.state.getMessages('bob_hex');
      expect(updated.length, 1);
      expect(updated.first.deliveryStatus, MessageDeliveryStatus.delivered);
    });

    test('Inbound packet parses structured JSON envelope with backwards compatibility', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(timelineProvider.notifier);

      // 1. Structured JSON envelope
      final envelopeJson = jsonEncode({'mid': 'custom_mid_42', 'txt': 'Hello in JSON envelope'});
      final structuredPacket = BitchatPacket(
        version: 1,
        type: MessageType.noiseEncrypted,
        ttl: 5,
        timestamp: 1700000010000,
        senderId: Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0]),
        recipientId: Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
        payload: Uint8List.fromList(utf8.encode(envelopeJson)),
      );

      notifier.handleInboundPacket(
        structuredPacket,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: 'test_peer',
          medium: TransportMedium.bleMesh,
        ),
        2, // 2 hops
      );

      const senderHex = '123456789abcdef0';
      final messages = notifier.state.getMessages(senderHex);
      expect(messages.length, 1);
      expect(messages.first.id, 'custom_mid_42');
      expect(messages.first.content, 'Hello in JSON envelope');
      expect(messages.first.hops, 2);

      // 2. Legacy raw plaintext packet
      final rawPacket = BitchatPacket(
        version: 1,
        type: MessageType.message,
        ttl: 7,
        timestamp: 1700000020000,
        senderId: Uint8List.fromList([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x11]),
        payload: Uint8List.fromList(utf8.encode('Plain old broadcast')),
      );

      notifier.handleInboundPacket(
        rawPacket,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: 'test_peer',
          medium: TransportMedium.bleMesh,
        ),
        0, // 0 hops
      );

      final meshMessages = notifier.state.getMessages('#mesh');
      expect(meshMessages.any((m) => m.content == 'Plain old broadcast' && m.hops == 0), isTrue);
    });
  });

  group('Anonymous Packet Hop Distance Telemetry', () {
    test('Calculates hop count mathematically from TTL without route header leaks', () {
      // TTL 7 -> 0 hops
      expect((7 - 7).clamp(0, 7), 0);
      // TTL 6 -> 1 hop
      expect((7 - 6).clamp(0, 7), 1);
      // TTL 5 -> 2 hops
      expect((7 - 5).clamp(0, 7), 2);
      // TTL 1 -> 6 hops
      expect((7 - 1).clamp(0, 7), 6);
      // TTL 0 -> 7 hops
      expect((7 - 0).clamp(0, 7), 7);
    });
  });

  group('DiagnosticsModule & Traceroute Ping/Pong', () {
    test('Echoes timestamp in pong when traceroute is allowed', () async {
      Uint8List? sentPongRecipient;
      Uint8List? sentPongPayload;

      final module = DiagnosticsModule(
        onSendPong: (recipientId, payload) async {
          sentPongRecipient = recipientId;
          sentPongPayload = payload;
        },
        isTraceAllowed: () => true,
      );

      final pingPayload = Uint8List(8);
      ByteData.sublistView(pingPayload).setUint64(0, 1700000000000, Endian.big);

      final senderId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final pingPacket = BitchatPacket(
        version: 1,
        type: MessageType.ping,
        ttl: 5,
        timestamp: 1700000000000,
        senderId: senderId,
        recipientId: Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]),
        payload: pingPayload,
      );

      await module.handleInboundPacket(
        pingPacket,
        const PacketContext(
          sourceLinkPeerId: 'neighbor_node',
          hops: 2,
          medium: TransportMedium.bleMesh,
        ),
      );

      expect(sentPongRecipient, senderId);
      expect(sentPongPayload, isNotNull);
      final echoedTs = ByteData.sublistView(sentPongPayload!).getUint64(0, Endian.big);
      expect(echoedTs, 1700000000000);
    });

    test('Silently drops ping when stealth mode is active (isTraceAllowed == false)', () async {
      var pongSent = false;

      final module = DiagnosticsModule(
        onSendPong: (recipientId, payload) async {
          pongSent = true;
        },
        isTraceAllowed: () => false, // Stealth Mode Active
      );

      final pingPayload = Uint8List(8);
      ByteData.sublistView(pingPayload).setUint64(0, 1700000000000, Endian.big);

      final pingPacket = BitchatPacket(
        version: 1,
        type: MessageType.ping,
        ttl: 5,
        timestamp: 1700000000000,
        senderId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        recipientId: Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]),
        payload: pingPayload,
      );

      await module.handleInboundPacket(
        pingPacket,
        const PacketContext(
          sourceLinkPeerId: 'neighbor_node',
          hops: 2,
          medium: TransportMedium.bleMesh,
        ),
      );

      expect(pongSent, isFalse, reason: 'Stealth mode must never respond to diagnostic pings');
    });

    test('Pong callback computes latency and reports hops', () async {
      Uint8List? reportedSender;
      int? reportedRtt;
      int? reportedHops;

      final module = DiagnosticsModule(
        onSendPong: (_, __) async {},
        onPongReceived: (senderId, rttMs, hops) {
          reportedSender = senderId;
          reportedRtt = rttMs;
          reportedHops = hops;
        },
        isTraceAllowed: () => true,
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final sentTs = now - 45; // 45ms latency
      final pongPayload = Uint8List(8);
      ByteData.sublistView(pongPayload).setUint64(0, sentTs, Endian.big);

      final senderId = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3, 2]);
      final pongPacket = BitchatPacket(
        version: 1,
        type: MessageType.pong,
        ttl: 4,
        timestamp: now,
        senderId: senderId,
        recipientId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        payload: pongPayload,
      );

      await module.handleInboundPacket(
        pongPacket,
        const PacketContext(
          sourceLinkPeerId: 'hop_relay',
          hops: 3,
          medium: TransportMedium.bleMesh,
        ),
      );

      expect(reportedSender, senderId);
      expect(reportedHops, 3);
      expect(reportedRtt, greaterThanOrEqualTo(40));
    });
  });

  group('MeshTrafficNotifier & Ring Buffer', () {
    test('Maintains bounded ring buffer of 200 items and tracks telemetry metrics', () {
      final notifier = MeshTrafficNotifier(null);

      // Add 250 entries
      for (var i = 0; i < 250; i++) {
        final direction = i % 4 == 0
            ? MeshTrafficDirection.inbound
            : i % 4 == 1
                ? MeshTrafficDirection.outbound
                : i % 4 == 2
                    ? MeshTrafficDirection.relayed
                    : MeshTrafficDirection.dropped;

        notifier.addEntry(MeshTrafficEntry(
          id: 'entry_$i',
          timestamp: DateTime.now(),
          direction: direction,
          type: MessageType.message,
          senderId: 'sender_$i',
          ttl: 6,
          hops: 1,
          payloadLength: 64,
          medium: TransportMedium.bleMesh,
          summary: 'Telemetry test packet $i',
        ));
      }

      // Must be capped at exactly 200 items
      expect(notifier.state.entries.length, 200);
      // Newest entry is at index 0
      expect(notifier.state.entries.first.id, 'entry_249');
      // Total count tracks all processed packets
      expect(notifier.state.totalCount, 250);
    });

    test('Filters entries by direction accurately', () {
      final notifier = MeshTrafficNotifier(null);

      notifier.addEntry(MeshTrafficEntry(
        id: '1',
        timestamp: DateTime.now(),
        direction: MeshTrafficDirection.relayed,
        type: MessageType.message,
        senderId: 's1',
        ttl: 5,
        hops: 2,
        payloadLength: 32,
        medium: TransportMedium.bleMesh,
        summary: 'Relayed packet',
      ));

      notifier.addEntry(MeshTrafficEntry(
        id: '2',
        timestamp: DateTime.now(),
        direction: MeshTrafficDirection.dropped,
        type: MessageType.message,
        senderId: 's2',
        ttl: 6,
        hops: 1,
        payloadLength: 32,
        medium: TransportMedium.bleMesh,
        dropReason: 'vampire flood',
        summary: 'Dropped',
      ));

      notifier.setFilter(MeshTrafficFilter.relayed);
      expect(notifier.state.filteredEntries.length, 1);
      expect(notifier.state.filteredEntries.first.id, '1');

      notifier.setFilter(MeshTrafficFilter.dropped);
      expect(notifier.state.filteredEntries.length, 1);
      expect(notifier.state.filteredEntries.first.id, '2');

      notifier.setFilter(MeshTrafficFilter.all);
      expect(notifier.state.filteredEntries.length, 2);
    });

    test('Pause prevents visual list updates while continuing cumulative counters', () {
      final notifier = MeshTrafficNotifier(null);

      notifier.addEntry(MeshTrafficEntry(
        id: '1',
        timestamp: DateTime.now(),
        direction: MeshTrafficDirection.inbound,
        type: MessageType.message,
        senderId: 's1',
        ttl: 7,
        hops: 0,
        payloadLength: 20,
        medium: TransportMedium.bleMesh,
        summary: 'Inbound',
      ));

      notifier.pause();
      expect(notifier.state.isPaused, isTrue);

      notifier.addEntry(MeshTrafficEntry(
        id: '2',
        timestamp: DateTime.now(),
        direction: MeshTrafficDirection.inbound,
        type: MessageType.message,
        senderId: 's2',
        ttl: 7,
        hops: 0,
        payloadLength: 20,
        medium: TransportMedium.bleMesh,
        summary: 'Inbound 2',
      ));

      // Visual list length remains 1
      expect(notifier.state.entries.length, 1);
      // Cumulative counter increments to 2
      expect(notifier.state.totalCount, 2);
      expect(notifier.state.inboundCount, 2);

      notifier.resume();
      expect(notifier.state.isPaused, isFalse);

      notifier.clear();
      expect(notifier.state.entries, isEmpty);
      expect(notifier.state.totalCount, 0);
    });
  });

  group('ChatCommand Parsing for Traceroute and Stealth', () {
    test('/trace parses peer target correctly', () {
      final cmd = ChatCommand.parse('/trace 8a9b0c1d');
      expect(cmd.type, ChatCommandType.trace);
      expect(cmd.target, '8a9b0c1d');
      expect(cmd.errorMessage, isNull);

      final emptyCmd = ChatCommand.parse('/trace');
      expect(emptyCmd.type, ChatCommandType.trace);
      expect(emptyCmd.errorMessage, isNotNull);
    });

    test('/stealth parses on and off correctly', () {
      final onCmd = ChatCommand.parse('/stealth on');
      expect(onCmd.type, ChatCommandType.stealth);
      expect(onCmd.argument, 'on');

      final offCmd = ChatCommand.parse('/stealth off');
      expect(offCmd.type, ChatCommandType.stealth);
      expect(offCmd.argument, 'off');

      final emptyCmd = ChatCommand.parse('/stealth');
      expect(emptyCmd.type, ChatCommandType.stealth);
      expect(emptyCmd.errorMessage, isNotNull);
    });
  });
}
