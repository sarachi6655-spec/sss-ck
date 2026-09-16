import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/document_value.dart';

/// Error boundary protecting the editor canvas from crashing if a plugin or renderer fails.
class WatchdogBoundary extends StatefulWidget {
  const WatchdogBoundary({
    super.key,
    this.child,
    this.builder,
    required this.controller,
    this.fallbackBuilder,
  }) : assert(child != null || builder != null, 'Must provide either child or builder');

  final Widget? child;
  final Widget Function(BuildContext context)? builder;
  final RichEditorController controller;
  final Widget Function(BuildContext context, Object error, DocumentValue lastValidDoc)?
      fallbackBuilder;

  @override
  State<WatchdogBoundary> createState() => _WatchdogBoundaryState();
}

class _WatchdogBoundaryState extends State<WatchdogBoundary> {
  Object? _caughtError;

  void resetError() {
    setState(() {
      _caughtError = null;
    });
  }

  Widget _buildFallback(BuildContext context, Object error) {
    if (widget.fallbackBuilder != null) {
      return widget.fallbackBuilder!(
        context,
        error,
        widget.controller.lastValidDocument,
      );
    }
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
              SizedBox(width: 8.0),
              Text(
                'Editor encountered an error',
                style: TextStyle(
                  color: Color(0xFF991B1B),
                  fontWeight: FontWeight.bold,
                  fontSize: 16.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Text(
            'Your content has been preserved in the last valid state.',
            style: TextStyle(color: Colors.grey.shade800),
          ),
          const SizedBox(height: 12.0),
          ElevatedButton(
            onPressed: () {
              widget.controller.import(widget.controller.lastValidDocument);
              resetError();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Recover Document'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_caughtError != null) {
      return _buildFallback(context, _caughtError!);
    }

    if (widget.builder != null) {
      try {
        return widget.builder!(context);
      } catch (e) {
        _caughtError = e;
        return _buildFallback(context, e);
      }
    }

    return widget.child!;
  }
}
