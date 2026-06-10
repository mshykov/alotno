import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:alotno/conversion.dart';

/// The mobile converter: pick a PNG → choose formats/options → convert → share.
///
/// Phones have no chosen output folder (iOS sandbox) and no "reveal in Finder",
/// so output goes to a temp dir and is handed to the native share sheet. All
/// conversion runs in the shared Rust core via `conversion.dart`.
class MobileConverterPage extends StatefulWidget {
  const MobileConverterPage({super.key});

  @override
  State<MobileConverterPage> createState() => _MobileConverterPageState();
}

class _MobileConverterPageState extends State<MobileConverterPage> {
  String? _pngPath;
  String? _pngName;
  Uint8List? _preview;
  final Set<String> _formats = {'svg'};
  String _preset = 'high';
  String _colorMode = 'mono';
  bool _lossless = false;
  bool _busy = false;
  String _status = 'Pick a PNG to convert.';

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    final path = res?.files.first.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    setState(() {
      _pngPath = path;
      _pngName = p.basename(path);
      _preview = bytes;
      _status = 'Ready — choose formats and convert.';
    });
  }

  Future<void> _convert() async {
    final path = _pngPath;
    if (path == null || _formats.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Converting…';
    });
    try {
      final dir = await getTemporaryDirectory();
      final files = await convertToFiles(
        pngPath: path,
        formats: _formats,
        outDir: dir.path,
        options: traceOptions(preset: _preset, colorMode: _colorMode),
        lossless: _lossless,
      );
      setState(() => _status = 'Done — sharing ${files.length} file(s)…');
      await Share.shareXFiles(
        files.map((f) => XFile(f.path)).toList(),
        subject: _pngName,
      );
      if (mounted) setState(() => _status = 'Shared. Pick another PNG to convert.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canConvert = _pngPath != null && _formats.isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('Alotno'), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Pick / preview ----
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _busy ? null : _pick,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_preview != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_preview!, width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 112),
                        )
                      else
                        Icon(Icons.add_photo_alternate_outlined, size: 40, color: cs.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _pngName ?? 'Choose a PNG…',
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
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
                      Switch(value: _lossless, onChanged: _busy ? null : (v) => setState(() => _lossless = v)),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              label: Text(_busy ? 'Converting…' : 'Convert & Share'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
