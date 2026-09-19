import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The redesign's code-entry row (Figma `customer-otp` 22:165).
///
/// Measured: a centred row of square cells, 64px, radius [DeliveryRadius.lg], 16px apart. A cell
/// holding a digit — or the one the caret is in — is white with a 2px [DeliveryColors.brand]
/// border and a brand-tinted lift; an empty cell is white with a 1px [DeliveryColors.borderFaint]
/// border. Digits are Rubik Bold 24 in [DeliveryColors.ink], and the active empty cell shows the
/// design's 2×24 brand caret.
///
/// [length] is parameterised because the design draws four digits for the SMS code while other
/// flows in the codebase use six; the cells shrink to fit rather than overflowing, so a six-digit
/// code still lays out inside the 24px screen gutters.
///
/// Behaviour: one real [TextField] sits transparently over the cells and owns the text, so
/// hardware keyboards, backspace, IME and the platform's one-time-code autofill all behave
/// normally. Tapping anywhere on the row focuses it.
class YdOtpCells extends StatefulWidget {
  const YdOtpCells({
    super.key,
    this.length = 4,
    this.controller,
    this.focusNode,
    this.autofocus = true,
    this.enabled = true,
    this.hasError = false,
    this.onChanged,
    this.onCompleted,
    this.cellSize = 64,
    this.gap = DeliverySpacing.md,
    this.semanticLabel,
  });

  /// Number of digits. 4 on the redesigned SMS screen; pass 6 where the flow still sends six.
  final int length;

  /// Optional external controller, so the screen can clear or prefill the code. When omitted one
  /// is created and disposed internally.
  final TextEditingController? controller;

  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Paints every cell's border with [DeliveryAccent.critical] — for a rejected code.
  final bool hasError;

  final ValueChanged<String>? onChanged;

  /// Fired once the last cell is filled.
  final ValueChanged<String>? onCompleted;

  /// The design's cell edge. Cells shrink below this when the row would not otherwise fit.
  final double cellSize;

  final double gap;

  /// Accessibility label for the whole row, localised by the caller.
  final String? semanticLabel;

  @override
  State<YdOtpCells> createState() => _YdOtpCellsState();
}

class _YdOtpCellsState extends State<YdOtpCells> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();

  bool get _ownsController => widget.controller == null;
  bool get _ownsFocusNode => widget.focusNode == null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  String _last = '';

  void _onTextChanged() {
    final String value = _controller.text;
    if (value == _last) {
      return;
    }
    _last = value;
    setState(() {});
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final String value = _controller.text;
    final bool focused = _focusNode.hasFocus;

    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      child: _CellRowSize(
        length: widget.length,
        cellSize: widget.cellSize,
        gap: widget.gap,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double side =
                _cellSide(constraints.maxWidth, widget.length, widget.cellSize, widget.gap);

            return Stack(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < widget.length; i++) ...<Widget>[
                      if (i > 0) SizedBox(width: widget.gap),
                      _YdOtpCell(
                        size: side,
                        digit: i < value.length ? value[i] : null,
                        // The caret sits in the first empty cell, and only while focused.
                        active: focused && i == value.length,
                        hasError: widget.hasError,
                      ),
                    ],
                  ],
                ),
                // The real field: full-bleed and invisible, so a tap anywhere focuses it and the
                // platform keyboard drives the cells above.
                Positioned.fill(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.oneTimeCode],
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    style: const TextStyle(color: Colors.transparent, height: 1),
                    cursorColor: Colors.transparent,
                    decoration: const InputDecoration(
                      filled: false,
                      isDense: true,
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The edge of each square cell when the row has [available] width: the design's [cellSize], or
/// less so that [length] cells and the gaps between them still fit.
double _cellSide(double available, int length, double cellSize, double gap) {
  final double totalGap = gap * (length - 1);
  return available.isFinite ? math.min(cellSize, (available - totalGap) / length) : cellSize;
}

/// Answers the size questions the row's [LayoutBuilder] cannot.
///
/// A layout that measures its content before laying it out — a [SliverFillRemaining] with
/// `hasScrollBody: false`, as the partner wizard's code step sits in, or an [IntrinsicHeight] — asks
/// the row how tall it would be at a width. A [LayoutBuilder] cannot say without running its builder:
/// it throws in a debug build and answers zero in release, which under-measures the screen by the
/// whole row. The answer needs no builder — the cells are square, as wide as [_cellSide] makes them
/// at that width — so this gives it, by the same rule the row lays out by. Layout itself passes
/// straight through.
class _CellRowSize extends SingleChildRenderObjectWidget {
  const _CellRowSize({
    required this.length,
    required this.cellSize,
    required this.gap,
    required Widget super.child,
  });

  final int length;
  final double cellSize;
  final double gap;

  @override
  _RenderCellRowSize createRenderObject(BuildContext context) =>
      _RenderCellRowSize(length: length, cellSize: cellSize, gap: gap);

  @override
  void updateRenderObject(BuildContext context, _RenderCellRowSize renderObject) {
    renderObject
      ..length = length
      ..cellSize = cellSize
      ..gap = gap;
  }
}

class _RenderCellRowSize extends RenderProxyBox {
  _RenderCellRowSize({required int length, required double cellSize, required double gap})
      : _length = length,
        _cellSize = cellSize,
        _gap = gap;

  int _length;
  set length(int value) {
    if (value == _length) return;
    _length = value;
    markNeedsLayout();
  }

  double _cellSize;
  set cellSize(double value) {
    if (value == _cellSize) return;
    _cellSize = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  /// The row at the design's own size: every cell full-size.
  double get _naturalWidth => _length * _cellSize + _gap * (_length - 1);

  @override
  double computeMinIntrinsicWidth(double height) => _naturalWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => _naturalWidth;

  @override
  double computeMinIntrinsicHeight(double width) => _cellSide(width, _length, _cellSize, _gap);

  @override
  double computeMaxIntrinsicHeight(double width) => _cellSide(width, _length, _cellSize, _gap);
}

class _YdOtpCell extends StatelessWidget {
  const _YdOtpCell({
    required this.size,
    required this.digit,
    required this.active,
    required this.hasError,
  });

  final double size;
  final String? digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final bool lit = digit != null || active;
    final Color borderColor = hasError
        ? DeliveryAccent.critical.color
        : lit
            ? DeliveryColors.brand
            : DeliveryColors.borderFaint;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        border: Border.all(color: borderColor, width: lit || hasError ? 2 : 1),
        boxShadow: lit
            ? <BoxShadow>[
                BoxShadow(
                  color: DeliveryColors.brand.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: digit != null
          ? Text(
              digit!,
              style: TextStyle(
                // 24 at the designed 64px cell; scaled down with the cell so a six-digit code
                // still reads as one row rather than as clipped glyphs.
                fontSize: 24 * (size / 64).clamp(0.65, 1.0),
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.2,
              ),
            )
          : active
              ? Container(
                  width: 2,
                  height: 24,
                  decoration: BoxDecoration(
                    color: DeliveryColors.brand,
                    borderRadius: BorderRadius.circular(1),
                  ),
                )
              : null,
    );
  }
}
