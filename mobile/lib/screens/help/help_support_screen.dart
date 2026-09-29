import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/theme.dart';
import '../../l10n/app_localizations.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:  Text(AppLocalizations.of(context).helpTitle),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            const Center(
              child: Icon(
                Icons.support_agent,
                size: 70,
              ),
            ),

            const SizedBox(height: 20),

             Center(
              child: Text(
                AppLocalizations.of(context).helpHowCanWeHelpYou,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 10),

             Center(
              child: Text(
                AppLocalizations.of(context).helpChooseOption,
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            Card(
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title:  Text(
                  AppLocalizations.of(context).helpRaiseRequest,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle:  Text(
                  AppLocalizations.of(context).helpReportIssue,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.push('/support');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}