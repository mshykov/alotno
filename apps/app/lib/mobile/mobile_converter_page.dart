import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:alotno/conversion.dart';
import 'package:alotno/mobile/incoming_files.dart';

class _QueueItem {
  _QueueItem(this.path, this.name, this.preview);
  final String path;
  final String name;
  final Uint8List preview;
}

/// The mobile converter: queue PNGs (picked, or shared/opened into the app) →
/// choose formats/options → convert → native share sheet. WebP outputs can also
/// be saved straight to Photos.
///
/// Phones have no chosen output folder (iOS sandbox) and no "reveal in Finder",
/// so output goes to a temp dir and is handed to the share sheet. All conversion
/// runs in the shared Rust core via `conversion.dart`.
class MobileConverterPage extends StatefulWidget {
  const MobileConverterPage({super.key});

  @override
  State<MobileConverterPage> createState() => _MobileConverterPageState();
}

class _MobileConverterPageState extends State<MobileConverterPage> {
  final List<_QueueItem> _queue = [];
  final Set<String> _formats = {'svg'};
  String _preset = 'high';
  String _colorMode = 'mono';
  bool _lossless = false;
  bool _busy = false;
  String _status = 'Pick PNGs to convert.';
  List<String> _webpOutputs = const []; // last convert's .webp files (Photos-savable)

  @override
  void initState() {
    super.initState();
    // PNGs shared/opened into the app land in the queue.
    IncomingFiles.init(onFiles: _addPaths);
  }

  Future<void> _addPaths(List<String> paths) async {
    var added = 0;
    for (final path in paths) {
      if (_queue.any((i) => i.path == path)) continue;
      try {
        final bytes = await File(path).readAsBytes();
        _queue.add(_QueueItem(path, p.basename(path), bytes));
        added++;
      } catch (_) {
        // unreadable — skip
      }
    }
    if (added > 0 && mounted) {
      setState(() {
        _status = '${_queue.length} file(s) queued.';
        _webpOutputs = const [];
      });
    }
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      allowMultiple: true,
    );
    if (res == null) return;
    await _addPaths(res.files.map((f) => f.path).whereType<String>().toList());
  }

  Future<void> _convert() async {
    if (_queue.isEmpty || _formats.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Converting…';
      _webpOutputs = const [];
    });
    try {
      final dir = await getTemporaryDirectory();
      final outputs = <File>[];
      for (final (i, item) in _queue.indexed) {
        setState(() => _status = 'Converting… ${i + 1}/${_queue.length}');
        outputs.addAll(await convertToFiles(
          pngPath: item.path,
          formats: _formats,
          outDir: dir.path,
          options: traceOptions(preset: _preset, colorMode: _colorMode),
          lossless: _lossless,
        ));
      }
      final webps =
          outputs.where((f) => f.path.toLowerCase().endsWith('.webp')).map((f) => f.path).toList();
      setState(() {
        _status = 'Done — ${_queue.length} file(s) → ${outputs.length} output(s). Sharing…';
        _webpOutputs = webps;
      });
      await Share.shareXFiles(
        outputs.map((f) => XFile(f.path)).toList(),
        subject: _queue.length == 1 ? _queue.first.name : '${_queue.length} conversions',
      );
      if (mounted) {
        setState(() => _status = 'Shared ${outputs.length} file(s).');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveWebpToPhotos() async {
    var saved = 0;
    try {
      for (final path in _webpOutputs) {
        await Gal.putImage(path, album: 'Alotno');
        saved++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $saved WebP image(s) to Photos.')),
        );
      }
    } on GalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photos couldn’t save this: ${e.type.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canConvert = _queue.isNotEmpty && _formats.isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alotno'),
        centerTitle: false,
        actions: [
          if (_queue.isNotEmpty)
            IconButton(
              tooltip: 'Clear queue',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _queue.clear();
                        _webpOutputs = const [];
                        _status = 'Pick PNGs to convert.';
                      }),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Pick card ----
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _busy ? null : _pick,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 40, color: cs.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _queue.isEmpty ? 'Choose PNGs…' : 'Add more PNGs…',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),

            // ---- Queue ----
            if (_queue.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._queue.map(
                (item) => ListTile(
                  key: ValueKey(item.path),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(item.preview,
                        width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 88),
                  ),
                  title: Text(item.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(humanSize(item.preview.length)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed:
                        _busy ? null : () => setState(() => _queue.remove(item)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // ---- Formats ----
            Text('Output formats', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: allFormats.map((f) {
                return FilterChip(
                  label: Text(f.toUpperCase()),
                  selected: _formats.contains(f),
                  onSelected: _busy
                      ? null
                      : (sel) => setState(() => sel ? _formats.add(f) : _formats.remove(f)),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ---- Options ----
            Text('Options', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownMenu<String>(
                  initialSelection: _preset,
                  label: const Text('Detail'),
                  enabled: !_busy,
                  onSelected: (v) => setState(() => _preset = v ?? _preset),
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 'low', label: 'Coarse'),
                    DropdownMenuEntry(value: 'medium', label: 'Medium'),
                    DropdownMenuEntry(value: 'high', label: 'Fine'),
                    DropdownMenuEntry(value: 'ultra', label: 'Super fine'),
                  ],
                ),
                DropdownMenu<String>(
                  initialSelection: _colorMode,
                  label: const Text('Color'),
                  enabled: !_busy,
                  onSelected: (v) => setState(() => _colorMode = v ?? _colorMode),
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 'mono', label: 'Mono'),
                    DropdownMenuEntry(value: 'posterized', label: 'Color'),
                  ],
                ),
                if (_formats.contains('webp'))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Adaptive: Cupertino-style switch on iOS, Material elsewhere.
                      Switch.adaptive(
                          value: _lossless,
                          onChanged: _busy ? null : (v) => setState(() => _lossless = v)),
                      const Text('Lossless WebP'),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 28),

            // ---- Convert ----
            FilledButton.icon(
              onPressed: canConvert ? _convert : null,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              label: Text(_busy
                  ? 'Converting…'
                  : _queue.length > 1
                      ? 'Convert & Share ${_queue.length} files'
                      : 'Convert & Share'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            if (_webpOutputs.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _saveWebpToPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('Save ${_webpOutputs.length} WebP to Photos'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
