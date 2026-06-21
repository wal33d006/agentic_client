import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// Schema = the prop sockets this widget reads. Nothing more.
/// Adding more fields on the backend is a no-op here until you decide
/// to render them.
final _buttonSchema = S.object(properties: {'title': A2uiSchemas.stringReference()}, required: ['title']);

final buttonItem = CatalogItem(
  name: 'MyButton',
  dataSchema: _buttonSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundString(
      dataContext: ctx.dataContext,
      value: data['title'],
      builder: (_, name) => _UserProfileTile(title: name ?? ''),
    );
  },
);

class _UserProfileTile extends StatelessWidget {
  const _UserProfileTile({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: () {}, child: Text('title'));
  }
}
