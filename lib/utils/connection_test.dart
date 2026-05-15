// lib/utils/connection_test.dart
import 'package:digi_sanchika/services/api_service.dart';
import 'package:flutter/foundation.dart';

class ConnectionTest {
  // Test if backend is reachable
  static Future<void> testBackendConnection() async {
    if (kDebugMode) {
      print('🔄 Testing connection to backend...');
    }

    final isConnected = await ApiService.checkConnection();

    if (isConnected) {
      if (kDebugMode) {
        print(
          '✅ SUCCESS! Backend is reachable at: ${ApiService.currentBaseUrl}',
        );
      }
    } else {
      if (kDebugMode) {
        print(
          '❌ FAILED! Cannot connect to backend at: ${ApiService.currentBaseUrl}',
        );
      }
      if (kDebugMode) {
        print('Please check:');
      }
      if (kDebugMode) {
        print('1. Is the server running at ${ApiService.currentBaseUrl}?');
      }
      if (kDebugMode) {
        print('2. Is your internet connection working?');
      }
      if (kDebugMode) {
        print('3. Is the port 8000 open?');
      }
    }
  }

  // Test login with test credentials
  static Future<void> testLogin() async {
    if (kDebugMode) {
      print('🔐 Testing login API...');
    }

    // Replace with your actual test credentials
    const testEmail = 'test@example.com';
    const testPassword = 'password123';

    final result = await ApiService.login(testEmail, testPassword);

    if (result['success'] == true) {
      if (kDebugMode) {
        print('✅ LOGIN SUCCESSFUL!');
      }
      if (kDebugMode) {
        print('Response data: ${result['data']}');
      }
      if (kDebugMode) {
        print('Token received: ${result['token'] != null ? "YES" : "NO"}');
      }
    } else {
      if (kDebugMode) {
        print('❌ LOGIN FAILED!');
      }
      if (kDebugMode) {
        print('Error: ${result['message']}');
      }

      // Check what type of error
      if (result['message'].toString().contains('Invalid email or password')) {
        if (kDebugMode) {
          print(
            '💡 Note: This might be expected if test credentials are incorrect',
          );
        }
        if (kDebugMode) {
          print('But it confirms the API is working!');
        }
      }
    }
  }

  // Run all tests
  static Future<void> runAllTests() async {
    if (kDebugMode) {
      print('🚀 Running backend connection tests...\n');
    }

    await testBackendConnection();
    if (kDebugMode) {
      print('');
    }

    await testLogin();
    if (kDebugMode) {
      print('');
    }

    if (kDebugMode) {
      print('📋 Test Summary:');
    }
    if (kDebugMode) {
      print(
        '1. Backend connection: ${await ApiService.checkConnection() ? "✅" : "❌"}',
      );
    }
    if (kDebugMode) {
      print('2. API response: Tested via login endpoint');
    }
    if (kDebugMode) {
      print('3. Token storage: ${await ApiService.isLoggedIn() ? "✅" : "❌"}');
    }
  }
}
