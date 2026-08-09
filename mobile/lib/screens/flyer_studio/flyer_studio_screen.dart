// FlyerStudioScreen — Flyer Studio v2's main editor.
//
// Design principles this screen follows:
// - Freeform canvas, zero fixed templates: every element is independently
//   positioned/sized/rotated/layered (see flyer_element.dart).
// - Client-side render: the final flyer image is produced on-device via
//   RepaintBoundary -> toImage() (wired in _exportAndShare), never on the
//   server. This is why there's no server-side design-rendering dependency
//   (sharp/libvips) for the final output.
// - AI is an accelerant, never a black box: "Generate with AI" proposes a
//   starting layout the counselor can still drag/resize/restyle by hand —
//   it never locks them into AI-only editing.
//
// NOT YET WIRED (deliberately flagged, not silently skipped):
// - The 4 ApiService calls below (createFlyerProject / getFlyerProject /
//   updateFlyerProjectCanvas / uploadFlyerElementImage / generateFlyerAI /
//   getTenantLogos) are written assuming ApiService's established static-
//   method + baseUrl + x-tenant-id-header convention (matching every other
//   module in this app). They need a final cross-check against the live
//   api_service.dart before this compiles — see the accompanying message.
// - Inline title-rename (tap-to-edit) — deferred, title is set at creation.
// - Multi-select / group-move — deferred, single-element selection only.
// - Snap-to-grid / alignment guides — deferred to a fast-follow polish pass.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import 'flyer_element.dart';
import 'flyer_canvas_element_widget.dart';
import '../services/api_service.dart';
import '../widgets/color_picker_dialog.dart';

class FlyerStudioScreen extends StatefulWidget {
  final String? projectId;
  final String? leadId;

  const FlyerStudioScreen({super.key, this.projectId, this.leadId});

  @override
  State<FlyerStudioScreen> createState() => _FlyerStudioScreenState();
}

class _FlyerStudioScreenState extends State<FlyerStudioScreen> {
  final GlobalKey _canvasRepaintKey = GlobalKey();
  final ImagePicker _imagePicker = ImagePicker();

  String? _projectId;
  String _title = 'Untitled Flyer';
  double _canvasWidth = 1080;
  double _canvasHeight = 1350;
  String _backgroundColor = '#FFFFFF';
  List<FlyerElement> _elements = [];

