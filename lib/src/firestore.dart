// Copyright (c) 2018, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:js';

import 'package:firestore_interop/firestore_interop.dart' as js;
import 'package:js/js.dart';
import 'package:node_interop/stream.dart';
import 'package:node_interop/util.dart';
import 'app.dart';
import 'bindings.dart' show AppOptions;

export 'bindings.dart' show AppOptions;

void _loadFirestore() {
  if (!context.hasProperty('FirebaseFirestore')) {
    context['FirebaseFirestore'] =
        context.callMethod('require', ['@google-cloud/firestore']);
  }
}

js.Firestore _initWithOptions(AppOptions options) {
  _loadFirestore();
  return new js.Firestore(options);
}

js.Firestore _initWithApp(App app) {
  _loadFirestore();
  return app.nativeInstance.firestore();
}

/// Represents a Firestore Database and is the entry point for all
/// Firestore operations.
class Firestore {
  final js.Firestore _nativeInstance;

  Firestore._(this._nativeInstance);

  Firestore(AppOptions options) : _nativeInstance = _initWithOptions(options);
  Firestore.forApp(App app) : _nativeInstance = _initWithApp(app);

  /// Gets a [CollectionReference] for the specified Firestore path.
  CollectionReference collection(String path) {
    assert(path != null);
    return new CollectionReference._(_nativeInstance.collection(path), this);
  }

  /// Gets a [DocumentReference] for the specified Firestore path.
  DocumentReference document(String path) {
    assert(path != null);
    return new DocumentReference._(_nativeInstance.doc(path), this);
  }
}

/// A CollectionReference object can be used for adding documents, getting
/// document references, and querying for documents (using the methods
/// inherited from [DocumentQuery]).
class CollectionReference extends DocumentQuery {
  CollectionReference._(
      js.CollectionReference nativeInstance, Firestore firestore)
      : super._(nativeInstance, firestore);

  @override
  js.CollectionReference get _nativeInstance => super._nativeInstance;

  /// For subcollections, parent returns the containing DocumentReference.
  ///
  /// For root collections, null is returned.
  DocumentReference get parent {
    return (_nativeInstance.parent != null)
        ? new DocumentReference._(_nativeInstance.parent, _firestore)
        : null;
  }

  /// Returns a `DocumentReference` with the provided path.
  ///
  /// If no [path] is provided, an auto-generated ID is used.
  ///
  /// The unique key generated is prefixed with a client-generated timestamp
  /// so that the resulting list will be chronologically-sorted.
  DocumentReference document([String path]) =>
      new DocumentReference._(_nativeInstance.doc(path), _firestore);

  /// Returns a `DocumentReference` with an auto-generated ID, after
  /// populating it with provided [data].
  ///
  /// The unique key generated is prefixed with a client-generated timestamp
  /// so that the resulting list will be chronologically-sorted.
  Future<DocumentReference> add(Map<String, dynamic> data) {
    return promiseToFuture(_nativeInstance.add(jsify(data)))
        .then((jsRef) => new DocumentReference._(jsRef, _firestore));
  }
}

/// A [DocumentReference] refers to a document location in a Firestore database
/// and can be used to write, read, or listen to the location.
///
/// The document at the referenced location may or may not exist.
/// A [DocumentReference] can also be used to create a [CollectionReference]
/// to a subcollection.
class DocumentReference {
  DocumentReference._(this._nativeInstance, this._firestore);

  final Firestore _firestore;
  final js.DocumentReference _nativeInstance;

  /// Slash-delimited path representing the database location of this query.
  String get path => _nativeInstance.path;

  /// This document's given or generated ID in the collection.
  String get documentID => _nativeInstance.id;

  /// Writes to the document referred to by this [DocumentReference]. If the
  /// document does not yet exist, it will be created. If you pass [SetOptions],
  /// the provided data will be merged into an existing document.
  Future<Null> setData(Map<String, dynamic> data, [js.SetOptions options]) {
    // Even though bindings declare special DocumentData type, in reality
    // it's a regular POJO.
    final docData = jsify(data);
    if (options != null) {
      return promiseToFuture(_nativeInstance.set(docData, options));
    }
    return promiseToFuture(_nativeInstance.set(docData));
  }

  /// Updates fields in the document referred to by this [DocumentReference].
  ///
  /// If no document exists yet, the update will fail.
  Future<Null> updateData(Map<String, dynamic> data) {
    // Even though bindings declare special DocumentData type, in reality
    // it's a regular POJO.
    final docData = jsify(data);
    return promiseToFuture(_nativeInstance.update(docData));
  }

  /// Reads the document referenced by this [DocumentReference].
  ///
  /// If no document exists, the read will return null.
  Future<DocumentSnapshot> get() {
    return promiseToFuture(_nativeInstance.get())
        .then((jsSnapshot) => new DocumentSnapshot._(jsSnapshot, _firestore));
  }

