import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'states.dart';

/// One sidebar destination in an admin console.
class AdminDestination {
  const AdminDestination({
    required this.label,
    required this.icon,
    required this.path,
    this.selectedIcon,
    this.badge,
  });
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String path;

  /// Optional count badge (computed from records).
  final int? badge;
}

/// Responsive admin console frame:
/// * ≥ 1100 px: collapsible sidebar (expanded by default)
/// * 720–1100 px: collapsed icon sidebar
/// * < 720 px: app bar + navigation drawer
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.workspaceName,
    required this.organizationLabel,
    required this.accent,
    required this.icon,
    required this.destinations,
    required this.currentPath,
    required this.child,
    this.notificationCount = 0,
    this.onNotifications,
    this.onSwitchWorkspace,
  });

  final String workspaceName;
  final String organizationLabel;
  final Color accent;
  final IconData icon;
  final List<AdminDestination> destinations;
  final String currentPath;
  final Widget child;
  final int notificationCount;
  final VoidCallback? onNotifications;
  final VoidCallback? onSwitchWorkspace;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool? _collapsed;

  AdminDestination? get _current {
    AdminDestination? best;
    for (final d in widget.destinations) {
      if (widget.currentPath == d.path ||
          widget.currentPath.startsWith('${d.path}/')) {
        if (best == null || d.path.length > best.path.length) best = d;
      }
    }
    return best;
  }

  void _go(String path) => context.go(path);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 720;
    final collapsed = _collapsed ?? width < 1100;
    final title = _current?.label ?? widget.workspaceName;

    if (narrow) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: AppColors.white,
          shape: const Border(bottom: BorderSide(color: AppColors.divider)),
          actions: [
            const Center(child: DemoBadge()),
            _bell(),
            const SizedBox(width: 4),
          ],
        ),
        drawer: Drawer(
          width: 288,
          child: SafeArea(
            child: _sidebar(context, collapsed: false, inDrawer: true),
          ),
        ),
        body: widget.child,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: collapsed ? 76 : 256,
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(right: BorderSide(color: AppColors.divider)),
            ),
            child: SafeArea(
              child: _sidebar(context, collapsed: collapsed, inDrawer: false),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    border: Border(
                      bottom: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: collapsed
                            ? 'Expand sidebar'
                            : 'Collapse sidebar',
                        onPressed: () =>
                            setState(() => _collapsed = !collapsed),
                        icon: Icon(
                          collapsed
                              ? Icons.menu_rounded
                              : Icons.menu_open_rounded,
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      const DemoBadge(),
                      const SizedBox(width: AppSpace.xs),
                      _bell(),
                    ],
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bell() => IconButton(
    tooltip: 'Notifications',
    onPressed: widget.onNotifications,
    icon: Badge(
      isLabelVisible: widget.notificationCount > 0,
      label: Text(
        '${widget.notificationCount > 99 ? '99+' : widget.notificationCount}',
      ),
      child: const Icon(Icons.notifications_none_rounded),
    ),
  );

  Widget _sidebar(
    BuildContext context, {
    required bool collapsed,
    required bool inDrawer,
  }) {
    final t = Theme.of(context).textTheme;
    final current = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            collapsed ? 14 : AppSpace.md,
            AppSpace.md,
            AppSpace.md,
            AppSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.accent,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(widget.icon, color: Colors.white, size: 22),
              ),
              if (!collapsed) ...[
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.workspaceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall,
                      ),
                      Text(
                        widget.organizationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall!.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 10 : AppSpace.sm,
              vertical: AppSpace.sm,
            ),
            children: [
              for (final d in widget.destinations)
                _NavItem(
                  destination: d,
                  selected: current == d,
                  collapsed: collapsed,
                  onTap: () {
                    if (inDrawer) Navigator.of(context).pop();
                    _go(d.path);
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.all(collapsed ? 10 : AppSpace.sm),
          child: _NavItem(
            destination: const AdminDestination(
              label: 'Sign out',
              icon: Icons.logout_rounded,
              path: '/',
            ),
            selected: false,
            collapsed: collapsed,
            onTap: () {
              if (inDrawer) Navigator.of(context).pop();
              (widget.onSwitchWorkspace ?? () => _go('/'))();
            },
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });
  final AdminDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = selected ? AppColors.primary : AppColors.textSecondary;
    final icon = Icon(
      selected
          ? (destination.selectedIcon ?? destination.icon)
          : destination.icon,
      color: fg,
      size: 22,
    );
    final badge = destination.badge ?? 0;
    final item = Material(
      color: selected ? AppColors.softBlue : Colors.transparent,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Container(
          height: 48,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : AppSpace.sm,
          ),
          alignment: collapsed ? Alignment.center : Alignment.centerLeft,
          child: collapsed
              ? Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: icon,
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelLarge!.copyWith(
                          color: fg,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.divider,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: t.labelSmall!.copyWith(
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        child: collapsed
            ? Tooltip(message: destination.label, child: item)
            : item,
      ),
    );
  }
}

/// Scrollable admin page body with consistent header and max width.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
    this.maxWidth = 1320,
  });

  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 720 ? AppSpace.md : AppSpace.xl;
    final t = Theme.of(context).textTheme;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpace.xxxl),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null || actions.isNotEmpty) ...[
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: AppSpace.sm,
                    spacing: AppSpace.md,
                    children: [
                      if (title != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title!, style: t.headlineSmall),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!,
                                  style: t.bodyMedium!.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (actions.isNotEmpty)
                        Wrap(
                          spacing: AppSpace.xs,
                          runSpacing: AppSpace.xs,
                          children: actions,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xl),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Destination for [MobileNavShell].
class MobileDestination {
  const MobileDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge = 0,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
}

/// Bottom-tab shell for the Employee and Driver apps (StatefulShellRoute).
class MobileNavShell extends StatelessWidget {
  const MobileNavShell({
    super.key,
    required this.navigationShell,
    required this.destinations,
    this.accessory,
    this.maxContentWidth = 640,
  });

  final StatefulNavigationShell navigationShell;
  final List<MobileDestination> destinations;

  /// Persistent bar above the tabs (e.g. "Active trip" quick-open).
  final Widget? accessory;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?accessory,
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (i) => navigationShell.goBranch(
                i,
                initialLocation: i == navigationShell.currentIndex,
              ),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: d.badge > 0,
                      label: Text('${d.badge}'),
                      child: Icon(d.icon),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: d.badge > 0,
                      label: Text('${d.badge}'),
                      child: Icon(d.selectedIcon),
                    ),
                    label: d.label,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile page body with gutters, max width and pull-to-refresh-free scroll.
class MobilePage extends StatelessWidget {
  const MobilePage({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ListView(
    padding:
        padding ??
        const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xxxl,
        ),
    children: children,
  );
}
