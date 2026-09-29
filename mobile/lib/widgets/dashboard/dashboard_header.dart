import 'package:flutter/material.dart';
import 'dashboard_theme.dart';

class DashboardHeader extends StatelessWidget {
  final String updatedText;

  const DashboardHeader({
    super.key,
    required this.updatedText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        

        // Column(
        //   crossAxisAlignment: CrossAxisAlignment.end,
        //   children: [

        //     const Icon(
        //       Icons.refresh,
        //       color: DashboardTheme.subtitle,
        //     ),

        //     const SizedBox(height: 6),

        //     Text(
        //       updatedText,
        //       style: const TextStyle(
        //         fontSize: 12,
        //         color: DashboardTheme.subtitle,
        //       ),
        //     )
        //   ],
        // )
      ],
    );
  }
}