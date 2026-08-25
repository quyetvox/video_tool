import 'dart:io';
import 'job_state.dart';

/// Abstract base class for all pipeline steps in video_engine.
abstract class StepBase {
  /// Unique identifier for this step (e.g. "s01_probe")
  String get stepId;

  /// List of step IDs this step depends on
  List<String> get dependsOn => const [];

  /// Configuration keys whose changes trigger invalidation of this step
  List<String> get stepConfigKeys => const [];

  /// Execute the pipeline step and return the step output dictionary.
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  );

  /// Check if step has already completed and output checkpoint exists.
  bool canSkip(Directory workspace) {
    final marker = File('${workspace.path}/$stepId.done');
    return marker.existsSync();
  }

  /// Mark step as complete by touching marker file.
  void markDone(Directory workspace) {
    final marker = File('${workspace.path}/$stepId.done');
    marker.createSync(recursive: true);
  }
}
