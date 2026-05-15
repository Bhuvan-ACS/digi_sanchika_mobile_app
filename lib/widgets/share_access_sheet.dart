import 'package:digi_sanchika/services/shares_service.dart';
import 'package:digi_sanchika/services/groups_service.dart';
import 'package:digi_sanchika/services/group_shares_service.dart';
import 'package:digi_sanchika/models/group.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';

class ShareAccessSheet {
  static Future<void> showForDocument({
    required BuildContext context,
    required String documentId,
    required String documentName,
  }) {
    return _show(
      context: context,
      type: ShareEntityType.document,
      entityId: documentId,
      title: documentName.isNotEmpty ? documentName : 'Document',
    );
  }

  static Future<void> showForFolder({
    required BuildContext context,
    required String folderId,
    required String folderName,
  }) {
    return _show(
      context: context,
      type: ShareEntityType.folder,
      entityId: folderId,
      title: folderName.isNotEmpty ? folderName : 'Folder',
    );
  }

  static Future<void> _show({
    required BuildContext context,
    required ShareEntityType type,
    required String entityId,
    required String title,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareAccessSheetWidget(
        type: type,
        entityId: entityId,
        title: title,
      ),
    );
  }
}

class _ShareAccessSheetWidget extends StatefulWidget {
  final ShareEntityType type;
  final String entityId;
  final String title;

  const _ShareAccessSheetWidget({
    required this.type,
    required this.entityId,
    required this.title,
  });

  @override
  State<_ShareAccessSheetWidget> createState() => _ShareAccessSheetWidgetState();
}

