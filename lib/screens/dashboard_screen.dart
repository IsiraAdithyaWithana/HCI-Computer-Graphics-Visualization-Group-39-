import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'editor_2d_screen.dart';
import '../theme/app_theme.dart';
import '../models/design_project.dart';
import '../services/layout_persistence_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen — main app hub
// Layout: collapsible sidebar + content area
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  /// The logged-in user's ID (derived from email at login).
  /// Used to namespace all storage so multiple users can coexist.
  final String userId;

  const DashboardScreen({super.key, required this.userId});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _NavItem _currentNav = _NavItem.home;
  bool _sidebarExpanded = true;
  List<PersistedProject> _projects = [];
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final projects = await LayoutPersistenceService.instance.loadProjects(
      widget.userId,
    );
    setState(() => _projects = projects);
  }

  List<PersistedProject> get _filtered {
    if (_searchQuery.isEmpty) return _projects;
    final q = _searchQuery.toLowerCase();
    return _projects
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.roomType.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Open an existing project by ID.
  void _openProject(String projectId) async {
    final project = _projects.firstWhere(
      (p) => p.id == projectId,
      orElse: () => _projects.first,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Editor2DScreen(
          projectId: project.id,
          userId: widget.userId,
          projectName: project.name,
        ),
      ),
    );
    // Refresh after returning — furniture count / lastModified may have changed
    _loadProjects();
  }

  /// Create a brand new project and open the editor.
  Future<void> _createNewProject({RoomTemplate? template}) async {
    final id = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    // Pick a colour based on template/room type
    final rt = template?.type ?? RoomType.other;
    final colorMap = {
      RoomType.livingRoom: 0xFF7C9A92,
      RoomType.bedroom: 0xFF9A7C8E,
      RoomType.kitchen: 0xFFB8956A,
      RoomType.office: 0xFF6A82B8,
      RoomType.diningRoom: 0xFF8EA87C,
      RoomType.bathroom: 0xFF6AA8B8,
      RoomType.other: 0xFFB86A6A,
    };
    final project = PersistedProject(
      id: id,
      name: template?.name ?? 'New Design',
      roomType: rt.name,
      widthM: template?.widthM ?? 6.0,
      depthM: template?.depthM ?? 5.0,
      furnitureCount: 0,
      lastModified: now,
      createdAt: now,
      previewColorValue: colorMap[rt] ?? 0xFF7C9A92,
    );
    await LayoutPersistenceService.instance.upsertProject(
      widget.userId,
      project,
    );
    await _loadProjects();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Editor2DScreen(
          projectId: project.id,
          userId: widget.userId,
          projectName: project.name,
        ),
      ),
    );
    _loadProjects();
  }

  void _toggleFavorite(String id) async {
    final idx = _projects.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final updated = _projects[idx].copyWith(
      isFavorite: !_projects[idx].isFavorite,
    );
    await LayoutPersistenceService.instance.upsertProject(
      widget.userId,
      updated,
    );
    setState(() => _projects[idx] = updated);
  }

  void _deleteProject(String id) async {
    final backup = List<PersistedProject>.from(_projects);
    setState(() => _projects.removeWhere((p) => p.id == id));
    await LayoutPersistenceService.instance.deleteProject(widget.userId, id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Project deleted'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surfaceAlt,
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppTheme.accent,
          onPressed: () async {
            // Restore: re-insert all projects from backup
            await LayoutPersistenceService.instance.saveProjects(
              widget.userId,
              backup,
            );
            _loadProjects();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────────
          _Sidebar(
            expanded: _sidebarExpanded,
            current: _currentNav,
            onNavChanged: (n) => setState(() => _currentNav = n),
            onToggle: () =>
                setState(() => _sidebarExpanded = !_sidebarExpanded),
            onNewDesign: () => _createNewProject(),
            onLogout: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: _currentNav.label,
                  searchCtrl: _searchCtrl,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onNewDesign: () => _createNewProject(),
                ),
                Expanded(
                  child: _currentNav == _NavItem.home
                      ? _HomeContent(
                          projects: _filtered,
                          allProjects: _projects,
                          onOpen: (id) => _openProject(id),
                          onFavorite: _toggleFavorite,
                          onDelete: _deleteProject,
                          onTemplate: (t) => _createNewProject(template: t),
                        )
                      : _PlaceholderContent(nav: _currentNav),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

enum _NavItem {
  home,
  projects,
  templates,
  settings;

  String get label {
    switch (this) {
      case _NavItem.home:
        return 'Dashboard';
      case _NavItem.projects:
        return 'My Projects';
      case _NavItem.templates:
        return 'Templates';
      case _NavItem.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case _NavItem.home:
        return Icons.dashboard_outlined;
      case _NavItem.projects:
        return Icons.folder_outlined;
      case _NavItem.templates:
        return Icons.space_dashboard_outlined;
      case _NavItem.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get iconFilled {
    switch (this) {
      case _NavItem.home:
        return Icons.dashboard_rounded;
      case _NavItem.projects:
        return Icons.folder_rounded;
      case _NavItem.templates:
        return Icons.space_dashboard_rounded;
      case _NavItem.settings:
        return Icons.settings_rounded;
    }
  }
}

class _Sidebar extends StatelessWidget {
  final bool expanded;
  final _NavItem current;
  final ValueChanged<_NavItem> onNavChanged;
  final VoidCallback onToggle, onNewDesign, onLogout;

  const _Sidebar({
    required this.expanded,
    required this.current,
    required this.onNavChanged,
    required this.onToggle,
    required this.onNewDesign,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final w = expanded ? AppTheme.sidebarWidth : AppTheme.sidebarCollapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      width: w,
      color: AppTheme.surfaceDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo bar
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    color: AppTheme.accent,
                    size: 19,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'Spazio',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          Divider(color: AppTheme.borderDark, height: 1),

          // New Design button
          Padding(
            padding: EdgeInsets.all(expanded ? 14 : 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              child: expanded
                  ? ElevatedButton.icon(
                      onPressed: onNewDesign,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Design'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.bgDark,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : Tooltip(
                      message: 'New Design',
                      child: InkWell(
                        onTap: onNewDesign,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.accent.withOpacity(0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: AppTheme.accent,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // Nav items
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 8),
              child: Column(
                children: [
                  ..._NavItem.values
                      .where((n) => n != _NavItem.settings)
                      .map(
                        (nav) => _NavTile(
                          nav: nav,
                          current: current,
                          expanded: expanded,
                          onTap: () => onNavChanged(nav),
                        ),
                      ),
                ],
              ),
            ),
          ),

          Divider(color: AppTheme.borderDark, height: 1),

          // Bottom: settings + user
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 10 : 8,
              vertical: 8,
            ),
            child: Column(
              children: [
                _NavTile(
                  nav: _NavItem.settings,
                  current: current,
                  expanded: expanded,
                  onTap: () => onNavChanged(_NavItem.settings),
                ),
              ],
            ),
          ),

          // User avatar
          Container(
            margin: EdgeInsets.fromLTRB(
              expanded ? 12 : 8,
              0,
              expanded ? 12 : 8,
              14,
            ),
            padding: EdgeInsets.all(expanded ? 10 : 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.accentDark.withOpacity(0.3),
                  child: const Text(
                    'JD',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Jane Designer',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Text(
                          'Studio Pro',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: onLogout,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Collapse toggle when closed
          if (!expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem nav, current;
  final bool expanded;
  final VoidCallback onTap;
  const _NavTile({
    required this.nav,
    required this.current,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = nav == current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: expanded ? '' : nav.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 12 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.accent.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isActive
                    ? AppTheme.accent.withOpacity(0.25)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: expanded ? null : double.infinity,
                  child: Icon(
                    isActive ? nav.iconFilled : nav.icon,
                    size: 18,
                    color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nav.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isActive
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNewDesign;

  const _TopBar({
    required this.title,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onNewDesign,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(bottom: BorderSide(color: AppTheme.borderDark)),
      ),
      child: Row(
        children: [
          Text(title, style: AppTheme.titleLarge),
          const SizedBox(width: 24),

          // Search
          Expanded(
            child: Container(
              height: 38,
              constraints: const BoxConstraints(maxWidth: 340),
              child: TextField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search projects…',
                  hintStyle: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 17,
                    color: AppTheme.textMuted,
                  ),
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            searchCtrl.clear();
                            onSearchChanged('');
                          },
                          icon: const Icon(Icons.close_rounded, size: 15),
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.borderDark),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppTheme.accent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),

          // New design button
          ElevatedButton.icon(
            onPressed: onNewDesign,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Design'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDark,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Notification bell
          _IconChip(icon: Icons.notifications_outlined, badge: true),
          const SizedBox(width: 8),
          _IconChip(icon: Icons.help_outline_rounded),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final bool badge;
  const _IconChip({required this.icon, this.badge = false});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderDark),
        ),
        child: Icon(icon, size: 17, color: AppTheme.textSecondary),
      ),
      if (badge)
        Positioned(
          right: 7,
          top: 7,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.surfaceDark, width: 1.5),
            ),
          ),
        ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Home content
// ─────────────────────────────────────────────────────────────────────────────

class _HomeContent extends StatelessWidget {
  final List<PersistedProject> projects, allProjects;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onFavorite;
  final ValueChanged<String> onDelete;
  final ValueChanged<RoomTemplate> onTemplate;

  const _HomeContent({
    required this.projects,
    required this.allProjects,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
    required this.onTemplate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Welcome + date ────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Good morning, Jane 👋',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dateString(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Stats strip ───────────────────────────────────────────────────
          _StatsStrip(projects: allProjects),

          const SizedBox(height: 32),

          // ── Recent projects ───────────────────────────────────────────────
          _SectionHeader(
            title: 'Recent Projects',
            subtitle: '${allProjects.length} designs total',
            action: TextButton(
              onPressed: () {},
              child: const Text(
                'View all',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          projects.isEmpty
              ? _EmptyProjects(onNew: () => onOpen(''))
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.22,
                  ),
                  itemCount: projects.length,
                  itemBuilder: (_, i) => _ProjectCard(
                    project: projects[i],
                    onOpen: () => onOpen(projects[i].id),
                    onFavorite: () => onFavorite(projects[i].id),
                    onDelete: () => onDelete(projects[i].id),
                  ),
                ),

          const SizedBox(height: 36),

          // ── Start from template ───────────────────────────────────────────
          _SectionHeader(
            title: 'Start from Template',
            subtitle: 'Pre-configured room layouts',
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kRoomTemplates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _TemplateCard(
                template: kRoomTemplates[i],
                onTap: () => onTemplate(kRoomTemplates[i]),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // ── Quick tips ─────────────────────────────────────────────────────
          _TipsSection(),
        ],
      ),
    );
  }

  String _dateString() {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

// ── Stats strip ────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  final List<PersistedProject> projects;
  const _StatsStrip({required this.projects});

  @override
  Widget build(BuildContext context) {
    final totalFurniture = projects.fold(0, (s, p) => s + p.furnitureCount);
    final favorites = projects.where((p) => p.isFavorite).length;

    return Row(
      children: [
        _StatCard(
          value: '${projects.length}',
          label: 'Total Designs',
          icon: Icons.folder_open_outlined,
          color: AppTheme.accent,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '$totalFurniture',
          label: 'Furniture Placed',
          icon: Icons.chair_alt_outlined,
          color: const Color(0xFF6A82B8),
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '$favorites',
          label: 'Favourites',
          icon: Icons.favorite_outline,
          color: const Color(0xFFE8A838),
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '${kRoomTemplates.length}',
          label: 'Templates',
          icon: Icons.space_dashboard_outlined,
          color: const Color(0xFF4CAF7D),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const _SectionHeader({required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTheme.bodyMedium),
          ],
        ],
      ),
      const Spacer(),
      if (action != null) action!,
    ],
  );
}

// ── Project card ───────────────────────────────────────────────────────────

class _ProjectCard extends StatefulWidget {
  final PersistedProject project;
  final VoidCallback onOpen, onFavorite, onDelete;
  const _ProjectCard({
    required this.project,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
  });
  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hovered = false;

  /// Resolve RoomType from persisted string name.
  RoomType get _roomType => RoomType.values.firstWhere(
    (e) => e.name == widget.project.roomType,
    orElse: () => RoomType.other,
  );

  Color get _previewColor => Color(widget.project.previewColorValue);

  String get _dimensions =>
      '${widget.project.widthM.toStringAsFixed(1)} × '
      '${widget.project.depthM.toStringAsFixed(1)} m';

  String get _timeAgo {
    final diff = DateTime.now().difference(widget.project.lastModified);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = widget.project.lastModified;
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final rt = _roomType;
    final color = _previewColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.surfaceAlt : AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? AppTheme.accent.withOpacity(0.35)
                  : AppTheme.borderDark,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview thumbnail
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: Stack(
                    children: [
                      // Floor-plan mini preview
                      SizedBox.expand(
                        child: CustomPaint(
                          painter: _MiniFloorPlanPainter(
                            color: color,
                            widthM: p.widthM,
                            depthM: p.depthM,
                          ),
                        ),
                      ),
                      // Room type pill
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.bgDark.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(rt.icon, size: 11, color: color),
                              const SizedBox(width: 5),
                              Text(
                                rt.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Favorite button
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: widget.onFavorite,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppTheme.bgDark.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              p.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_outline,
                              size: 15,
                              color: p.isFavorite
                                  ? const Color(0xFFE8A838)
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Card body
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        _CardMenu(
                          onOpen: widget.onOpen,
                          onDelete: widget.onDelete,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _MetaChip(
                          icon: Icons.straighten_rounded,
                          label: _dimensions,
                        ),
                        const SizedBox(width: 8),
                        _MetaChip(
                          icon: Icons.chair_alt_outlined,
                          label: '${p.furnitureCount} items',
                        ),
                        const Spacer(),
                        Text(
                          _timeAgo,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: AppTheme.textMuted),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
      ),
    ],
  );
}

class _CardMenu extends StatelessWidget {
  final VoidCallback onOpen, onDelete;
  const _CardMenu({required this.onOpen, required this.onDelete});
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_horiz, size: 16, color: AppTheme.textMuted),
    padding: EdgeInsets.zero,
    color: AppTheme.surfaceAlt,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: AppTheme.borderDark),
    ),
    itemBuilder: (_) => [
      _menuItem(
        'open',
        Icons.open_in_new_rounded,
        'Open',
        AppTheme.textPrimary,
      ),
      _menuItem(
        'duplicate',
        Icons.copy_rounded,
        'Duplicate',
        AppTheme.textSecondary,
      ),
      _menuItem(
        'rename',
        Icons.drive_file_rename_outline,
        'Rename',
        AppTheme.textSecondary,
      ),
      const PopupMenuDivider(height: 4),
      _menuItem(
        'delete',
        Icons.delete_outline_rounded,
        'Delete',
        AppTheme.error,
      ),
    ],
    onSelected: (v) {
      if (v == 'open') onOpen();
      if (v == 'delete') onDelete();
    },
  );

  PopupMenuItem<String> _menuItem(
    String v,
    IconData icon,
    String label,
    Color color,
  ) => PopupMenuItem(
    value: v,
    height: 38,
    child: Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    ),
  );
}

// ── Template card ──────────────────────────────────────────────────────────

class _TemplateCard extends StatefulWidget {
  final RoomTemplate template;
  final VoidCallback onTap;
  const _TemplateCard({required this.template, required this.onTap});
  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final color = t.type.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 200,
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.surfaceAlt : AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? color.withOpacity(0.5) : AppTheme.borderDark,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(13),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(t.type.icon, size: 22, color: color),
                      const SizedBox(height: 8),
                      Text(
                        t.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.description,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${t.widthM.toStringAsFixed(0)}×${t.depthM.toStringAsFixed(0)} m',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
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

// ── Quick tips ─────────────────────────────────────────────────────────────

class _TipsSection extends StatelessWidget {
  final _tips = const [
    (
      Icons.touch_app_outlined,
      'Select any furniture in the sidebar — the canvas switches to draw mode instantly.',
    ),
    (
      Icons.view_in_ar_outlined,
      'Hit "Realistic 3D View" to see your room rendered with real 3D furniture models.',
    ),
    (
      Icons.add_box_outlined,
      'Import custom .glb files to add your own furniture to the library.',
    ),
    (
      Icons.save_outlined,
      'Custom furniture is auto-saved and survives app restarts.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeader(
        title: 'Quick Tips',
        subtitle: 'Get the most out of Spazio',
      ),
      const SizedBox(height: 14),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 360,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.8,
        ),
        itemCount: _tips.length,
        itemBuilder: (_, i) {
          final tip = _tips[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(tip.$1, size: 16, color: AppTheme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tip.$2,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ],
  );
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyProjects extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyProjects({required this.onNew});
  @override
  Widget build(BuildContext context) => Container(
    height: 220,
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
          ),
          child: const Icon(
            Icons.folder_off_outlined,
            size: 28,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No projects found',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Start a new design or try a different search.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create First Design'),
        ),
      ],
    ),
  );
}

// ── Placeholder for other nav items ───────────────────────────────────────

class _PlaceholderContent extends StatelessWidget {
  final _NavItem nav;
  const _PlaceholderContent({required this.nav});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(nav.iconFilled, size: 48, color: AppTheme.textMuted),
        const SizedBox(height: 16),
        Text(nav.label, style: AppTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Coming soon',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini floor plan painter — used in project card thumbnails
// ─────────────────────────────────────────────────────────────────────────────

class _MiniFloorPlanPainter extends CustomPainter {
  final Color color;
  final double widthM, depthM;
  const _MiniFloorPlanPainter({
    required this.color,
    required this.widthM,
    required this.depthM,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withOpacity(0.12), AppTheme.bgDark.withOpacity(0.95)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw a simple floor plan scaled to room ratio
    final margin = 14.0;
    final ratio = (widthM / depthM).clamp(0.5, 2.5);
    double rW, rH;
    if (ratio >= 1) {
      rW = size.width - margin * 2;
      rH = rW / ratio;
    } else {
      rH = size.height - margin * 2;
      rW = rH * ratio;
    }
    rH = rH.clamp(0, size.height - margin * 2);

    final left = (size.width - rW) / 2;
    final top = (size.height - rH) / 2;
    final room = Rect.fromLTWH(left, top, rW, rH);

    final wallPaint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = color.withOpacity(0.06)
      ..style = PaintingStyle.fill;

    canvas.drawRect(room, fillPaint);
    canvas.drawRect(room, wallPaint);

    // Random-looking furniture blobs (deterministic based on room dims)
    final rng = math.Random(widthM.toInt() * 100 + depthM.toInt());
    final furniPaint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final furniStroke = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 5; i++) {
      final fx = left + margin / 2 + rng.nextDouble() * (rW - margin);
      final fy = top + margin / 2 + rng.nextDouble() * (rH - margin);
      final fw = 8 + rng.nextDouble() * (rW / 4);
      final fh = 6 + rng.nextDouble() * (rH / 4);
      final fr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(fx, fy), width: fw, height: fh),
        const Radius.circular(2),
      );
      canvas.drawRRect(fr, furniPaint);
      canvas.drawRRect(fr, furniStroke);
    }

    // Grid dots
    final dotPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    for (int xi = 0; xi < 5; xi++) {
      for (int yi = 0; yi < 4; yi++) {
        canvas.drawCircle(
          Offset(left + rW / 5 * xi, top + rH / 4 * yi),
          1.5,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniFloorPlanPainter old) =>
      old.color != color || old.widthM != widthM || old.depthM != depthM;
}
