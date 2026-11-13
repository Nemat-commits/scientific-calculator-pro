import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// A short message that floats above the keypad for a moment.
final class ToastMessage {
  const ToastMessage(this.id, this.text);

  /// Distinguishes two messages with the same text.
  final int id;
  final String text;
}

/// The message [ToastHost] is showing, if any.
final NotifierProvider<ToastNotifier, ToastMessage?> toastProvider =
    NotifierProvider<ToastNotifier, ToastMessage?>(ToastNotifier.new);

class ToastNotifier extends Notifier<ToastMessage?> {
  int _serial = 0;

  @override
  ToastMessage? build() => null;

  /// Shows [text]; a message that is still up is replaced.
  void show(String text) => state = ToastMessage(++_serial, text);

  /// Takes the message [id] down (a newer one stays).
  void dismiss(int id) {
    if (state?.id == id) state = null;
  }
}

/// Floats the current [toastProvider] message over [child] and takes it down
/// again after [ToastHost.duration]. Touches pass through the message.
class ToastHost extends ConsumerStatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  /// How long a message stays up.
  static const Duration duration = Duration(milliseconds: 1500);

  @override
  ConsumerState<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends ConsumerState<ToastHost> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ToastMessage?>(toastProvider, (_, next) {
      _timer?.cancel();
      if (next == null) return;
      _timer = Timer(ToastHost.duration, () {
        if (mounted) ref.read(toastProvider.notifier).dismiss(next.id);
      });
    });
    final message = ref.watch(toastProvider);
    return Stack(
      children: <Widget>[
        Positioned.fill(child: widget.child),
        Positioned(
          left: 16,
          right: 16,
          bottom: 28,
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: message == null
                  ? const SizedBox.shrink()
                  : Center(
                      key: ValueKey<int>(message.id),
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.toast,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.accentSoft),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(color: AppColors.scrim, blurRadius: 18, offset: Offset(0, 6)),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            child: Text(
                              AppTypography.signs(message.text),
                              textAlign: TextAlign.center,
                              style: AppTypography.ui(size: 13, weight: AppWeight.medium, color: AppColors.textPrimary),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
