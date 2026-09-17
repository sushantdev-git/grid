import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/mesh_engine.dart';

void main() {
  group('TokenBucketRateLimiter Vampire Attack & DoS Defense Tests', () {
    late TokenBucketRateLimiter limiter;

    setUp(() {
      limiter = TokenBucketRateLimiter(capacity: 20.0, fillRate: 10.0);
    });

    test('allows burst requests up to configured capacity', () {
      const peerKey = 'attacker_node_01';

      // First 20 requests in immediate succession should all be allowed
      for (int i = 0; i < 20; i++) {
        expect(limiter.allow(peerKey), isTrue, reason: 'Request $i should be allowed');
      }

      // 21st request exceeds burst allowance and must be dropped
      expect(limiter.allow(peerKey), isFalse, reason: 'Request 21 should be rate-limited');
    });

    test('separate peers have independent rate limit buckets', () {
      const peerA = 'peer_node_a';
      const peerB = 'peer_node_b';

      // Exhaust peer A's bucket
      for (int i = 0; i < 20; i++) {
        limiter.allow(peerA);
      }
      expect(limiter.allow(peerA), isFalse);

      // Peer B must still have full burst capacity available
      expect(limiter.allow(peerB), isTrue);
    });

    test('refills tokens over time based on fillRate', () async {
      const peerKey = 'intermittent_peer';

      // Exhaust tokens
      for (int i = 0; i < 20; i++) {
        limiter.allow(peerKey);
      }
      expect(limiter.allow(peerKey), isFalse);

      // Wait 150ms -> at 10 tokens/sec, should regenerate ~1.5 tokens
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Should now allow at least 1 token
      expect(limiter.allow(peerKey), isTrue);
    });

    test('clear resets all token buckets', () {
      const peerKey = 'cleared_peer';

      for (int i = 0; i < 20; i++) {
        limiter.allow(peerKey);
      }
      expect(limiter.allow(peerKey), isFalse);

      limiter.clear();

      // After clear, fresh bucket allows immediate requests
      expect(limiter.allow(peerKey), isTrue);
    });
  });
}
