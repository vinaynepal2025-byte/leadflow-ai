// FlyerStudioScreen — Flyer Studio v2's editor.
//
// Design principles:
// - Freeform canvas, zero fixed templates: every element is independently
//   positioned/sized/rotated/layered/locked (see flyer_element.dart).
// - Client-side render: the final image is produced on-device via
//   RepaintBoundary -> toImage() -> PNG, so what the counselor sees is
//   exactly what gets sent, and there's no server rendering dependency.
// - AI is an accelerant, never a cage: "Generate with AI" proposes a
//   starting layout that stays fully hand-editable afterwards.
// - Autosave over manual save: a counselor building a flyer between calls
//   should never lose work to a backgrounded app. Manual save still exists
//   for reassurance, but isn't load-bearing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../theme/appearance_settings.dart';
import '../../theme/glass_settings.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../widgets/glass_widgets.dart';
import 'flyer_element.dart';
import 'flyer_canvas_element_widget.dart';

class FlyerStudioScreen extends StatefulWidget {
  final String? projectId;
  final String? leadId;

  const FlyerStudioScreen({super.key, this.projectId, this.leadId});

  @override
  State<FlyerStudioScreen> createState() => _FlyerStudioScreenState();
}

class _FlyerStudioScreenState extends State<FlyerStudioScreen> {
  final ApiService _api = ApiService();
  final GlobalKey _canvasRepaintKey = GlobalKey();
  final ImagePicker _imagePicker = ImagePicker();

  String? _projectId;
  String _title = 'Untitled Flyer';
  double _canvasWidth = 1080;
  double _canvasHeight = 1350;
  String _backgroundColor = '#FFFFFF';
  String? _backgroundImageUrl;
  List<FlyerElement> _elements = [];

  String? _selectedId;
  bool _loading = true;
  bool _saving = false;
  bool _generatingAI = false;
  bool _exporting = false;
  bool _dirty = false;
  String? _error;
  List<FlyerSnapGuide> _snapGuides = const [];
  bool _showGrid = false;
  final Set<String> _multiSelectedIds = {};

  // Canvas-level multi-select: a distinct mode from the normal single
  // selection above (which drives the per-element handle panel) -- while
  // active, taps toggle group membership and dragging any selected element
  // (or the group's own bounding box) moves the whole group together.
  bool _groupSelectMode = false;
  final Set<String> _groupSelectedIds = {};
  double? _groupRotateStartAngle;

  Timer? _autosaveTimer;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _maxHistory = 40;