  String? _selectedId;
  bool _loading = true;
  bool _saving = false;
  bool _generatingAI = false;
  String? _error;

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _maxHistory = 30;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.projectId != null) {
      await _loadProject(widget.projectId!);
    } else {
      await _createBlankProject();
    }
  }

  Future<void> _loadProject(String id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getFlyerProject(id);
      _applyProjectData(data);
    } catch (e) {
      setState(() => _error = 'Could not load flyer: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createBlankProject() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.createFlyerProject(
        title: 'Untitled Flyer',
        leadId: widget.leadId,
      );
      _applyProjectData(data);
    } catch (e) {
      setState(() => _error = 'Could not create flyer: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyProjectData(Map<String, dynamic> data) {
    _projectId = data['id']?.toString();
    _title = data['title']?.toString() ?? 'Untitled Flyer';
    _canvasWidth = (data['canvas_width'] as num?)?.toDouble() ?? 1080;
    _canvasHeight = (data['canvas_height'] as num?)?.toDouble() ?? 1350;
    _backgroundColor = data['background_color']?.toString() ?? '#FFFFFF';
    final rawElements = (data['canvas_json'] as List?) ?? [];
    _elements = rawElements
        .whereType<Map>()
        .map((e) => FlyerElement.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Undo / redo — snapshot-based (simple, robust, matches this project's
  // "explainable over clever" philosophy used elsewhere, e.g. engagementTrend).
  // ---------------------------------------------------------------------

  String _snapshot() => jsonEncode(_elements.map((e) => e.toJson()).toList());

  void _pushUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restoreFromEncodedSnapshot(String snapshot) {
    try {
      final rawList = jsonDecode(snapshot) as List;
      setState(() {
        _elements = rawList
            .whereType<Map>()
            .map((e) => FlyerElement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _selectedId = null;
      });
    } catch (_) {
      // Corrupt snapshot (shouldn't happen — we only ever write via
      // jsonEncode above) — fail safe by leaving the canvas untouched
      // rather than crashing the editor.
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    final prev = _undoStack.removeLast();
    _restoreFromEncodedSnapshot(prev);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    final next = _redoStack.removeLast();
    _restoreFromEncodedSnapshot(next);
  }

  // ---------------------------------------------------------------------
  // Element mutations
  // ---------------------------------------------------------------------

  void _selectElement(String? id) => setState(() => _selectedId = id);

  void _onElementChanged(FlyerElement el) {
    setState(() {}); // element is mutated in-place by the wrapper widget
  }

  void _addTextElement() {
    _pushUndo();
    final el = FlyerElement(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: FlyerElementType.text,
      x: _canvasWidth / 2 - 120,
      y: _canvasHeight / 2 - 30,
      width: 240,
      height: 60,
      text: 'Double-tap to edit',
      fontSize: 28,
      zIndex: _nextZIndex(),
    );
    setState(() {
      _elements.add(el);
      _selectedId = el.id;
    });
  }

  int _nextZIndex() =>
      _elements.isEmpty ? 0 : (_elements.map((e) => e.zIndex).reduce(math.max) + 1);

  Future<void> _addImageElement({bool asLogoPicker = false}) async {
    if (asLogoPicker) {
      await _showLogoPicker();
      return;
    }
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || _projectId == null) return;

    setState(() => _saving = true);
    try {
      final result = await ApiService.uploadFlyerElementImage(_projectId!, picked.path);
      final url = result['image_url']?.toString();
      _pushUndo();
      final el = FlyerElement(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: FlyerElementType.image,
        x: _canvasWidth / 2 - 150,
        y: _canvasHeight / 2 - 150,
        width: 300,
        height: 300,
        url: url,
        zIndex: _nextZIndex(),
      );
      setState(() {
        _elements.add(el);
        _selectedId = el.id;
      });
    } catch (e) {
      _showSnack('Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showLogoPicker() async {
    List<dynamic> logos = [];
    try {
      logos = await ApiService.getTenantLogos();
    } catch (e) {
      _showSnack('Could not load logos: $e');
      return;
    }
    if (!mounted) return;
    if (logos.isEmpty) {
      _showSnack('No saved logos yet — add one from Settings first.');
      return;
    }
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: logos.map((l) {
            final logo = Map<String, dynamic>.from(l);
            return ListTile(
              leading: const Icon(Icons.workspace_premium),
              title: Text(logo['label']?.toString() ?? 'Logo'),
              onTap: () {
                Navigator.pop(ctx);
                _pushUndo();
                final el = FlyerElement(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  type: FlyerElementType.logo,
                  x: 40,
                  y: 40,
                  width: 160,
                  height: 160,
                  fit: 'contain',
                  url: logo['image_url']?.toString(),
                  zIndex: _nextZIndex(),
                );
                setState(() {
                  _elements.add(el);
                  _selectedId = el.id;
                });
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    _pushUndo();
    setState(() {
      _elements.removeWhere((e) => e.id == _selectedId);
      _selectedId = null;
    });
  }

  void _reorderLayer(String id, int direction) {
    _pushUndo();
    setState(() {
      final idx = _elements.indexWhere((e) => e.id == id);
      if (idx < 0) return;
      final swapWith = idx + direction;
      if (swapWith < 0 || swapWith >= _elements.length) return;
      final a = _elements[idx].zIndex;
      _elements[idx].zIndex = _elements[swapWith].zIndex;
      _elements[swapWith].zIndex = a;
      _elements.sort((x, y) => x.zIndex.compareTo(y.zIndex));
    });
  }

  // ---------------------------------------------------------------------
  // Save / AI generate / export
  // ---------------------------------------------------------------------

  Future<void> _save() async {
    if (_projectId == null) return;
    setState(() => _saving = true);
    try {
      await ApiService.updateFlyerProjectCanvas(
        _projectId!,
        _elements.map((e) => e.toJson()).toList(),
      );
      _showSnack('Saved');
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateWithAI() async {
    if (_projectId == null) return;
    final promptController = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate with AI'),
        content: TextField(
          controller: promptController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. "MBBS admission open, navy and gold, urgent tone"',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, promptController.text.trim()),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (prompt == null || prompt.isEmpty) return;

    if (_elements.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace current design?'),
          content: const Text(
            'AI will generate a new layout. Your current elements will be replaced — this can be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _generatingAI = true);
    try {
      final result = await ApiService.generateFlyerAI(_projectId!, prompt);
      final rawList = (result['canvas_json'] as List?) ?? [];
      _pushUndo();
      setState(() {
        _elements = rawList
            .whereType<Map>()
            .map((e) => FlyerElement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _selectedId = null;
      });
      _showSnack('AI layout applied — tap Save to keep it');
    } catch (e) {
      _showSnack('AI generation failed: $e');
    } finally {
      if (mounted) setState(() => _generatingAI = false);
    }
  }

  Future<void> _exportAndShare() async {
    try {
      final boundary =
          _canvasRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || _projectId == null) return;
      final bytes = byteData.buffer.asUint8List();
      await ApiService.uploadFlyerRender(_projectId!, bytes);
      _showSnack('Flyer rendered — ready to share from Layers menu');
    } catch (e) {
      _showSnack('Export failed: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedId == null ? null : _elements.firstWhere((e) => e.id == _selectedId, orElse: () => _elements.first);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoStack.isEmpty ? null : _undo,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _redoStack.isEmpty ? null : _redo,
            tooltip: 'Redo',
          ),
          IconButton(
            icon: _generatingAI
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            onPressed: _generatingAI ? null : _generateWithAI,
            tooltip: 'Generate with AI',
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _showLayersSheet,
            tooltip: 'Layers',
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
            tooltip: 'Save',
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: _exportAndShare,
            tooltip: 'Export & Share',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : Column(
                  children: [
                    Expanded(child: _buildCanvasArea()),
                    if (selected != null) _buildStylePanel(selected),
                    _buildToolbar(),
                  ],
                ),
    );
  }

  Widget _buildCanvasArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = math.min(constraints.maxWidth - 16, 420.0);
        final scale = maxW / _canvasWidth;
        final displayH = _canvasHeight * scale;

        return Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: RepaintBoundary(
                key: _canvasRepaintKey,
                child: GestureDetector(
                  onTap: () => _selectElement(null),
                  child: Container(
                    width: maxW,
                    height: displayH,
                    decoration: BoxDecoration(
                      color: flyerHexToColor(_backgroundColor),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: (_elements..sort((a, b) => a.zIndex.compareTo(b.zIndex)))
                          .map((el) => FlyerCanvasElementWidget(
                                key: ValueKey(el.id),
                                element: el,
                                scale: scale,
                                selected: el.id == _selectedId,
                                onTap: () => _selectElement(el.id),
                                onChanged: _onElementChanged,
                                onDragStart: _pushUndo,
                                onDragEnd: () {},
                                onDelete: () {
                                  setState(() {
                                    _elements.removeWhere((e) => e.id == el.id);
                                    _selectedId = null;
                                  });
                                },
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _toolbarButton(Icons.text_fields, 'Text', _addTextElement),
          _toolbarButton(Icons.add_photo_alternate, 'Image', () => _addImageElement()),
          _toolbarButton(
              Icons.workspace_premium, 'Logo', () => _addImageElement(asLogoPicker: true)),
          _toolbarButton(
            Icons.delete_outline,
            'Delete',
            _selectedId == null ? null : _deleteSelected,
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap == null ? Colors.grey.shade400 : null),
            Text(label,
                style: TextStyle(fontSize: 11, color: onTap == null ? Colors.grey.shade400 : null)),
          ],
        ),
      ),
    );
  }

  Widget _buildStylePanel(FlyerElement el) {
    if (el.type == FlyerElementType.text) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: kFlyerFontFamilies.contains(el.fontFamily)
                        ? el.fontFamily
                        : kFlyerFontFamilies.first,
                    isExpanded: true,
                    items: kFlyerFontFamilies
                        .map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f))))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => el.fontFamily = v);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(el.fontWeight == 'bold' ? Icons.format_bold : Icons.format_bold_outlined),
                  onPressed: () => setState(
                      () => el.fontWeight = el.fontWeight == 'bold' ? 'normal' : 'bold'),
                ),
                IconButton(
                  icon: Container(width: 20, height: 20, color: flyerHexToColor(el.color)),
                  onPressed: () async {
                    final picked = await showDialog<Color>(
                      context: context,
                      builder: (_) => ColorPickerDialog(initialColor: flyerHexToColor(el.color)),
                    );
                    if (picked != null) {
                      setState(() => el.color =
                          '#${picked.value.toRadixString(16).substring(2).toUpperCase()}');
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.format_size, size: 18),
                Expanded(
                  child: Slider(
                    value: el.fontSize.clamp(8, 120),
                    min: 8,
                    max: 120,
                    onChanged: (v) => setState(() => el.fontSize = v),
                  ),
                ),
                for (final a in ['left', 'center', 'right'])
                  IconButton(
                    icon: Icon(
                      a == 'left'
                          ? Icons.format_align_left
                          : a == 'center'
                              ? Icons.format_align_center
                              : Icons.format_align_right,
                      color: el.textAlign == a ? const Color(0xFF4C6FFF) : null,
                    ),
                    onPressed: () => setState(() => el.textAlign = a),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (el.type == FlyerElementType.image || el.type == FlyerElementType.logo) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          children: [
            const Icon(Icons.opacity, size: 18),
            Expanded(
              child: Slider(
                value: el.opacity.clamp(0.1, 1.0),
                min: 0.1,
                max: 1.0,
                onChanged: (v) => setState(() => el.opacity = v),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => el.fit = el.fit == 'cover' ? 'contain' : 'cover'),
              child: Text(el.fit == 'cover' ? 'Fill' : 'Fit'),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final sorted = [..._elements]..sort((a, b) => b.zIndex.compareTo(a.zIndex));
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.5,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Layers', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: sorted.length,
                        itemBuilder: (ctx, i) {
                          final el = sorted[i];
                          return ListTile(
                            leading: Icon(_iconFor(el.type)),
                            title: Text(_labelFor(el)),
                            selected: el.id == _selectedId,
                            onTap: () {
                              _selectElement(el.id);
                              Navigator.pop(ctx);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward, size: 18),
                                  onPressed: () {
                                    _reorderLayer(el.id, 1);
                                    setSheetState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_downward, size: 18),
                                  onPressed: () {
                                    _reorderLayer(el.id, -1);
                                    setSheetState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () {
                                    _pushUndo();
                                    setState(() => _elements.removeWhere((e) => e.id == el.id));
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _iconFor(FlyerElementType t) {
    switch (t) {
      case FlyerElementType.text:
        return Icons.text_fields;
      case FlyerElementType.image:
        return Icons.image;
      case FlyerElementType.logo:
        return Icons.workspace_premium;
      case FlyerElementType.shape:
        return Icons.square;
    }
  }

  String _labelFor(FlyerElement el) {
    if (el.type == FlyerElementType.text) {
      final t = el.text ?? '';
      return t.length > 24 ? '${t.substring(0, 24)}…' : (t.isEmpty ? 'Text' : t);
    }
    return flyerElementTypeToString(el.type);
  }
}
