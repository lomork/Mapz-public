// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovered_road.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetDiscoveredRoadCollection on Isar {
  IsarCollection<DiscoveredRoad> get discoveredRoads => this.collection();
}

const DiscoveredRoadSchema = CollectionSchema(
  name: r'DiscoveredRoad',
  id: 1312444566418923223,
  properties: {
    r'latitude': PropertySchema(
      id: 0,
      name: r'latitude',
      type: IsarType.double,
    ),
    r'longitude': PropertySchema(
      id: 1,
      name: r'longitude',
      type: IsarType.double,
    ),
    r'placeId': PropertySchema(
      id: 2,
      name: r'placeId',
      type: IsarType.string,
    )
  },
  estimateSize: _discoveredRoadEstimateSize,
  serialize: _discoveredRoadSerialize,
  deserialize: _discoveredRoadDeserialize,
  deserializeProp: _discoveredRoadDeserializeProp,
  idName: r'id',
  indexes: {
    r'placeId': IndexSchema(
      id: 5619906205779282708,
      name: r'placeId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'placeId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _discoveredRoadGetId,
  getLinks: _discoveredRoadGetLinks,
  attach: _discoveredRoadAttach,
  version: '3.1.0+1',
);

int _discoveredRoadEstimateSize(
  DiscoveredRoad object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.placeId.length * 3;
  return bytesCount;
}

void _discoveredRoadSerialize(
  DiscoveredRoad object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.latitude);
  writer.writeDouble(offsets[1], object.longitude);
  writer.writeString(offsets[2], object.placeId);
}

DiscoveredRoad _discoveredRoadDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DiscoveredRoad();
  object.id = id;
  object.latitude = reader.readDouble(offsets[0]);
  object.longitude = reader.readDouble(offsets[1]);
  object.placeId = reader.readString(offsets[2]);
  return object;
}

P _discoveredRoadDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDouble(offset)) as P;
    case 1:
      return (reader.readDouble(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _discoveredRoadGetId(DiscoveredRoad object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _discoveredRoadGetLinks(DiscoveredRoad object) {
  return [];
}

void _discoveredRoadAttach(
    IsarCollection<dynamic> col, Id id, DiscoveredRoad object) {
  object.id = id;
}

extension DiscoveredRoadByIndex on IsarCollection<DiscoveredRoad> {
  Future<DiscoveredRoad?> getByPlaceId(String placeId) {
    return getByIndex(r'placeId', [placeId]);
  }

  DiscoveredRoad? getByPlaceIdSync(String placeId) {
    return getByIndexSync(r'placeId', [placeId]);
  }

  Future<bool> deleteByPlaceId(String placeId) {
    return deleteByIndex(r'placeId', [placeId]);
  }

  bool deleteByPlaceIdSync(String placeId) {
    return deleteByIndexSync(r'placeId', [placeId]);
  }

  Future<List<DiscoveredRoad?>> getAllByPlaceId(List<String> placeIdValues) {
    final values = placeIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'placeId', values);
  }

  List<DiscoveredRoad?> getAllByPlaceIdSync(List<String> placeIdValues) {
    final values = placeIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'placeId', values);
  }

  Future<int> deleteAllByPlaceId(List<String> placeIdValues) {
    final values = placeIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'placeId', values);
  }

  int deleteAllByPlaceIdSync(List<String> placeIdValues) {
    final values = placeIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'placeId', values);
  }

  Future<Id> putByPlaceId(DiscoveredRoad object) {
    return putByIndex(r'placeId', object);
  }

  Id putByPlaceIdSync(DiscoveredRoad object, {bool saveLinks = true}) {
    return putByIndexSync(r'placeId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPlaceId(List<DiscoveredRoad> objects) {
    return putAllByIndex(r'placeId', objects);
  }

  List<Id> putAllByPlaceIdSync(List<DiscoveredRoad> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'placeId', objects, saveLinks: saveLinks);
  }
}

extension DiscoveredRoadQueryWhereSort
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QWhere> {
  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension DiscoveredRoadQueryWhere
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QWhereClause> {
  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause> idBetween(
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

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause>
      placeIdEqualTo(String placeId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'placeId',
        value: [placeId],
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterWhereClause>
      placeIdNotEqualTo(String placeId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'placeId',
              lower: [],
              upper: [placeId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'placeId',
              lower: [placeId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'placeId',
              lower: [placeId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'placeId',
              lower: [],
              upper: [placeId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension DiscoveredRoadQueryFilter
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QFilterCondition> {
  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
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

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
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

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition> idBetween(
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

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      latitudeEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      latitudeGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      latitudeLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      latitudeBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'latitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      longitudeEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      longitudeGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      longitudeLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      longitudeBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'longitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'placeId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'placeId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'placeId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'placeId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'placeId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'placeId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'placeId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'placeId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'placeId',
        value: '',
      ));
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterFilterCondition>
      placeIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'placeId',
        value: '',
      ));
    });
  }
}

extension DiscoveredRoadQueryObject
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QFilterCondition> {}

extension DiscoveredRoadQueryLinks
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QFilterCondition> {}

extension DiscoveredRoadQuerySortBy
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QSortBy> {
  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> sortByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy>
      sortByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> sortByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy>
      sortByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> sortByPlaceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'placeId', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy>
      sortByPlaceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'placeId', Sort.desc);
    });
  }
}

extension DiscoveredRoadQuerySortThenBy
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QSortThenBy> {
  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> thenByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy>
      thenByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> thenByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy>
      thenByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy> thenByPlaceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'placeId', Sort.asc);
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QAfterSortBy>
      thenByPlaceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'placeId', Sort.desc);
    });
  }
}

extension DiscoveredRoadQueryWhereDistinct
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QDistinct> {
  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QDistinct> distinctByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'latitude');
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QDistinct>
      distinctByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'longitude');
    });
  }

  QueryBuilder<DiscoveredRoad, DiscoveredRoad, QDistinct> distinctByPlaceId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'placeId', caseSensitive: caseSensitive);
    });
  }
}

extension DiscoveredRoadQueryProperty
    on QueryBuilder<DiscoveredRoad, DiscoveredRoad, QQueryProperty> {
  QueryBuilder<DiscoveredRoad, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DiscoveredRoad, double, QQueryOperations> latitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'latitude');
    });
  }

  QueryBuilder<DiscoveredRoad, double, QQueryOperations> longitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'longitude');
    });
  }

  QueryBuilder<DiscoveredRoad, String, QQueryOperations> placeIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'placeId');
    });
  }
}