  // Inline WYSIWYG text editing -- typing directly onto the canvas instead
  // of through a dialog. Only used for unrotated text (see _beginInlineEdit);
  // rotated text falls back to the dialog since a rotated TextField's
  // touch/caret geometry doesn't match its visual position.
  String? _editingTextId;
  TextEditingController? _inlineController;
  FocusNode? _inlineFocusNode;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _inlineController?.dispose();
    _inlineFocusNode?.dispose();
    super.dispose();
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
      final data = await _api.getFlyerProject(id);
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
      final data = await _api.createFlyerProject(
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
    _backgroundImageUrl = data['background_image_url']?.toString();
    final raw = (data['canvas_json'] as List?) ?? [];
    _elements = raw
        .whereType<Map>()
        .map((e) => FlyerElement.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _sortElements();
  }

  void _sortElements() => _elements.sort((a, b) => a.zIndex.compareTo(b.zIndex));

  FlyerElement? get _selected {
    if (_selectedId == null) return null;
    for (final e in _elements) {
      if (e.id == _selectedId) return e;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // History + autosave
  // ------------------------------------------------------------------

  String _snapshot() => jsonEncode(_elements.map((e) => e.toJson()).toList());

  void _pushUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restoreSnapshot(String snapshot) {
    try {
      final raw = jsonDecode(snapshot) as List;
      setState(() {
        _elements = raw
            .whereType<Map>()
            .map((e) => FlyerElement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _sortElements();
        _selectedId = null;
      });
      _markDirty();
    } catch (_) {
      // Snapshots are always written via jsonEncode, so this shouldn't
      // happen — but fail by leaving the canvas untouched rather than
      // crashing an editor with unsaved work in it.
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    _restoreSnapshot(_redoStack.removeLast());
  }

  /// Debounced autosave. Editing is a burst activity (drag, drag, drag,
  /// type) so saving on every frame would hammer the API; 2.5s after the
  /// last change is late enough to batch and early enough that a killed
  /// app rarely costs more than one edit.
  void _markDirty() {
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 2500), () {
      _save(silent: true);
    });
  }

  Future<void> _save({bool silent = false}) async {
    if (_projectId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _api.updateFlyerProjectCanvas(
        _projectId!,
        _elements.map((e) => e.toJson()).toList(),
      );
      _dirty = false;
      if (!silent) _showSnack('Saved');
    } catch (e) {
      if (!silent) _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmExit() async {
    _autosaveTimer?.cancel();
    if (!_dirty) return true;
    await _save(silent: true);
    return true;
  }

  // ------------------------------------------------------------------
  // Element operations
  // ------------------------------------------------------------------

  void _selectElement(String? id) {
    if (id != _selectedId && context.read<AppearanceSettings>().haptics) {
      HapticFeedback.selectionClick();
    }
    setState(() => _selectedId = id);
  }

  void _onElementChanged(FlyerElement el) {
    setState(() {});
    _markDirty();
  }

  void _toggleGroupSelectMode() {
    if (context.read<AppearanceSettings>().haptics) HapticFeedback.selectionClick();
    setState(() {
      _groupSelectMode = !_groupSelectMode;
      _groupSelectedIds.clear();
      if (_groupSelectMode) _selectedId = null;
    });
  }

  void _toggleGroupMember(String id) {
    if (context.read<AppearanceSettings>().haptics) HapticFeedback.selectionClick();
    setState(() {
      if (_groupSelectedIds.contains(id)) {
        _groupSelectedIds.remove(id);
      } else {
        _groupSelectedIds.add(id);
      }
    });
  }

  /// Union bounding box (canvas units) of every selected group member, or
  /// null when nothing is selected -- drives both the dashed group outline
  /// and the drag handle that moves everything together.
  Rect? _groupBoundsRect() {
    double? minX, minY, maxX, maxY;
    for (final el in _elements) {
      if (!_groupSelectedIds.contains(el.id)) continue;
      minX = minX == null ? el.x : math.min(minX, el.x);
      minY = minY == null ? el.y : math.min(minY, el.y);
      maxX = maxX == null ? el.x + el.width : math.max(maxX, el.x + el.width);
      maxY = maxY == null ? el.y + el.height : math.max(maxY, el.y + el.height);
    }
    if (minX == null) return null;
    return Rect.fromLTRB(minX, minY!, maxX!, maxY!);
  }

  void _groupDrag(Offset rawDelta) {
    final dx = rawDelta.dx;
    final dy = rawDelta.dy;
    setState(() {
      for (final el in _elements) {
        if (_groupSelectedIds.contains(el.id) && !el.locked) {
          el.x += dx;
          el.y += dy;
        }
      }
    });
    _markDirty();
  }

  /// Spins the whole group as one rigid body around its own bounding-box
  /// centre: every element's own rotation advances by the same delta, and
  /// each element's position revolves around the shared pivot so the
  /// cluster visually rotates together rather than each element spinning
  /// in place. The pivot is recomputed each tick from the elements'
  /// axis-aligned bounds (not their true rotated footprint), so a long
  /// continuous rotate can drift slightly -- an accepted simplification
  /// matching how the align feature already treats bounds.
  void _groupRotate(double deltaRad) {
    final bounds = _groupBoundsRect();
    if (bounds == null) return;
    final pivotX = bounds.left + bounds.width / 2;
    final pivotY = bounds.top + bounds.height / 2;
    final cosT = math.cos(deltaRad);
    final sinT = math.sin(deltaRad);
    final deltaDeg = deltaRad * 180 / math.pi;
    setState(() {
      for (final el in _elements) {
        if (!_groupSelectedIds.contains(el.id) || el.locked) continue;
        final cx = el.x + el.width / 2;
        final cy = el.y + el.height / 2;
        final vx = cx - pivotX;
        final vy = cy - pivotY;
        final nvx = vx * cosT - vy * sinT;
        final nvy = vx * sinT + vy * cosT;
        el.x = pivotX + nvx - el.width / 2;
        el.y = pivotY + nvy - el.height / 2;
        el.rotation += deltaDeg;
      }
    });
    _markDirty();
  }

  void _groupDuplicate() => _bulkDuplicateSelected(Set<String>.from(_groupSelectedIds));

  void _groupDelete() {
    _bulkDeleteSelected(Set<String>.from(_groupSelectedIds));
    setState(() => _groupSelectedIds.clear());
  }

  /// Aligns every selected element to one edge/centre of the group's own
  /// bounding box -- the Canva/Figma "align selection" toolset, not
  /// alignment against the page.
  void _groupAlign(String edge) {
    final bounds = _groupBoundsRect();
    if (bounds == null) return;
    _pushUndo();
    setState(() {
      for (final el in _elements) {
        if (!_groupSelectedIds.contains(el.id) || el.locked) continue;
        switch (edge) {
          case 'left':
            el.x = bounds.left;
            break;
          case 'centerH':
            el.x = bounds.left + bounds.width / 2 - el.width / 2;
            break;
          case 'right':
            el.x = bounds.right - el.width;
            break;
          case 'top':
            el.y = bounds.top;
            break;
          case 'centerV':
            el.y = bounds.top + bounds.height / 2 - el.height / 2;
            break;
          case 'bottom':
            el.y = bounds.bottom - el.height;
            break;
        }
      }
    });
    _markDirty();
  }

  int _nextZIndex() =>
      _elements.isEmpty ? 0 : (_elements.map((e) => e.zIndex).reduce(math.max) + 1);

  void _addElement(FlyerElement el) {
    _pushUndo();
    setState(() {
      _elements.add(el);
      _sortElements();
      _selectedId = el.id;
    });
    _markDirty();
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _addTextElement() {
    final el = FlyerElement(
      id: _newId(),
      type: FlyerElementType.text,
      x: _canvasWidth * 0.1,
      y: _canvasHeight / 2 - 40,
      width: _canvasWidth * 0.8,
      height: 90,
      text: 'Your text here',
      fontSize: _canvasWidth * 0.05,
      fontFamily: 'Montserrat',
      fontWeight: 'bold',
      textAlign: 'center',
      zIndex: _nextZIndex(),
    );
    _addElement(el);
    // Jump straight into editing -- Canva's "add text" behaviour is to put
    // the caret in immediately, not leave the placeholder sitting there
    // waiting for a second tap.
    _beginInlineEdit(el);
  }

  void _addShapeElement() {
    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.shape,
      x: _canvasWidth * 0.15,
      y: _canvasHeight * 0.4,
      width: _canvasWidth * 0.7,
      height: _canvasHeight * 0.12,
      shapeColor: '#1B2A4A',
      zIndex: _nextZIndex(),
    ));
  }

  void _duplicateSelected() {
    final el = _selected;
    if (el == null) return;
    final copy = el.clone();
    copy.id = _newId();
    copy.x += _canvasWidth * 0.03;
    copy.y += _canvasHeight * 0.02;
    copy.zIndex = _nextZIndex();
    copy.locked = false;
    _addElement(copy);
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    _pushUndo();
    setState(() {
      _elements.removeWhere((e) => e.id == _selectedId);
      _selectedId = null;
    });
    _markDirty();
  }

  void _nudge(double dx, double dy) {
    final el = _selected;
    if (el == null || el.locked) return;
    setState(() {
      el.x += dx;
      el.y += dy;
    });
    _markDirty();
  }

  void _reorderLayer(String id, int direction) {
    _pushUndo();
    setState(() {
      _sortElements();
      final idx = _elements.indexWhere((e) => e.id == id);
      if (idx < 0) return;
      final swapWith = idx + direction;
      if (swapWith < 0 || swapWith >= _elements.length) return;
      final tmp = _elements[idx].zIndex;
      _elements[idx].zIndex = _elements[swapWith].zIndex;
      _elements[swapWith].zIndex = tmp;
      _sortElements();
    });
    _markDirty();
  }

  Future<void> _editTextElement(FlyerElement el) async {
    if (el.type != FlyerElementType.text) return;
    final controller = TextEditingController(text: el.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Type your text',
            helperText: 'Enter for a new line',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (result == null) return;
    _pushUndo();
    setState(() => el.text = result);
    _markDirty();
  }

  /// True WYSIWYG editing: a real TextField sits exactly over the element
  /// on the canvas, matching its font/size/color/alignment, so typing shows
  /// up in place instead of in a separate dialog. Only safe for unrotated
  /// text -- a rotated TextField's caret/selection hit-testing doesn't
  /// track its visually rotated glyphs, so rotated text keeps the dialog.
  void _beginInlineEdit(FlyerElement el) {
    if (el.type != FlyerElementType.text) return;
    if (el.rotation != 0) {
      _editTextElement(el);
      return;
    }
    _pushUndo();
    _inlineController?.dispose();
    _inlineFocusNode?.dispose();
    _inlineController = TextEditingController(text: el.text ?? '');
    _inlineFocusNode = FocusNode();
    setState(() {
      _selectedId = el.id;
      _editingTextId = el.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineFocusNode?.requestFocus();
    });
  }

  void _endInlineEdit() {
    if (_editingTextId == null) return;
    setState(() => _editingTextId = null);
    _markDirty();
  }

  Future<void> _replaceElementImage(FlyerElement el) async {
    final picked =
        await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || _projectId == null) return;
    setState(() => _saving = true);
    try {
      final result = await _api.uploadFlyerElementImage(_projectId!, picked.path);
      _pushUndo();
      setState(() => el.url = result['image_url']?.toString());
      _markDirty();
    } catch (e) {
      _showSnack('Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addImageElement() async {
    final picked =
        await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || _projectId == null) return;
    setState(() => _saving = true);
    try {
      final result = await _api.uploadFlyerElementImage(_projectId!, picked.path);
      _addElement(FlyerElement(
        id: _newId(),
        type: FlyerElementType.image,
        x: _canvasWidth * 0.15,
        y: _canvasHeight * 0.25,
        width: _canvasWidth * 0.7,
        height: _canvasWidth * 0.7,
        url: result['image_url']?.toString(),
        zIndex: _nextZIndex(),
      ));
    } catch (e) {
      _showSnack('Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLogoElement() async {
    List<Map<String, dynamic>> logos = [];
    try {
      logos = await _api.getTenantLogos();
    } catch (e) {
      _showSnack('Could not load logos: $e');
      return;
    }
    if (!mounted) return;
    if (logos.isEmpty) {
      _showSnack('No saved logos yet — add one in Settings > Brand Logos');
      return;
    }
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.read<AppearanceSettings>().cornerRadius.clamp(0, 24))),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            _sheetDragHandle(),
            ...logos.map((l) {
            final logo = Map<String, dynamic>.from(l);
            return ListTile(
              leading: logo['image_url'] != null
                  ? Image.network(logo['image_url'].toString(),
                      width: 40, height: 40, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.workspace_premium))
                  : const Icon(Icons.workspace_premium),
              title: Text(logo['label']?.toString() ?? 'Logo'),
              subtitle: logo['is_default'] == true ? const Text('Default') : null,
              onTap: () {
                Navigator.pop(ctx);
                _addElement(FlyerElement(
                  id: _newId(),
                  type: FlyerElementType.logo,
                  x: _canvasWidth * 0.35,
                  y: _canvasHeight * 0.05,
                  width: _canvasWidth * 0.3,
                  height: _canvasWidth * 0.18,
                  fit: 'contain',
                  url: logo['image_url']?.toString(),
                  zIndex: _nextZIndex(),
                ));
              },
            );
            }),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Canvas-level settings
  // ------------------------------------------------------------------

  Future<void> _renameFlyer() async {
    final controller = TextEditingController(text: _title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Flyer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || _projectId == null) return;
    setState(() => _title = result);
    try {
      await _api.updateFlyerProject(_projectId!, title: result);
    } catch (e) {
      _showSnack('Rename failed: $e');
    }
  }

  Future<void> _changeCanvasSize() async {
    final primaryColor = context.read<AppearanceSettings>().primaryColor;
    final preset = await showModalBottomSheet<FlyerCanvasPreset>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.read<AppearanceSettings>().cornerRadius.clamp(0, 24))),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            _sheetDragHandle(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Canvas Size',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...kFlyerCanvasPresets.map((p) {
              final isCurrent = p.width == _canvasWidth && p.height == _canvasHeight;
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.check_circle : Icons.crop_original,
                  color: isCurrent ? primaryColor : null,
                ),
                title: Text(p.name),
                subtitle: Text('${p.note}  ·  ${p.width.toInt()}×${p.height.toInt()}'),
                onTap: () => Navigator.pop(ctx, p),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (preset == null || _projectId == null) return;
    if (preset.width == _canvasWidth && preset.height == _canvasHeight) return;

    // Scale existing elements proportionally so a design isn't destroyed by
    // a size change — switching a finished 4:5 flyer to a Story should
    // reflow it, not scatter everything off-canvas.
    final scaleX = preset.width / _canvasWidth;
    final scaleY = preset.height / _canvasHeight;
    _pushUndo();
    setState(() {
      for (final el in _elements) {
        el.x *= scaleX;
        el.y *= scaleY;
        el.width *= scaleX;
        el.height *= scaleY;
        if (el.type == FlyerElementType.text) el.fontSize *= scaleX;
      }
      _canvasWidth = preset.width;
      _canvasHeight = preset.height;
    });
    try {
      await _api.updateFlyerProject(
        _projectId!,
        canvasWidth: preset.width,
        canvasHeight: preset.height,
      );
      _markDirty();
    } catch (e) {
      _showSnack('Could not change size: $e');
    }
  }

  Future<void> _changeBackgroundColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(
        initial: flyerHexToColor(_backgroundColor),
        title: 'Background Colour',
      ),
    );
    if (picked == null || _projectId == null) return;
    setState(() => _backgroundColor = flyerColorToHex(picked));
    try {
      await _api.updateFlyerProject(_projectId!, backgroundColor: _backgroundColor);
    } catch (e) {
      _showSnack('Could not save background: $e');
    }
  }

  Future<void> _changeBackgroundImage() async {
    final picked =
        await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || _projectId == null) return;
    setState(() => _saving = true);
    try {
      final result = await _api.uploadFlyerBackground(_projectId!, picked.path);
      setState(() =>
          _backgroundImageUrl = result['background_image_url']?.toString());
    } catch (e) {
      _showSnack('Background upload failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showBackgroundSheet() {
    final appearance = context.read<AppearanceSettings>();
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(appearance.cornerRadius.clamp(0, 24))),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              _sheetDragHandle(),
              ListTile(
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: flyerHexToColor(_backgroundColor),
                    border: Border.all(color: Colors.grey.shade400),
                    shape: BoxShape.circle,
                  ),
                ),
                title: const Text('Background colour'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeBackgroundColor();
                },
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper),
                title: const Text('Background photo'),
                subtitle: Text(_backgroundImageUrl == null ? 'None' : 'Tap to replace'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeBackgroundImage();
                },
              ),
              if (_backgroundImageUrl != null)
                ListTile(
                  leading: const Icon(Icons.hide_image_outlined),
                  title: const Text('Remove background photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _backgroundImageUrl = null);
                    _showSnack('Removed from view — re-open to restore from server');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio),
                title: const Text('Canvas size'),
                subtitle: Text('${_canvasWidth.toInt()}×${_canvasHeight.toInt()}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeCanvasSize();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.grid_on),
                title: const Text('Grid & rulers'),
                subtitle: const Text('A 10x10 guide overlay plus numbered edge rulers'),
                value: _showGrid,
                onChanged: (v) {
                  setState(() => _showGrid = v);
                  setSheetState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The small rounded handle bar every bottom sheet in Flyer Studio opens
  /// with -- a lightweight, reusable stand-in for a proper sheet theme, so
  /// every sheet reads as one designed surface instead of a bare ListView.
  Widget _sheetDragHandle() {
    final appearance = context.read<AppearanceSettings>();
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: appearance.primaryColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // AI + export
  // ------------------------------------------------------------------

  Future<void> _generateWithAI() async {
    if (_projectId == null) return;
    final promptController = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate with AI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: promptController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. "MBBS admission open, navy and gold, urgent tone"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI proposes a layout. Everything stays editable afterwards.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
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
              'AI will generate a new layout, replacing what is on the canvas. You can undo this.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _generatingAI = true);
    try {
      final result = await _api.generateFlyerAI(_projectId!, prompt);
      final raw = (result['canvas_json'] as List?) ?? [];
      _pushUndo();
      setState(() {
        _elements = raw
            .whereType<Map>()
            .map((e) => FlyerElement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _sortElements();
        _selectedId = null;
      });
      _markDirty();
      _showSnack('AI layout applied — drag anything to adjust');
    } catch (e) {
      _showSnack('AI generation failed: $e');
    } finally {
      if (mounted) setState(() => _generatingAI = false);
    }
  }

  /// Captures the on-screen canvas RepaintBoundary at full canvas resolution
  /// (not screen resolution), regardless of what phone this was designed on.
  /// Caller is responsible for setting `_exporting = true` and waiting a
  /// frame first, so editor chrome (handles/borders/guides) never ends up
  /// baked into the PNG.
  Future<Uint8List?> _captureCanvasBytes() async {
    final boundary =
        _canvasRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final onScreenWidth = boundary.size.width;
    final pixelRatio = (_canvasWidth / onScreenWidth).clamp(1.0, 4.0);
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<File> _writeCanvasPngFile(Uint8List bytes, {String? suffix}) async {
    final dir = await getTemporaryDirectory();
    final safeTitle = _title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final tag = suffix == null ? '' : '-$suffix';
    return File('${dir.path}/$safeTitle$tag-${DateTime.now().millisecondsSinceEpoch}.png');
  }

  Future<void> _exportAndShare() async {
    if (_projectId == null) return;
    // Deselect and drop editor chrome so handles/borders don't end up
    // baked into the exported PNG.
    setState(() {
      _selectedId = null;
      _exporting = true;
    });
    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final bytes = await _captureCanvasBytes();
      if (bytes == null) return;

      // Write to a temp file first: the OS share sheet (and WhatsApp /
      // Instagram specifically) need a real file, not raw bytes.
      final file = await _writeCanvasPngFile(bytes);
      await file.writeAsBytes(bytes);

      // Archive to storage too, so the flyer shows a thumbnail in history
      // later. Deliberately non-fatal: sharing is the user's actual intent,
      // so a backup failure warns but never blocks the share sheet.
      try {
        await _api.uploadFlyerRender(_projectId!, bytes);
      } catch (e) {
        _showSnack('Shared, but cloud backup failed');
      }

      await Share.shareXFiles([XFile(file.path)], text: _title);
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Renders the current design at every canvas preset in one pass and
  /// shares them together -- Canva's "Download all sizes". Elements are
  /// rescaled the same proportional way manual size-switching already does
  /// (see _changeCanvasSize), one preset at a time, then the original size
  /// and every element's original geometry are restored exactly at the end
  /// -- this is a one-shot export, not a standing size change.
  Future<void> _exportAllSizes() async {
    if (_projectId == null || _elements.isEmpty) return;

    final originalWidth = _canvasWidth;
    final originalHeight = _canvasHeight;
    final originalElements = _elements.map((e) => e.clone()).toList();

    setState(() {
      _selectedId = null;
      _exporting = true;
    });

    final files = <File>[];
    try {
      for (final preset in kFlyerCanvasPresets) {
        final scaleX = preset.width / _canvasWidth;
        final scaleY = preset.height / _canvasHeight;
        setState(() {
          for (final el in _elements) {
            el.x *= scaleX;
            el.y *= scaleY;
            el.width *= scaleX;
            el.height *= scaleY;
            if (el.type == FlyerElementType.text) el.fontSize *= scaleX;
          }
          _canvasWidth = preset.width;
          _canvasHeight = preset.height;
        });
        // Let the resized frame actually paint before capturing it.
        await Future.delayed(const Duration(milliseconds: 200));

        final bytes = await _captureCanvasBytes();
        if (bytes == null) continue;
        final file = await _writeCanvasPngFile(bytes, suffix: preset.id);
        await file.writeAsBytes(bytes);
        files.add(file);
      }

      if (files.isEmpty) {
        _showSnack('Export failed: nothing captured');
        return;
      }
      await Share.shareXFiles(
        files.map((f) => XFile(f.path)).toList(),
        text: '$_title -- all sizes',
      );
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      // Restore the design exactly as the counsellor left it -- this was a
      // one-shot export, never a standing size change.
      if (mounted) {
        setState(() {
          _elements = originalElements;
          _canvasWidth = originalWidth;
          _canvasHeight = originalHeight;
          _exporting = false;
        });
      }
    }
  }

  /// Share options. Sending straight to the lead is listed first and framed
  /// by name, because that is the actual job to be done -- the generic share
  /// sheet costs three extra taps (pick app, search contact, pick contact) at
  /// exactly the moment the counsellor is trying to move fast.
  Future<void> _showShareOptions() async {
    if (widget.leadId == null) {
      await _exportAndShare();
      return;
    }
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.read<AppearanceSettings>().cornerRadius.clamp(0, 24))),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetDragHandle(),
            ListTile(
              leading: const Icon(Icons.send, color: Color(0xFF25D366)),
              title: const Text('Send to this lead on WhatsApp'),
              subtitle: const Text('Opens their chat directly'),
              onTap: () {
                Navigator.pop(ctx);
                _sendToLead();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share as image'),
              subtitle: const Text('Any app, pick the contact yourself'),
              onTap: () {
                Navigator.pop(ctx);
                _exportAndShare();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Render, upload, then open this specific lead's WhatsApp chat with the
  /// flyer link already in the message box.
  Future<void> _sendToLead() async {
    if (_projectId == null || widget.leadId == null) return;

    setState(() {
      _selectedId = null;
      _exporting = true;
    });
    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final boundary =
          _canvasRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final onScreenWidth = boundary.size.width;
      final pixelRatio = (_canvasWidth / onScreenWidth).clamp(1.0, 4.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      // The link points at the stored render, so the upload has to land
      // before the link is requested -- not in parallel.
      await _api.uploadFlyerRender(_projectId!, byteData.buffer.asUint8List());

      final share = await _api.getFlyerShareLink(_projectId!, leadId: widget.leadId);
      final link = share['whatsapp_link']?.toString();

      if (link == null || link.isEmpty) {
        _showSnack(share['warning']?.toString() ?? 'This lead has no phone number on file');
        return;
      }

      final launched = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!launched) {
        _showSnack('Could not open WhatsApp');
        return;
      }

      // wa.me gives no delivery callback, so record the hand-off ourselves --
      // otherwise the flyer never appears in the lead's communication history.
      try {
        await _api.confirmFlyerSent(_projectId!, widget.leadId!,
            message: share['message']?.toString());
      } catch (_) {}
    } catch (e) {
      _showSnack('Could not send: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await _confirmExit();
        if (ok && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _renameFlyer,
            child: Row(
              children: [
                Flexible(child: Text(_title, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 14),
              ],
            ),
          ),
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
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              onPressed: _generatingAI ? null : _generateWithAI,
              tooltip: 'Generate with AI',
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'layers') _showLayersSheet();
                if (v == 'background') _showBackgroundSheet();
                if (v == 'save') _save();
                if (v == 'rename') _renameFlyer();
                if (v == 'exportAll') _exportAllSizes();
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'layers', child: Text('Layers')),
                PopupMenuItem(value: 'background', child: Text('Background & size')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'save', child: Text('Save now')),
                PopupMenuItem(
                    value: 'exportAll', child: Text('Export all sizes (Story/Post/A4...)')),
              ],
            ),
          ],
        ),
        floatingActionButton: _loading || _error != null
            ? null
            : FloatingActionButton.extended(
                onPressed: _exporting ? null : _showShareOptions,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.share),
                label: const Text('Share'),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : Column(
                    children: [
                      Expanded(child: _buildCanvasArea()),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: Alignment.bottomCenter,
                        child: _groupSelectMode
                            ? (_groupSelectedIds.isNotEmpty
                                ? _buildGroupActionBar()
                                : const SizedBox(width: double.infinity, height: 0))
                            : (selected != null
                                ? _buildStylePanel(selected)
                                : const SizedBox(width: double.infinity, height: 0)),
                      ),
                      _buildToolbar(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    final appearance = context.watch<AppearanceSettings>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth - 24;
        final availableH = constraints.maxHeight - 24;
        // Fit the whole canvas on screen in both axes — a Story (9:16)
        // canvas must not overflow vertically just because it's tall.
        final scale = math.min(
          availableW / _canvasWidth,
          availableH / _canvasHeight,
        );
        final displayW = _canvasWidth * scale;
        final displayH = _canvasHeight * scale;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: RepaintBoundary(
              key: _canvasRepaintKey,
              child: GestureDetector(
                onTap: () => _selectElement(null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: displayW,
                  height: displayH,
                  decoration: BoxDecoration(
                    color: flyerHexToColor(_backgroundColor),
                    boxShadow: _exporting
                        ? null
                        : [
                            BoxShadow(
                              color: appearance.glowEnabled
                                  ? appearance.glowColor
                                      .withValues(alpha: 0.4 * appearance.glowIntensity)
                                  : Colors.black.withValues(alpha: 0.18),
                              blurRadius: appearance.glowEnabled
                                  ? 22 + 22 * appearance.glowIntensity
                                  : 10,
                              spreadRadius: appearance.glowEnabled ? 1 : 0,
                            ),
                            if (appearance.glowEnabled)
                              BoxShadow(
                                color: appearance.glowColor
                                    .withValues(alpha: 0.2 * appearance.glowIntensity),
                                blurRadius: 44 + 30 * appearance.glowIntensity,
                                spreadRadius: 2,
                              ),
                          ],
                  ),
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        if (_backgroundImageUrl != null)
                          Positioned.fill(
                            child: Image.network(
                              _backgroundImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        if (_showGrid && !_exporting)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: FlyerGridPainter(
                                  scale: scale,
                                  canvasWidth: _canvasWidth,
                                  canvasHeight: _canvasHeight,
                                ),
                              ),
                            ),
                          ),
                        if (_showGrid && !_exporting)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: FlyerRulerPainter(
                                  scale: scale,
                                  canvasWidth: _canvasWidth,
                                  canvasHeight: _canvasHeight,
                                ),
                              ),
                            ),
                          ),
                        ..._elements
                            .where((el) => el.id != _editingTextId)
                            .map((el) => FlyerCanvasElementWidget(
                              key: ValueKey(el.id),
                              element: el,
                              scale: scale,
                              selected: !_exporting && !_groupSelectMode && el.id == _selectedId,
                              exporting: _exporting,
                              canvasWidth: _canvasWidth,
                              canvasHeight: _canvasHeight,
                              groupMode: _groupSelectMode,
                              groupSelected: _groupSelectedIds.contains(el.id),
                              siblings: _exporting
                                  ? const []
                                  : _elements.where((e) => e.id != el.id).toList(),
                              onTap: () => _groupSelectMode
                                  ? _toggleGroupMember(el.id)
                                  : _selectElement(el.id),
                              onDoubleTap: () {
                                if (el.type == FlyerElementType.text) {
                                  _beginInlineEdit(el);
                                } else {
                                  _selectElement(el.id);
                                  _replaceElementImage(el);
                                }
                              },
                              onChanged: _onElementChanged,
                              onDragStart: _pushUndo,
                              onDragEnd: () {},
                              onDelete: () {
                                _pushUndo();
                                setState(() {
                                  _elements.removeWhere((e) => e.id == el.id);
                                  _selectedId = null;
                                });
                                _markDirty();
                              },
                              onSnapGuides: (guides) {
                                if (guides.length != _snapGuides.length) {
                                  if (guides.isNotEmpty &&
                                      _snapGuides.isEmpty &&
                                      context.read<AppearanceSettings>().haptics) {
                                    HapticFeedback.selectionClick();
                                  }
                                  setState(() => _snapGuides = guides);
                                }
                              },
                            )),
                        if (_editingTextId != null) _buildInlineTextEditor(scale),
                        if (_groupSelectMode && _groupSelectedIds.isNotEmpty && !_exporting)
                          _buildGroupBoundsOverlay(scale),
                        if (_snapGuides.isNotEmpty && !_exporting)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: FlyerSnapGuidePainter(
                                    guides: _snapGuides, scale: scale),
                              ),
                            ),
                          ),
                      ],
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

  static const Color _groupHighlightColor = Color(0xFF9C6ADE);

  /// The dashed-style bounding box around every group-selected element,
  /// draggable to move the whole group together in one gesture, with a
  /// floating rotate handle above it (same stalk pattern as a single
  /// element's own rotate handle) that spins the whole cluster around its
  /// shared centre -- the piece that makes group-select an actual editing
  /// tool rather than just a bulk-delete picker.
  Widget _buildGroupBoundsOverlay(double scale) {
    final bounds = _groupBoundsRect();
    if (bounds == null) return const SizedBox.shrink();
    const pad = 8.0;
    final boxWidth = bounds.width * scale + pad * 2;
    final boxHeight = bounds.height * scale + pad * 2;
    return Positioned(
      left: bounds.left * scale - pad,
      top: bounds.top * scale - pad,
      width: boxWidth,
      height: boxHeight,
      child: Builder(
        builder: (boxContext) => Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => _pushUndo(),
              onPanUpdate: (details) => _groupDrag(details.delta / scale),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _groupHighlightColor, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: _groupHighlightColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.open_with, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              left: boxWidth / 2 - 1,
              top: -22,
              child: Container(
                  width: 2, height: 22, color: _groupHighlightColor.withValues(alpha: 0.6)),
            ),
            Positioned(
              left: boxWidth / 2 - 18,
              top: -46,
              child: GestureDetector(
                onPanStart: (_) {
                  _pushUndo();
                  _groupRotateStartAngle = null;
                },
                onPanUpdate: (details) {
                  final box = boxContext.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final centre =
                      box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
                  final angle = math.atan2(
                    details.globalPosition.dy - centre.dy,
                    details.globalPosition.dx - centre.dx,
                  );
                  if (_groupRotateStartAngle != null) {
                    _groupRotate(angle - _groupRotateStartAngle!);
                  }
                  _groupRotateStartAngle = angle;
                },
                onPanEnd: (_) => _groupRotateStartAngle = null,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _groupHighlightColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                    ),
                    child: const Icon(Icons.rotate_right, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The live overlay for inline WYSIWYG editing -- a real TextField sized,
  /// positioned, and styled to exactly match the FlyerElement it's replacing
  /// while `_editingTextId` is set (see _beginInlineEdit). Falls back to
  /// nothing if the element vanished mid-edit (e.g. deleted from Layers).
  Widget _buildInlineTextEditor(double scale) {
    FlyerElement? el;
    for (final e in _elements) {
      if (e.id == _editingTextId) {
        el = e;
        break;
      }
    }
    if (el == null || _inlineController == null) return const SizedBox.shrink();

    final textAlign = el.textAlign == 'center'
        ? TextAlign.center
        : el.textAlign == 'right'
            ? TextAlign.right
            : TextAlign.left;

    return Positioned(
      left: el.x * scale,
      top: el.y * scale,
      width: math.max(el.width * scale, 6.0),
      height: math.max(el.height * scale, 6.0),
      child: Container(
        color: el.backgroundColor != null
            ? flyerHexToColor(el.backgroundColor!)
            : Colors.transparent,
        child: TextField(
          controller: _inlineController,
          focusNode: _inlineFocusNode,
          maxLines: null,
          minLines: null,
          expands: true,
          textAlign: textAlign,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: flyerHexToColor(el.color),
          style: TextStyle(
            fontSize: el.fontSize * scale,
            fontFamily: el.fontFamily,
            color: flyerHexToColor(el.color),
            fontWeight: el.fontWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
            fontStyle: el.italic ? FontStyle.italic : FontStyle.normal,
            height: el.lineHeight,
            letterSpacing: el.letterSpacing * scale,
            decoration: el.underline ? TextDecoration.underline : TextDecoration.none,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.all(4),
          ),
          onChanged: (v) {
            el!.text = v;
            _markDirty();
          },
          onTapOutside: (_) => _endInlineEdit(),
          onEditingComplete: _endInlineEdit,
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final appearance = context.watch<AppearanceSettings>();
    final glass = context.watch<GlassSettings>();
    final hasSelection = _selectedId != null;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(appearance.cornerRadius.clamp(0, 24)),
      topRight: Radius.circular(appearance.cornerRadius.clamp(0, 24)),
    );
    final glowShadow = navBarGlowShadow(appearance);

    Widget bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: glass.enabled
            ? Colors.white.withValues(alpha: appearance.darkMode ? 0.06 : 0.55)
            : Theme.of(context).navigationBarTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
        borderRadius: radius,
        border: Border(
          top: BorderSide(color: appearance.primaryColor.withValues(alpha: 0.1)),
        ),
        boxShadow: [
          glowShadow ??
              const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _toolbarButton(Icons.text_fields, 'Text', _addTextElement, appearance),
              _toolbarButton(
                  Icons.add_photo_alternate, 'Photo', _addImageElement, appearance),
              _toolbarButton(Icons.workspace_premium, 'Logo', _addLogoElement, appearance),
              _toolbarButton(Icons.rectangle, 'Shape', _addShapeElement, appearance),
              _toolbarButton(
                  Icons.wallpaper, 'Background', _showBackgroundSheet, appearance),
              _toolbarButton(Icons.layers, 'Layers', _showLayersSheet, appearance),
              _toolbarToggleButton(
                  Icons.select_all, 'Group', _groupSelectMode, _toggleGroupSelectMode, appearance),
              _toolbarButton(Icons.copy, 'Duplicate',
                  hasSelection ? _duplicateSelected : null, appearance),
              _toolbarButton(Icons.delete_outline, 'Delete',
                  hasSelection ? _deleteSelected : null, appearance),
            ],
          ),
        ),
      ),
    );

    if (!glass.enabled) return bar;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: glass.blur * 0.5, sigmaY: glass.blur * 0.5),
        child: bar,
      ),
    );
  }

  Widget _toolbarToggleButton(IconData icon, String label, bool active, VoidCallback onTap,
      AppearanceSettings appearance) {
    final color = active ? appearance.primaryColor : null;
    return TouchFeedbackWrapper(
      appearance: appearance,
      radius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (appearance.haptics) HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? appearance.primaryColor.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton(
      IconData icon, String label, VoidCallback? onTap, AppearanceSettings appearance) {
    final disabled = onTap == null;
    final color = disabled ? Colors.grey.shade400 : appearance.primaryColor;
    return TouchFeedbackWrapper(
      appearance: appearance,
      radius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap == null
            ? null
            : () {
                if (appearance.haptics) HapticFeedback.selectionClick();
                onTap();
              },
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupActionBar() {
    final appearance = context.watch<AppearanceSettings>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: appearance.primaryColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Text('${_groupSelectedIds.length} selected',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Align selection',
            icon: const Icon(Icons.align_horizontal_left, size: 20),
            onSelected: _groupAlign,
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'left', child: Text('Align left')),
              PopupMenuItem(value: 'centerH', child: Text('Align centre (horizontal)')),
              PopupMenuItem(value: 'right', child: Text('Align right')),
              PopupMenuItem(value: 'top', child: Text('Align top')),
              PopupMenuItem(value: 'centerV', child: Text('Align middle (vertical)')),
              PopupMenuItem(value: 'bottom', child: Text('Align bottom')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Duplicate group',
            onPressed: _groupDuplicate,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete group',
            onPressed: _groupDelete,
          ),
        ],
      ),
    );
  }

  Widget _buildStylePanel(FlyerElement el) {
    final appearance = context.watch<AppearanceSettings>();
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: appearance.primaryColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: appearance.primaryColor.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: SingleChildScrollView(
                key: ValueKey('${el.id}-${el.type}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNudgeRow(el),
                    if (el.type == FlyerElementType.text) ..._textControls(el),
                    if (el.type == FlyerElementType.image ||
                        el.type == FlyerElementType.logo)
                      ..._imageControls(el),
                    if (el.type == FlyerElementType.shape) ..._shapeControls(el),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNudgeRow(FlyerElement el) {
    final step = _canvasWidth * 0.01;
    final appearance = context.watch<AppearanceSettings>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Nudge', style: TextStyle(fontSize: 11, color: Colors.grey)),
          IconButton(
              icon: const Icon(Icons.keyboard_arrow_left, size: 20),
              onPressed: () => _nudge(-step, 0)),
          IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: () => _nudge(0, -step)),
          IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: () => _nudge(0, step)),
          IconButton(
              icon: const Icon(Icons.keyboard_arrow_right, size: 20),
              onPressed: () => _nudge(step, 0)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.center_focus_strong, size: 20),
            tooltip: 'Centre horizontally',
            onPressed: () {
              setState(() => el.x = _canvasWidth / 2 - el.width / 2);
              _markDirty();
            },
          ),
          IconButton(
            icon: Icon(el.aspectLocked ? Icons.link : Icons.link_off,
                size: 20, color: el.aspectLocked ? appearance.primaryColor : null),
            tooltip: el.aspectLocked ? 'Aspect ratio locked' : 'Lock aspect ratio',
            onPressed: () {
              setState(() => el.aspectLocked = !el.aspectLocked);
              _markDirty();
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _textControls(FlyerElement el) {
    final activeColor = context.watch<AppearanceSettings>().primaryColor;
    return [
      Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              value: kFlyerFontFamilies.contains(el.fontFamily)
                  ? el.fontFamily
                  : kFlyerFontFamilies.first,
              isExpanded: true,
              items: kFlyerFontFamilies
                  .map((f) => DropdownMenuItem(
                      value: f, child: Text(f, style: TextStyle(fontFamily: f))))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => el.fontFamily = v);
                _markDirty();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Edit text',
            onPressed: () => _beginInlineEdit(el),
          ),
        ],
      ),
      Row(
        children: [
          IconButton(
            icon: Icon(Icons.format_bold,
                color: el.fontWeight == 'bold' ? activeColor : null),
            onPressed: () {
              setState(() =>
                  el.fontWeight = el.fontWeight == 'bold' ? 'normal' : 'bold');
              _markDirty();
            },
          ),
          IconButton(
            icon: Icon(Icons.format_italic, color: el.italic ? activeColor : null),
            onPressed: () {
              setState(() => el.italic = !el.italic);
              _markDirty();
            },
          ),
          IconButton(
            icon: Icon(Icons.format_underlined, color: el.underline ? activeColor : null),
            onPressed: () {
              setState(() => el.underline = !el.underline);
              _markDirty();
            },
          ),
          for (final a in ['left', 'center', 'right'])
            IconButton(
              icon: Icon(
                a == 'left'
                    ? Icons.format_align_left
                    : a == 'center'
                        ? Icons.format_align_center
                        : Icons.format_align_right,
                color: el.textAlign == a ? activeColor : null,
              ),
              onPressed: () {
                setState(() => el.textAlign = a);
                _markDirty();
              },
            ),
          IconButton(
            icon: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: flyerHexToColor(el.color),
                border: Border.all(color: Colors.grey.shade400),
                shape: BoxShape.circle,
              ),
            ),
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(
                    initial: flyerHexToColor(el.color), title: 'Text Colour'),
              );
              if (picked != null) {
                setState(() => el.color = flyerColorToHex(picked));
                _markDirty();
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.blur_on, color: el.textShadow ? activeColor : null),
            tooltip: 'Drop shadow',
            onPressed: () {
              setState(() => el.textShadow = !el.textShadow);
              _markDirty();
            },
          ),
        ],
      ),
      _sliderRow(
        icon: Icons.format_size,
        value: el.fontSize.clamp(8, _canvasWidth * 0.25),
        min: 8,
        max: _canvasWidth * 0.25,
        onChanged: (v) {
          setState(() => el.fontSize = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.opacity,
        value: el.opacity.clamp(0.1, 1.0),
        min: 0.1,
        max: 1.0,
        onChanged: (v) {
          setState(() => el.opacity = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.space_bar,
        value: el.letterSpacing.clamp(-2.0, 20.0),
        min: -2.0,
        max: 20.0,
        onChanged: (v) {
          setState(() => el.letterSpacing = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.format_line_spacing,
        value: el.lineHeight.clamp(0.8, 2.5),
        min: 0.8,
        max: 2.5,
        onChanged: (v) {
          setState(() => el.lineHeight = v);
          _markDirty();
        },
      ),
    ];
  }

  List<Widget> _imageControls(FlyerElement el) {
    return [
      Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Replace'),
            onPressed: () => _replaceElementImage(el),
          ),
          TextButton(
            onPressed: () {
              setState(() => el.fit = el.fit == 'cover' ? 'contain' : 'cover');
              _markDirty();
            },
            child: Text(el.fit == 'cover' ? 'Fill' : 'Fit'),
          ),
        ],
      ),
      _sliderRow(
        icon: Icons.opacity,
        value: el.opacity.clamp(0.1, 1.0),
        min: 0.1,
        max: 1.0,
        onChanged: (v) {
          setState(() => el.opacity = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.rounded_corner,
        value: el.cornerRadius.clamp(0, 200),
        min: 0,
        max: 200,
        onChanged: (v) {
          setState(() => el.cornerRadius = v);
          _markDirty();
        },
      ),
    ];
  }

  List<Widget> _shapeControls(FlyerElement el) {
    return [
      Row(
        children: [
          IconButton(
            icon: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: flyerHexToColor(el.shapeColor),
                border: Border.all(color: Colors.grey.shade400),
                shape: BoxShape.circle,
              ),
            ),
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(
                    initial: flyerHexToColor(el.shapeColor), title: 'Shape Colour'),
              );
              if (picked != null) {
                setState(() => el.shapeColor = flyerColorToHex(picked));
                _markDirty();
              }
            },
          ),
          TextButton(
            onPressed: () {
              setState(
                  () => el.shapeKind = el.shapeKind == 'circle' ? 'rect' : 'circle');
              _markDirty();
            },
            child: Text(el.shapeKind == 'circle' ? 'Circle' : 'Rectangle'),
          ),
          IconButton(
            icon: Icon(Icons.gradient,
                color: el.shapeGradientEnd != null
                    ? context.watch<AppearanceSettings>().primaryColor
                    : null),
            tooltip: el.shapeGradientEnd != null ? 'Remove gradient' : 'Add gradient',
            onPressed: () async {
              if (el.shapeGradientEnd != null) {
                setState(() => el.shapeGradientEnd = null);
                _markDirty();
                return;
              }
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(
                    initial: flyerHexToColor(el.shapeColor), title: 'Gradient End Colour'),
              );
              if (picked != null) {
                setState(() => el.shapeGradientEnd = flyerColorToHex(picked));
                _markDirty();
              }
            },
          ),
          IconButton(
            icon: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: el.strokeColor != null
                    ? flyerHexToColor(el.strokeColor!)
                    : Colors.transparent,
                border: Border.all(
                    color: Colors.grey.shade400,
                    width: el.strokeColor != null ? 3 : 1),
                shape: BoxShape.circle,
              ),
            ),
            tooltip: 'Stroke colour',
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(
                    initial: flyerHexToColor(el.strokeColor ?? '#000000'),
                    title: 'Stroke Colour'),
              );
              if (picked != null) {
                setState(() {
                  el.strokeColor = flyerColorToHex(picked);
                  if (el.strokeWidth <= 0) el.strokeWidth = 4;
                });
                _markDirty();
              }
            },
          ),
        ],
      ),
      _sliderRow(
        icon: Icons.opacity,
        value: el.opacity.clamp(0.1, 1.0),
        min: 0.1,
        max: 1.0,
        onChanged: (v) {
          setState(() => el.opacity = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.border_outer,
        value: el.strokeWidth.clamp(0.0, 20.0),
        min: 0.0,
        max: 20.0,
        onChanged: (v) {
          setState(() => el.strokeWidth = v);
          _markDirty();
        },
      ),
      if (el.shapeKind != 'circle')
        _sliderRow(
          icon: Icons.rounded_corner,
          value: el.cornerRadius.clamp(0, 200),
          min: 0,
          max: 200,
          onChanged: (v) {
            setState(() => el.cornerRadius = v);
            _markDirty();
          },
        ),
    ];
  }

  Widget _sliderRow({
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  void _bulkDeleteSelected(Set<String> ids) {
    if (ids.isEmpty) return;
    _pushUndo();
    setState(() {
      _elements.removeWhere((e) => ids.contains(e.id));
      if (_selectedId != null && ids.contains(_selectedId)) _selectedId = null;
    });
    _markDirty();
  }

  void _bulkDuplicateSelected(Set<String> ids) {
    if (ids.isEmpty) return;
    _pushUndo();
    setState(() {
      for (final id in ids.toList()) {
        FlyerElement? found;
        for (final e in _elements) {
          if (e.id == id) {
            found = e;
            break;
          }
        }
        if (found == null) continue;
        final copy = found.clone();
        copy.id = _newId();
        copy.x += _canvasWidth * 0.03;
        copy.y += _canvasHeight * 0.02;
        copy.zIndex = _nextZIndex();
        copy.locked = false;
        _elements.add(copy);
      }
      _sortElements();
    });
    _markDirty();
  }

  Widget _layerThumbnail(FlyerElement el) {
    Widget content;
    switch (el.type) {
      case FlyerElementType.text:
        content = Container(
          color: flyerHexToColor(el.color).withValues(alpha: 0.15),
          alignment: Alignment.center,
          child: Text('T',
              style: TextStyle(color: flyerHexToColor(el.color), fontWeight: FontWeight.bold)),
        );
        break;
      case FlyerElementType.image:
      case FlyerElementType.logo:
        content = (el.url != null && el.url!.isNotEmpty)
            ? Image.network(el.url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(_iconFor(el.type), size: 18, color: Colors.grey))
            : Icon(_iconFor(el.type), size: 18, color: Colors.grey);
        break;
      case FlyerElementType.shape:
        content = Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: flyerHexToColor(el.shapeColor),
            shape: el.shapeKind == 'circle' ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: el.shapeKind == 'circle' ? null : BorderRadius.circular(4),
          ),
        );
        break;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(width: 36, height: 36, color: Colors.grey.shade200, child: content),
    );
  }

  void _showLayersSheet() {
    final appearance = context.read<AppearanceSettings>();
    bool multiSelect = false;
    _multiSelectedIds.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(appearance.cornerRadius.clamp(0, 24))),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final sorted = [..._elements]
              ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(
                  children: [
                    _sheetDragHandle(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Layers  ·  top to bottom',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          TextButton(
                            onPressed: sorted.isEmpty
                                ? null
                                : () => setSheetState(() {
                                      multiSelect = !multiSelect;
                                      _multiSelectedIds.clear();
                                    }),
                            child: Text(multiSelect ? 'Done' : 'Select'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: sorted.isEmpty
                          ? const Center(child: Text('Nothing on the canvas yet'))
                          : ListView.builder(
                              itemCount: sorted.length,
                              itemBuilder: (ctx, i) {
                                final el = sorted[i];
                                final checked = _multiSelectedIds.contains(el.id);
                                return ListTile(
                                  dense: true,
                                  leading: multiSelect
                                      ? Checkbox(
                                          value: checked,
                                          onChanged: (_) => setSheetState(() {
                                            checked
                                                ? _multiSelectedIds.remove(el.id)
                                                : _multiSelectedIds.add(el.id);
                                          }),
                                        )
                                      : _layerThumbnail(el),
                                  title: Text(_labelFor(el),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  selected: !multiSelect && el.id == _selectedId,
                                  onTap: () {
                                    if (multiSelect) {
                                      setSheetState(() {
                                        checked
                                            ? _multiSelectedIds.remove(el.id)
                                            : _multiSelectedIds.add(el.id);
                                      });
                                      return;
                                    }
                                    _selectElement(el.id);
                                    Navigator.pop(ctx);
                                  },
                                  trailing: multiSelect
                                      ? null
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                  el.locked ? Icons.lock : Icons.lock_open,
                                                  size: 17),
                                              onPressed: () {
                                                setState(() => el.locked = !el.locked);
                                                setSheetState(() {});
                                                _markDirty();
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.arrow_upward, size: 17),
                                              onPressed: () {
                                                _reorderLayer(el.id, 1);
                                                setSheetState(() {});
                                              },
                                            ),
                                            IconButton(
                                              icon:
                                                  const Icon(Icons.arrow_downward, size: 17),
                                              onPressed: () {
                                                _reorderLayer(el.id, -1);
                                                setSheetState(() {});
                                              },
                                            ),
                                            IconButton(
                                              icon:
                                                  const Icon(Icons.delete_outline, size: 17),
                                              onPressed: () {
                                                _pushUndo();
                                                setState(() {
                                                  _elements
                                                      .removeWhere((e) => e.id == el.id);
                                                  if (_selectedId == el.id) {
                                                    _selectedId = null;
                                                  }
                                                });
                                                setSheetState(() {});
                                                _markDirty();
                                              },
                                            ),
                                          ],
                                        ),
                                );
                              },
                            ),
                    ),
                    if (multiSelect && _multiSelectedIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${_multiSelectedIds.length} selected',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Duplicate'),
                              onPressed: () {
                                final ids = Set<String>.from(_multiSelectedIds);
                                _bulkDuplicateSelected(ids);
                                setSheetState(() => _multiSelectedIds.clear());
                              },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete'),
                              onPressed: () {
                                final ids = Set<String>.from(_multiSelectedIds);
                                _bulkDeleteSelected(ids);
                                setSheetState(() => _multiSelectedIds.clear());
                              },
                            ),
                          ],
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
        return Icons.rectangle;
    }
  }

  String _labelFor(FlyerElement el) {
    if (el.type == FlyerElementType.text) {
      final t = (el.text ?? '').replaceAll('\n', ' ');
      if (t.isEmpty) return 'Text';
      return t.length > 28 ? '${t.substring(0, 28)}…' : t;
    }
    return flyerElementTypeToString(el.type);
  }
}
