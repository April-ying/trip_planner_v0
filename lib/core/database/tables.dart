import 'package:drift/drift.dart';

class Rois extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get isOfflineCached => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Animes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get bangumiId => text().nullable().unique()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Pois extends Table {
  TextColumn get id => text()();
  TextColumn get roiId =>
      text().nullable().references(Rois, #id, onDelete: KeyAction.setNull)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get address => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get businessHours => text().nullable()();
  TextColumn get contactInfo => text().nullable()();
  TextColumn get coverImageUri => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PoiAnimes extends Table {
  TextColumn get poiId =>
      text().references(Pois, #id, onDelete: KeyAction.cascade)();
  TextColumn get animeId =>
      text().references(Animes, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {poiId, animeId};
}

class PoiTags extends Table {
  TextColumn get poiId =>
      text().references(Pois, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {poiId, tagId};
}

class TimeChunks extends Table {
  TextColumn get id => text()();
  TextColumn get poiId => text().references(Pois, #id)();
  TextColumn get date => text().nullable()();
  TextColumn get startTime => text().nullable()();
  TextColumn get endTime => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('backlog'))();

  @override
  Set<Column> get primaryKey => {id};
}

class ReferenceImages extends Table {
  TextColumn get id => text()();
  TextColumn get poiId => text().references(Pois, #id)();
  TextColumn get localUri => text()();
  TextColumn get remoteUrl => text().nullable()();
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class MediaAssets extends Table {
  TextColumn get id => text()();
  TextColumn get poiId => text().references(Pois, #id)();
  TextColumn get type => text()();
  TextColumn get localUri => text()();
  TextColumn get remoteUrl => text().nullable()();
  TextColumn get metadata => text().nullable()();
  TextColumn get referenceImageId => text()
      .nullable()
      .references(ReferenceImages, #id, onDelete: KeyAction.setNull)();

  @override
  Set<Column> get primaryKey => {id};
}
