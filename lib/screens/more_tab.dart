import 'package:flutter/material.dart';
import 'row_scan_screen.dart';
import 'replacement_report_screen.dart';
import 'member_management_screen.dart';
import 'login_screen.dart';

class MoreTab extends StatelessWidget {
  final bool isLoggedIn;
  final bool isAdmin;
  final VoidCallback onLogout;
  final VoidCallback onStatusChanged;

  const MoreTab({
    super.key,
    required this.isLoggedIn,
    required this.isAdmin,
    required this.onLogout,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 8),

        // Row Scan Mode
        ListTile(
          leading: const Icon(Icons.format_list_numbered, color: Colors.orange),
          title: const Text('Row Scan Mode'),
          subtitle: const Text('Scan an entire row of vines'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const RowScanScreen()),
            );
          },
        ),
        const Divider(),

        // Vine Replacement Report
        ListTile(
          leading: const Icon(Icons.assignment, color: Colors.green),
          title: const Text('Vine Replacement Report'),
          subtitle: const Text('Order list for dead vines and empty spots'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const ReplacementReportScreen()),
            );
          },
        ),
        const Divider(),

        // Member Management (admin only)
        if (isLoggedIn && isAdmin) ...[
          ListTile(
            leading: const Icon(Icons.people, color: Colors.deepPurple),
            title: const Text('Manage Members'),
            subtitle: const Text('Invite and manage organization members'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (context) => const MemberManagementScreen()),
              );
            },
          ),
          const Divider(),
        ],

        // Login / Logout
        if (isLoggedIn)
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onLogout();
                      },
                      child: const Text('LOGOUT'),
                    ),
                  ],
                ),
              );
            },
          )
        else
          ListTile(
            leading: const Icon(Icons.login, color: Colors.blue),
            title: const Text('Login'),
            subtitle: const Text('Sign in to sync data with server'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  )
                  .then((_) => onStatusChanged());
            },
          ),

        const Divider(),

        // App info
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Vineyard Inventory',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
