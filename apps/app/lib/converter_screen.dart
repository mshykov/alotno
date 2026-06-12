import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:alotno/conversion.dart';
import 'package:alotno/desktop/settings_sheet.dart';
import 'package:alotno/desktop/sidebar_content.dart';
import 'package:alotno/desktop/store.dart';
import 'package:alotno/src/rust/api/simple.dart';
import 'package:alotno/widgets/converter_parts.dart';

class _Item {
  _Item(this.path, this.name, this.bytes, this.w, this.h);
  final String path;
  final String name;
  final Uint8List bytes;
  final int w;
  final int h;
  int get size => bytes.length;
}

/// The main converter window. Holds the queue + selections and wires the
/// extracted widgets (`widgets/converter_parts.dart`) to the conversion service
/// (`conversion.dart`).
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final List<_Item> _queue = [];
  Set<String> _formats = {'svg'};
  String _preset = 'high';
  String _colorMode = 'mono';
  bool _lossless = false;
  String? _outDir;
  bool _dragging = false;
  bool _busy = false;
  String _status = 'Drop PNGs to begin.';
  DesktopStore? _store;

  @override
  void initState() {
    super.initState();
    // Sidebar state (presets/recents/settings) loads async; UI works without it.
    DesktopStore.open().then((s) {
      if (!mounted) return;
      setState(() {
        _store = s;
        _outDir ??= s.defaultOutDir;
      });
    });
  }

  // ---- sidebar / option actions ----

  /// Quiet "Reset" next to the OPTIONS header: restores job parameters to the
  /// app defaults (queue is untouched — clearing it is the toolbar's job).
  void _resetOptions() => setState(() {
        _formats = {'svg'};
        _preset = 'high';
        _colorMode = 'mono';
        _lossless = false;
        _status = 'Options reset to defaults.';
      });

  void _applyPreset(Preset p) => setState(() {
        _formats = {...p.formats};
        _preset = p.detail;
        _colorMode = p.colorMode;
        _lossless = p.lossless;
        _status = 'Preset "${p.name}" applied.';
      });

  /// Drag PNGs onto a sidebar preset → convert immediately with that preset.
  /// Output goes to the default folder (Settings) or next to each source.
  Future<void> _quickConvertWithPreset(Preset preset, List<String> paths) async {
    if (_busy) return;
    _applyPreset(preset);
    setState(() {
      _busy = true;
      _status = 'Converting ${paths.length} file(s) with "${preset.name}"…';
    });
    try {
      final outputs = <File>[];
      String? lastDir;
      for (final path in paths) {
        final dir = _store?.defaultOutDir ?? p.dirname(path);
        lastDir = dir;
        outputs.addAll(await convertToFiles(
          pngPath: path,
          formats: preset.formats,
          outDir: dir,
          options: traceOptions(preset: preset.detail, colorMode: preset.colorMode),
          lossless: preset.lossless,
        ));
      }
      await _recordRecent(
        label: paths.length == 1
            ? p.basename(paths.first)
            : '${p.basename(paths.first)} +${paths.length - 1}',
        outDir: lastDir!,
        outputCount: outputs.length,
        formats: preset.formats.toList(),
      );
      setState(() => _status =
          'Done — ${outputs.length} file(s) via "${preset.name}".');
      await launchUrl(Uri.directory(lastDir));
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCurrentAsPreset(String name) async {
    final store = _store;
    if (store == null) return;
    await store.addPreset(Preset(
      name: name,
      formats: {..._formats},
      detail: _preset,
      colorMode: _colorMode,
      lossless: _lossless,
    ));
    if (mounted) setState(() => _status = 'Preset "$name" saved.');
  }

  Future<void> _recordRecent({
    required String label,
    required String outDir,
    required int outputCount,
    required List<String> formats,
  }) async {
    final store = _store;
    if (store == null) return;
    await store.addRecent(RecentEntry(
      whenMillis: DateTime.now().millisecondsSinceEpoch,
      label: label,
      outDir: outDir,
      outputCount: outputCount,
      formats: formats,
    ));
    if (mounted) setState(() {});
  }

  // ---- data helpers ----

  Future<void> _addPaths(Iterable<String> paths) async {
    var added = 0;
    var failed = 0;
    for (final path in paths) {
      if (!path.toLowerCase().endsWith('.png')) continue;
      if (_queue.any((i) => i.path == path)) continue;
      try {
        final bytes = await File(path).readAsBytes();
        // Dimensions come from the core (no in-Dart PNG parsing); 0×0 if unreadable.
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

  Future<void> _convert() async {
    final dir = _outDir;
    if (_queue.isEmpty || _formats.isEmpty || dir == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Converting…';
    });
    final opts = traceOptions(preset: _preset, colorMode: _colorMode);
    var totalIn = 0, totalOut = 0, count = 0;
    String? lastOut;
    try {
      for (final item in _queue) {
        final base = item.name.replaceAll(RegExp(r'\.png$', caseSensitive: false), '');
        for (final fmt in _formats) {
          final file = await createUnique(dir, base, fmt); // atomic, no overwrite
          totalOut += await writeConverted(
            bytes: item.bytes,
            fmt: fmt,
            file: file,
            options: opts,
            lossless: _lossless,
          );
          lastOut = file.path;
          count++;
        }
        totalIn += item.size;
      }
      final savings = (count == 1)
          ? '${p.basename(lastOut!)} · ${humanSize(totalIn)} → ${humanSize(totalOut)}'
          : '$count file(s) · ${humanSize(totalOut)} total';
      await _recordRecent(
        label: _queue.length == 1
            ? _queue.first.name
            : '${_queue.first.name} +${_queue.length - 1}',
        outDir: dir,
        outputCount: count,
        formats: _formats.toList(),
      );
      setState(() => _status = 'Done — $savings');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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

  Sidebar _sidebar() => Sidebar(
        minWidth: 220,
        builder: (context, scrollController) {
          final store = _store;
          if (store == null) return const SizedBox.shrink();
          return SidebarContent(
            store: store,
            busy: _busy,
            onApplyPreset: _applyPreset,
            onDropOnPreset: _quickConvertWithPreset,
            onSaveCurrentAsPreset: _saveCurrentAsPreset,
            onOpenRecent: (e) => launchUrl(Uri.directory(e.outDir)),
            onOpenSettings: () => showSettingsSheet(
              context,
              store,
              onChanged: () {
                if (mounted) {
                  setState(() => _outDir = store.defaultOutDir ?? _outDir);
                }
              },
            ),
          );
        },
      );

  ToolBar _toolBar() => ToolBar(
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
      );

  Widget _dropzoneSection() => Dropzone(
        dragging: _dragging,
        busy: _busy,
        onTap: _pick,
        onDragEntered: () => setState(() => _dragging = true),
        onDragExited: () => setState(() => _dragging = false),
        onDropPaths: (paths) {
          setState(() => _dragging = false);
          _addPaths(paths);
        },
      );

  List<Widget> _queueSection() => [
        const SizedBox(height: 16),
        ..._queue.map((i) => QueueRow(
              name: i.name,
              width: i.w,
              height: i.h,
              bytes: i.bytes,
              busy: _busy,
              onRemove: () => setState(() => _queue.remove(i)),
            )),
      ];

  Widget _optionsHeader() => Row(
        children: [
          const SectionLabel('Options'),
          const Spacer(),
          // Quiet, contextual reset — secondary by design.
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.arrow_counterclockwise, size: 13),
            padding: EdgeInsets.zero,
            onPressed: _busy ? null : _resetOptions,
          ),
        ],
      );

  Widget _optionsSection() => OptionsPanel(
        preset: _preset,
        colorMode: _colorMode,
        showLossless: _formats.contains('webp'),
        lossless: _lossless,
        busy: _busy,
        onPreset: (v) => setState(() => _preset = v),
        onColorMode: (v) => setState(() => _colorMode = v),
        onLossless: (v) => setState(() => _lossless = v),
      );

  Widget _actionsSection() => ActionsBar(
        canConvert: _queue.isNotEmpty && _formats.isNotEmpty && _outDir != null && !_busy,
        busy: _busy,
        queueCount: _queue.length,
        showReveal: _outDir != null,
        status: _status,
        onConvert: _convert,
        onReveal: _reveal,
      );

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      sidebar: _sidebar(),
      child: MacosScaffold(
        toolBar: _toolBar(),
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
                      _dropzoneSection(),
                      if (_queue.isNotEmpty) ..._queueSection(),
                      const SizedBox(height: 24),
                      const SectionLabel('Output formats'),
                      const SizedBox(height: 8),
                      FormatChips(
                        selected: _formats,
                        busy: _busy,
                        onToggle: (f) => setState(
                            () => _formats.contains(f) ? _formats.remove(f) : _formats.add(f)),
                      ),
                      const SizedBox(height: 20),
                      _optionsHeader(),
                      const SizedBox(height: 8),
                      _optionsSection(),
                      const SizedBox(height: 20),
                      const SectionLabel('Save to'),
                      const SizedBox(height: 8),
                      OutputRow(outDir: _outDir, busy: _busy, onChoose: _pickOutDir),
                      const SizedBox(height: 24),
                      _actionsSection(),
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
}
