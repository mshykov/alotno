import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/conversion.dart' show humanSize;
import 'package:alotno/design/tokens.dart';
import 'package:alotno/theme.dart';

/// All output formats the UI offers, in display order.
const kAllFormats = ['svg', 'pdf', 'eps', 'dxf', 'webp'];

/// Small uppercase section heading ("OUTPUT FORMATS", "OPTIONS", …).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppPalette.of(context).muted,
          letterSpacing: 0.5,
        ),
      );
}

/// Drag-and-drop target + click-to-pick area.
class Dropzone extends StatelessWidget {
  const Dropzone({
    super.key,
    required this.dragging,
    required this.busy,
    required this.onTap,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDropPaths,
  });

  final bool dragging;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final void Function(Iterable<String> paths) onDropPaths;

  @override
  Widget build(BuildContext context) {
    final pal = AppPalette.of(context);
    return DropTarget(
      onDragEntered: (_) => onDragEntered(),
      onDragExited: (_) => onDragExited(),
      onDragDone: (d) => onDropPaths(d.files.map((f) => f.path)),
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 160,
          decoration: BoxDecoration(
            color: dragging ? pal.accent.withValues(alpha: 0.10) : pal.sunken,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dragging ? pal.accent : pal.outline, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MacosIcon(CupertinoIcons.cloud_upload, size: 34, color: dragging ? pal.accent : pal.muted),
                const SizedBox(height: 8),
                Text('Drop PNGs here, or click to choose', style: TextStyle(color: pal.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One queued image: thumbnail, name, dimensions/size, remove button.
class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.name,
    required this.width,
    required this.height,
    required this.bytes,
    required this.busy,
    required this.onRemove,
  });

  final String name;
  final int width;
  final int height;
  final Uint8List bytes;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.of(context).muted;
    final body = MacosTheme.of(context).typography.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // cacheWidth caps the decoded thumbnail to ~2x its display size, so a
            // queue of large PNGs doesn't decode each one at full resolution.
            child: Image.memory(bytes, width: 36, height: 36, fit: BoxFit.cover, cacheWidth: 72, cacheHeight: 72),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: body)),
          const SizedBox(width: 8),
          Text(
            '$width×$height · ${humanSize(bytes.length)}',
            // 'Menlo' is a system mono: Tokens.fontFamilyMono is a CSS font stack
            // (for the web), not a single family Flutter can use.
            style: TextStyle(fontFamily: 'Menlo', fontSize: Tokens.fontSizeXs, color: muted),
          ),
          const SizedBox(width: 4),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.clear, size: 14),
            onPressed: busy ? null : onRemove,
          ),
        ],
      ),
    );
  }
}

/// Toggle buttons for the output formats (SVG/PDF/EPS/DXF/WebP).
class FormatChips extends StatelessWidget {
  const FormatChips({super.key, required this.selected, required this.busy, required this.onToggle});

  final Set<String> selected;
  final bool busy;
  final void Function(String fmt) onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = AppPalette.of(context).accent;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAllFormats.map((f) {
        final on = selected.contains(f);
        return PushButton(
          controlSize: ControlSize.regular,
          secondary: !on,
          color: on ? accent : null,
          onPressed: busy ? null : () => onToggle(f),
          child: Text(f.toUpperCase()),
        );
      }).toList(),
    );
  }
}

/// Detail / color-mode pickers + the contextual "Lossless WebP" checkbox.
class OptionsPanel extends StatelessWidget {
  const OptionsPanel({
    super.key,
    required this.preset,
    required this.colorMode,
    required this.showLossless,
    required this.lossless,
    required this.busy,
    required this.onPreset,
    required this.onColorMode,
    required this.onLossless,
  });

  final String preset;
  final String colorMode;
  final bool showLossless;
  final bool lossless;
  final bool busy;
  final ValueChanged<String> onPreset;
  final ValueChanged<String> onColorMode;
  final ValueChanged<bool> onLossless;

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.of(context).muted;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Detail  ', style: TextStyle(color: muted)),
            MacosPopupButton<String>(
              value: preset,
              onChanged: busy ? null : (v) => onPreset(v!),
              items: const [
                MacosPopupMenuItem(value: 'low', child: Text('Coarse')),
                MacosPopupMenuItem(value: 'medium', child: Text('Medium')),
                MacosPopupMenuItem(value: 'high', child: Text('Fine')),
                MacosPopupMenuItem(value: 'ultra', child: Text('Super fine')),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Color  ', style: TextStyle(color: muted)),
            MacosPopupButton<String>(
              value: colorMode,
              onChanged: busy ? null : (v) => onColorMode(v!),
              items: const [
                MacosPopupMenuItem(value: 'mono', child: Text('Mono')),
                MacosPopupMenuItem(value: 'posterized', child: Text('Color')),
              ],
            ),
          ],
        ),
        if (showLossless)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosCheckbox(value: lossless, onChanged: busy ? null : onLossless),
              const SizedBox(width: 6),
              Text('Lossless WebP', style: TextStyle(color: muted)),
            ],
          ),
      ],
    );
  }
}

/// Output-folder display + "Choose…" button.
class OutputRow extends StatelessWidget {
  const OutputRow({super.key, required this.outDir, required this.busy, required this.onChoose});

  final String? outDir;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.of(context).muted;
    final body = MacosTheme.of(context).typography.body;
    return Row(
      children: [
        Expanded(
          child: Text(
            outDir ?? 'No folder chosen',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Menlo', fontSize: 12, color: outDir == null ? muted : body.color),
          ),
        ),
        const SizedBox(width: 8),
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: busy ? null : onChoose,
          child: const Text('Choose…'),
        ),
      ],
    );
  }
}

/// Convert button (+ progress), Reveal-in-Finder, and the status line.
class ActionsBar extends StatelessWidget {
  const ActionsBar({
    super.key,
    required this.canConvert,
    required this.busy,
    required this.queueCount,
    required this.showReveal,
    required this.status,
    required this.onConvert,
    required this.onReveal,
  });

  final bool canConvert;
  final bool busy;
  final int queueCount;
  final bool showReveal;
  final String status;
  final VoidCallback onConvert;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final accent = AppPalette.of(context).accent;
    final muted = AppPalette.of(context).muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PushButton(
                controlSize: ControlSize.large,
                color: accent,
                onPressed: canConvert ? onConvert : null,
                child: busy
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ProgressCircle(radius: 8),
                          SizedBox(width: 8),
                          Text('Converting…'),
                        ],
                      )
                    : Text(queueCount <= 1 ? 'Convert' : 'Convert $queueCount files'),
              ),
            ),
            if (showReveal) ...[
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: busy ? null : onReveal,
                child: const Text('Reveal in Finder'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(status, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13)),
      ],
    );
  }
}
