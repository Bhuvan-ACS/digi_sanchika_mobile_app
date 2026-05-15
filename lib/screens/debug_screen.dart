// lib/screens/debug_screen.dart
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/utils/connection_test.dart';

class DebugScreen extends StatefulWidget {
  // ignore: use_super_parameters
  const DebugScreen({Key? key}) : super(key: key);

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  String _status = 'Ready to test';
  bool _isTesting = false;
  bool _isConnected = false;
  bool _isLoggedIn = false;
  String? _token;

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _status = 'Testing connection...';
    });

    await ApiService.initialize();
    _isConnected = await ApiService.checkConnection();

    setState(() {
      _status = _isConnected
          ? '✅ Connected to backend!'
          : '❌ Cannot connect to backend';
      _isTesting = false;
    });
  }

  Future<void> _testLogin() async {
    setState(() {
      _isTesting = true;
      _status = 'Testing login...';
    });

    // Use your actual test credentials here
    const testEmail = 'test@example.com';
    const testPassword = 'password123';

    final result = await ApiService.login(testEmail, testPassword);

    setState(() {
      if (result['success'] == true) {
        _status = '✅ Login successful!';
        _token = result['token'];
      } else {
        _status = '❌ Login failed: ${result['message']}';
      }
      _isTesting = false;
    });
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await ApiService.isLoggedIn();
    // final token = await ApiService.getAuthToken();

    setState(() {
      _isLoggedIn = loggedIn;
      // _token = token;
      _status = _isLoggedIn ? '✅ User is logged in' : '❌ User is not logged in';
    });
  }

  Future<void> _clearToken() async {
    // await ApiService.clearAuthToken();
    setState(() {
      _isLoggedIn = false;
      _token = null;
      _status = 'Token cleared';
    });
  }

  Future<void> _runAllTests() async {
    await ConnectionTest.runAllTests();
    await _checkLoginStatus();
  }

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    ApiService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Debug'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Server Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.cloud, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ApiService.currentBaseUrl,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.error,
                          color: _isConnected ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isConnected ? 'Connected' : 'Not Connected',
                          style: TextStyle(
                            color: _isConnected ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Status Display
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _status.contains('✅')
                            ? Colors.green
                            : _status.contains('❌')
                            ? Colors.red
                            : Colors.blue,
                      ),
                    ),
                    if (_token != null) ...[
                      const SizedBox(height: 10),
                      const Text('Token (first 20 chars):'),
                      Text(
                        _token!.substring(
                          0,
                          _token!.length > 20 ? 20 : _token!.length,
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Buttons
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: const Icon(Icons.wifi),
                    label: const Text('Test Connection'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('Test Login'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _checkLoginStatus,
                    icon: const Icon(Icons.info),
                    label: const Text('Check Login Status'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _clearToken,
                    icon: const Icon(Icons.logout),
                    label: const Text('Clear Token (Logout)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _runAllTests,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run All Tests'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Help Text
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  '💡 Test Login will fail if credentials are wrong, '
                  'but that\'s OK! It shows the API is working.\n\n'
                  'Check console logs for detailed debug info.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
