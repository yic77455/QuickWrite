// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'writing_stat.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWritingStatModelCollection on Isar {
  IsarCollection<WritingStatModel> get writingStatModels => this.collection();
}

const WritingStatModelSchema = CollectionSchema(
  name: r'WritingStatModel',
  id: 8214268691442849871,
  properties: {
    r'bookUuid': PropertySchema(
      id: 0,
      name: r'bookUuid',
      type: IsarType.string,
    ),
    r'date': PropertySchema(
      id: 1,
      name: r'date',
      type: IsarType.dateTime,
    ),
    r'durationSeconds': PropertySchema(
      id: 2,
      name: r'durationSeconds',
      type: IsarType.long,
    ),
    r'typedWords': PropertySchema(
      id: 3,
      name: r'typedWords',
      type: IsarType.long,
    ),
    r'updatedAt': PropertySchema(
      id: 4,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'wordsAdded': PropertySchema(
      id: 5,
      name: r'wordsAdded',
      type: IsarType.long,
    )
  },
  estimateSize: _writingStatModelEstimateSize,
  serialize: _writingStatModelSerialize,
  deserialize: _writingStatModelDeserialize,
  deserializeProp: _writingStatModelDeserializeProp,
  idName: r'id',
  indexes: {
    r'bookUuid': IndexSchema(
      id: -1177453174310852450,
      name: r'bookUuid',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'bookUuid',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'date': IndexSchema(
      id: -7552997827385218417,
      name: r'date',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'date',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _writingStatModelGetId,
  getLinks: _writingStatModelGetLinks,
  attach: _writingStatModelAttach,
  version: '3.1.0+1',
);

int _writingStatModelEstimateSize(
  WritingStatModel object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.bookUuid.length * 3;
  return bytesCount;
}

void _writingStatModelSerialize(
  WritingStatModel object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.bookUuid);
  writer.writeDateTime(offsets[1], object.date);
  writer.writeLong(offsets[2], object.durationSeconds);
  writer.writeLong(offsets[3], object.typedWords);
  writer.writeDateTime(offsets[4], object.updatedAt);
  writer.writeLong(offsets[5], object.wordsAdded);
}

WritingStatModel _writingStatModelDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WritingStatModel();
  object.bookUuid = reader.readString(offsets[0]);
  object.date = reader.readDateTime(offsets[1]);
  object.durationSeconds = reader.readLong(offsets[2]);
  object.id = id;
  object.typedWords = reader.readLong(offsets[3]);
  object.updatedAt = reader.readDateTime(offsets[4]);
  object.wordsAdded = reader.readLong(offsets[5]);
  return object;
}

P _writingStatModelDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _writingStatModelGetId(WritingStatModel object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _writingStatModelGetLinks(WritingStatModel object) {
  return [];
}

void _writingStatModelAttach(
    IsarCollection<dynamic> col, Id id, WritingStatModel object) {
  object.id = id;
}

extension WritingStatModelQueryWhereSort
    on QueryBuilder<WritingStatModel, WritingStatModel, QWhere> {
  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhere> anyDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'date'),
      );
    });
  }
}

extension WritingStatModelQueryWhere
    on QueryBuilder<WritingStatModel, WritingStatModel, QWhereClause> {
  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      bookUuidEqualTo(String bookUuid) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'bookUuid',
        value: [bookUuid],
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      bookUuidNotEqualTo(String bookUuid) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookUuid',
              lower: [],
              upper: [bookUuid],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookUuid',
              lower: [bookUuid],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookUuid',
              lower: [bookUuid],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookUuid',
              lower: [],
              upper: [bookUuid],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      dateEqualTo(DateTime date) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'date',
        value: [date],
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      dateNotEqualTo(DateTime date) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      dateGreaterThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [date],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      dateLessThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [],
        upper: [date],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterWhereClause>
      dateBetween(
    DateTime lowerDate,
    DateTime upperDate, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [lowerDate],
        includeLower: includeLower,
        upper: [upperDate],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension WritingStatModelQueryFilter
    on QueryBuilder<WritingStatModel, WritingStatModel, QFilterCondition> {
  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bookUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bookUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bookUuid',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'bookUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'bookUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'bookUuid',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'bookUuid',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      bookUuidIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'bookUuid',
        value: '',
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      dateEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      dateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      dateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      dateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'date',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      durationSecondsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'durationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      durationSecondsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'durationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      durationSecondsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'durationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      durationSecondsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'durationSeconds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      typedWordsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'typedWords',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      typedWordsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'typedWords',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      typedWordsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'typedWords',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      typedWordsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'typedWords',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      wordsAddedEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'wordsAdded',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      wordsAddedGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'wordsAdded',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      wordsAddedLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'wordsAdded',
        value: value,
      ));
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterFilterCondition>
      wordsAddedBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'wordsAdded',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension WritingStatModelQueryObject
    on QueryBuilder<WritingStatModel, WritingStatModel, QFilterCondition> {}

extension WritingStatModelQueryLinks
    on QueryBuilder<WritingStatModel, WritingStatModel, QFilterCondition> {}

extension WritingStatModelQuerySortBy
    on QueryBuilder<WritingStatModel, WritingStatModel, QSortBy> {
  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByBookUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookUuid', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByBookUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookUuid', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy> sortByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByDurationSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByTypedWords() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typedWords', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByTypedWordsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typedWords', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByWordsAdded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsAdded', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      sortByWordsAddedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsAdded', Sort.desc);
    });
  }
}

extension WritingStatModelQuerySortThenBy
    on QueryBuilder<WritingStatModel, WritingStatModel, QSortThenBy> {
  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByBookUuid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookUuid', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByBookUuidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookUuid', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy> thenByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByDurationSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByTypedWords() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typedWords', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByTypedWordsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typedWords', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByWordsAdded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsAdded', Sort.asc);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QAfterSortBy>
      thenByWordsAddedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsAdded', Sort.desc);
    });
  }
}

extension WritingStatModelQueryWhereDistinct
    on QueryBuilder<WritingStatModel, WritingStatModel, QDistinct> {
  QueryBuilder<WritingStatModel, WritingStatModel, QDistinct>
      distinctByBookUuid({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bookUuid', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QDistinct> distinctByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'date');
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QDistinct>
      distinctByDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'durationSeconds');
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QDistinct>
      distinctByTypedWords() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'typedWords');
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<WritingStatModel, WritingStatModel, QDistinct>
      distinctByWordsAdded() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'wordsAdded');
    });
  }
}

extension WritingStatModelQueryProperty
    on QueryBuilder<WritingStatModel, WritingStatModel, QQueryProperty> {
  QueryBuilder<WritingStatModel, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WritingStatModel, String, QQueryOperations> bookUuidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bookUuid');
    });
  }

  QueryBuilder<WritingStatModel, DateTime, QQueryOperations> dateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'date');
    });
  }

  QueryBuilder<WritingStatModel, int, QQueryOperations>
      durationSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'durationSeconds');
    });
  }

  QueryBuilder<WritingStatModel, int, QQueryOperations> typedWordsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'typedWords');
    });
  }

  QueryBuilder<WritingStatModel, DateTime, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<WritingStatModel, int, QQueryOperations> wordsAddedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'wordsAdded');
    });
  }
}
