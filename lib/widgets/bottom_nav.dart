import 'package:flutter/material.dart';

class BottomNav extends StatelessWidget {
  final String current;
  final Function(String) navigate;

  const BottomNav({
    super.key,
    required this.current,
    required this.navigate,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      {
        'id': 'dashboard',
        'label': 'Beranda',
        'icon': Icons.space_dashboard_rounded,
      },
      {
        'id': 'history',
        'label': 'Histori',
        'icon': Icons.access_time_rounded,
      },
      {
        'id': 'device',
        'label': 'Perangkat',
        'icon': Icons.memory_rounded,
      },
      {
        'id': 'emergency',
        'label': 'SOS',
        'icon': Icons.warning_amber_rounded,
      },
    ];

    return Container(
      height: 68 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.black.withOpacity(0.06),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: Row(
        children: items.map((item) {
          final isActive = current == item['id'];
          final isEmergency = item['id'] == 'emergency';
          final activeColor = isEmergency
              ? const Color(0xFFDC2626)
              : const Color(0xFF0A858C);
          final inactiveColor = isEmergency
              ? const Color(0xFFEF4444)
              : const Color(0xFF94A3B8);
          final color = isActive ? activeColor : inactiveColor;

          return Expanded(
            child: GestureDetector(
              onTap: () => navigate(item['id'] as String),
              behavior: HitTestBehavior.opaque,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Top indicator
                  if (isActive)
                    Container(
                      height: 3,
                      width: 32,
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isActive
                                ? color.withOpacity(0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['label'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
