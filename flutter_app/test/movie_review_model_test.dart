import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/screens/movie_review/models/movie_review_model.dart';

void main() {
  group('MovieReviewModel Tests', () {
    test('WordBudget SOP calculation matches Golden Ratio for storyReview and critique', () {
      // 6 minutes at 1.15x speed -> 6 * 161 = 966 words
      final storyBudget = WordBudget.calculate(360, 1.15, ReviewStyle.storyReview);
      expect(storyBudget.totalWords, 966);
      expect(storyBudget.wordsPerMin, 161);
      expect(storyBudget.hookWords, 97); // 10%
      expect(storyBudget.reviewWords, 97); // 10%
      expect(storyBudget.outroWords, 48); // 5%
      expect(storyBudget.hookWords + storyBudget.storyWords + storyBudget.reviewWords + storyBudget.outroWords, storyBudget.totalWords);

      final critiqueBudget = WordBudget.calculate(360, 1.15, ReviewStyle.critique);
      expect(critiqueBudget.totalWords, 966);
      expect(critiqueBudget.hookWords, 145); // 15%
      expect(critiqueBudget.reviewWords, 290); // 30%
      expect(critiqueBudget.outroWords, 97); // 10%
      expect(critiqueBudget.hookWords + critiqueBudget.storyWords + critiqueBudget.reviewWords + critiqueBudget.outroWords, critiqueBudget.totalWords);
    });

    test('WordBudget calculateOptimalDuration and dynamic chapters sizing', () {
      // Short film <= 20m -> 180s (3m)
      expect(WordBudget.calculateOptimalDuration(600), 180);
      expect(WordBudget.calculateOptimalDuration(1200), 180);

      // Episode 45m (2700s) -> ~300-480s
      final dur45m = WordBudget.calculateOptimalDuration(2700);
      expect(dur45m >= 300 && dur45m <= 480, isTrue);

      // Feature film 120m (7200s) -> 600s (10m)
      expect(WordBudget.calculateOptimalDuration(7200), 600);

      // Very long movie 180m (10800s) -> capped at 900s (15m)
      expect(WordBudget.calculateOptimalDuration(10800), 900);

      // Dynamic chapters: 720s -> 6 chapters, 900s -> 8 chapters
      final budget720 = WordBudget.calculate(720, 1.45);
      expect(budget720.numChapters, 6);
      expect(budget720.chapterWords > 200, isTrue);

      final budget900 = WordBudget.calculate(900, 1.45);
      expect(budget900.numChapters, 8);
      expect(budget900.chapterWords > 250, isTrue);
    });

    test('ScriptSegment serialization roundtrip preserves data', () {
      const scene = SceneMeta(
        sceneId: 45,
        startSec: 125.5,
        endSec: 128.0,
        duration: 2.5,
        imagePath: 'scene_0045.jpg',
        act: 'hook',
      );

      const seg = ScriptSegment(
        id: 1,
        section: 'hook',
        voiceoverText: 'Bị dồn vào đường cùng trong gang tấc...',
        scenesToUse: [scene],
        audioFile: 'voice_001.mp3',
        audioDuration: 6.4,
      );

      final json = seg.toJson();
      expect(json['id'], 1);
      expect(json['section'], 'hook');
      expect(json['audio_duration'], 6.4);

      final parsed = ScriptSegment.fromJson(json, [scene]);
      expect(parsed.id, seg.id);
      expect(parsed.voiceoverText, seg.voiceoverText);
      expect(parsed.scenesToUse.length, 1);
      expect(parsed.scenesToUse.first.sceneId, 45);
    });

    test('MovieReviewState estimated duration and word count operate properly', () {
      const seg1 = ScriptSegment(
        id: 1,
        section: 'hook',
        voiceoverText: 'Một hai ba bốn năm sáu bảy tám chín mười', // 10 words
        scenesToUse: [],
      );

      const state = MovieReviewState(
        ttsSpeed: 1.0,
        segments: [seg1],
      );

      expect(state.currentWordCount, 10);
      // 10 words at 140 wpm -> (10 / 140) * 60 = 4.285 seconds
      expect(state.estimatedDurationSec, closeTo(4.28, 0.05));
    });

    test('MovieReviewState new properties and MovieGenreExt tests', () {
      expect(MovieGenre.linearAction.recommendedRange, '5 - 8 phút');
      expect(MovieGenre.complexPsychological.recommendedRange, '10 - 15 phút');
      expect(MovieGenre.shorts.recommendedRange, '1 - 3 phút');
      expect(MovieGenre.custom.recommendedRange, 'Tùy chỉnh');

      const state = MovieReviewState(
        projectName: 'chu-truc-tu',
        aiModel: 'gemini-3.5-flash-lite',
        bgmVolume: 0.20,
        hasCachedData: true,
        targetLang: 'vi',
        burnSubtitles: true,
        enableInpaint: false,
        flipHorizontal: false,
        cropZoom: false,
        muteMovieAudio: false,
        customPrompt: 'Kịch tính và bất ngờ',
      );

      expect(state.projectName, 'chu-truc-tu');
      expect(state.aiModel, 'gemini-3.5-flash-lite');
      expect(state.bgmVolume, 0.20);
      expect(state.hasCachedData, isTrue);
      expect(state.targetLang, 'vi');
      expect(state.burnSubtitles, isTrue);
      expect(state.enableInpaint, isFalse);
      expect(state.flipHorizontal, isFalse);
      expect(state.cropZoom, isFalse);
      expect(state.muteMovieAudio, isFalse);
      expect(state.customPrompt, 'Kịch tính và bất ngờ');

      final copy = state.copyWith(
        bgmVolume: 0.35,
        hasCachedData: false,
        targetLang: 'en',
        burnSubtitles: false,
        enableInpaint: true,
        flipHorizontal: true,
        cropZoom: true,
        muteMovieAudio: true,
        customPrompt: 'Phân tích plot twist',
      );
      expect(copy.bgmVolume, 0.35);
      expect(copy.hasCachedData, isFalse);
      expect(copy.projectName, 'chu-truc-tu');
      expect(copy.targetLang, 'en');
      expect(copy.burnSubtitles, isFalse);
      expect(copy.enableInpaint, isTrue);
      expect(copy.flipHorizontal, isTrue);
      expect(copy.cropZoom, isTrue);
      expect(copy.muteMovieAudio, isTrue);
      expect(copy.customPrompt, 'Phân tích plot twist');
    });

    test('ActStructureConfig Story-Anchor Auto-Balancing and Toggle tests', () {
      final defaultConfig = ActStructureConfig.defaultFor(ReviewStyle.storyReview);
      expect(defaultConfig.hookPct, 0.10);
      expect(defaultConfig.storyPct, 0.75);
      expect(defaultConfig.reviewPct, 0.10);
      expect(defaultConfig.outroPct, 0.05);
      expect(defaultConfig.hookPct + defaultConfig.storyPct + defaultConfig.reviewPct + defaultConfig.outroPct, closeTo(1.0, 0.01));

      // Update hookPct to 20% -> storyPct should balance to 65%
      final updatedHook = defaultConfig.updateActPct('hook', 0.20);
      expect(updatedHook.hookPct, 0.20);
      expect(updatedHook.storyPct, 0.65);
      expect(updatedHook.hookPct + updatedHook.storyPct + updatedHook.reviewPct + updatedHook.outroPct, closeTo(1.0, 0.01));

      // Toggle hook OFF -> hookPct becomes 0%, storyPct absorbs it to 75% + 10% = 85%
      final toggledOff = defaultConfig.toggleAct('hook', false);
      expect(toggledOff.enableHook, isFalse);
      expect(toggledOff.hookPct, 0.0);
      expect(toggledOff.storyPct, 0.85);
      expect(toggledOff.hookPct + toggledOff.storyPct + toggledOff.reviewPct + toggledOff.outroPct, closeTo(1.0, 0.01));

      // Toggle hook back ON -> restores default hookPct (10%) and storyPct returns to 75%
      final toggledOn = toggledOff.toggleAct('hook', true);
      expect(toggledOn.enableHook, isTrue);
      expect(toggledOn.hookPct, 0.10);
      expect(toggledOn.storyPct, 0.75);

      // Chapter selection
      final chConfig = defaultConfig.copyWith(
        availableChapters: [
          {'chapter_id': 1, 'title': 'Chương 1'},
          {'chapter_id': 2, 'title': 'Chương 2'},
        ],
      );
      final withCh1 = chConfig.toggleChapter(1);
      expect(withCh1.selectedChapterIds, [1]);
      final withBoth = withCh1.toggleChapter(2);
      expect(withBoth.selectedChapterIds, [1, 2]);
      final withoutCh1 = withBoth.toggleChapter(1);
      expect(withoutCh1.selectedChapterIds, [2]);

      final allSelected = chConfig.selectAllChapters(true);
      expect(allSelected.selectedChapterIds, [1, 2]);
      final noneSelected = chConfig.selectAllChapters(false);
      expect(noneSelected.selectedChapterIds, isEmpty);

      // JSON serialization
      final json = chConfig.toJson();
      expect(json['hook'], isTrue);
      expect(json['hook_pct'], 0.10);
      expect(json['story_pct'], 0.75);
    });

    test('WordBudget with custom ActStructureConfig', () {
      const actCfg = ActStructureConfig(
        enableHook: true,
        enableStory: true,
        enableReview: false,
        enableOutro: true,
        hookPct: 0.20,
        storyPct: 0.70,
        reviewPct: 0.0,
        outroPct: 0.10,
        selectedChapterIds: [1, 2],
      );

      final budget = WordBudget.calculate(360, 1.45, ReviewStyle.storyReview, actCfg);
      expect(budget.hookWords > 0, isTrue);
      expect(budget.storyWords > 0, isTrue);
      expect(budget.reviewWords, 0);
      expect(budget.outroWords > 0, isTrue);
      expect(budget.numChapters, 2);
    });

    test('MovieReviewState supports 3 independent volume streams', () {
      const state = MovieReviewState(
        ttsVolume: 0.85,
        originalAudioVolume: 0.10,
        bgmVolume: 0.25,
      );

      expect(state.ttsVolume, 0.85);
      expect(state.originalAudioVolume, 0.10);
      expect(state.bgmVolume, 0.25);

      final copy = state.copyWith(
        ttsVolume: 1.0,
        originalAudioVolume: 0.0,
        bgmVolume: 0.15,
      );

      expect(copy.ttsVolume, 1.0);
      expect(copy.originalAudioVolume, 0.0);
      expect(copy.bgmVolume, 0.15);
    });
  });
}

