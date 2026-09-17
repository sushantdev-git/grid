import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/bitchat_coordinator.dart';
import '../../infrastructure/services/local_storage_service.dart';
import '../../infrastructure/services/voice_service.dart';
import 'channels_notifier.dart';
import 'identity_state.dart';
import 'peers_notifier.dart';
import 'timeline_notifier.dart';

/// Coordinator executing an instantaneous unconfirmed emergency panic wipe.
///
/// Features:
/// - Zeroizes in-memory ephemeral message buffers across all channels
/// - Clears discovered peer directories and radio cache
/// - Resets joined channels to standard defaults
/// - Overwrites and scrubs all local disk persistence files
/// - Overwrites and scrubs all voice note recordings with zeros
/// - Wipes coordinator courier outbox, active noise sessions, and stops radio
/// - Re-generates a fresh ephemeral identity key pair with private key scrubbing
class PanicController {
  final Ref ref;

  PanicController(this.ref);

  /// Executes the instantaneous panic zeroization wipe without confirmation.
  Future<void> executePanicWipe() async {
    // 1. Wipe timelines
    await ref.read(timelineProvider.notifier).clearAll();

    // 2. Wipe peer cache
    ref.read(peersProvider.notifier).clear();

    // 3. Reset channels
    ref.read(channelsProvider.notifier).clear();

    // 4. Scrub and purge all persistent files on disk
    try {
      await ref.read(localStorageServiceProvider).wipeAll();
    } catch (_) {}

    // 5. Forensically zeroize and delete all voice note audio files
    try {
      await ref.read(voiceServiceProvider).wipeAllVoiceNotes();
    } catch (_) {}

    // 4. Wipe coordinator (courier outbox, noise sessions, radio)
    final coordinator = ref.read(bitchatCoordinatorProvider);
    if (coordinator != null) {
      await coordinator.panicWipe(
        activeKeyPair: ref.read(identityProvider).keyPair,
      );
    }

    // 5. Zeroize and regenerate cryptographic keys
    await ref.read(identityProvider.notifier).panicWipe();

    // 6. Ensure the new coordinator and radio links are cleanly started and ready for discovery
    final newCoordinator = ref.read(bitchatCoordinatorProvider);
    if (newCoordinator != null) {
      await newCoordinator.start();
      await newCoordinator.startScan();
    }
  }
}

/// Global provider for the emergency panic wipe controller.
final panicControllerProvider = Provider<PanicController>((ref) {
  return PanicController(ref);
});
