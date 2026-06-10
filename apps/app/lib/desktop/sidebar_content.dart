import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/desktop/store.dart';
import 'package:alotno/theme.dart';

/// The left sidebar: brand, New conversion, PRESETS (click to apply, drop PNGs
/// to convert instantly), RECENT (click to reveal), Settings at the bottom.
/// Pure content widget — all behavior is injected by the converter screen.
class SidebarContent extends StatefulWidget {
  const SidebarContent({
    super.key,
    required this.store,
    required this.busy,
    required this.onNew,
    required this.onApplyPreset,
    required this.onDropOnPreset,
    required this.onSaveCurrentAsPreset,
    required this.onOpenRecent,
    required this.onOpenSettings,
  });

  final DesktopStore store;
  final bool busy;
  final VoidCallback onNew;
  final void Function(Preset preset) onApplyPreset;
  final void Function(Preset preset, List<String> paths) onDropOnPreset;
  final void Function(String name) onSaveCurrentAsPreset;
  final void Function(RecentEntry entry) onOpenRecent;
  final VoidCallback onOpenSettings;

  @override
  State<SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<SidebarContent> {
  String? _dragOverPreset;

  @override
  Widget build(BuildContext context) {
    final pal = AppPalette.of(context);
    final body = MacosTheme.of(context).typography.body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Brand ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Row(
            children: [
              Image.asset('assets/tray_icon.png', width: 20, height: 20, color: pal.accent),
              const SizedBox(width: 8),
              Text('Alotno',
                  style: body.copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),

        // ---- New conversion ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: widget.busy ? null : widget.onNew,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                MacosIcon(CupertinoIcons.add, size: 13),
                SizedBox(width: 6),
                Text('New conversion'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Scrollable middle: presets + recents ----
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _sectionHeader(
                'Presets',
                pal.muted,
                trailing: MacosIconButton(
                  icon: MacosIcon(CupertinoIcons.add_circled, size: 14, color: pal.muted),
                  padding: EdgeInsets.zero,
                  onPressed: widget.busy ? null : () => _askPresetName(context),
                ),
              ),
              ...widget.store.presets.map(_presetRow),
              const SizedBox(height: 14),
              if (widget.store.recents.isNotEmpty) ...[
                _sectionHeader('Recent', pal.muted),
                ...widget.store.recents.map(_recentRow),
              ],
            ],
          ),
        ),

        // ---- Settings ----
        Padding(
          padding: const EdgeInsets.all(8),
          child: _HoverRow(
            onTap: widget.onOpenSettings,
            child: Row(
              children: [
                MacosIcon(CupertinoIcons.gear, size: 15, color: pal.muted),
                const SizedBox(width: 8),
                Text('Settings', style: body.copyWith(color: pal.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text, Color muted, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: muted),
              ),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _presetRow(Preset preset) {
    final pal = AppPalette.of(context);
    final body = MacosTheme.of(context).typography.body;
    final highlighted = _dragOverPreset == preset.name;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragOverPreset = preset.name),
      onDragExited: (_) => setState(() => _dragOverPreset = null),
      onDragDone: (d) {
        setState(() => _dragOverPreset = null);
        final paths = d.files
            .map((f) => f.path)
            .where((p) => p.toLowerCase().endsWith('.png'))
            .toList();
        if (paths.isNotEmpty && !widget.busy) widget.onDropOnPreset(preset, paths);
      },
      child: _HoverRow(
        onTap: widget.busy ? null : () => widget.onApplyPreset(preset),
        highlight: highlighted ? pal.accent.withValues(alpha: 0.18) : null,
        child: Row(
          children: [
            MacosIcon(CupertinoIcons.square_stack_3d_up,
                size: 14, color: highlighted ? pal.accent : pal.accent.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(preset.name,
                  overflow: TextOverflow.ellipsis,
                  style: body.copyWith(fontSize: 12.5)),
            ),
            Text(preset.formats.map((f) => f.toUpperCase()).join(' '),
                style: TextStyle(fontSize: 9.5, color: pal.muted)),
          ],
        ),
      ),
    );
  }

  Widget _recentRow(RecentEntry entry) {
    final pal = AppPalette.of(context);
    final body = MacosTheme.of(context).typography.body;
    return _HoverRow(
      onTap: () => widget.onOpenRecent(entry),
      child: Row(
        children: [
          MacosIcon(CupertinoIcons.checkmark_circle, size: 14, color: pal.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.label,
                overflow: TextOverflow.ellipsis, style: body.copyWith(fontSize: 12.5)),
          ),
          Text(_relative(entry.when), style: TextStyle(fontSize: 9.5, color: pal.muted)),
        ],
      ),
    );
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Future<void> _askPresetName(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showMacosSheet<String>(
      context: context,
      builder: (ctx) => MacosSheet(
        insetPadding: const EdgeInsets.all(120),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Save current settings as a preset',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              MacosTextField(
                controller: controller,
                placeholder: 'Preset name',
                autofocus: true,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (name != null && name.isNotEmpty) widget.onSaveCurrentAsPreset(name);
  }
}

/// Sidebar row with hover affordance (macOS-style quiet list rows).
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.onTap, this.highlight});

  final Widget child;
  final VoidCallback? onTap;
  final Color? highlight;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pal = AppPalette.of(context);
    final bg = widget.highlight ??
        (_hover && widget.onTap != null ? pal.sunken : null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
