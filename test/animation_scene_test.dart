import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';

void main() {
  group('AnimationScene.fromJson', () {
    test('parses a full scene and clamps coordinates', () {
      final scene = AnimationScene.fromJson({
        'pitch_area': 'attacking third',
        'players': [
          {
            'id': 'o1',
            'label': '10',
            'team': 'own',
            'start': {'x': -0.5, 'y': 0.4},
            'end': {'x': 1.4, 'y': 0.9},
            'role': 'asiste',
          },
          {
            'id': 'r1',
            'label': 'r',
            'team': 'rival',
            'start': {'x': 0.6, 'y': 0.8},
            'end': {'x': 0.6, 'y': 0.8},
          },
        ],
        'ball_path': [
          {'x': 0.2, 'y': 0.5},
          {'x': 0.9, 'y': 0.85},
        ],
        'movements': [
          {
            'player': 'o1',
            'from': {'x': 0.2, 'y': 0.4},
            'to': {'x': 0.8, 'y': 0.9},
            'start_s': 0,
            'end_s': 3,
            'type': 'pase',
          },
        ],
        'zones': [
          {'type': 'target', 'label': 'area', 'x': 0.3, 'y': 0.8, 'width': 0.4, 'height': 0.2},
        ],
        'coaching_cues': ['ataca el primer palo', ''],
        'duration_seconds': 7,
      });

      expect(scene.pitchArea, 'attacking_third');
      expect(scene.players, hasLength(2));
      expect(scene.players.first.start.x, 0.0); // clamped from -0.5
      expect(scene.players.first.end.x, 1.0); // clamped from 1.4
      expect(scene.players[1].team, 'rival');
      expect(scene.ballPath, hasLength(2));
      expect(scene.movements.single.type, 'pase');
      expect(scene.zones.single.type, 'target');
      expect(scene.coachingCues, ['ataca el primer palo']);
      expect(scene.durationSeconds, 7);
      expect(scene.isFallback, isFalse);
      expect(scene.hasContent, isTrue);
    });

    test('empty json has no content', () {
      final scene = AnimationScene.fromJson(const {});
      expect(scene.hasContent, isFalse);
    });
  });

  group('AnimationScene.fromBlockText — different exercises differ', () {
    AnimationScene press() => AnimationScene.fromBlockText(
          text: 'Presion tras perdida: recuperar en 5 segundos',
          space: 'cuadrado reducido 20x20',
          playerCount: 8,
        );
    AnimationScene buildOut() => AnimationScene.fromBlockText(
          text: 'Salida desde el fondo con amplitud y circulacion',
          space: 'tres cuartos de cancha',
          playerCount: 14,
        );

    test('pitch area reflects the space', () {
      expect(press().pitchArea, 'small_grid');
      expect(buildOut().pitchArea, 'defensive_third');
    });

    test('scenes are structurally distinct', () {
      final a = press();
      final b = buildOut();
      expect(a.players.length == b.players.length, isFalse);
      expect(a.ballPath.length == b.ballPath.length, isFalse);
      expect(
        a.zones.map((z) => z.type).toSet(),
        isNot(equals(b.zones.map((z) => z.type).toSet())),
      );
      expect(a.isFallback, isTrue);
      expect(b.isFallback, isTrue);
      expect(a.hasContent && b.hasContent, isTrue);
    });

    test('build-out has lane zones, press has a recovery target', () {
      expect(buildOut().zones.any((z) => z.type == 'lane'), isTrue);
      expect(press().zones.every((z) => z.type == 'lane'), isFalse);
      expect(press().zones.any((z) => z.type == 'target'), isTrue);
    });
  });

  test('TrainingBlock round-trips animation_scene through json', () {
    final block = TrainingBlock(
      'Rondo de presion',
      '10 min',
      'Presion tras perdida en espacio reducido',
      animationScene: AnimationScene.fromBlockText(
        text: 'presion tras perdida',
        space: 'reducido',
        playerCount: 6,
      ),
    );
    final restored = TrainingBlock.fromJson(block.toJson());
    expect(restored.animationScene, isNotNull);
    expect(restored.animationScene!.players, isNotEmpty);
    expect(restored.animationScene!.pitchArea, 'small_grid');
  });

  test('old session without animation_scene falls back cleanly', () {
    final restored = TrainingBlock.fromJson(const {
      'name': 'Activacion',
      'duration': '8 min',
      'description': 'Movilidad y pases cortos',
    });
    expect(restored.animationScene, isNull);
    final scene = restored.sceneOrFallback(space: 'medio campo', playerCount: 10);
    expect(scene.isFallback, isTrue);
    expect(scene.hasContent, isTrue);
  });
}
