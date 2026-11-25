import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';

typedef FocusOnKeyDownCallback = KeyEventResult Function();

/// 高亮组件（支持长按）
class HighlightWidget extends StatefulWidget {
  final AppFocusNode focusNode;
  final Widget child;
  final FocusOnKeyDownCallback? onUpKey;
  final FocusOnKeyDownCallback? onDownKey;
  final FocusOnKeyDownCallback? onLeftKey;
  final FocusOnKeyDownCallback? onRightKey;
  final Function(bool)? onFocusChange;
  final Function()? onTap;
  final Function()? onLongPress;
  final Color foucsedColor;
  final Color color;
  final bool autofocus;
  final BorderRadius? borderRadius;
  final double order;
  final bool selected;

  const HighlightWidget({
    required this.focusNode,
    required this.child,
    this.onUpKey,
    this.onDownKey,
    this.onLeftKey,
    this.onRightKey,
    this.onFocusChange,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.selected = false,
    this.borderRadius,
    this.order = 0.0,
    this.color = Colors.transparent,
    this.foucsedColor = Colors.white,
    Key? key,
  }) : super(key: key);

  @override
  State<HighlightWidget> createState() => _HighlightWidgetState();
}

class _HighlightWidgetState extends State<HighlightWidget> {
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  // 只有本次「按下」被我们受理过，才处理配对的「抬起」。
  // 弹窗在按下的瞬间就响应并关闭，焦点随即回到本按钮，同一个按键的抬起
  // 会落回这里：以前会再触发一次 onTap（表现为弹窗又被调起、点"取消"没反应）。
  bool _enterDown = false;

  void _resetKeyState() {
    _longPressTimer?.cancel();
    _longPressTriggered = false;
    _enterDown = false;
  }

  @override
  void didUpdateWidget(covariant HighlightWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _resetKeyState();
    }
  }

  void _handleKeyEvent(KeyEvent e) {
    if (e is KeyDownEvent) {
      if (e.logicalKey == LogicalKeyboardKey.enter ||
          e.logicalKey == LogicalKeyboardKey.select ||
          e.logicalKey == LogicalKeyboardKey.space) {
        _enterDown = true;
        _longPressTriggered = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 600), () {
          _longPressTriggered = true;
          widget.onLongPress?.call();
        });
      }
    } else if (e is KeyUpEvent) {
      if (e.logicalKey == LogicalKeyboardKey.enter ||
          e.logicalKey == LogicalKeyboardKey.select ||
          e.logicalKey == LogicalKeyboardKey.space) {
        // 没有对应的按下（例如弹窗刚关闭、焦点才回到本按钮）就不触发
        if (!_enterDown) {
          return;
        }
        _enterDown = false;
        _longPressTimer?.cancel();
        if (!_longPressTriggered) {
          widget.onTap?.call();
        }
        _longPressTriggered = false;
      }
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) {
          if (!hasFocus) {
            _resetKeyState();
          }
          widget.onFocusChange?.call(hasFocus);
        },
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent) {
            if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
              return widget.onRightKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
              return widget.onLeftKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
              return widget.onUpKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
              return widget.onDownKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.space) {
              _handleKeyEvent(e);
              return KeyEventResult.handled; 
            }
          } else if (e is KeyUpEvent) {
            if (e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.space) {
              _handleKeyEvent(e);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Obx(
            () => AnimatedScale(
              scale: widget.focusNode.isFoucsed.value ? 1.1 : 1,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    boxShadow: widget.focusNode.isFoucsed.value
                        ? AppStyle.highlightShadow
                        : null,
                    color: (widget.focusNode.isFoucsed.value || widget.selected)
                        ? widget.foucsedColor
                        : widget.color,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
