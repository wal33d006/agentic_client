import 'package:a2ui_core/a2ui_core.dart' show CommonSchemas;
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// Schema = the prop sockets this widget reads. Nothing more.
/// Adding more fields on the backend is a no-op here until you decide
/// to render them.
final _buttonSchema = S.object(
  properties: {'title': CommonSchemas.dynamicString},
  required: ['title'],
  additionalProperties: true,
);

final buttonItem = ComponentImplementation(
  name: 'MyButton',
  schema: _buttonSchema,
  builder: (context, node, props, buildChild) => _UserProfileTile(title: props.string('title') ?? ''),
);

class _UserProfileTile extends StatelessWidget {
  const _UserProfileTile({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: () {}, child: Text('title'));
  }
}
