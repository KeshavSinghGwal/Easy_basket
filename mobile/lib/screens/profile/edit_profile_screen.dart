
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
import '../../l10n/app_localizations.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  DateTime? _selectedBirthday;
  bool _isSaving = false;


  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _nameController.text = authProvider.user?.name ?? '';
    _selectedBirthday = authProvider.user?.birthday;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryGreen,
              onPrimary: AppTheme.white,
              surface: AppTheme.white,
              onSurface: AppTheme.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedBirthday) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      await authProvider.updateProfile(
        name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        birthday: _selectedBirthday,
      );

      if (!mounted) return;

      if (authProvider.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(AppLocalizations.of(context).profileUpdated),
              ],
            ),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? 'Failed to update profile'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: AppTheme.lightGrey,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppTheme.white,
        iconTheme: const IconThemeData(color: AppTheme.black),
        title:  Text(
          AppLocalizations.of(context).profileEditTitle,
          style: TextStyle(
            color: AppTheme.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.black),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Form Fields
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).profileFullName,
                        hintText: AppLocalizations.of(context).profileFullNameHint,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.lightGrey,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.primaryGreen,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: AppTheme.lightGrey.withOpacity(0.3),
                      ),
                      style: const TextStyle(fontSize: 16),
                      validator: (value) {
                        // Name is optional, but if provided should not be empty
                        if (value != null && value.trim().isNotEmpty && value.trim().length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    // Phone Number (Read-only)
                    TextFormField(
                      initialValue: authProvider.user?.phoneNumber ?? '',
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).profilePhoneNumber,
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.lightGrey,
                            width: 1.5,
                          ),
                        ),
                        filled: true,
                        fillColor: AppTheme.lightGrey.withOpacity(0.3),
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.grey,
                      ),
                      readOnly: true,
                      enabled: false,
                    ),
                    const SizedBox(height: 20),
                    // Birthday Field
                    GestureDetector(
                      onTap: _selectBirthday,
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: TextEditingController(
                            text: _selectedBirthday != null
                                ? dateFormat.format(_selectedBirthday!)
                                : '',
                          ),
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context).profileBirthday,
                            hintText: AppLocalizations.of(context).profileBirthdayHint,
                            prefixIcon: const Icon(Icons.calendar_today_outlined),
                            suffixIcon: Icon(
                              Icons.arrow_drop_down_rounded,
                              color: AppTheme.grey,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppTheme.lightGrey,
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppTheme.primaryGreen,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: AppTheme.lightGrey.withOpacity(0.3),
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    if (authProvider.user?.email != null) ...[
                      const SizedBox(height: 20),
                      // Email (Read-only if exists)
                      TextFormField(
                        initialValue: authProvider.user?.email ?? '',
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).profileEmail,
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppTheme.lightGrey,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: AppTheme.lightGrey.withOpacity(0.3),
                        ),
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.grey,
                        ),
                        readOnly: true,
                        enabled: false,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Save Button
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                width: double.infinity,
                child: AppTheme.gradientButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  height: 52,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                          ),
                        )
                      :  Text(
                          AppLocalizations.of(context).profileSaveChanges,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}