class _ShareAccessSheetWidgetState extends State<_ShareAccessSheetWidget>
    with SingleTickerProviderStateMixin {
  final SharesService _service = SharesService();
  final GroupsService _groupsService = GroupsService();
  final GroupSharesService _groupSharesService = GroupSharesService();

  late final TabController _tabController;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _users = [];
  Map<String, Map<String, dynamic>> _usersById = {};
  Map<String, Map<String, dynamic>> _usersByEmail = {};
  List<Map<String, dynamic>> _shares = [];

  final TextEditingController _userSearch = TextEditingController();
  final TextEditingController _groupSearch = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final Set<String> _selectedUserIds = <String>{};
  List<Group> _groups = [];
  String? _selectedGroupId;

  String _permission = 'view';
  bool _allowDownload = true;
  bool _allowEdit = false;
  int? _expiryDays;
  int? _expiryHours;
  bool _showAdvanced = false;
  String _expiryMode = 'none'; // none | hours | days
  String _daysPreset = 'none'; // none | 1 | 3 | 5 | 7 | 14 | 20 | custom
  final TextEditingController _customDaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSearch.dispose();
    _groupSearch.dispose();
    _messageController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _service.getUsers(),
        _service.listShares(type: widget.type, entityId: widget.entityId),
      ]);
      final groups = await _groupsService.listGroups();

      if (!mounted) return;
      final users = results[0];
      final byId = <String, Map<String, dynamic>>{};
      final byEmail = <String, Map<String, dynamic>>{};
      for (final u in users) {
        final id = _userId(u);
        if (id.isNotEmpty) byId[id] = u;
        final email = _userEmail(u).trim().toLowerCase();
        if (email.isNotEmpty) byEmail[email] = u;
      }
      setState(() {
        _users = users;
        _usersById = byId;
        _usersByEmail = byEmail;
        _shares = results[1];
        _groups = groups.where((g) => g.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _userId(Map<String, dynamic> u) {
    return (u['id'] ?? u['user_id'] ?? u['userId'] ?? '').toString();
  }

  String _userName(Map<String, dynamic> u) {
    return (u['name'] ??
            u['full_name'] ??
            u['display_name'] ??
            u['username'] ??
            'User')
        .toString();
  }

  String _userEmail(Map<String, dynamic> u) {
    return (u['email'] ?? u['email_address'] ?? u['mail'] ?? '').toString();
  }

  String _userSubtitle(Map<String, dynamic> u) {
    final employeeId = (u['employee_id'] ?? u['emp_id'] ?? '').toString();
    final email = _userEmail(u);
    if (employeeId.isNotEmpty && email.isNotEmpty) return '$employeeId • $email';
    if (employeeId.isNotEmpty) return employeeId;
    if (email.isNotEmpty) return email;
    return '';
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _userSearch.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      final hay = '${_userName(u)} ${_userEmail(u)} ${_userSubtitle(u)}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  String _shareId(Map<String, dynamic> s) {
    return (s['id'] ?? s['share_id'] ?? s['shareId'] ?? '').toString();
  }

  Map<String, dynamic> _shareUser(Map<String, dynamic> s) {
    final sharedWith = s['sharedWith'] ??
        s['shared_with'] ??
        s['shared_with_user'] ??
        s['sharedWithUser'] ??
        s['recipient'] ??
        s['user'];
    if (sharedWith is Map<String, dynamic>) return sharedWith;
    if (sharedWith is Map) return Map<String, dynamic>.from(sharedWith);
    return const <String, dynamic>{};
  }

  String _shareUserIdFromShare(Map<String, dynamic> s) {
    final v = s['sharedWithId'] ??
        s['shared_with_id'] ??
        s['shared_with_user_id'] ??
        s['recipient_id'] ??
        s['user_id'];
    return v?.toString() ?? '';
  }

  String _shareUserEmailFromShare(Map<String, dynamic> s) {
    final v = s['sharedWithEmail'] ??
        s['shared_with_email'] ??
        s['email'] ??
        s['shared_email'];
    return v?.toString() ?? '';
  }

  String _shareUserNameFromShare(Map<String, dynamic> s) {
    final v = s['sharedWithName'] ??
        s['shared_with_name'] ??
        s['name'] ??
        s['full_name'] ??
        s['display_name'];
    return v?.toString() ?? '';
  }

  Map<String, dynamic> _resolveUserForShare(Map<String, dynamic> share) {
    final nested = _shareUser(share);
    if (nested.isNotEmpty) return nested;

    final id = _shareUserIdFromShare(share);
    if (id.isNotEmpty && _usersById.containsKey(id)) {
      return _usersById[id]!;
    }
    final email = _shareUserEmailFromShare(share).trim().toLowerCase();
    if (email.isNotEmpty && _usersByEmail.containsKey(email)) {
      return _usersByEmail[email]!;
    }

    // Last resort: synthesize a minimal user object so the UI shows something meaningful.
    final name = _shareUserNameFromShare(share);
    return <String, dynamic>{
      if (id.isNotEmpty) 'id': id,
      if (email.isNotEmpty) 'email': email,
      if (name.isNotEmpty) 'name': name,
    };
  }

  bool _shareAllowDownload(Map<String, dynamic> s) {
    final v = s['allow_download'] ?? s['allowDownload'];
    return v == null ? true : v == true;
  }

  bool _shareAllowEdit(Map<String, dynamic> s) {
    final v = s['allow_edit'] ?? s['allowEdit'];
    return v == null ? false : v == true;
  }

  List<Group> get _filteredGroups {
    final q = _groupSearch.text.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    return _groups
        .where((g) => g.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _submitShare() async {
    if (_selectedUserIds.isEmpty) return;

    setState(() {
      _saving = true;
    });

    try {
      final msg = _messageController.text.trim();
      bool allOk = true;
      for (final userId in _selectedUserIds) {
        final ok = await _service.share(
          type: widget.type,
          entityId: widget.entityId,
          sharedWithIdOrEmail: userId,
          permission: _permission,
          expiryDays: _expiryDays,
          expiryHours: _expiryHours,
          allowDownload: _allowDownload,
          allowEdit: _allowEdit,
          message: msg.isNotEmpty ? msg : null,
        );
        allOk = allOk && ok;
      }

      if (!mounted) return;
      if (allOk) {
        _selectedUserIds.clear();
        _messageController.clear();
        await _refreshShares();

        // Show a modal success message, then close the sheet.
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Success'),
            content: const Text('Shared successfully'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(true);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some shares failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _refreshShares() async {
    final shares = await _service.listShares(
      type: widget.type,
      entityId: widget.entityId,
    );
    if (!mounted) return;
    setState(() {
      _shares = shares;
    });
  }

  Future<void> _toggleShareFlag({
    required Map<String, dynamic> share,
    required bool allowDownload,
    required bool allowEdit,
  }) async {
    final id = _shareId(share);
    if (id.isEmpty) return;

    final ok = await _service.updateShare(
      type: widget.type,
      shareId: id,
      allowDownload: allowDownload,
      allowEdit: allowEdit,
    );
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update access'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await _refreshShares();
  }

  Future<void> _revokeShare(Map<String, dynamic> share) async {
    final id = _shareId(share);
    if (id.isEmpty) return;

    final ok = await _service.revokeShare(type: widget.type, shareId: id);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to revoke access'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await _refreshShares();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Access revoked'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _submitGroupShare() async {
    final groupId = (_selectedGroupId ?? '').trim();
    if (groupId.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final expiryDays = _expiryMode == 'days' ? _expiryDays : null;
      final expiryHours = _expiryMode == 'hours' ? _expiryHours : null;

      final ok = switch (widget.type) {
        ShareEntityType.document => (await _groupSharesService.shareDocumentWithGroup(
              documentId: widget.entityId,
              groupId: groupId,
              permission: _permission,
              allowDownload: _allowDownload,
              allowEdit: _allowEdit,
              expiryDays: expiryDays,
              expiryHours: expiryHours,
            )) !=
            null,
        ShareEntityType.folder => (await _groupSharesService.shareFolderWithGroup(
              folderId: widget.entityId,
              groupId: groupId,
              permission: _permission,
              allowDownload: _allowDownload,
              allowEdit: _allowEdit,
              expiryDays: expiryDays,
              expiryHours: expiryHours,
            )) !=
            null,
      };

      if (!mounted) return;
      if (ok) {
        // Show a modal success message, then close the sheet.
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Success'),
            content: const Text('Shared with group successfully'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(true);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        setState(() => _error = 'Failed to share with group');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildHeader() {
    final noun = widget.type == ShareEntityType.document ? 'Document' : 'Folder';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share $noun',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildShareTab() {
    const dayOptions = <String>[
      '1',
      '3',
      '5',
      '7',
      '14',
      '20',
      'custom',
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _userSearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _userSearch.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _userSearch.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _permission,
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('View')),
                    DropdownMenuItem(value: 'edit', child: Text('Edit')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _permission = v;
                            if (_permission == 'view') {
                              _allowEdit = false;
                            }
                            if (_permission == 'edit') {
                              _allowEdit = true;
                            }
                          });
                        },
                  decoration: InputDecoration(
                    labelText: 'Permission',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allowDownload,
                  onChanged:
                      _saving ? null : (v) => setState(() => _allowDownload = v),
                  title: const Text('Download'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _saving ? null : () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced ? Icons.expand_less : Icons.expand_more,
                    color: Colors.indigo,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Advanced options',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_expiryDays != null ||
                      _expiryHours != null ||
                      _messageController.text.trim().isNotEmpty ||
                      _allowEdit)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Set',
                        style: TextStyle(color: Colors.indigo, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_showAdvanced) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _expiryMode,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('No expiry')),
                      DropdownMenuItem(value: 'hours', child: Text('Expiry: Hours')),
                      DropdownMenuItem(value: 'days', child: Text('Expiry: Days')),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() {
                              _expiryMode = v;
                              if (v == 'none') {
                                _expiryDays = null;
                                _expiryHours = null;
                                _daysPreset = 'none';
                                _customDaysController.clear();
                              }
                              if (v == 'hours') {
                                _expiryDays = null;
                                _daysPreset = 'none';
                                _customDaysController.clear();
                                _expiryHours ??= 1;
                              }
                              if (v == 'days') {
                                _expiryHours = null;
                                _expiryDays ??= 1;
                                _daysPreset = _expiryDays?.toString() ?? '1';
                              }
                            });
                          },
                    decoration: InputDecoration(
                      labelText: 'Expiry',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _allowEdit,
                    onChanged: (_saving || _permission != 'edit')
                        ? null
                        : (v) => setState(() => _allowEdit = v),
                    title: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ),
          if (_expiryMode == 'hours')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DropdownButtonFormField<int>(
                value: (_expiryHours != null && _expiryHours! >= 1 && _expiryHours! <= 24)
                    ? _expiryHours
                    : 1,
                items: List.generate(
                  24,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('${i + 1} hour(s)'),
                  ),
                ),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _expiryHours = v;
                        }),
                decoration: InputDecoration(
                  labelText: 'Hours',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          if (_expiryMode == 'days')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _daysPreset == 'none' ? '1' : _daysPreset,
                      items: [
                        for (final d in dayOptions)
                          DropdownMenuItem(
                            value: d,
                            child: Text(d == 'custom' ? 'Custom…' : '$d day(s)'),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _daysPreset = v;
                                if (v != 'custom') {
                                  _customDaysController.clear();
                                  _expiryDays = int.tryParse(v) ?? 1;
                                } else {
                                  // Keep current value; user will type.
                                  _expiryDays = _expiryDays ?? 1;
                                }
                              });
                            },
                      decoration: InputDecoration(
                        labelText: 'Days',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _customDaysController,
                      enabled: !_saving && _daysPreset == 'custom',
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        setState(() {
                          _expiryDays = (parsed != null && parsed > 0) ? parsed : null;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Custom',
                        hintText: 'Days',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Message (optional)',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 72),
            itemCount: _filteredUsers.length,
            itemBuilder: (context, index) {
              final u = _filteredUsers[index];
              final id = _userId(u);
              if (id.isEmpty) return const SizedBox.shrink();
              final selected = _selectedUserIds.contains(id);
              final subtitle = _userSubtitle(u);
              final name = _userName(u);
              return Card(
                elevation: selected ? 2 : 1,
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color:
                        selected ? Colors.indigo.withAlpha(120) : Colors.grey.withAlpha(40),
                  ),
                ),
                child: ListTile(
                  onTap: _saving
                      ? null
                      : () {
                          setState(() {
                            if (selected) {
                              _selectedUserIds.remove(id);
                            } else {
                              _selectedUserIds.add(id);
                            }
                          });
                        },
                  leading: CircleAvatar(
                    backgroundColor:
                        selected ? Colors.indigo.withAlpha(30) : Colors.grey.withAlpha(20),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: TextStyle(
                        color: selected ? Colors.indigo : Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                  trailing: Checkbox(
                    value: selected,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() {
                              if (v == true) {
                                _selectedUserIds.add(id);
                              } else {
                                _selectedUserIds.remove(id);
                              }
                            });
                          },
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: (_saving || _selectedUserIds.isEmpty)
                    ? null
                    : _submitShare,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _selectedUserIds.isEmpty
                      ? 'Select users to share'
                      : 'Share with ${_selectedUserIds.length} user(s)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  elevation: _selectedUserIds.isEmpty ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManageTab() {
    if (_shares.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No one has access yet.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshShares,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        itemCount: _shares.length,
        itemBuilder: (context, index) {
          final share = _shares[index];
          final user = _resolveUserForShare(share);
          final rawName = _userName(user);
          final rawEmail = _userEmail(user);
          final fallbackEmail = _shareUserEmailFromShare(share);
          final name = rawName.isNotEmpty ? rawName : _shareUserNameFromShare(share);
          final email = rawEmail.isNotEmpty ? rawEmail : fallbackEmail;
          final displayName =
              name.isNotEmpty ? name : (email.isNotEmpty ? email : 'User');
          final allowDownload = _shareAllowDownload(share);
          final allowEdit = _shareAllowEdit(share);

          return Card(
            elevation: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.withAlpha(40)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.indigo.withAlpha(24),
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(color: Colors.indigo),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (email.isNotEmpty)
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Revoke',
                        onPressed: () => _revokeShare(share),
                        icon: const Icon(Icons.block, color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: allowDownload,
                          onChanged: (v) => _toggleShareFlag(
                            share: share,
                            allowDownload: v,
                            allowEdit: allowEdit,
                          ),
                          title: const Text('Download'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: allowEdit,
                          onChanged: (v) => _toggleShareFlag(
                            share: share,
                            allowDownload: allowDownload,
                            allowEdit: v,
                          ),
                          title: const Text('Edit'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGroupShareTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _groupSearch,
            decoration: InputDecoration(
              hintText: 'Search groups',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _groupSearch.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _groupSearch.clear()),
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _groups.isEmpty
                ? Center(
                    child: Text(
                      'No groups available',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredGroups.length,
                    itemBuilder: (context, index) {
                      final g = _filteredGroups[index];
                      return RadioListTile<String>(
                        value: g.id,
                        groupValue: _selectedGroupId,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _selectedGroupId = v),
                        title: Text(g.name),
                        subtitle: (g.description ?? '').trim().isNotEmpty
                            ? Text(g.description!.trim())
                            : null,
                        secondary: g.avatarEmoji != null && g.avatarEmoji!.trim().isNotEmpty
                            ? Text(g.avatarEmoji!.trim(), style: const TextStyle(fontSize: 18))
                            : const Icon(Icons.groups_rounded),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _permission,
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('View')),
                    DropdownMenuItem(value: 'edit', child: Text('Edit')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _permission = v;
                            if (_permission == 'view') _allowEdit = false;
                            if (_permission == 'edit') _allowEdit = true;
                          });
                        },
                  decoration: InputDecoration(
                    labelText: 'Permission',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allowDownload,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _allowDownload = v),
                  title: const Text('Download'),
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _allowEdit,
            onChanged: (_saving || _permission == 'view')
                ? null
                : (v) => setState(() => _allowEdit = v),
            title: const Text('Allow edit'),
            subtitle: const Text('Group share override'),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _expiryMode,
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Expiry: Default')),
                    DropdownMenuItem(value: 'hours', child: Text('Expiry: Hours')),
                    DropdownMenuItem(value: 'days', child: Text('Expiry: Days')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _expiryMode = v;
                            if (_expiryMode == 'none') {
                              _expiryDays = null;
                              _expiryHours = null;
                            }
                          });
                        },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: TextField(
                  enabled: !_saving && _expiryMode != 'none',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: _expiryMode == 'hours' ? 'Hours' : 'Days',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    setState(() {
                      if (_expiryMode == 'hours') {
                        _expiryHours = n;
                        _expiryDays = null;
                      } else if (_expiryMode == 'days') {
                        _expiryDays = n;
                        _expiryHours = null;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedGroupId == null || _saving)
                  ? null
                  : _submitGroupShare,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add_outlined),
              label: Text(_saving ? 'Sharing...' : 'Share with group'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return DismissKeyboard(child: Container(
      constraints: BoxConstraints(maxHeight: height * 0.92),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildHeader(),
          TabBar(
            controller: _tabController,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'Share'),
              Tab(text: 'Groups'),
              Tab(text: 'Manage'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Failed to load sharing',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildShareTab(),
                      _buildGroupShareTab(),
                      _buildManageTab(),
                    ],
                  ),
          ),
        ],
      ),
    ));
  }
}
