import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Bell in the header with the number of unread updates from the clinic.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final unread = data.unreadNotifications;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showNotificationsSheet(context),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none,
                    size: 20,
                    color: AppColors.textDark,
                    semanticLabel: unread > 0 ? '$unread new updates' : 'Updates',
                  ),
                ),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.paper, width: 1.5),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The list of updates. Opening it marks them as read.
Future<void> showNotificationsSheet(BuildContext context) async {
  final data = AppData.instance;
  final unreadIds = data.notifications.where((n) => !n.isRead).map((n) => n.id).toSet();
  data.markNotificationsRead().catchError((_) {});
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: AnimatedBuilder(
          animation: data,
          builder: (ctx, _) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Text('Updates from the clinic', style: AppText.heading(18)),
              const SizedBox(height: 4),
              const Text('Screening reviews and changes to your appointments.',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
              const SizedBox(height: 14),
              if (data.notifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No updates yet.', textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textGrey)),
                ),
              for (final n in data.notifications) _NotificationTile(n, isNew: unreadIds.contains(n.id)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The database stores UTC as `YYYY-MM-DD HH:MM:SS`; show it in the phone's time.
String _localTime(String utc) {
  final t = DateTime.tryParse('${utc.replaceFirst(' ', 'T')}Z')?.toLocal();
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.day}/${t.month} ${two(t.hour)}:${two(t.minute)}';
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final bool isNew;
  const _NotificationTile(this.notification, {required this.isNew});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isNew ? AppColors.successBg : AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isNew ? AppColors.primary : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(n.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
              ),
              Text(_localTime(n.createdAt), style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(n.body, style: const TextStyle(color: AppColors.textGrey, fontSize: 13.5, height: 1.35)),
        ],
      ),
    );
  }
}
