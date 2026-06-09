import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:alotno/design/tokens.dart';
import 'package:alotno/src/rust/api/simple.dart';

const _allFormats = ['svg', 'pdf', 'eps', 'dxf', 'webp'];

class _Item {
  _Item(this.path, this.name, this.bytes, this.w, this.h);
  final String path;
  final String name;
  final Uint8List bytes;
  final int w;
  final int h;
  int get size => bytes.length;
}

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final List<_Item> _queue = [];
  final Set<String> _formats = {'svg'};
  String _preset = 'high';
  String _colorMode = 'mono';
  bool _lossless = false;
  String? _outDir;
  bool _dragging = false;
  bool _busy = false;
  String _status = 'Drop PNGs to begin.';

  // ---- data helpers ----

  String _human(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<void> _addPaths(Iterable<String> paths) async {
    var added = 0;
    var failed = 0;
    for (final path in paths) {
      if (!path.toLowerCase().endsWith('.png')) continue;
      if (_queue.any((i) => i.path == path)) continue;
      try {
        final bytes = await File(path).readAsBytes();
        // Dimensions come from the core (no in-Dart PNG parsing); fall back to
        // 0×0 if the header can't be read.
        var w = 0, h = 0;
        try {
          final d = await imageDimensions(pngBytes: bytes);
          w = d.width;
          h = d.height;
        } catch (_) {}
        _queue.add(_Item(path, p.basename(path), bytes, w, h));
        added++;
      } catch (_) {
        failed++; // unreadable / permission denied — report rather than swallow
      }
    }
    if (mounted) {
      setState(() {
        if (added > 0) {
          _status = failed > 0 ? '$added added, $failed unreadable.' : '$added file(s) added.';
        } else {
          _status = failed > 0 ? 'Could not read $failed file(s).' : 'No new PNGs.';
        }
      });
    }
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      allowMultiple: true,
    );
    if (res != null) await _addPaths(res.files.map((f) => f.path).whereType<String>());
  }

  Future<void> _pickOutDir() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Choose output folder');
    if (dir != null) setState(() => _outDir = dir);
  }

  TraceOptions _opts() => TraceOptions(
    preset: _preset,
    colorMode: _colorMode,
    curveType: 'curves',
    stacking: 'cutouts',
    posterizeSteps: 4,
    threshold: 128,
    version: '1.1',
    drawStyle: 'fill',
    groupBy: 'none',
    strokeColor: '#000000',
    strokeWidth: 1.0,
    nonScalingStroke: false,
    fixedSize: false,
    adobeCompat: false,
    clipOverflow: false,
  );

  Future<void> _convert() async {
    final dir = _outDir;
    if (_queue.isEmpty || _formats.isEmpty || dir == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Converting…';
    });
    var totalIn = 0, totalOut = 0, count = 0;
    String? lastOut;
    try {
      for (final item in _queue) {
        final base = item.name.replaceAll(RegExp(r'\.png$', caseSensitive: false), '');
        for (final fmt in _formats) {
          // Atomically claim a unique output path (no overwrite, no TOCTOU).
          final file = await _createUnique(dir, base, fmt);
          int len;
          switch (fmt) {
            case 'svg':
              final s = await tracePngToSvg(pngBytes: item.bytes, options: _opts());
              await file.writeAsString(s);
              len = s.length;
            case 'eps':
              final s = await convertPngToEps(pngBytes: item.bytes, options: _opts());
              await file.writeAsString(s);
              len = s.length;
            case 'dxf':
              final s = await convertPngToDxf(pngBytes: item.bytes, options: _opts());
              await file.writeAsString(s);
              len = s.length;
            case 'pdf':
              final b = await convertPngToPdf(pngBytes: item.bytes, options: _opts());
              await file.writeAsBytes(b);
              len = b.length;
            default: // webp
              final b = await convertPngToWebp(
                pngBytes: item.bytes,
                quality: 82,
                lossless: _lossless,
                mono: _colorMode == 'mono',
              );
              await file.writeAsBytes(b);
              len = b.length;
          }
          totalOut += len;
          lastOut = file.path;
          count++;
        }
        totalIn += item.size;
      }
      final savings = (count == 1)
          ? '${p.basename(lastOut!)} · ${_human(totalIn)} → ${_human(totalOut)}'
          : '$count file(s) · ${_human(totalOut)} total';
      setState(() => _status = 'Done — $savings');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Never overwrite: atomically create `base.ext`, falling back to Finder-style
  /// " (n)" suffixes. Uses `create(exclusive: true)` (O_EXCL) so the name is
  /// claimed atomically — there's no check-then-write gap a concurrent writer
  /// (or a second app instance) could slip through. Async, so the filesystem
  /// work stays off the UI isolate.
  Future<File> _createUnique(String dir, String base, String ext) async {
    for (var n = 0; ; n++) {
      final name = n == 0 ? '$base.$ext' : '$base ($n).$ext';
      final file = File(p.join(dir, name));
      try {
        return await file.create(exclusive: true);
      } on FileSystemException {
        // If it now exists, it's a name collision → try the next suffix.
        // Otherwise (permission, missing dir, …) it's a real error → surface it.
        if (!await file.exists()) rethrow;
      }
    }
  }

  Future<void> _reveal() async {
    final dir = _outDir;
    if (dir == null) return;
    // url_launcher opens the folder via NSWorkspace — sandbox-legal for a
    // user-selected directory. (Spawning `open` is blocked by the App Sandbox.)
    try {
      final ok = await launchUrl(Uri.directory(dir));
      if (!ok && mounted) setState(() => _status = 'Could not open the output folder.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not open the folder: $e');
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final t = MacosTheme.of(context);
    final isDark = t.brightness == Brightness.dark;
    final accent = isDark ? TokensDark.colorBrand500 : Tokens.colorBrand500;
    final sunken = isDark ? TokensDark.colorSurfaceSunken : Tokens.colorSurfaceSunken;
    final outline = isDark ? TokensDark.colorOutlineStrong : Tokens.colorOutlineStrong;
    final muted = isDark ? TokensDark.colorInkMuted : Tokens.colorInkMuted;
    final body = t.typography.body;

    return MacosWindow(
      child: MacosScaffold(
        toolBar: ToolBar(
          title: const Text('Alotno'),
          titleWidth: 200,
          actions: [
            ToolBarIconButton(
              label: 'Clear queue',
              icon: const MacosIcon(CupertinoIcons.trash),
              showLabel: false,
              onPressed: _queue.isEmpty || _busy
                  ? null
                  : () => setState(() {
                      _queue.clear();
                      _status = 'Cleared.';
                    }),
            ),
          ],
        ),
        children: [
          ContentArea(
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dropzone(accent, sunken, outline, muted),
                      if (_queue.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ..._queue.map((i) => _row(i, muted, body)),
                      ],
                      const SizedBox(height: 24),
                      _label('Output formats', muted),
                      const SizedBox(height: 8),
                      _formatChips(accent),
                      const SizedBox(height: 20),
                      _label('Options', muted),
                      const SizedBox(height: 8),
                      _options(muted, body),
                      const SizedBox(height: 20),
                      _label('Save to', muted),
                      const SizedBox(height: 8),
                      _outputRow(muted, body),
                      const SizedBox(height: 24),
                      _actions(accent, muted, body),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String s, Color muted) => Text(
    s.toUpperCase(),
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.5),
  );

  Widget _dropzone(Color accent, Color sunken, Color outline, Color muted) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _addPaths(d.files.map((f) => f.path));
      },
      child: GestureDetector(
        onTap: _busy ? null : _pick,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 160,
          decoration: BoxDecoration(
            color: _dragging ? accent.withValues(alpha: 0.10) : sunken,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _dragging ? accent : outline, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MacosIcon(CupertinoIcons.cloud_upload, size: 34, color: _dragging ? accent : muted),
                const SizedBox(height: 8),
                Text('Drop PNGs here, or click to choose', style: TextStyle(color: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(_Item i, Color muted, TextStyle body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // cacheWidth caps the decoded thumbnail to ~2x its display size, so a
            // queue of large PNGs doesn't decode each one at full resolution.
            child: Image.memory(
              i.bytes,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              cacheWidth: 72,
              cacheHeight: 72,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(i.name, overflow: TextOverflow.ellipsis, style: body)),
          const SizedBox(width: 8),
          Text(
            '${i.w}×${i.h} · ${_human(i.size)}',
            // 'Menlo' is a system mono: Tokens.fontFamilyMono is a CSS font
            // stack (for the web), not a single family Flutter can use.
            style: TextStyle(fontFamily: 'Menlo', fontSize: Tokens.fontSizeXs, color: muted),
          ),
          const SizedBox(width: 4),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.clear, size: 14),
            onPressed: _busy ? null : () => setState(() => _queue.remove(i)),
          ),
        ],
      ),
    );
  }

  Widget _formatChips(Color accent) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allFormats.map((f) {
        final on = _formats.contains(f);
        return PushButton(
          controlSize: ControlSize.regular,
          secondary: !on,
          color: on ? accent : null,
          onPressed: _busy
              ? null
              : () => setState(() {
                  on ? _formats.remove(f) : _formats.add(f);
                }),
          child: Text(f.toUpperCase()),
        );
      }).toList(),
    );
  }

  Widget _options(Color muted, TextStyle body) {
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
              value: _preset,
              onChanged: _busy ? null : (v) => setState(() => _preset = v!),
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
              value: _colorMode,
              onChanged: _busy ? null : (v) => setState(() => _colorMode = v!),
              items: const [
                MacosPopupMenuItem(value: 'mono', child: Text('Mono')),
                MacosPopupMenuItem(value: 'posterized', child: Text('Color')),
              ],
            ),
          ],
        ),
        // Contextual: only meaningful when WebP is a chosen output.
        if (_formats.contains('webp'))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosCheckbox(
                value: _lossless,
                onChanged: _busy ? null : (v) => setState(() => _lossless = v),
              ),
              const SizedBox(width: 6),
              Text('Lossless WebP', style: TextStyle(color: muted)),
            ],
          ),
      ],
    );
  }

  Widget _outputRow(Color muted, TextStyle body) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _outDir ?? 'No folder chosen',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 12,
              color: _outDir == null ? muted : body.color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: _busy ? null : _pickOutDir,
          child: const Text('Choose…'),
        ),
      ],
    );
  }

  Widget _actions(Color accent, Color muted, TextStyle body) {
    final canConvert = _queue.isNotEmpty && _formats.isNotEmpty && _outDir != null && !_busy;
    final n = _queue.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PushButton(
                controlSize: ControlSize.large,
                color: accent,
                onPressed: canConvert ? _convert : null,
                child: _busy
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ProgressCircle(radius: 8),
                          SizedBox(width: 8),
                          Text('Converting…'),
                        ],
                      )
                    : Text(n <= 1 ? 'Convert' : 'Convert $n files'),
              ),
            ),
            if (_outDir != null) ...[
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: _busy ? null : _reveal,
                child: const Text('Reveal in Finder'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13),
        ),
      ],
    );
  }
}
