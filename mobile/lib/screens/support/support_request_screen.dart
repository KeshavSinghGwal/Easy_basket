import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/support_service.dart';
import '../../l10n/app_localizations.dart';

class SupportRequestScreen extends StatefulWidget {
  final int? orderId;

  const SupportRequestScreen({
    super.key,
    this.orderId,
  });

  @override
  State<SupportRequestScreen> createState() => _SupportRequestScreenState();
}

class _SupportRequestScreenState extends State<SupportRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  final SupportService _supportService = SupportService();

  String _selectedCategory = 'Order Issue';
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Order Issue',
    'Payment Issue',
    'Delivery Issue',
    'Product Issue',
    'Other',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final token = authProvider.accessToken ?? authProvider.token;

    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Text(AppLocalizations.of(context).supportLoginAgain),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _supportService.createSupportRequest(
        category: _selectedCategory,
        description: _descriptionController.text.trim(),
        orderId: widget.orderId,
        token: token,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Text(AppLocalizations.of(context).supportSubmitted),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit support request: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:  Text(AppLocalizations.of(context).helpTitle),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(
                Icons.support_agent,
                size: 64,
              ),

              const SizedBox(height: 16),

               Text(
                AppLocalizations.of(context).supportHowCanWeHelp,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

               Text(
                AppLocalizations.of(context).supportTellUs,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration:  InputDecoration(
                  labelText: AppLocalizations.of(context).supportCategory,
                  border: OutlineInputBorder(),
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _descriptionController,
                maxLines: 6,
                maxLength: 1000,
                decoration:  InputDecoration(
                  labelText: AppLocalizations.of(context).supportDescribeProblem,
                  hintText: AppLocalizations.of(context).supportExplainHint,
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please describe your problem';
                  }

                  if (value.trim().length < 5) {
                    return 'Please provide a little more detail';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      :  Text(
                          AppLocalizations.of(context).supportSubmit,
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}