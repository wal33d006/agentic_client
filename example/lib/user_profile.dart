import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// Schema = the prop sockets this widget reads. Nothing more.
/// Adding more fields on the backend is a no-op here until you decide
/// to render them.
final _userProfileSchema = S.object(
  properties: {'name': A2uiSchemas.stringReference(), 'email': A2uiSchemas.stringReference()},
  required: ['name', 'email'],
);

final userProfileItem = CatalogItem(
  name: 'UserProfile',
  dataSchema: _userProfileSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundString(
      dataContext: ctx.dataContext,
      value: data['name'],
      builder: (_, name) => BoundString(
        dataContext: ctx.dataContext,
        value: data['email'],
        builder: (_, email) => _UserProfileTile(name: name ?? '', email: email ?? ''),
      ),
    );
  },
);

class _UserProfileTile extends StatelessWidget {
  const _UserProfileTile({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          title: Text(name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            email,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
