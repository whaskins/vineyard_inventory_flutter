import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/api/user_api.dart';
import '../services/api/auth_service.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final AuthService _authService = AuthService();
  List<UserApiModel> _members = [];
  String? _inviteCode;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _authService.getMembers(),
        _authService.getInviteCode(),
      ]);

      if (mounted) {
        setState(() {
          _members = results[0] as List<UserApiModel>;
          _inviteCode = results[1] as String;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleMemberActive(UserApiModel member) async {
    final isCurrentlyActive = member.isActive;
    final action = isCurrentlyActive ? 'deactivate' : 'reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isCurrentlyActive ? 'Deactivate' : 'Reactivate'} Member'),
        content: Text(
          'Are you sure you want to $action ${member.fullName ?? member.email}?\n\n'
          '${isCurrentlyActive ? 'They will no longer be able to log in.' : 'They will be able to log in again.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action.toUpperCase()),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (isCurrentlyActive) {
        await _authService.deactivateMember(member.id!);
      } else {
        await _authService.activateMember(member.id!);
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.fullName ?? member.email} has been ${action}d'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $action member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _regenerateInviteCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Invite Code'),
        content: const Text(
          'This will invalidate the current invite code. '
          'Anyone who has the old code will no longer be able to use it to join.\n\n'
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('REGENERATE'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final newCode = await _authService.regenerateInviteCode();
      setState(() {
        _inviteCode = newCode;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite code regenerated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Members'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Invite code card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.vpn_key, color: Colors.green),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Invite Code',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Share this code with employees to let them join your organization.',
                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _inviteCode ?? '...',
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        color: Colors.green,
                                        letterSpacing: 3,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      icon: const Icon(Icons.copy, color: Colors.green),
                                      tooltip: 'Copy to clipboard',
                                      onPressed: () {
                                        if (_inviteCode != null) {
                                          Clipboard.setData(ClipboardData(text: _inviteCode!));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Invite code copied')),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _regenerateInviteCode,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Regenerate Code'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Members list header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            const Text(
                              'Members',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_members.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Members list
                      ..._members.map((member) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: member.isActive
                                    ? Colors.green[100]
                                    : Colors.grey[300],
                                child: Icon(
                                  member.isAdmin ? Icons.admin_panel_settings : Icons.person,
                                  color: member.isActive
                                      ? (member.isAdmin ? Colors.orange : Colors.green)
                                      : Colors.grey,
                                ),
                              ),
                              title: Text(
                                member.fullName ?? member.email,
                                style: TextStyle(
                                  color: member.isActive ? null : Colors.grey,
                                  decoration: member.isActive
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    member.email,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: member.isActive ? Colors.grey[600] : Colors.grey,
                                    ),
                                  ),
                                  if (member.isAdmin) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Admin',
                                        style: TextStyle(fontSize: 10, color: Colors.orange),
                                      ),
                                    ),
                                  ],
                                  if (!member.isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.red[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Inactive',
                                        style: TextStyle(fontSize: 10, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  member.isActive
                                      ? Icons.person_remove
                                      : Icons.person_add,
                                  color: member.isActive ? Colors.red : Colors.green,
                                ),
                                tooltip: member.isActive ? 'Deactivate' : 'Reactivate',
                                onPressed: () => _toggleMemberActive(member),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
    );
  }
}
