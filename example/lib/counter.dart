import 'package:a2ui_core/a2ui_core.dart' show CommonSchemas;
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// Schema = the prop sockets this widget reads. Nothing more.
/// Adding more fields on the backend is a no-op here until you decide
/// to render them.
final _counterSchema = S.object(
  properties: {'count': CommonSchemas.dynamicString},
  required: ['count'],
  additionalProperties: true,
);

final counterItem = ComponentImplementation(
  name: 'MyCounter',
  schema: _counterSchema,
  builder: (context, node, props, buildChild) => _CounterTile(
    count: props.string('count') ?? '0',
    // Taps dispatch actions that AguiChat hands to the transport, which
    // packs them into `forwarded_props.pending_action` for the backend.
    onIncrement: () => node.context?.dispatchAction({
      'event': {'name': 'increment'},
    }),
    onDecrement: () => node.context?.dispatchAction({
      'event': {'name': 'decrement'},
    }),
  ),
);

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.count,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String count;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CounterButton(icon: Icons.remove, onPressed: onDecrement),
          // Fixed minimum width so 1 → 10 → 100 doesn't shift the buttons.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                count,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
          _CounterButton(icon: Icons.add, onPressed: onIncrement),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: scheme.onPrimary, size: 20),
        ),
      ),
    );
  }
}