  /// Deletes the document referred to by this [DocumentReference].
  Future<Null> delete() => promiseToFuture(_nativeInstance.delete());

  /// Returns the reference of a collection contained inside of this
  /// document.
  CollectionReference collection(String path) =>
      new CollectionReference._(_nativeInstance.collection(path), _firestore);

  /// Notifies of documents at this location.
  Stream<DocumentSnapshot> get snapshots {
    Function cancelCallback;
    // It's fine to let the StreamController be garbage collected once all the
    // subscribers have cancelled; this analyzer warning is safe to ignore.
    StreamController<DocumentSnapshot> controller; // ignore: close_sinks

    void _onNextSnapshot(js.DocumentSnapshot jsSnapshot) {
      controller.add(new DocumentSnapshot._(jsSnapshot, _firestore));
    }

    controller = new StreamController<DocumentSnapshot>.broadcast(
      onListen: () {
        cancelCallback =
            _nativeInstance.onSnapshot(allowInterop(_onNextSnapshot));
      },
      onCancel: () {
        cancelCallback();
      },
    );
    return controller.stream;
  }
}

/// An enumeration of document change types.
enum DocumentChangeType {
  /// Indicates a new document was added to the set of documents matching the
  /// query.
  added,

  /// Indicates a document within the query was modified.
  modified,

  /// Indicates a document within the query was removed (either deleted or no
  /// longer matches the query.
  removed,
}

/// A DocumentChange represents a change to the documents matching a query.
///
/// It contains the document affected and the type of change that occurred
/// (added, modified, or removed).
class DocumentChange {
  DocumentChange._(this._nativeInstance, this._firestore);

  final js.DocumentChange _nativeInstance;
  final Firestore _firestore;

  /// The type of change that occurred (added, modified, or removed).
  DocumentChangeType get type {
    if (_type != null) return _type;
    _type = DocumentChangeType.values.firstWhere((value) {
      return value.toString().endsWith(_nativeInstance.type);
    });
    return _type;
  }

  DocumentChangeType _type;

  /// The index of the changed document in the result set immediately prior to
  /// this [DocumentChange] (i.e. supposing that all prior DocumentChange objects
  /// have been applied).
  ///
  /// -1 for [DocumentChangeType.added] events.
  int get oldIndex => _nativeInstance.oldIndex.toInt();

  /// The index of the changed document in the result set immediately after this
  /// DocumentChange (i.e. supposing that all prior [DocumentChange] objects
  /// and the current [DocumentChange] object have been applied).
  ///
  /// -1 for [DocumentChangeType.removed] events.
  int get newIndex => _nativeInstance.newIndex.toInt();

  /// The document affected by this change.
  DocumentSnapshot get document =>
      _document ??= new DocumentSnapshot._(_nativeInstance.doc, _firestore);
  DocumentSnapshot _document;
}

class DocumentSnapshot {
  DocumentSnapshot._(this._nativeInstance, this._firestore);

  final Firestore _firestore;
  final js.DocumentSnapshot _nativeInstance;

  /// The reference that produced this snapshot
  DocumentReference get reference =>
      _reference ??= new DocumentReference._(_nativeInstance.ref, _firestore);
  DocumentReference _reference;

  /// Contains all the data of this snapshot
  Map<String, dynamic> get data => _data ??= dartify(_nativeInstance.data());
  Map<String, dynamic> _data;

  /// Reads individual values from the snapshot.
  dynamic operator [](String key) => data[key];

  /// Returns the ID of the snapshot's document
  String get documentID => reference.documentID;

  DateTime get createTime => _nativeInstance.createTime != null
      ? DateTime.parse(_nativeInstance.createTime)
      : null;

  DateTime get updateTime => DateTime.parse(_nativeInstance.updateTime);
}

/// A QuerySnapshot contains zero or more DocumentSnapshot objects.
class QuerySnapshot {
  QuerySnapshot._(this._nativeInstance, this._firestore);

  final Firestore _firestore;
  final js.QuerySnapshot _nativeInstance;

  /// Gets a list of all the documents included in this snapshot
  List<DocumentSnapshot> get documents => _documents ??= _nativeInstance.docs
      .map((jsDoc) => new DocumentSnapshot._(jsDoc, _firestore))
      .toList(growable: false);
  List<DocumentSnapshot> _documents;

  /// An array of the documents that changed since the last snapshot. If this
  /// is the first snapshot, all documents will be in the list as Added changes.
  List<DocumentChange> get documentChanges =>
      _changes ??= _nativeInstance.docChanges
          .map((jsChange) => new DocumentChange._(jsChange, _firestore))
          .toList(growable: false);
  List<DocumentChange> _changes;
}

