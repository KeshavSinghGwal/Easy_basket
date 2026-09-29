import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';

class AdminUsersScreen extends StatefulWidget {
  final String? role;

  const AdminUsersScreen({super.key, this.role});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _selectedRole = 'all';
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.role ?? 'all';
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (adminProvider.hasMore && !adminProvider.isLoadingMore) {
        final role = _selectedRole == 'all' ? null : _selectedRole;
        adminProvider.fetchUsers(role: role, token: authProvider.token, loadMore: true);
      }
    }
  }

  void _loadUsers() {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final role = _selectedRole == 'all' ? null : _selectedRole;
    adminProvider.fetchUsers(role: role, token: authProvider.token);
  }

  Future<void> _updateUserRole(int userId, String newRole) async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.token == null) return;

    final success = await adminProvider.changeUserRole(
      token: authProvider.token!,
      userId: userId,
      role: newRole,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User role updated successfully!')),
      );
      _loadUsers();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminProvider.error ?? 'Failed to update user')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminProvider = Provider.of<AdminProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/dashboard'),
        ),
      ),
      body: Column(
        children: [
          // Role Filter
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _RoleChip(
                    label: 'All',
                    isSelected: _selectedRole == 'all',
                    onTap: () {
                      setState(() => _selectedRole = 'all');
                      _loadUsers();
                    },
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(
                    label: 'Customers',
                    isSelected: _selectedRole == 'customer',
                    onTap: () {
                      setState(() => _selectedRole = 'customer');
                      _loadUsers();
                    },
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(
                    label: 'Delivery',
                    isSelected: _selectedRole == 'delivery',
                    onTap: () {
                      setState(() => _selectedRole = 'delivery');
                      _loadUsers();
                    },
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(
                    label: 'Admins',
                    isSelected: _selectedRole == 'admin',
                    onTap: () {
                      setState(() => _selectedRole = 'admin');
                      _loadUsers();
                    },
                  ),
                ],
              ),
            ),
          ),

          // Users List
          Expanded(
            child: adminProvider.isLoading && adminProvider.users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : adminProvider.users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: AppTheme.grey),
                            const SizedBox(height: 16),
                            Text(
                              'No users found',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: adminProvider.users.length + (adminProvider.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == adminProvider.users.length) {
                            // Load more indicator
                            if (adminProvider.isLoadingMore) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          final user = adminProvider.users[index];
                          return _UserCard(
                            user: user,
                            onRoleUpdate: _updateUserRole,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryGreen,
      checkmarkColor: AppTheme.white,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.white : AppTheme.black,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final dynamic user;
  final Function(int userId, String role) onRoleUpdate;

  const _UserCard({
    required this.user,
    required this.onRoleUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(user.role).withOpacity(0.2),
          child: Icon(
            _getRoleIcon(user.role),
            color: _getRoleColor(user.role),
          ),
        ),
        title: Text(
          user.name ?? 'User',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.phoneNumber),
            if (user.email != null) Text(user.email!),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (role) => onRoleUpdate(user.id, role),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'customer',
              child: Text('Customer'),
            ),
            const PopupMenuItem(
              value: 'delivery',
              child: Text('Delivery'),
            ),
            const PopupMenuItem(
              value: 'admin',
              child: Text('Admin'),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getRoleColor(user.role).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              user.role.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _getRoleColor(user.role),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'delivery':
        return Icons.delivery_dining;
      default:
        return Icons.person;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'delivery':
        return Colors.orange;
      default:
        return AppTheme.primaryGreen;
    }
  }
}

