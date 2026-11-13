import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'app_icons.dart';

/// A single-line text field (system keyboard) in the look of the app.
class AppTextField extends StatefulWidget {
  const AppTextField({super.key, required this.onChanged, this.hint = '', this.leading});

  final ValueChanged<String> onChanged;
  final String hint;
  final AppIconGlyph? leading;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.ui(size: 14, color: AppColors.textPrimary);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.bgObsidian,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _focus.hasFocus ? AppColors.accent : AppColors.panelBorder),
        ),
        child: Row(
          children: <Widget>[
            if (widget.leading != null) ...<Widget>[
              AppIcon(widget.leading!, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  if (_controller.text.isEmpty)
                    Text(widget.hint, maxLines: 1, style: style.copyWith(color: AppColors.textFaint)),
                  EditableText(
                    controller: _controller,
                    focusNode: _focus,
                    style: style,
                    cursorColor: AppColors.caret,
                    backgroundCursorColor: AppColors.textFaint,
                    selectionColor: AppColors.accentSoft,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    onChanged: widget.onChanged,
                  ),
                ],
              ),
            ),
            if (_controller.text.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _controller.clear();
                  widget.onChanged('');
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: AppIcon(AppIconGlyph.close, size: 14, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
