// local_storage_service.dart
import 'dart:convert';
// import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';

class LocalStorageService {
  static const String _documentsKey = 'user_documents';
  static const String _publicDocumentsKey = 'public_documents';
  static const String _foldersKey = 'user_folders';

  // Save documents to local storage
  static Future<void> saveDocuments(
    List<Document> documents, {
    bool isPublic = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = isPublic ? _publicDocumentsKey : _documentsKey;

      final documentsJson = documents.map((doc) => doc.toJson()).toList();
      await prefs.setString(key, json.encode(documentsJson));

      if (kDebugMode) {
        print('Saved ${documents.length} documents (Public: $isPublic)');
        print('Document names: ${documents.map((d) => d.name).toList()}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving documents: $e');
      }
    }
  }

  // Load documents from local storage
  static Future<List<Document>> loadDocuments({bool isPublic = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = isPublic ? _publicDocumentsKey : _documentsKey;

      final documentsJson = prefs.getString(key);
      if (documentsJson != null) {
        final List<dynamic> documentsList = json.decode(documentsJson);
        final loadedDocuments = documentsList
            .map((docJson) => Document.fromJson(docJson))
            .toList();

        if (kDebugMode) {
          print(
            'Loaded ${loadedDocuments.length} documents (Public: $isPublic)',
          );
        }

        return loadedDocuments;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading documents: $e');
      }
    }
    return [];
  }

  // Add single document
  static Future<void> addDocument(
    Document document, {
    bool isPublic = false,
  }) async {
    final documents = await loadDocuments(isPublic: isPublic);
    documents.add(document);
    await saveDocuments(documents, isPublic: isPublic);

    if (kDebugMode) {
      print('Added document: ${document.name} {Public: $isPublic}');
    }
  }

  // Delete document
  static Future<bool> deleteDocument(
    String documentName, {
    bool isPublic = false,
  }) async {
    final documents = await loadDocuments(isPublic: isPublic);
    final initialLength = documents.length;
    documents.removeWhere((doc) => doc.name == documentName);

    if (documents.length < initialLength) {
      await saveDocuments(documents, isPublic: isPublic);
      if (kDebugMode) {
        print('Deleted document: $documentName (Public: $isPublic)');
      }
      return true;
    }
    return false;
  }

  static Future<void> saveFolders(List<Folder> folders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foldersJson = folders
          .map((folder) => _folderToJson(folder))
          .toList();
      await prefs.setString(_foldersKey, json.encode(foldersJson));

      if (kDebugMode) {
        print('Saved ${folders.length} folders');
        print('Folder names: ${folders.map((f) => f.name).toList()}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving folders: $e');
      }
    }
  }

  // Load folders
  static Future<List<Folder>> loadFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foldersJson = prefs.getString(_foldersKey);
      if (foldersJson != null) {
        final List<dynamic> foldersList = json.decode(foldersJson);
        final loadedFolders = foldersList
            .map((folderJson) => _folderFromJson(folderJson))
            .toList();

        if (kDebugMode) {
          print('Loaded ${loadedFolders.length} folders');
        }

        return loadedFolders;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading folders: $e');
      }
    }

    if (kDebugMode) {
      print('No folders found, returning default Home folder');
    }
    return [
      Folder(
        name: 'Home',
        id: 'home',
        documents: [],
        createdAt: DateTime.now(),
        owner: 'System',
      ),
    ];
  }

  static Future<List<Document>> loadSharedDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const sharedDocumentsKey = 'shared_documents'; // New key for shared docs

      final documentsJson = prefs.getString(sharedDocumentsKey);
      if (documentsJson != null) {
        final List<dynamic> documentsList = json.decode(documentsJson);
        final loadedDocuments = documentsList
            .map((docJson) => Document.fromJson(docJson))
            .toList();

        if (kDebugMode) {
          print('Loaded ${loadedDocuments.length} shared documents');
        }

        return loadedDocuments;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading shared documents: $e');
      }
    }
    return [];
  }

  static Future<void> saveSharedDocuments(List<Document> documents) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const sharedDocumentsKey = 'shared_documents'; // New key for shared docs

      final documentsJson = documents.map((doc) => doc.toJson()).toList();
      await prefs.setString(sharedDocumentsKey, json.encode(documentsJson));

      if (kDebugMode) {
        print('Saved ${documents.length} shared documents');
        print(
          'Shared document names: ${documents.map((d) => d.name).toList()}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving shared documents: $e');
      }
    }
  }

  static Future<void> addFolder(Folder folder) async {
    final folders = await loadFolders();
    folders.add(folder);
    await saveFolders(folders);

    if (kDebugMode) {
      print('Added folder: ${folder.name}');
    }
  }

  // Add single shared document
  static Future<void> addSharedDocument(Document document) async {
    final documents = await loadSharedDocuments();
    documents.add(document);
    await saveSharedDocuments(documents);

    if (kDebugMode) {
      print('Added shared document: ${document.name}');
    }
  }

  // Delete shared document
  static Future<bool> deleteSharedDocument(String documentId) async {
    final documents = await loadSharedDocuments();
    final initialLength = documents.length;
    documents.removeWhere((doc) => doc.id == documentId);

    if (documents.length < initialLength) {
      await saveSharedDocuments(documents);
      if (kDebugMode) {
        print('Deleted shared document with id: $documentId');
      }
      return true;
    }
    return false;
  }

  static Future<bool> deleteFolder(String folderId) async {
    final folders = await loadFolders();
    final initialLength = folders.length;
    folders.removeWhere((folder) => folder.id == folderId);

    if (folders.length < initialLength) {
      await saveFolders(folders);
      if (kDebugMode) {
        print('Deleted folder with id: $folderId');
      }
      return true;
    }
    return false;
  }

  // Update a folder (for adding/removing documents)
  static Future<void> updateFolder(Folder updatedFolder) async {
    final folders = await loadFolders();
    final index = folders.indexWhere((folder) => folder.id == updatedFolder.id);

    if (index != -1) {
      folders[index] = updatedFolder;
      await saveFolders(folders);

      if (kDebugMode) {
        print('Updated folder: ${updatedFolder.name}');
      }
    }
  }

  // Helper methods for Folder serialization
  static Map<String, dynamic> _folderToJson(Folder folder) {
    return {
      'name': folder.name,
      'id': folder.id,
      'parentId': folder.parentId,
      'documents': folder.documents.map((doc) => doc.toJson()).toList(),
      'createdAt': folder.createdAt.toIso8601String(),
    };
  }

  static Folder _folderFromJson(Map<String, dynamic> json) {
    return Folder(
      name: json['name'],
      id: json['id'],
      parentId: json['parentId'],
      documents: (json['documents'] as List)
          .map((docJson) => Document.fromJson(docJson))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      owner: 'System',
    );
  }
}
