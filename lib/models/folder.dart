// models/folder.dart
import 'package:digi_sanchika/models/document.dart';
import 'package:flutter/foundation.dart';

class Folder {
  final String name;
  final String id;
  final String? parentId;
  final List<Document> documents;
  final DateTime createdAt;
  final String owner; // ADDED owner field

  Folder({
    required this.name,
    required this.id,
    required this.documents,
    required this.owner, // ADDED to constructor
    this.parentId,
    required this.createdAt,
  });

  // Add these methods for local storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id': id,
      'owner': owner, // ADDED
      'parentId': parentId,
      'documents': documents.map((doc) => doc.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // For backend API response
  Map<String, dynamic> toApiJson() {
    return {
      'name': name,
      'id': id,
      'owner': owner, // ADDED
      'parent_id': parentId,
      'documents': documents.map((doc) => doc.toApiJson()).toList(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Folder.fromJson(Map<String, dynamic> json) {
    try {
      return Folder(
        name: json['name'] ?? 'Unnamed Folder',
        id:
            json['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        owner: json['owner'] ?? 'Unknown', // ADDED
        parentId: json['parentId'] ?? json['parent_id'],
        documents:
            (json['documents'] as List<dynamic>?)
                ?.map((docJson) => Document.fromJson(docJson))
                .toList() ??
            [],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing Folder from JSON: $e');
      }
      if (kDebugMode) {
        print('JSON data: $json');
      }
      return Folder(
        name: 'Error Folder',
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        owner: 'System', // ADDED
        documents: [],
        createdAt: DateTime.now(),
      );
    }
  }

  // Copy with method for immutability
  Folder copyWith({
    String? name,
    String? id,
    String? owner,
    String? parentId,
    List<Document>? documents,
    DateTime? createdAt,
  }) {
    return Folder(
      name: name ?? this.name,
      id: id ?? this.id,
      owner: owner ?? this.owner, // ADDED
      parentId: parentId ?? this.parentId,
      documents: documents ?? this.documents,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Add document to folder
  Folder addDocument(Document document) {
    return copyWith(documents: List<Document>.from(documents)..add(document));
  }

  // Remove document from folder
  Folder removeDocument(String documentId) {
    return copyWith(
      documents: documents.where((doc) => doc.id != documentId).toList(),
    );
  }

  // Get document count
  int get documentCount => documents.length;

  // Check if folder is empty
  bool get isEmpty => documents.isEmpty;

  // Check if folder has specific document
  bool hasDocument(String documentId) {
    return documents.any((doc) => doc.id == documentId);
  }

  // Get document by ID
  Document? getDocumentById(String documentId) {
    try {
      return documents.firstWhere((doc) => doc.id == documentId);
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    return 'Folder(name: $name, id: $id, owner: $owner, documents: ${documents.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Folder && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
