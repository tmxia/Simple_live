










import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class CommentTypeTag extends $pb.ProtobufEnum {
  static const CommentTypeTag COMMENTTYPETAGUNKNOWN = CommentTypeTag._(0, _omitEnumNames ? '' : 'COMMENTTYPETAGUNKNOWN');
  static const CommentTypeTag COMMENTTYPETAGSTAR = CommentTypeTag._(1, _omitEnumNames ? '' : 'COMMENTTYPETAGSTAR');

  static const $core.List<CommentTypeTag> values = <CommentTypeTag> [
    COMMENTTYPETAGUNKNOWN,
    COMMENTTYPETAGSTAR,
  ];

  static final $core.Map<$core.int, CommentTypeTag> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CommentTypeTag? valueOf($core.int value) => _byValue[value];

  const CommentTypeTag._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
