import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/studio_state_notifier.dart';

class StudioKeyboardHandler extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onDeleteSelected;

  const StudioKeyboardHandler({
    super.key,
    required this.child,
    this.onTogglePlay,
    this.onDeleteSelected,
  });

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, WidgetRef ref) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isControl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Check if the user is currently focused on any child input widget
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isChildFocused = primaryFocus != null && primaryFocus != node;
    final isTextInputFocused = isChildFocused ||
        (primaryFocus?.context?.widget is EditableText) ||
        (primaryFocus?.debugLabel?.toLowerCase().contains('editable') == true) ||
        (primaryFocus?.debugLabel?.toLowerCase().contains('text') == true);

    // If any child input is focused, NEVER intercept Space, Backspace, or Delete
    if (isTextInputFocused) {
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        return KeyEventResult.ignored;
      }
    }

    // Space: Play / Pause
    if (event.logicalKey == LogicalKeyboardKey.space && !isControl) {
      if (onTogglePlay != null) {
        onTogglePlay!();
        return KeyEventResult.handled;
      }
    }

    // Ctrl+Z: Undo
    if (isControl && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      ref.read(studioStateProvider.notifier).undo();
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+Z or Ctrl+Y: Redo
    if ((isControl && isShift && event.logicalKey == LogicalKeyboardKey.keyZ) ||
        (isControl && event.logicalKey == LogicalKeyboardKey.keyY)) {
      ref.read(studioStateProvider.notifier).redo();
      return KeyEventResult.handled;
    }

    // Delete / Backspace: Delete active selection when NOT typing
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (onDeleteSelected != null) {
        onDeleteSelected!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(node, event, ref),
      child: child,
    );
  }
}
