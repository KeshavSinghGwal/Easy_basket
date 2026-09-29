import 'package:flutter/material.dart';
import 'dashboard_theme.dart';

class DashboardStatTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? change;
  final bool isPositive;

  const DashboardStatTile({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.change,
    this.isPositive = true,
  });

  @override
Widget build(BuildContext context) {

  final width = MediaQuery.of(context).size.width;

  if (width < 600) {
    return _mobileCard();
  }

  return _desktopCard();
}
Widget _mobileCard() {

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: DashboardTheme.cardDecoration,

    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Row(
          children: [

            Container(
              padding: const EdgeInsets.all(8),

              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
              ),

              child: Icon(
                icon,
                size: 20,
                color: color,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: DashboardTheme.subtitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const Spacer(),

        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: DashboardTheme.title,
          ),
        ),

        if(change!=null)...[

          const SizedBox(height:6),

          Row(

            children:[

              Icon(
                Icons.trending_up,
                size:15,
                color:DashboardTheme.success,
              ),

              const SizedBox(width:4),

              Text(
                change!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: DashboardTheme.success,
                ),
              )

            ],
          )

        ]

      ],
    ),
  );

}
Widget _desktopCard() {

  return Container(

    padding: const EdgeInsets.all(20),

    decoration: DashboardTheme.cardDecoration,

    child: Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Container(
          padding: const EdgeInsets.all(12),

          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(14),
          ),

          child: Icon(
            icon,
            color: color,
          ),
        ),

        const Spacer(),

        Text(
          value,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height:6),

        Text(
          title,
          style: const TextStyle(
            color: DashboardTheme.subtitle,
            fontSize:14,
          ),
        ),

        if(change!=null)...[

          const SizedBox(height:10),

          Row(

            children:[

              const Icon(
                Icons.trending_up,
                color: DashboardTheme.success,
                size:16,
              ),

              const SizedBox(width:4),

              Text(
                change!,
                style: const TextStyle(
                  color: DashboardTheme.success,
                  fontWeight: FontWeight.bold,
                ),
              )

            ],

          )

        ]

      ],

    ),

  );

}
}