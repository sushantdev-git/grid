import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/presentation/models/chat_message.dart';
import 'package:grid/presentation/models/peer_model.dart';
import 'package:grid/presentation/theme/app_theme.dart';
import 'package:grid/presentation/views/chat_screen.dart';
import 'package:grid/presentation/views/conversation_list_screen.dart';
import 'package:grid/presentation/views/mesh_traffic_screen.dart';
import 'package:grid/presentation/views/peer_directory_screen.dart';
import 'package:grid/presentation/widgets/app_drawer.dart';
import 'package:grid/presentation/widgets/message_bubble.dart';
import 'package:grid/presentation/widgets/message_details_sheet.dart';
import 'package:grid/presentation/widgets/safety_number_card.dart';
import 'package:grid/presentation/widgets/three_d_scan_visualizer.dart';
import 'package:grid/presentation/widgets/transport_badge.dart';

void main() {
  group('Minimalist Custom UI Widgets', () {
    testWidgets('TransportBadge renders BLE Mesh and Nostr indicators', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TransportBadge(medium: TransportMedium.bleMesh, rssi: -65),
                TransportBadge(medium: TransportMedium.nostr),
              ],
            ),
          ),
        ),
      );

      expect(find.text('BLE -65 dBm'), findsOneWidget);
      expect(find.text('Nostr'), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('MessageBubble renders outgoing, incoming, and system messages', (tester) async {
      final outgoing = ChatMessage(
        id: '1',
        senderId: 'local',
        senderNickname: 'Me',
        content: 'Outgoing secret',
        timestamp: DateTime(2026, 1, 1, 12, 34),
        isOutgoing: true,
        isEncrypted: true,
        channelOrPeerId: 'peer1',
        deliveryStatus: MessageDeliveryStatus.delivered,
      );

      final incoming = ChatMessage(
        id: '2',
        senderId: 'peer1',
        senderNickname: 'Alice',
        content: 'Incoming public',
        timestamp: DateTime(2026, 1, 1, 12, 35),
        isOutgoing: false,
        isEncrypted: false,
        channelOrPeerId: '#mesh',
      );

      final system = ChatMessage.system(
        id: '3',
        content: 'System announcement',
        channelOrPeerId: '#mesh',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ListView(
              children: [
                MessageBubble(message: outgoing),
                MessageBubble(message: incoming),
                MessageBubble(message: system),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Outgoing secret'), findsOneWidget);
      expect(find.text('Incoming public'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('System announcement'), findsOneWidget);

      // Lock icon for E2EE message
      expect(find.byIcon(Icons.lock), findsOneWidget);
      // Double checkmark for delivered
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('MessageBubble clusters correctly with BubblePosition', (tester) async {
      final msg = ChatMessage(
        id: '1',
        senderId: 'local',
        senderNickname: 'Me',
        content: 'Clustered message',
        timestamp: DateTime.now(),
        isOutgoing: true,
        channelOrPeerId: 'peer1',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(message: msg, position: BubblePosition.first),
                MessageBubble(message: msg, position: BubblePosition.middle),
                MessageBubble(message: msg, position: BubblePosition.last),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Clustered message'), findsNWidgets(3));
    });

    testWidgets('SafetyNumberCard displays 12 blocks and triggers verification toggle', (tester) async {
      var toggleCalled = false;
      final peer = PeerModel(
        peerId: 'alice_id',
        nickname: 'Alice',
        lastSeen: DateTime.now(),
        isVerified: false,
        safetyNumber: '11111 22222 33333 44444 55555 66666 77777 88888 99999 00000 12345 67890',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SafetyNumberCard(
              peer: peer,
              onToggleVerified: () => toggleCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Safety Number with Alice'), findsOneWidget);
      expect(find.text('11111'), findsOneWidget);
      expect(find.text('67890'), findsOneWidget);
      expect(find.text('Mark as Verified'), findsOneWidget);

      // Tap switch
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(toggleCalled, isTrue);
    });

    testWidgets('ConversationListScreen pumps and displays channels and navigation menu', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ConversationListScreen(),
          ),
        ),
      );
      await tester.pump();

      // Channels section
      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.text('#mesh'), findsOneWidget);
      expect(find.text('#general'), findsOneWidget);

      // Direct Messages section
      expect(find.text('DIRECT MESSAGES'), findsOneWidget);

      // Menu button is present, FAB is removed
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('ChatScreen sends message and displays message bubble', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(channelOrPeerId: '#mesh'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('#mesh'), findsOneWidget);
      expect(find.text('Public Mesh Channel'), findsOneWidget);

      // Enter text and send
      await tester.enterText(find.byType(TextField), 'Hello Grid World!');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Hello Grid World!'), findsOneWidget);
    });

    testWidgets('ChatScreen shows slash command popup when user types /', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(channelOrPeerId: '#mesh'),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '/s');
      await tester.pump();

      // Autocomplete popup should show /slap
      expect(find.text('/slap'), findsOneWidget);
      expect(find.text('Slap a peer with a large trout'), findsOneWidget);
    });

    testWidgets('AppDrawer opens via hamburger menu and shows navigation and account tab', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ConversationListScreen(),
          ),
        ),
      );
      await tester.pump();

      // Tap hamburger menu icon
      expect(find.byIcon(Icons.menu), findsOneWidget);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer is now open
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Peers'), findsOneWidget);
      expect(find.text('Mesh Network Online'), findsOneWidget);

      // Bottom account tab is displayed with edit icon
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('AppDrawer calls onOpenEditProfile when account tab is tapped', (tester) async {
      var profileOpened = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              drawer: AppDrawer(
                onOpenEditProfile: () => profileOpened = true,
              ),
              body: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap bottom account tab
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(profileOpened, isTrue);
    });

    testWidgets('AppDrawer tapping Peers navigates to PeerDirectoryScreen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ConversationListScreen(),
          ),
        ),
      );
      await tester.pump();

      // Open drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap 'Peers' item
      await tester.tap(find.text('Peers'));
      await tester.pumpAndSettle();

      // Peer Directory screen should be visible
      expect(find.text('Discovered Peers'), findsOneWidget);
    });

    testWidgets('ThreeDScanVisualizer renders scanning badge, telemetry, and handles stop callback', (tester) async {
      var stopped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ThreeDScanVisualizer(
              peerCount: 3,
              onStopScan: () => stopped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('RADIO DISCOVERY BURST'), findsOneWidget);
      expect(find.text('SCANNING'), findsOneWidget);
      expect(find.text('3 Peers Found'), findsOneWidget);
      expect(find.text('BLE 2.4 GHz + Nostr Relays'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(stopped, isTrue);
    });

    testWidgets('PeerDirectoryScreen shows scan triggers and toggles 3D visualizer on scan', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PeerDirectoryScreen(),
          ),
        ),
      );
      await tester.pump();

      // Initially not scanning: AppBar shows radar scan icon, empty state shows Scan for Nearby Peers button
      expect(find.byIcon(Icons.radar), findsOneWidget);
      expect(find.text('Scan for Nearby Peers'), findsOneWidget);
      expect(find.byType(ThreeDScanVisualizer), findsNothing);

      // Tap the AppBar radar icon to initiate scan
      await tester.tap(find.byIcon(Icons.radar));
      await tester.pump();

      // Scanning is active: 3D visualizer is mounted and AppBar indicates Scanning
      expect(find.byType(ThreeDScanVisualizer), findsOneWidget);
      expect(find.text('Scanning'), findsOneWidget);

      // Stop scan from visualizer's stop button
      await tester.tap(find.text('Stop'));
      await tester.pump();

      // Visualizer is removed and radar icon returns
      expect(find.byType(ThreeDScanVisualizer), findsNothing);
      expect(find.byIcon(Icons.radar), findsOneWidget);
    });

    testWidgets('MessageDetailsSheet renders delivery status, hop count, and E2EE details', (tester) async {
      final msg = ChatMessage(
        id: 'msg_det_test_123',
        senderId: '1122334455667788',
        senderNickname: 'Alice',
        content: 'Confidential Payload',
        timestamp: DateTime(2026, 1, 1, 14, 30, 15),
        isOutgoing: false,
        isEncrypted: true,
        medium: TransportMedium.bleMesh,
        channelOrPeerId: '1122334455667788',
        deliveryStatus: MessageDeliveryStatus.delivered,
        hops: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: MessageDetailsSheet(message: msg),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Message Telemetry'), findsOneWidget);
      expect(find.text('Inbound Receipt'), findsOneWidget);
      expect(find.text('Hop Distance Telemetry'), findsOneWidget);
      expect(find.text('2-Hop Mesh Relay Route'), findsOneWidget);
      expect(find.text('Noise_XX E2EE'), findsOneWidget);
      expect(find.text('Message ID: msg_det_test_123'), findsOneWidget);
    });

    testWidgets('MessageBubble long-press opens MessageDetailsSheet', (tester) async {
      final msg = ChatMessage(
        id: 'bubble_lp_test',
        senderId: 'self',
        senderNickname: 'Me',
        content: 'Long press me',
        timestamp: DateTime(2026, 1, 1, 15, 0, 0),
        isOutgoing: true,
        isEncrypted: true,
        medium: TransportMedium.bleMesh,
        channelOrPeerId: 'peer_target',
        deliveryStatus: MessageDeliveryStatus.delivered,
        hops: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: MessageBubble(message: msg),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Long press me'), findsOneWidget);
      expect(find.text('Message Telemetry'), findsNothing);

      // Long-press bubble
      await tester.longPress(find.text('Long press me'));
      await tester.pumpAndSettle();

      expect(find.text('Message Telemetry'), findsOneWidget);
      expect(find.text('Delivery Confirmation'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
    });

    testWidgets('MeshTrafficScreen renders live telemetry metrics, filters, and traceroute action', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MeshTrafficScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Traffic Inspector'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('RELAYED'), findsOneWidget);
      expect(find.text('INBOUND'), findsOneWidget);
      expect(find.text('DROPPED'), findsOneWidget);
      expect(find.text('Listening for Mesh Telemetry...'), findsOneWidget);

      // Tap traceroute button
      await tester.tap(find.byIcon(Icons.alt_route_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Diagnostic Traceroute'), findsOneWidget);
      expect(find.text('Send Probe'), findsOneWidget);
    });

    testWidgets('AppDrawer includes Traffic Inspector navigation tile', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              drawer: AppDrawer(),
            ),
          ),
        ),
      );

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Traffic Inspector'), findsOneWidget);
      expect(find.byIcon(Icons.troubleshoot_rounded), findsOneWidget);
    });
  });
}
