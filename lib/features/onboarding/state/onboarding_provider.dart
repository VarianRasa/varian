import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  final bool ready;
  final bool dismissed;
  final int step;

  const OnboardingState({
    this.ready = false,
    this.dismissed = false,
    this.step = 0,
  });

  bool get shouldShow => ready && !dismissed;

  OnboardingState copyWith({bool? ready, bool? dismissed, int? step}) =>
      OnboardingState(
        ready: ready ?? this.ready,
        dismissed: dismissed ?? this.dismissed,
        step: step ?? this.step,
      );
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
      (ref) => OnboardingNotifier(),
    );

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  static const _dismissedKey = 'onboarding_dismissed';

  OnboardingNotifier() : super(const OnboardingState());

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = OnboardingState(
        ready: true,
        dismissed: prefs.getBool(_dismissedKey) ?? false,
      );
    } catch (_) {
      // Onboarding is helpful, never a prerequisite for local work.
      state = const OnboardingState(ready: true);
    }
  }

  Future<void> skip() async {
    state = state.copyWith(ready: true, dismissed: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, true);
    } catch (_) {}
  }

  Future<void> resume() async {
    state = state.copyWith(ready: true, dismissed: false, step: 0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, false);
    } catch (_) {}
  }

  void setStep(int step) {
    if (step < 0 || step > 2) return;
    state = state.copyWith(step: step);
  }
}