/// Represents a query over the data at a particular location.
class DocumentQuery {
  DocumentQuery._(this._nativeInstance, this._firestore);

  final Firestore _firestore;
  final js.Query _nativeInstance;

  /// Notifies of query results at this location
  Stream<QuerySnapshot> get snapshots {
    // It's fine to let the StreamController be garbage collected once all the
    // subscribers have cancelled; this analyzer warning is safe to ignore.
    StreamController<QuerySnapshot> controller; // ignore: close_sinks

    void onSnapshot(js.QuerySnapshot snapshot) {
      controller.add(new QuerySnapshot._(snapshot, _firestore));
    }

    void onError(error) {
      controller.addError(error);
    }

    Readable stream;

    controller = new StreamController<QuerySnapshot>.broadcast(
      onListen: () {
        stream = _nativeInstance.stream();
        stream.on('data', allowInterop(onSnapshot));
        stream.on('error', allowInterop(onError));
      },
      onCancel: () {
        stream.removeAllListeners('data');
        stream.removeAllListeners('error');
      },
    );
    return controller.stream;
  }

  /// Creates and returns a new [DocumentQuery] with additional filter on specified
  /// [field].
  ///
  /// Only documents satisfying provided condition are included in the result
  /// set.
  DocumentQuery where(
    String field, {
    dynamic isEqualTo,
    dynamic isLessThan,
    dynamic isLessThanOrEqualTo,
    dynamic isGreaterThan,
    dynamic isGreaterThanOrEqualTo,
    bool isNull,
  }) {
    js.Query query = _nativeInstance;

    void addCondition(String field, String opStr, dynamic value) {
      query = query.where(field, opStr, value);
    }

    if (isEqualTo != null) addCondition(field, '==', isEqualTo);
    if (isLessThan != null) addCondition(field, '<', isLessThan);
    if (isLessThanOrEqualTo != null)
      addCondition(field, '<=', isLessThanOrEqualTo);
    if (isGreaterThan != null) addCondition(field, '>', isGreaterThan);
    if (isGreaterThanOrEqualTo != null)
      addCondition(field, '>=', isGreaterThanOrEqualTo);
    if (isNull != null) {
      assert(
          isNull,
          'isNull can only be set to true. '
          'Use isEqualTo to filter on non-null values.');
      addCondition(field, '==', null);
    }

    return new DocumentQuery._(query, _firestore);
  }

  /// Creates and returns a new [DocumentQuery] that's additionally sorted by the specified
  /// [field].
  DocumentQuery orderBy(String field, {bool descending: false}) {
    String direction = descending ? 'desc' : 'asc';
    return new DocumentQuery._(
        _nativeInstance.orderBy(field, direction), _firestore);
  }

  /// Takes a list of [values], creates and returns a new [DocumentQuery] that starts after
  /// the provided fields relative to the order of the query.
  ///
  /// The [values] must be in order of [orderBy] filters.
  ///
  /// Cannot be used in combination with [startAt].
  DocumentQuery startAfter(List<dynamic> values) {
    final jsValues = jsify(values);
    return new DocumentQuery._(
        _nativeInstance.startAfter(jsValues), _firestore);
  }

  /// Takes a list of [values], creates and returns a new [DocumentQuery] that starts at
  /// the provided fields relative to the order of the query.
  ///
  /// The [values] must be in order of [orderBy] filters.
  ///
  /// Cannot be used in combination with [startAfter].
  DocumentQuery startAt(List<dynamic> values) {
    final jsValues = jsify(values);
    return new DocumentQuery._(_nativeInstance.startAt(jsValues), _firestore);
  }

  /// Takes a list of [values], creates and returns a new [DocumentQuery] that ends at the
  /// provided fields relative to the order of the query.
  ///
  /// The [values] must be in order of [orderBy] filters.
  ///
  /// Cannot be used in combination with [endBefore].
  DocumentQuery endAt(List<dynamic> values) {
    assert(values != null);
    final jsValues = jsify(values);
    return new DocumentQuery._(_nativeInstance.endAt(jsValues), _firestore);
  }

  /// Takes a list of [values], creates and returns a new [DocumentQuery] that ends before
  /// the provided fields relative to the order of the query.
  ///
  /// The [values] must be in order of [orderBy] filters.
  ///
  /// Cannot be used in combination with [endAt].
  DocumentQuery endBefore(List<dynamic> values) {
    assert(values != null);
    final jsValues = jsify(values);
    return new DocumentQuery._(_nativeInstance.endBefore(jsValues), _firestore);
  }

  /// Creates and returns a new Query that's additionally limited to only return up
  /// to the specified number of documents.
  DocumentQuery limit(int length) {
    assert(length != null);
    return new DocumentQuery._(_nativeInstance.limit(length), _firestore);
  }
}
