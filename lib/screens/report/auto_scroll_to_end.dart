part of '../report_screen.dart';

class _AutoScrollToEnd extends StatefulWidget {
  final String signature;
  final Widget Function(ScrollController controller) builder;
  const _AutoScrollToEnd({
    required this.signature,
    required this.builder,
  });
  @override
  State<_AutoScrollToEnd> createState() => _AutoScrollToEndState();
}

class _AutoScrollToEndState extends State<_AutoScrollToEnd> {
  final ScrollController _controller = ScrollController();
  bool _hasScrolled = false;

  @override
  void didUpdateWidget(covariant _AutoScrollToEnd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.signature != oldWidget.signature) {
      _hasScrolled = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToEndProperly() {
    if (_hasScrolled || !_controller.hasClients) return;

    final double maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent <= 0) {
      _hasScrolled = true;
      return;
    }

    _controller.animateTo(
      maxExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    _hasScrolled = true;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEndProperly();
    });
    return widget.builder(_controller);
  }
}
