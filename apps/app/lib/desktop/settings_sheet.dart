import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/desktop/store.dart';
import 'package:alotno/theme.dart';

/// App-level settings (sidebar gear): default output folder + clear history.
/// Job parameters (formats/detail/color) intentionally live in the main pane.
Future<void> showSettingsSheet(BuildContext context, DesktopStore store,
    {required VoidCallback onChanged}) {
  return showMacosSheet(
    context: context,
    builder: (ctx) => _SettingsSheet(store: store, onChanged: onChanged),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.store, required this.onChanged});

  final DesktopStore store;
  final VoidCallback onChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final pal = AppPalette.of(context);
    final body = MacosTheme.of(context).typography.body;
    final store = widget.store;

    return MacosSheet(
      insetPadding: const EdgeInsets.all(100),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 18),

            // ---- Default output folder ----
            Text('DEFAULT OUTPUT FOLDER',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: pal.muted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.defaultOutDir ?? 'Not set — drops next to source / asks',
                    overflow: TextOverflow.ellipsis,
                    style: body.copyWith(
                        fontFamily: 'Menlo',
                        fontSize: 11.5,
                        color: store.defaultOutDir == null ? pal.muted : null),
                  ),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: () async {
                    final dir = await FilePicker.getDirectoryPath(
                        dialogTitle: 'Default output folder');
                    if (dir != null) {
                      store.defaultOutDir = dir;
                      await store.save();
                      widget.onChanged();
                      setState(() {});
                    }
                  },
                  child: const Text('Choose…'),
                ),
                if (store.defaultOutDir != null) ...[
                  const SizedBox(width: 6),
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () async {
                      store.defaultOutDir = null;
                      await store.save();
                      widget.onChanged();
                      setState(() {});
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // ---- History ----
            Text('HISTORY',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: pal.muted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('${store.recents.length} recent conversion(s) on disk',
                      style: body.copyWith(fontSize: 12, color: pal.muted)),
                ),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: store.recents.isEmpty
                      ? null
                      : () async {
                          await store.clearRecents();
                          widget.onChanged();
                          setState(() {});
                        },
                  child: const Text('Clear recents'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerRight,
              child: PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
