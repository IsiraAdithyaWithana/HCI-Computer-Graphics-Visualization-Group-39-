import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';
import 'editor_2d_screen.dart';
import '../theme/app_theme.dart';
import '../models/design_project.dart';
import '../services/layout_persistence_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
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

  // Notification panel
  bool _showNotifications = false;
  final List<_Notification> _notifications = [
    _Notification(
      icon: Icons.new_releases_outlined,
      color: Color(0xFF6A82B8),
      title: 'Spazio updated',
      body: 'New: ceiling layer, lighting system & background colour picker.',
      time: '2h ago',
    ),
    _Notification(
      icon: Icons.tips_and_updates_outlined,
      color: Color(0xFFE8A838),
      title: 'Tip: Scale your GLB models',
      body:
          'Open 3D View → select a piece → use the Scale slider and tap Save Size.',
      time: '1d ago',
    ),
    _Notification(
      icon: Icons.star_outline_rounded,
      color: Color(0xFF4CAF7D),
      title: 'Favourite your best designs',
      body: 'Tap the heart on any project card to pin it to your favourites.',
      time: '3d ago',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final projects = await LayoutPersistenceService.instance.loadProjects(
      widget.userId,
    );
    if (mounted) setState(() => _projects = projects);
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

  // ── Derive display name from userId (email) ──────────────────────────────
  String get _displayName {
    final raw = widget.userId;
    if (raw == 'guest') return 'Guest';
    final local = raw.split('@').first;
    return local
        .split(RegExp(r'[._-]'))
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ')
        .trim();
  }

  String get _initials {
    final parts = _displayName.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?';
  }

  // ── Project actions ───────────────────────────────────────────────────────

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
    _loadProjects();
  }

  Future<void> _createNewProject({RoomTemplate? template}) async {
    // Ask for a project name before creating
    final defaultName = template?.name ?? 'New Design';
    final ctrl = TextEditingController(text: defaultName);
    // Select all text so user can type immediately
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: ctrl.text.length,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewProjectDialog(
        ctrl: ctrl,
        defaultName: defaultName,
        template: template,
      ),
    );
    ctrl.dispose();
    if (result == null) return; // user cancelled

    final id = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
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
      name: result.trim().isEmpty ? defaultName : result.trim(),
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

    // If the template has pre-built furniture, save it into the project's
    // layout storage now — the editor will load it on first open.
    if (template?.furnitureJson != null) {
      await LayoutPersistenceService.instance.save(
        userId: widget.userId,
        projectId: id,
        furnitureJson: template!.furnitureJson!,
        roomWidthM: project.widthM,
        roomDepthM: project.depthM,
      );
    }

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
  }

  void _renameProject(String id) async {
    final idx = _projects.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final ctrl = TextEditingController(text: _projects[idx].name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(ctrl: ctrl),
    );
    if (result != null && result.trim().isNotEmpty && mounted) {
      final updated = _projects[idx].copyWith(
        name: result.trim(),
        lastModified: DateTime.now(),
      );
      await LayoutPersistenceService.instance.upsertProject(
        widget.userId,
        updated,
      );
      setState(() => _projects[idx] = updated);
    }
  }

  void _duplicateProject(String id) async {
    final idx = _projects.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final orig = _projects[idx];
    final newId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    final copy = PersistedProject(
      id: newId,
      name: '${orig.name} (Copy)',
      roomType: orig.roomType,
      widthM: orig.widthM,
      depthM: orig.depthM,
      furnitureCount: orig.furnitureCount,
      lastModified: now,
      createdAt: now,
      previewColorValue: orig.previewColorValue,
    );
    // Also copy furniture data from persistence
    final snapshot = await LayoutPersistenceService.instance.load(
      userId: widget.userId,
      projectId: id,
    );
    await LayoutPersistenceService.instance.upsertProject(widget.userId, copy);
    if (snapshot != null) {
      await LayoutPersistenceService.instance.save(
        userId: widget.userId,
        projectId: newId,
        furnitureJson: snapshot.furnitureJson,
        roomWidthM: snapshot.roomWidthM,
        roomDepthM: snapshot.roomDepthM,
        colourScheme: snapshot.colourScheme,
        canvasBgColour: snapshot.canvasBgColour,
      );
    }
    await _loadProjects();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(
        children: [
          Row(
            children: [
              _Sidebar(
                expanded: _sidebarExpanded,
                current: _currentNav,
                initials: _initials,
                displayName: _displayName,
                userId: widget.userId,
                onNavChanged: (n) => setState(() {
                  _currentNav = n;
                  _showNotifications = false;
                }),
                onToggle: () =>
                    setState(() => _sidebarExpanded = !_sidebarExpanded),
                onNewDesign: () => _createNewProject(),
                onLogout: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: _currentNav.label,
                      searchCtrl: _searchCtrl,
                      onSearchChanged: (v) => setState(() => _searchQuery = v),
                      onNewDesign: () => _createNewProject(),
                      notificationCount: _notifications.length,
                      onNotification: () => setState(
                        () => _showNotifications = !_showNotifications,
                      ),
                      onHelp: () => _showHelp(),
                    ),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
          // Notification overlay
          if (_showNotifications)
            Positioned(
              top: 64,
              right: 16,
              child: _NotificationPanel(
                notifications: _notifications,
                onClose: () => setState(() => _showNotifications = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentNav) {
      case _NavItem.home:
        return _HomeContent(
          projects: _filtered,
          allProjects: _projects,
          onOpen: _openProject,
          onFavorite: _toggleFavorite,
          onDelete: _deleteProject,
          onRename: _renameProject,
          onDuplicate: _duplicateProject,
          onTemplate: (t) => _createNewProject(template: t),
          onViewAllProjects: () =>
              setState(() => _currentNav = _NavItem.projects),
        );
      case _NavItem.projects:
        return _ProjectsContent(
          projects: _filtered,
          searchQuery: _searchQuery,
          onOpen: _openProject,
          onFavorite: _toggleFavorite,
          onDelete: _deleteProject,
          onRename: _renameProject,
          onDuplicate: _duplicateProject,
          onNew: () => _createNewProject(),
        );
      case _NavItem.templates:
        return _TemplatesContent(
          onTemplate: (t) => _createNewProject(template: t),
        );
      case _NavItem.settings:
        return _SettingsContent(
          userId: widget.userId,
          displayName: _displayName,
          onLogout: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
        );
    }
  }

  void _showHelp() {
    showDialog(context: context, builder: (_) => const _HelpDialog());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav enum
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

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final bool expanded;
  final _NavItem current;
  final String initials, displayName, userId;
  final ValueChanged<_NavItem> onNavChanged;
  final VoidCallback onToggle, onNewDesign, onLogout;

  const _Sidebar({
    required this.expanded,
    required this.current,
    required this.initials,
    required this.displayName,
    required this.userId,
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
            child: expanded
                ? ElevatedButton.icon(
                    onPressed: onNewDesign,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Design'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.bgDark,
                      minimumSize: const Size(double.infinity, 40),
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

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 10 : 8,
              vertical: 8,
            ),
            child: _NavTile(
              nav: _NavItem.settings,
              current: current,
              expanded: expanded,
              onTap: () => onNavChanged(_NavItem.settings),
            ),
          ),

          // User avatar — shows actual login userId
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
                  child: Text(
                    initials,
                    style: const TextStyle(
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
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          userId == 'guest' ? 'Guest user' : userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
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
                      child: const Icon(
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
  final int notificationCount;
  final VoidCallback onNotification;
  final VoidCallback onHelp;

  const _TopBar({
    required this.title,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onNewDesign,
    required this.notificationCount,
    required this.onNotification,
    required this.onHelp,
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

          // Search bar
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
          Tooltip(
            message: 'Notifications',
            child: _IconBtn(
              icon: Icons.notifications_outlined,
              badge: notificationCount > 0,
              badgeCount: notificationCount,
              onTap: onNotification,
            ),
          ),
          const SizedBox(width: 8),

          // Help button
          Tooltip(
            message: 'Help & Tips',
            child: _IconBtn(icon: Icons.help_outline_rounded, onTap: onHelp),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool badge;
  final int badgeCount;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    this.badge = false,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(
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
            right: 6,
            top: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.surfaceDark, width: 1.5),
              ),
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification panel
// ─────────────────────────────────────────────────────────────────────────────

class _Notification {
  final IconData icon;
  final Color color;
  final String title, body, time;
  const _Notification({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.time,
  });
}

class _NotificationPanel extends StatelessWidget {
  final List<_Notification> notifications;
  final VoidCallback onClose;
  const _NotificationPanel({
    required this.notifications,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderDark),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${notifications.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.borderDark, height: 1),
            ...notifications.map((n) => _NotifItem(n: n)),
          ],
        ),
      ),
    );
  }
}

class _NotifItem extends StatelessWidget {
  final _Notification n;
  const _NotifItem({required this.n});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: n.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(n.icon, size: 18, color: n.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      n.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    n.time,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                n.body,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AppTheme.borderDark, height: 1),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Home content
// ─────────────────────────────────────────────────────────────────────────────

class _HomeContent extends StatelessWidget {
  final List<PersistedProject> projects, allProjects;
  final ValueChanged<String> onOpen,
      onFavorite,
      onDelete,
      onRename,
      onDuplicate;
  final ValueChanged<RoomTemplate> onTemplate;
  final VoidCallback onViewAllProjects;

  const _HomeContent({
    required this.projects,
    required this.allProjects,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
    required this.onTemplate,
    required this.onViewAllProjects,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting 👋',
                    style: const TextStyle(
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
          _StatsStrip(projects: allProjects),
          const SizedBox(height: 32),

          // Recent projects
          _SectionHeader(
            title: 'Recent Projects',
            subtitle: '${allProjects.length} designs total',
            action: TextButton(
              onPressed: onViewAllProjects,
              child: const Text(
                'View all →',
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
              ? _EmptyProjects(onNew: onViewAllProjects)
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.22,
                  ),
                  itemCount: projects.length > 6 ? 6 : projects.length,
                  itemBuilder: (_, i) => _ProjectCard(
                    project: projects[i],
                    onOpen: () => onOpen(projects[i].id),
                    onFavorite: () => onFavorite(projects[i].id),
                    onDelete: () => onDelete(projects[i].id),
                    onRename: () => onRename(projects[i].id),
                    onDuplicate: () => onDuplicate(projects[i].id),
                  ),
                ),

          const SizedBox(height: 36),

          // Templates
          const _SectionHeader(
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

// ─────────────────────────────────────────────────────────────────────────────
// My Projects page
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectsContent extends StatefulWidget {
  final List<PersistedProject> projects;
  final String searchQuery;
  final ValueChanged<String> onOpen,
      onFavorite,
      onDelete,
      onRename,
      onDuplicate;
  final VoidCallback onNew;

  const _ProjectsContent({
    required this.projects,
    required this.searchQuery,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
    required this.onNew,
  });

  @override
  State<_ProjectsContent> createState() => _ProjectsContentState();
}

class _ProjectsContentState extends State<_ProjectsContent> {
  String _sort = 'recent'; // recent | name | furniture
  bool _favOnly = false;

  List<PersistedProject> get _display {
    var list = widget.projects;
    if (_favOnly) list = list.where((p) => p.isFavorite).toList();
    switch (_sort) {
      case 'name':
        list = [...list]..sort((a, b) => a.name.compareTo(b.name));
      case 'furniture':
        list = [...list]
          ..sort((a, b) => b.furnitureCount.compareTo(a.furnitureCount));
      default: // recent
        list = [...list]
          ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Controls
          Row(
            children: [
              Text(
                '${_display.length} project${_display.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              // Favourites filter
              _FilterChip(
                label: 'Favourites',
                icon: Icons.favorite_outline,
                active: _favOnly,
                onTap: () => setState(() => _favOnly = !_favOnly),
              ),
              const SizedBox(width: 10),
              // Sort dropdown
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderDark),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sort,
                    dropdownColor: AppTheme.surfaceAlt,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'recent',
                        child: Text('Most recent'),
                      ),
                      DropdownMenuItem(value: 'name', child: Text('Name A–Z')),
                      DropdownMenuItem(
                        value: 'furniture',
                        child: Text('Most furniture'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _sort = v ?? 'recent'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Expanded(
            child: _display.isEmpty
                ? _EmptyProjects(onNew: widget.onNew)
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.22,
                        ),
                    itemCount: _display.length,
                    itemBuilder: (_, i) => _ProjectCard(
                      project: _display[i],
                      onOpen: () => widget.onOpen(_display[i].id),
                      onFavorite: () => widget.onFavorite(_display[i].id),
                      onDelete: () => widget.onDelete(_display[i].id),
                      onRename: () => widget.onRename(_display[i].id),
                      onDuplicate: () => widget.onDuplicate(_display[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? AppTheme.accent.withOpacity(0.15) : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? AppTheme.accent.withOpacity(0.4)
              : AppTheme.borderDark,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: active ? AppTheme.accent : AppTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: active ? AppTheme.accent : AppTheme.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Templates page
// ─────────────────────────────────────────────────────────────────────────────

class _TemplatesContent extends StatelessWidget {
  final ValueChanged<RoomTemplate> onTemplate;
  const _TemplatesContent({required this.onTemplate});

  static const List<RoomTemplate> _extended = [
    ...kRoomTemplates,
    RoomTemplate(
      name: 'Cosy Dining',
      type: RoomType.diningRoom,
      widthM: 5.0,
      depthM: 4.0,
      description: 'Intimate dining space',
    ),
    RoomTemplate(
      name: 'Master Bathroom',
      type: RoomType.bathroom,
      widthM: 4.0,
      depthM: 3.5,
      description: 'Luxury en-suite',
    ),
    RoomTemplate(
      name: 'Grand Living Room',
      type: RoomType.livingRoom,
      widthM: 9.0,
      depthM: 7.0,
      description: 'Open-plan living',
    ),
    RoomTemplate(
      name: 'Kids Bedroom',
      type: RoomType.bedroom,
      widthM: 4.0,
      depthM: 3.5,
      description: 'Fun & functional',
    ),
    RoomTemplate(
      name: 'Home Studio',
      type: RoomType.office,
      widthM: 5.5,
      depthM: 4.5,
      description: 'Creative workspace',
    ),
    RoomTemplate(
      name: 'Open Kitchen',
      type: RoomType.kitchen,
      widthM: 6.0,
      depthM: 5.0,
      description: 'Island kitchen layout',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Group by room type
    final grouped = <RoomType, List<RoomTemplate>>{};
    for (final t in _extended) {
      grouped.putIfAbsent(t.type, () => []).add(t);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a template to start your design with the right room size and setup.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 28),
          ...grouped.entries.map((entry) {
            final rt = entry.key;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(rt.icon, size: 16, color: rt.color),
                    const SizedBox(width: 8),
                    Text(
                      rt.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: rt.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: entry.value.length,
                  itemBuilder: (_, i) => _TemplateGridCard(
                    template: entry.value[i],
                    onTap: () => onTemplate(entry.value[i]),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _TemplateGridCard extends StatefulWidget {
  final RoomTemplate template;
  final VoidCallback onTap;
  const _TemplateGridCard({required this.template, required this.onTap});
  @override
  State<_TemplateGridCard> createState() => _TemplateGridCardState();
}

class _TemplateGridCardState extends State<_TemplateGridCard> {
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.surfaceAlt : AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? color.withOpacity(0.5) : AppTheme.borderDark,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: color.withOpacity(0.12), blurRadius: 12)]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(t.type.icon, size: 16, color: color),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${t.widthM.toStringAsFixed(0)}×${t.depthM.toStringAsFixed(0)} m',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                t.description,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const Spacer(),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    _hovered ? 'Use template →' : '',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings page
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsContent extends StatelessWidget {
  final String userId, displayName;
  final VoidCallback onLogout;
  const _SettingsContent({
    required this.userId,
    required this.displayName,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account section
          _SettingsSection(
            title: 'Account',
            children: [
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                label: 'Name',
                trailing: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              _SettingsRow(
                icon: Icons.alternate_email_rounded,
                label: 'Login ID',
                trailing: Text(
                  userId,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              _SettingsRow(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                danger: true,
                onTap: onLogout,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // App section
          _SettingsSection(
            title: 'Application',
            children: [
              _SettingsRow(
                icon: Icons.info_outline_rounded,
                label: 'App name',
                trailing: const Text(
                  'Spazio Room Designer',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
              _SettingsRow(
                icon: Icons.tag_rounded,
                label: 'Version',
                trailing: const Text(
                  '1.0.0',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
              _SettingsRow(
                icon: Icons.code_rounded,
                label: 'Built with',
                trailing: const Text(
                  'Flutter · Three.js · Dart',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // How to use section
          _SettingsSection(
            title: 'How to use',
            children: [
              _SettingsRow(
                icon: Icons.mouse_outlined,
                label: '2D Canvas',
                trailing: const Text(
                  'Select tool → click to place furniture',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              _SettingsRow(
                icon: Icons.view_in_ar_outlined,
                label: '3D View',
                trailing: const Text(
                  'Left-drag orbit · Scroll zoom · Right-drag pan',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              _SettingsRow(
                icon: Icons.open_in_new_rounded,
                label: 'Import furniture',
                trailing: const Text(
                  'Sidebar → + button → choose .glb file',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              _SettingsRow(
                icon: Icons.straighten_rounded,
                label: 'Resize in 3D',
                trailing: const Text(
                  'Select item in 3D → Scale slider → Save Size',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Data section
          _SettingsSection(
            title: 'Data & Storage',
            children: [
              _SettingsRow(
                icon: Icons.storage_outlined,
                label: 'Storage',
                trailing: const Text(
                  'Local device (SharedPreferences)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              _SettingsRow(
                icon: Icons.cloud_off_outlined,
                label: 'Cloud sync',
                trailing: const Text(
                  'Not available — all data is local',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.textMuted,
          letterSpacing: 1.0,
        ),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderDark),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final bool danger;
  final VoidCallback? onTap;
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: danger ? AppTheme.error : AppTheme.textSecondary,
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: danger ? AppTheme.error : AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
          if (onTap != null && trailing == null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppTheme.textMuted,
            ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Help dialog
// ─────────────────────────────────────────────────────────────────────────────

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: AppTheme.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Help & Shortcuts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: AppTheme.borderDark),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HelpSection(
                      title: '2D Canvas',
                      items: const [
                        ('Select tool', 'Click any item to select it'),
                        (
                          'Place furniture',
                          'Choose item in sidebar → click canvas',
                        ),
                        ('Move', 'Drag selected item'),
                        ('Rotate', 'Drag the blue circle handle above item'),
                        ('Delete', 'Select item → press Delete key'),
                        ('Undo / Redo', 'Ctrl+Z / Ctrl+Y or top-bar buttons'),
                        ('Zoom', 'Scroll wheel or +/- buttons'),
                        ('Pan canvas', 'Switch to Hand tool → drag'),
                        ('Multi-select', 'Ctrl+click or drag a selection box'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _HelpSection(
                      title: '3D View',
                      items: const [
                        ('Orbit', 'Left-drag'),
                        ('Zoom', 'Scroll wheel or W/S keys'),
                        ('Pan', 'Right-drag or Arrow keys'),
                        ('Rotate view', 'A/D keys'),
                        ('Select furniture', 'Enable Select mode → left-click'),
                        ('Scale selected', 'Use the Scale slider → Save Size'),
                        (
                          'Tint colour',
                          'Pick a colour in the panel → Save Tint',
                        ),
                        ('Background colour', 'Top-right Background button'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _HelpSection(
                      title: 'Lights',
                      items: const [
                        ('Floor lamp', 'Place anywhere on the floor'),
                        ('Table lamp', 'Place on top of a table/desk'),
                        ('Wall light', 'Snaps automatically to nearest wall'),
                        (
                          'Ceiling spot',
                          'Enable Ceiling Layer → place on ceiling canvas',
                        ),
                        ('Window', 'Snaps to nearest wall'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _HelpSection(
                      title: 'Projects & Dashboard',
                      items: const [
                        ('Rename', 'Three-dot menu on project card → Rename'),
                        ('Duplicate', 'Three-dot menu → Duplicate'),
                        ('Delete', 'Three-dot menu → Delete (with undo)'),
                        ('Favourite', 'Tap the heart icon on any card'),
                        (
                          'Search',
                          'Type in the search bar — filters all pages',
                        ),
                        ('Templates', 'Dashboard sidebar → Templates'),
                        ('Import custom GLB', 'Sidebar + button in editor'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<(String, String)> items;
  const _HelpSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.accent,
          letterSpacing: 1.0,
        ),
      ),
      const SizedBox(height: 10),
      ...items.map(
        (item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 160,
                child: Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rename dialog
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// New project dialog — asks for name + shows template info
// ─────────────────────────────────────────────────────────────────────────────

class _NewProjectDialog extends StatelessWidget {
  final TextEditingController ctrl;
  final String defaultName;
  final RoomTemplate? template;
  const _NewProjectDialog({
    required this.ctrl,
    required this.defaultName,
    this.template,
  });

  @override
  Widget build(BuildContext context) {
    final rt = template?.type;
    return Dialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (rt?.color ?? AppTheme.accent).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    rt?.icon ?? Icons.add_box_outlined,
                    size: 20,
                    color: rt?.color ?? AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Design',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (template != null)
                        Text(
                          '${template!.widthM.toStringAsFixed(0)} × ${template!.depthM.toStringAsFixed(0)} m  ·  ${template!.description}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Project name',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: defaultName,
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.borderDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.accent,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(
                context,
                v.trim().isEmpty ? defaultName : v.trim(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    ctrl.text.trim().isEmpty ? defaultName : ctrl.text.trim(),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text(
                    'Create',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.bgDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatelessWidget {
  final TextEditingController ctrl;
  const _RenameDialog({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rename Project',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Project name…',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.borderDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.accent,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, ctrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.bgDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Rename',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats strip
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Project card
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectCard extends StatefulWidget {
  final PersistedProject project;
  final VoidCallback onOpen, onFavorite, onDelete, onRename, onDuplicate;
  const _ProjectCard({
    required this.project,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
  });

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hovered = false;

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
              // Preview
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: Stack(
                    children: [
                      SizedBox.expand(
                        child: CustomPaint(
                          painter: _MiniFloorPlanPainter(
                            color: color,
                            widthM: p.widthM,
                            depthM: p.depthM,
                          ),
                        ),
                      ),
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
                          onRename: widget.onRename,
                          onDuplicate: widget.onDuplicate,
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
  final VoidCallback onOpen, onDelete, onRename, onDuplicate;
  const _CardMenu({
    required this.onOpen,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
  });

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
        'rename',
        Icons.drive_file_rename_outline,
        'Rename',
        AppTheme.textSecondary,
      ),
      _menuItem(
        'duplicate',
        Icons.copy_rounded,
        'Duplicate',
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
      if (v == 'rename') onRename();
      if (v == 'duplicate') onDuplicate();
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

// ─────────────────────────────────────────────────────────────────────────────
// Template card (horizontal scroll on home page)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Tips section
// ─────────────────────────────────────────────────────────────────────────────

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
      Icons.straighten_rounded,
      'Resize any furniture in 3D view — the new size is saved for ALL projects.',
    ),
    (
      Icons.wb_incandescent_outlined,
      'Enable the Ceiling Layer to place ceiling spotlights and see them in 3D.',
    ),
    (
      Icons.copy_rounded,
      'Duplicate a project from the three-dot menu to experiment without losing the original.',
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.bgDark,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini floor plan painter
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
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withOpacity(0.12), AppTheme.bgDark.withOpacity(0.95)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

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

    canvas.drawRect(room, Paint()..color = color.withOpacity(0.06));
    canvas.drawRect(
      room,
      Paint()
        ..color = color.withOpacity(0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

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
