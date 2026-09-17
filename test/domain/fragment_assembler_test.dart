import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/fragment_assembler.dart';
import 'package:grid/infrastructure/codecs/fragment_codec.dart';

void main() {
  group('FragmentAssembler', () {
    test('reassembles in-order chunks successfully', () {
      final assembler = FragmentAssembler();
      final originalData = Uint8List.fromList(List.generate(1200, (i) => i % 256));
      final fragmentId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final slices = FragmentCodec.slice(originalData, fragmentId: fragmentId, maxChunkSize: 400);
      expect(slices.length, equals(3));

      expect(assembler.ingestFragment(slices[0]), isNull);
      expect(assembler.getProgress(fragmentId), closeTo(1 / 3, 0.01));

      expect(assembler.ingestFragment(slices[1]), isNull);
      expect(assembler.getProgress(fragmentId), closeTo(2 / 3, 0.01));

      final assembled = assembler.ingestFragment(slices[2]);
      expect(assembled, isNotNull);
      expect(assembled, equals(originalData));
      expect(assembler.activeSessionCount, equals(0));
    });

    test('reassembles out-of-order chunks successfully', () {
      final assembler = FragmentAssembler();
      final originalData = Uint8List.fromList(List.generate(1000, (i) => (i * 3) % 256));
      final fragmentId = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3, 2]);

      final slices = FragmentCodec.slice(originalData, fragmentId: fragmentId, maxChunkSize: 350);
      expect(slices.length, equals(3));

      // Ingest 2, then 0, then 1
      expect(assembler.ingestFragment(slices[2]), isNull);
      expect(assembler.ingestFragment(slices[0]), isNull);
      final assembled = assembler.ingestFragment(slices[1]);

      expect(assembled, isNotNull);
      expect(assembled, equals(originalData));
    });

    test('prunes stale sessions after max age', () {
      final assembler = FragmentAssembler(maxSessionAge: const Duration(milliseconds: 50));
      final fragmentId = Uint8List.fromList([1, 1, 1, 1, 1, 1, 1, 1]);

      final fragment = FragmentPayload(
        fragmentId: fragmentId,
        index: 0,
        total: 2,
        chunk: Uint8List.fromList([1, 2, 3]),
      );

      assembler.ingestFragment(fragment);
      expect(assembler.activeSessionCount, equals(1));

      // Wait past maxSessionAge
      Future.delayed(const Duration(milliseconds: 60), () {
        assembler.pruneStaleSessions();
        expect(assembler.activeSessionCount, equals(0));
      });
    });

    test('clears all sessions on clear()', () {
      final assembler = FragmentAssembler();
      final fragment = FragmentPayload(
        fragmentId: Uint8List(8),
        index: 0,
        total: 2,
        chunk: Uint8List(10),
      );

      assembler.ingestFragment(fragment);
      expect(assembler.activeSessionCount, equals(1));

      assembler.clear();
      expect(assembler.activeSessionCount, equals(0));
    });
  });
}
