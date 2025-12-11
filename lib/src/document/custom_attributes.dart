import 'attribute.dart';

// Attributes that don't conform to standard Quill Delta
// and are not compatible with https://quilljs.com/docs/delta/

/// This attribute represents the space between text lines. The line height can be
/// adjusted using predefined constants or custom values
///
/// The attribute at the json looks like: "attributes":{"line-height": 1.5 }
class LineHeightAttribute extends Attribute<double?> {
  const LineHeightAttribute({double? lineHeight})
      : super('line-height', AttributeScope.block, lineHeight);

  static const Attribute<double?> lineHeightNormal =
      LineHeightAttribute(lineHeight: 1);

  static const Attribute<double?> lineHeightTight =
      LineHeightAttribute(lineHeight: 1.15);

  static const Attribute<double?> lineHeightOneAndHalf =
      LineHeightAttribute(lineHeight: 1.5);

  static const Attribute<double?> lineHeightDouble =
      LineHeightAttribute(lineHeight: 2);
}

/// This attribute represents the reminder time for a task/checkbox item.
/// The value is stored as milliseconds since epoch (DateTime.millisecondsSinceEpoch).
///
/// The attribute at the json looks like: "attributes":{"task-reminder": 1234567890123 }
class TaskReminderAttribute extends Attribute<int?> {
  const TaskReminderAttribute({int? reminderTime})
      : super('task-reminder', AttributeScope.block, reminderTime);
}

/// This attribute represents the priority level for a task/checkbox item.
/// Priority values: 1 = low, 2 = medium, 3 = high
///
/// The attribute at the json looks like: "attributes":{"task-priority": 2 }
class TaskPriorityAttribute extends Attribute<int?> {
  const TaskPriorityAttribute({int? priority})
      : super('task-priority', AttributeScope.block, priority);

  static const Attribute<int?> low = TaskPriorityAttribute(priority: 1);
  static const Attribute<int?> medium = TaskPriorityAttribute(priority: 2);
  static const Attribute<int?> high = TaskPriorityAttribute(priority: 3);
}
