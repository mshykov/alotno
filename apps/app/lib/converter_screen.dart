import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'design/tokens.dart';
import 'src/rust/api/simple.dart';

/// The Alotno converter: pick a PNG, choose a format, convert via the Rust core,
/// save the result. Styled from the generated design tokens.
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  Uint8List? _png;
  String? _name;
  String _preset = 'high';
  String _colorMode = 'mono';
  bool _lossless = false;
  bool _busy = false;
  String _status = 'Pick a PNG to start.';

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

  Future<void> _pickPng() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    if (file.bytes == null) return;
    setState(() {
      _png = file.bytes;
      _name = file.name;
      _status = 'Loaded ${file.name} (${file.bytes!.length} bytes).';
    });
  }

  String _baseName() {
    final n = _name ?? 'alotno.png';
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }

  Future<String?> _chooseSavePath(String ext) => FilePicker.saveFile(
    dialogTitle: 'Save ${ext.toUpperCase()}',
    fileName: '${_baseName()}.$ext',
  );

  Future<void> _saveText(String ext, String text) async {
    final path = await _chooseSavePath(ext);
    if (path == null) return setState(() => _status = 'Save cancelled.');
    await File(path).writeAsString(text);
    setState(() => _status = 'Saved ${path.split('/').last}.');
  }

  Future<void> _saveBytes(String ext, List<int> bytes) async {
    final path = await _chooseSavePath(ext);
    if (path == null) return setState(() => _status = 'Save cancelled.');
    await File(path).writeAsBytes(bytes);
    setState(() => _status = 'Saved ${path.split('/').last}.');
  }

  Future<void> _convert(String fmt) async {
    final png = _png;
    if (png == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Converting to ${fmt.toUpperCase()}…';
    });
    try {
      switch (fmt) {
        case 'svg':
          await _saveText('svg', await tracePngToSvg(pngBytes: png, options: _opts()));
        case 'eps':
          await _saveText('eps', await convertPngToEps(pngBytes: png, options: _opts()));
        case 'dxf':
          await _saveText('dxf', await convertPngToDxf(pngBytes: png, options: _opts()));
        case 'pdf':
          await _saveBytes('pdf', await convertPngToPdf(pngBytes: png, options: _opts()));
        case 'webp':
          await _saveBytes(
            'webp',
            await convertPngToWebp(pngBytes: png, quality: 82, lossless: _lossless),
          );
      }
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorSurfaceBase,
      appBar: AppBar(
        backgroundColor: Tokens.colorSurfaceElevated,
        title: const Text('Alotno', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.all(Tokens.space6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dropzone(),
                SizedBox(height: Tokens.space5),
                _options(),
                SizedBox(height: Tokens.space5),
                _formatButtons(),
                SizedBox(height: Tokens.space4),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Tokens.colorInkSubtle, fontSize: Tokens.fontSizeSm),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropzone() {
    return InkWell(
      onTap: _busy ? null : _pickPng,
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Tokens.colorSurfaceSunken,
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          border: Border.all(color: Tokens.colorOutlineStrong, width: 2),
        ),
        child: Center(
          child: _png == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file, size: 32, color: Tokens.colorInkSubtle),
                    SizedBox(height: Tokens.space2),
                    Text(
                      'Drop a PNG, or click to choose',
                      style: TextStyle(color: Tokens.colorInkMuted),
                    ),
                  ],
                )
              : Padding(
                  padding: EdgeInsets.all(Tokens.space3),
                  child: Image.memory(_png!, fit: BoxFit.contain),
                ),
        ),
      ),
    );
  }

  Widget _options() {
    return Wrap(
      spacing: Tokens.space4,
      runSpacing: Tokens.space3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Detail', style: TextStyle(color: Tokens.colorInkMuted)),
            SizedBox(width: Tokens.space2),
            DropdownButton<String>(
              value: _preset,
              onChanged: _busy ? null : (v) => setState(() => _preset = v!),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Coarse')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('Fine')),
                DropdownMenuItem(value: 'ultra', child: Text('Super fine')),
              ],
            ),
          ],
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'mono', label: Text('Mono')),
            ButtonSegment(value: 'posterized', label: Text('Color')),
          ],
          selected: {_colorMode},
          onSelectionChanged: _busy ? null : (s) => setState(() => _colorMode = s.first),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: _lossless,
              onChanged: _busy ? null : (v) => setState(() => _lossless = v ?? false),
            ),
            Text('Lossless WebP', style: TextStyle(color: Tokens.colorInkMuted)),
          ],
        ),
      ],
    );
  }

  Widget _formatButtons() {
    final enabled = _png != null && !_busy;
    Widget btn(String fmt) => FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.colorBrand500,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusSm)),
      ),
      onPressed: enabled ? () => _convert(fmt) : null,
      child: Text(fmt.toUpperCase()),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Tokens.space3,
      runSpacing: Tokens.space3,
      children: [btn('svg'), btn('pdf'), btn('eps'), btn('dxf'), btn('webp')],
    );
  }
}
