import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/models/lecture_illustrator_model.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/controllers/lecture_illustrator_controller.dart';

void main() {
  group('Lecture Storyboard Management State & Controller Tests', () {
    test('LectureIllustratorState initial selection is empty', () {
      const state = LectureIllustratorState();
      expect(state.selectedBatchIds, isEmpty);
      expect(state.isBatchReauthoring, false);
      expect(state.batchReauthorProgress, 0.0);
    });

    test('LectureIllustratorState copyWith updates selection and batch reauthoring state', () {
      const state = LectureIllustratorState();
      final updated = state.copyWith(
        selectedBatchIds: {'batch_001', 'batch_002'},
        isBatchReauthoring: true,
        batchReauthorProgress: 0.5,
      );

      expect(updated.selectedBatchIds, contains('batch_001'));
      expect(updated.selectedBatchIds, contains('batch_002'));
      expect(updated.selectedBatchIds.length, 2);
      expect(updated.isBatchReauthoring, true);
      expect(updated.batchReauthorProgress, 0.5);
    });

    test('Controller toggles batch selection', () {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      controller.toggleSelectBatch('batch_001');
      expect(controller.currentState.selectedBatchIds.contains('batch_001'), true);

      controller.toggleSelectBatch('batch_002');
      expect(controller.currentState.selectedBatchIds.length, 2);

      controller.toggleSelectBatch('batch_001');
      expect(controller.currentState.selectedBatchIds.contains('batch_001'), false);
      expect(controller.currentState.selectedBatchIds.length, 1);
    });

    test('Controller selectAllBatches selects all and deselects all', () {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      const b1 = LectureBatch(id: 'batch_001', startSec: 0, endSec: 4, transcriptOriginal: 'Intro');
      const b2 = LectureBatch(id: 'batch_002', startSec: 4, endSec: 8, transcriptOriginal: 'Body');

      // Set batches in state
      controller.setBatchesForTesting([b1, b2]);

      controller.selectAllBatches(true);
      expect(controller.currentState.selectedBatchIds.length, 2);
      expect(controller.currentState.selectedBatchIds.contains('batch_001'), true);
      expect(controller.currentState.selectedBatchIds.contains('batch_002'), true);

      controller.selectAllBatches(false);
      expect(controller.currentState.selectedBatchIds, isEmpty);
    });
  });
}
