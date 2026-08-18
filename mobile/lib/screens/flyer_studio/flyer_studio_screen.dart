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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import 'flyer_fonts.dart';
import 'svg_sanitizer.dart';

class FlyerStudioScreen extends StatefulWidget {
  final String? projectId;
  final String? leadId;
  // Logo Studio mode -- same freeform canvas engine (shapes, text,
  // images, groups, undo/redo, export), just started with a square
  // canvas, a transparent background (a logo composites onto other
  // designs, unlike a flyer which is always its own opaque page), and
  // an extra "Save to Brand Logos" export destination alongside the
  // normal flyer save/share flow. Nothing about the editor itself
  // branches on this flag -- every tool works exactly the same either
  // way, it only changes the starting defaults and what "done" saves to.
  final bool isLogoMode;

  const FlyerStudioScreen({super.key, this.projectId, this.leadId, this.isLogoMode = false});

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

  // Multi-page designs (Canva-parity Phase H). _elements is always "the
  // active page's elements" -- unchanged in meaning from before this
  // existed, so the 40+ existing call sites that read/mutate it keep
  // working untouched. _pages holds every page's elements, kept in sync
  // with _elements via _syncActivePage() immediately before any read
  // (switch/save) that needs the full set. A brand-new/legacy single-
  // page project is just _pages.length == 1, which round-trips through
  // canvas_json in the exact same flat-array shape it always has --
  // multi-page only changes the wire format for genuinely multi-page
  // projects, so no existing saved project's data shape changes.
  List<List<FlyerElement>> _pages = [[]];
  int _activePageIndex = 0;

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

  // Draw tool (Canva-parity Phase E). A distinct mode, same shape as
  // _groupSelectMode above -- while active, the canvas captures freehand
  // pan gestures into a new drawing element instead of the normal
  // drag/resize/select interaction. _liveStrokePoints is screen-space
  // (raw pixels within the canvas view) for the in-progress preview only;
  // the finished element stores fractional points instead (see
  // FlyerElement.drawingPoints).
  bool _drawMode = false;
  List<Offset> _liveStrokePoints = [];
  Color _drawColor = const Color(0xFF1B2A4A);
  double _drawStrokeWidth = 4;

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
        title: widget.isLogoMode ? 'Untitled Logo' : 'Untitled Flyer',
        leadId: widget.leadId,
        canvasWidth: widget.isLogoMode ? 512 : null,
        canvasHeight: widget.isLogoMode ? 512 : null,
        backgroundColor: widget.isLogoMode ? 'transparent' : null,
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
    _pages = parsePagesFromCanvasJson((data['canvas_json'] as List?) ?? []);
    _activePageIndex = 0;
    _elements = _pages[0];
    _sortElements();
  }

  /// Writes the currently-active page's in-progress edits back into
  /// _pages before anything (page switch, save) needs the full set.
  void _syncActivePage() {
    if (_activePageIndex >= 0 && _activePageIndex < _pages.length) {
      _pages[_activePageIndex] = _elements;
    }
  }

  List<Map<String, dynamic>> _canvasJsonForSave() {
    _syncActivePage();
    return canvasJsonForPages(_pages);
  }

  void _switchToPage(int index) {
    if (index == _activePageIndex || index < 0 || index >= _pages.length) return;
    _syncActivePage();
    setState(() {
      _activePageIndex = index;
      _elements = _pages[index];
      _selectedId = null;
      // Undo/redo history doesn't cross page boundaries -- a snapshot
      // taken on one page can't be meaningfully restored onto another.
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  void _addPage() {
    _syncActivePage();
    setState(() {
      _pages.add([]);
      _activePageIndex = _pages.length - 1;
      _elements = _pages[_activePageIndex];
      _selectedId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _markDirty();
  }

  Future<void> _deletePage(int index) async {
    if (_pages.length <= 1) {
      _showSnack('A design needs at least one page');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete this page?'),
        content: const Text('This removes the page and everything on it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _pages.removeAt(index);
      if (_activePageIndex >= _pages.length) _activePageIndex = _pages.length - 1;
      _elements = _pages[_activePageIndex];
      _selectedId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _markDirty();
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
        _canvasJsonForSave(),
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

  void _toggleDrawMode() {
    if (context.read<AppearanceSettings>().haptics) HapticFeedback.selectionClick();
    setState(() {
      _drawMode = !_drawMode;
      _liveStrokePoints = [];
      if (_drawMode) {
        _selectedId = null;
        _groupSelectMode = false;
        _groupSelectedIds.clear();
      }
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

  /// Scales the whole group together from its top-left corner, the same
  /// proportional-rescale math _changeCanvasSize already uses for the
  /// whole canvas, just anchored on the group's own bounds instead of the
  /// page. Bounds are recomputed fresh each tick so the scale factor is
  /// always relative to the group's current (not original) size, matching
  /// how a single element's own resize handle accumulates incrementally.
  void _groupResize(Offset rawDelta) {
    final bounds = _groupBoundsRect();
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;
    final newWidth = (bounds.width + rawDelta.dx).clamp(40.0, 8000.0);
    final newHeight = (bounds.height + rawDelta.dy).clamp(40.0, 8000.0);
    final scaleX = newWidth / bounds.width;
    final scaleY = newHeight / bounds.height;
    setState(() {
      for (final el in _elements) {
        if (!_groupSelectedIds.contains(el.id) || el.locked) continue;
        el.x = bounds.left + (el.x - bounds.left) * scaleX;
        el.y = bounds.top + (el.y - bounds.top) * scaleY;
        el.width *= scaleX;
        el.height *= scaleY;
        if (el.type == FlyerElementType.text) el.fontSize *= scaleX;
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

  // Canva-parity Phase D -- photo grids. A layout is just a set of
  // pre-positioned, empty `image` elements tiling a region of the canvas
  // seamlessly -- each one is a fully independent, already-existing image
  // element (drag/resize/replace/adjust all work on it unchanged), so
  // "grids" reuses 100% of existing image-element machinery rather than
  // inventing a new nested/grouped element type this app's flat-list
  // canvas model doesn't have. Tapping an empty slot already opens the
  // image picker via the same "Tap, then Replace" flow every empty image
  // element has.
  Future<void> _addPhotoGrid() async {
    final layout = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Photo grid layout'),
        children: [
          _gridLayoutOption(ctx, '2h', '2-up, side by side'),
          _gridLayoutOption(ctx, '2v', '2-up, stacked'),
          _gridLayoutOption(ctx, '3big', '1 large + 2 small'),
          _gridLayoutOption(ctx, '4up', '2x2 grid'),
        ],
      ),
    );
    if (layout == null) return;

    const gap = 8.0;
    final regionX = _canvasWidth * 0.1;
    final regionY = _canvasHeight * 0.2;
    final regionW = _canvasWidth * 0.8;
    final regionH = _canvasHeight * 0.5;

    List<Rect> slots;
    switch (layout) {
      case '2v':
        final h = (regionH - gap) / 2;
        slots = [
          Rect.fromLTWH(regionX, regionY, regionW, h),
          Rect.fromLTWH(regionX, regionY + h + gap, regionW, h),
        ];
        break;
      case '3big':
        final leftW = regionW * 0.6;
        final rightW = regionW - leftW - gap;
        final rightH = (regionH - gap) / 2;
        slots = [
          Rect.fromLTWH(regionX, regionY, leftW, regionH),
          Rect.fromLTWH(regionX + leftW + gap, regionY, rightW, rightH),
          Rect.fromLTWH(regionX + leftW + gap, regionY + rightH + gap, rightW, rightH),
        ];
        break;
      case '4up':
        final w = (regionW - gap) / 2;
        final h = (regionH - gap) / 2;
        slots = [
          Rect.fromLTWH(regionX, regionY, w, h),
          Rect.fromLTWH(regionX + w + gap, regionY, w, h),
          Rect.fromLTWH(regionX, regionY + h + gap, w, h),
          Rect.fromLTWH(regionX + w + gap, regionY + h + gap, w, h),
        ];
        break;
      case '2h':
      default:
        final w = (regionW - gap) / 2;
        slots = [
          Rect.fromLTWH(regionX, regionY, w, regionH),
          Rect.fromLTWH(regionX + w + gap, regionY, w, regionH),
        ];
    }

    _pushUndo();
    setState(() {
      var z = _nextZIndex();
      for (final slot in slots) {
        _elements.add(FlyerElement(
          id: '${_newId()}-$z',
          type: FlyerElementType.image,
          x: slot.left,
          y: slot.top,
          width: slot.width,
          height: slot.height,
          fit: 'cover',
          zIndex: z,
        ));
        z++;
      }
      _sortElements();
    });
    _markDirty();
  }

  Widget _gridLayoutOption(BuildContext ctx, String value, String label) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(
        children: [
          Icon(
            value == '2h'
                ? Icons.view_column_outlined
                : value == '2v'
                    ? Icons.table_rows_outlined
                    : value == '3big'
                        ? Icons.dashboard_customize_outlined
                        : Icons.grid_view_outlined,
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
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

  // Canva-parity Phase E -- turns the just-finished freehand stroke
  // (_liveStrokePoints, screen-space) into a real FlyerElement.
  // _addElement already pushes undo, so this doesn't call it separately.
  void _finishDrawing(double scale) {
    final pts = _liveStrokePoints;
    setState(() => _liveStrokePoints = []);
    if (pts.length < 2) return; // an accidental tap, not a real stroke

    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    // A perfectly straight vertical/horizontal stroke has zero width or
    // height in one axis -- clamp to a minimum so the element still has
    // a real, selectable/resizable bounding box afterwards.
    final boundingW = math.max(maxX - minX, 20.0);
    final boundingH = math.max(maxY - minY, 20.0);
    final fractionalPoints = pts
        .map((p) => [
              ((p.dx - minX) / boundingW).clamp(0.0, 1.0),
              ((p.dy - minY) / boundingH).clamp(0.0, 1.0),
            ])
        .toList();

    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.drawing,
      x: minX / scale,
      y: minY / scale,
      width: boundingW / scale,
      height: boundingH / scale,
      drawingPoints: fractionalPoints,
      shapeColor: flyerColorToHex(_drawColor),
      strokeWidth: _drawStrokeWidth,
      zIndex: _nextZIndex(),
    ));
  }

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

  void _addShapeElement([String kind = 'rect']) {
    // A line/arrow reads better wide and short; everything else (rect/
    // circle/triangle/star) reads better closer to square -- matches
    // what each shape actually looks like at the old fixed size rather
    // than forcing all 6 kinds into one aspect ratio.
    final wide = kind == 'line' || kind == 'arrow';
    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.shape,
      x: _canvasWidth * (wide ? 0.15 : 0.3),
      y: _canvasHeight * (wide ? 0.4 : 0.3),
      width: _canvasWidth * (wide ? 0.7 : 0.4),
      height: wide ? _canvasHeight * 0.12 : _canvasWidth * 0.4,
      shapeKind: kind,
      shapeColor: '#1B2A4A',
      zIndex: _nextZIndex(),
    ));
  }

  void _addIconElement(String iconKey, {String color = '#1B2A4A'}) {
    final size = math.min(_canvasWidth, _canvasHeight) * 0.28;
    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.icon,
      x: (_canvasWidth - size) / 2,
      y: (_canvasHeight - size) / 2,
      width: size,
      height: size,
      iconKey: iconKey,
      shapeColor: color,
      zIndex: _nextZIndex(),
    ));
  }

  /// Imports a user-picked .svg file as a true vector element -- stays
  /// editable (recolourable, moveable, resizable, re-exportable as SVG
  /// later) rather than flattening it to a bitmap on the way in. Every
  /// file is run through sanitizeSvg() before it ever touches the
  /// document model (see svg_sanitizer.dart for what that strips).
  /// [replaceTarget] set swaps an existing SVG element's artwork in place
  /// (its "Replace SVG" button) instead of adding a new element.
  Future<void> _importSvgElement({FlyerElement? replaceTarget}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );
    if (picked == null || picked.files.single.path == null) return;

    String raw;
    try {
      raw = await File(picked.files.single.path!).readAsString();
    } catch (e) {
      _showSnack('Could not read that file: $e');
      return;
    }

    String sanitized;
    try {
      sanitized = sanitizeSvg(raw);
    } on SvgSanitizeException catch (e) {
      _showSnack('Could not import: ${e.message}');
      return;
    } catch (e) {
      _showSnack('Could not import this SVG: $e');
      return;
    }

    if (replaceTarget != null) {
      _pushUndo();
      setState(() => replaceTarget.svgData = sanitized);
      _markDirty();
      return;
    }

    final size = math.min(_canvasWidth, _canvasHeight) * 0.4;
    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.svg,
      x: (_canvasWidth - size) / 2,
      y: (_canvasHeight - size) / 2,
      width: size,
      height: size,
      svgData: sanitized,
      zIndex: _nextZIndex(),
    ));
  }

  /// Shared by both the picker grid and the AI Icon Finder result --
  /// see _openIconPicker's replaceTarget doc for why this branches.
  void _applyIconChoice(FlyerElement? replaceTarget, String iconKey, {String? color}) {
    if (replaceTarget != null) {
      _pushUndo();
      setState(() {
        replaceTarget.iconKey = iconKey;
        if (color != null) replaceTarget.shapeColor = color;
      });
      _markDirty();
    } else {
      _addIconElement(iconKey, color: color ?? '#1B2A4A');
    }
  }

  /// Icon Library + AI Icon Finder -- "different shapes ... jaha apni
  /// marzi se logo banaya ja sake" needed more than 6 hand-drawn shapes;
  /// this is the other half of that ask, plus the one AI-integrated
  /// tool from this pass: type a concept, the real configured AI
  /// provider (POST /ai/find-icon) picks the closest match from the
  /// curated set and a fitting colour, one tap to drop it on the canvas.
  ///
  /// [replaceTarget] set (from an icon element's own "change icon"
  /// button) swaps that element's icon in place instead of adding a new
  /// one -- same picker UI, different outcome, so there's exactly one
  /// icon-choosing surface to build and maintain rather than two.
  Future<void> _openIconPicker({FlyerElement? replaceTarget}) async {
    final searchCtrl = TextEditingController();
    bool searching = false;
    String? searchError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetDragHandle(),
                Text('Add an icon', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Describe one, e.g. "graduation cap"',
                          prefixIcon: Icon(Icons.auto_awesome, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) async {
                          if (searchCtrl.text.trim().isEmpty) return;
                          setSheetState(() {
                            searching = true;
                            searchError = null;
                          });
                          try {
                            final result = await _api.aiFindIcon(
                              searchCtrl.text.trim(),
                              kFlyerIconLibrary.keys.toList(),
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              _applyIconChoice(replaceTarget, result['iconKey'] as String, color: result['color'] as String?);
                            }
                          } catch (e) {
                            setSheetState(() {
                              searching = false;
                              searchError = 'Could not find a match: $e';
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (searching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(searchError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                const Text('Or pick one', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: kFlyerIconLibrary.entries.map((e) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyIconChoice(replaceTarget, e.key);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(e.value, size: 22),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _shapePreviewIcon(String kind) {
    switch (kind) {
      case 'circle':
        return Icons.circle_outlined;
      case 'triangle':
        return Icons.change_history;
      case 'line':
        return Icons.horizontal_rule;
      case 'arrow':
        return Icons.arrow_forward;
      case 'star':
        return Icons.star_border;
      case 'rect':
      default:
        return Icons.crop_square;
    }
  }

  // Canva-parity Phase A -- one searchable "Elements" panel replacing the
  // 4 separate Shape/Icon/SVG/Assets toolbar entry points, tabbed rather
  // than 4 different bottom sheets a user had to already know to look
  // for individually. Each tab reuses the exact same underlying add/
  // insert logic those 4 buttons always called (_applyIconChoice/
  // _addShapeElement/_importSvgElement/_insertAsset) -- this is a UI
  // consolidation, not a rewrite of any of them, so none of their
  // existing behaviour (AI icon search's replaceTarget variant, SVG
  // sanitization, asset upload/delete) changes.
  Future<void> _openElementsPanel() async {
    var search = '';
    List<Map<String, dynamic>> assets = [];
    var assetsLoading = true;
    String? assetsError;
    Timer? debounce;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.read<AppearanceSettings>().cornerRadius.clamp(0, 24))),
      ),
      builder: (ctx) => DefaultTabController(
        length: 4,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> loadAssets() async {
              try {
                final result =
                    await _api.getTenantAssets(search: search.isEmpty ? null : search);
                if (!ctx.mounted) return;
                setSheetState(() {
                  assets = result;
                  assetsLoading = false;
                  assetsError = null;
                });
              } catch (e) {
                if (!ctx.mounted) return;
                setSheetState(() {
                  assetsLoading = false;
                  assetsError = e.toString();
                });
              }
            }

            if (assetsLoading && assetsError == null && assets.isEmpty) {
              // Kick off the initial load exactly once -- this builder
              // re-runs on every setSheetState, so this guard (not
              // initState, since StatefulBuilder has none) is what keeps
              // it from re-fetching every rebuild.
              loadAssets();
            }

            final searchLower = search.toLowerCase();
            final filteredIcons = kFlyerIconLibrary.entries
                .where((e) => searchLower.isEmpty || e.key.toLowerCase().contains(searchLower))
                .toList();
            final filteredShapes = kFlyerShapeKindLabels.entries
                .where((e) => searchLower.isEmpty || e.value.toLowerCase().contains(searchLower))
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 16, right: 16, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetDragHandle(),
                    Row(
                      children: [
                        Text('Elements', style: Theme.of(ctx).textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          tooltip: 'Upload image to My Assets',
                          onPressed: () async {
                            final picked = await _imagePicker.pickImage(
                                source: ImageSource.gallery, imageQuality: 90);
                            if (picked == null) return;
                            try {
                              final created = await _api.uploadTenantAsset(
                                  filePath: picked.path, kind: 'image');
                              setSheetState(() => assets = [created, ...assets]);
                            } catch (e) {
                              _showSnack('Upload failed: $e');
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search icons, shapes, assets...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        setSheetState(() => search = v);
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 350), () {
                          setSheetState(() => assetsLoading = true);
                          loadAssets();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const TabBar(tabs: [
                      Tab(text: 'Icons'),
                      Tab(text: 'Shapes'),
                      Tab(text: 'SVG'),
                      Tab(text: 'My Assets'),
                    ]),
                    Expanded(
                      child: TabBarView(
                        children: [
                          filteredIcons.isEmpty
                              ? const Center(child: Text('No matching icons'))
                              : GridView.count(
                                  crossAxisCount: 6,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  children: filteredIcons.map((e) {
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _applyIconChoice(null, e.key);
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(e.value, size: 22),
                                      ),
                                    );
                                  }).toList(),
                                ),
                          GridView.count(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.3,
                            children: filteredShapes.map((e) {
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _addShapeElement(e.key);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(_shapePreviewIcon(e.key), size: 26),
                                      const SizedBox(height: 4),
                                      Text(e.value, style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.polyline, size: 40, color: Colors.grey),
                                const SizedBox(height: 12),
                                Text('Import a vector SVG file', style: TextStyle(color: Colors.grey.shade600)),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  icon: const Icon(Icons.upload_file),
                                  label: const Text('Import SVG'),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _importSvgElement();
                                  },
                                ),
                              ],
                            ),
                          ),
                          assetsLoading
                              ? const Center(child: CircularProgressIndicator())
                              : assetsError != null
                                  ? Center(child: Text('Could not load assets: $assetsError'))
                                  : assets.isEmpty
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Text(
                                              'No saved assets yet — save an SVG from its properties panel, or upload an image from the Asset Library.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: Colors.grey.shade600),
                                            ),
                                          ),
                                        )
                                      : GridView.builder(
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 4,
                                            mainAxisSpacing: 8,
                                            crossAxisSpacing: 8,
                                          ),
                                          itemCount: assets.length,
                                          itemBuilder: (gridCtx, i) {
                                            final asset = assets[i];
                                            return InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                _insertAsset(asset);
                                              },
                                              onLongPress: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (dctx) => AlertDialog(
                                                    title: const Text('Remove asset?'),
                                                    content: const Text(
                                                        'This only removes it from your Asset Library.'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () => Navigator.pop(dctx, false),
                                                          child: const Text('Cancel')),
                                                      FilledButton(
                                                          onPressed: () => Navigator.pop(dctx, true),
                                                          child: const Text('Remove')),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  try {
                                                    await _api.deleteTenantAsset(asset['id'].toString());
                                                    setSheetState(() => assets =
                                                        assets.where((a) => a['id'] != asset['id']).toList());
                                                  } catch (e) {
                                                    _showSnack('Could not remove: $e');
                                                  }
                                                }
                                              },
                                              child: _assetThumbnail(asset),
                                            );
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
        ),
      ),
    );
    debounce?.cancel();
  }

  Widget _assetThumbnail(Map<String, dynamic> asset) {
    final kind = asset['kind']?.toString();
    Widget content;
    if (kind == 'svg' && asset['svg_data'] != null) {
      content = SvgPicture.string(asset['svg_data'].toString(), fit: BoxFit.contain);
    } else if (asset['asset_url'] != null) {
      content = Image.network(
        asset['asset_url'].toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    } else {
      content = const Icon(Icons.image_not_supported, color: Colors.grey);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      child: content,
    );
  }

  void _insertAsset(Map<String, dynamic> asset) {
    if (asset['kind']?.toString() == 'svg') {
      final svgData = asset['svg_data']?.toString();
      if (svgData == null) return;
      final size = math.min(_canvasWidth, _canvasHeight) * 0.4;
      _addElement(FlyerElement(
        id: _newId(),
        type: FlyerElementType.svg,
        x: (_canvasWidth - size) / 2,
        y: (_canvasHeight - size) / 2,
        width: size,
        height: size,
        svgData: svgData,
        zIndex: _nextZIndex(),
      ));
      return;
    }
    final url = asset['asset_url']?.toString();
    if (url == null) {
      _showSnack('This asset\'s file is no longer available');
      return;
    }
    final size = _canvasWidth * 0.6;
    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.image,
      x: (_canvasWidth - size) / 2,
      y: (_canvasHeight - size) / 2,
      width: size,
      height: size,
      url: url,
      zIndex: _nextZIndex(),
    ));
  }

  Future<void> _saveSvgToLibrary(FlyerElement el) async {
    if (el.svgData == null || el.svgData!.isEmpty) return;
    final labelCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save to Asset Library'),
        content: TextField(
          controller: labelCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Label (optional)', border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.saveSvgAsset(
        el.svgData!,
        label: labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
      );
      _showSnack('Saved to Asset Library');
    } catch (e) {
      _showSnack('Could not save: $e');
    }
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
                leading: _backgroundColor == 'transparent'
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: ClipOval(child: CustomPaint(painter: const CheckerboardPainter(cellSize: 7))),
                      )
                    : Container(
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
              if (widget.isLogoMode)
                ListTile(
                  leading: Icon(
                    _backgroundColor == 'transparent' ? Icons.check_circle : Icons.circle_outlined,
                    color: _backgroundColor == 'transparent' ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: const Text('Transparent background'),
                  subtitle: const Text('Recommended -- a logo usually composites onto other designs'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (_projectId == null) return;
                    setState(() => _backgroundColor = 'transparent');
                    _markDirty();
                    try {
                      await _api.updateFlyerProject(_projectId!, backgroundColor: 'transparent');
                    } catch (e) {
                      _showSnack('Could not save background: $e');
                    }
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
              decoration: InputDecoration(
                hintText: widget.isLogoMode
                    ? 'e.g. "Medical education consultancy, navy and gold, a graduation-cap mark"'
                    : 'e.g. "MBBS admission open, navy and gold, urgent tone"',
                border: const OutlineInputBorder(),
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
      // Logo Studio gets a dedicated logo-composition prompt (icon + brand
      // mark + minimal text, 2-4 elements) instead of the flyer prompt's
      // promotional-layout style (headline/body/image placeholder) --
      // reusing the flyer endpoint here would produce results that don't
      // fit a logo at all. Both stay real, editable canvas_json though --
      // same "propose, don't auto-save" validated pipeline either way.
      final result = widget.isLogoMode
          ? await _api.generateLogoAI(_projectId!, prompt, kFlyerIconLibrary.keys.toList())
          : await _api.generateFlyerAI(_projectId!, prompt);
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

  /// Logo Studio's "done" action -- captures the canvas exactly like
  /// _exportAndShare, but saves straight into the tenant's Brand Logos
  /// library (the same upload endpoint the Upload and AI-Generate logo
  /// flows already use) instead of opening the OS share sheet. A
  /// transparent background here really does export as a transparent
  /// PNG -- toImage() captures actual alpha, the checkerboard shown
  /// while editing is a sibling widget outside this RepaintBoundary,
  /// never part of what gets captured.
  Future<void> _saveAsLogo() async {
    if (_projectId == null) return;
    setState(() {
      _selectedId = null;
      _exporting = true;
    });
    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final bytes = await _captureCanvasBytes();
      if (bytes == null) return;
      final file = await _writeCanvasPngFile(bytes);
      await file.writeAsBytes(bytes);

      await _api.uploadTenantLogo(filePath: file.path, label: _title, isDefault: false);

      try {
        await _api.uploadFlyerRender(_projectId!, bytes);
      } catch (_) {
        // Non-fatal -- the logo library save above is what matters here.
      }

      if (mounted) {
        _showSnack('Saved to Brand Logos');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('Could not save to Brand Logos: $e');
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

  /// Real multi-format export -- JPG/WebP/Favicon via the backend's sharp
  /// pipeline (POST /flyer-projects/:id/export), on top of the plain-PNG
  /// capture every other export path here uses. "Never rename one file
  /// type as another" (master spec §17): each format is a genuine
  /// conversion, not the same PNG bytes wearing a different extension --
  /// see backend/routes/flyerProjects.js for the sharp calls and the
  /// hand-rolled PNG-in-ICO container for 'favicon'.
  Future<void> _showExportFormatSheet() async {
    if (_projectId == null) return;
    final choice = await showModalBottomSheet<String>(
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
              leading: const Icon(Icons.image_outlined),
              title: const Text('JPG'),
              subtitle: const Text('Smaller file, no transparency'),
              onTap: () => Navigator.pop(ctx, 'jpg'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('WebP'),
              subtitle: const Text('Smaller file, keeps transparency'),
              onTap: () => Navigator.pop(ctx, 'webp'),
            ),
            ListTile(
              leading: const Icon(Icons.web),
              title: const Text('Favicon (.ico)'),
              subtitle: const Text('32×32, for a website tab icon'),
              onTap: () => Navigator.pop(ctx, 'favicon'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _exportAsFormat(choice);
  }

  Future<void> _exportAsFormat(String format) async {
    if (_projectId == null) return;
    setState(() {
      _selectedId = null;
      _exporting = true;
    });
    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final pngBytes = await _captureCanvasBytes();
      if (pngBytes == null) return;

      final converted = await _api.exportFlyerFormat(
        _projectId!,
        pngBytes,
        format,
        width: format == 'favicon' ? 32 : null,
        height: format == 'favicon' ? 32 : null,
      );

      final ext = format == 'favicon' ? 'ico' : format;
      final dir = await getTemporaryDirectory();
      final safeTitle = _title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
      final file = File('${dir.path}/$safeTitle-${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(converted);

      await Share.shareXFiles([XFile(file.path)], text: _title);
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Logo Variations (master spec §15) -- mechanical transforms over the
  /// existing document model, deliberately NOT new AI calls: a variant is
  /// a colour/composition rule applied to the current elements, not a
  /// fresh generation that could drift from the original mark. Each
  /// variant becomes its own saved project (via the real duplicate
  /// endpoint, so it's independently editable/reopenable afterwards),
  /// linked back to this one only by both having started from the same
  /// canvas -- there's no separate "variant group" concept to keep in
  /// sync, which also means a variant surviving further hand-editing is
  /// just... editing a normal project, no special-casing needed anywhere
  /// else in the app.
  Future<void> _generateVariants() async {
    if (_projectId == null || _elements.isEmpty) {
      _showSnack('Add some elements to the logo first');
      return;
    }
    final choice = await showModalBottomSheet<String>(
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Generate variant', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_symbols_outlined),
              title: const Text('Icon only'),
              subtitle: const Text('Drops text -- for a social avatar / favicon'),
              onTap: () => Navigator.pop(ctx, 'icon_only'),
            ),
            ListTile(
              leading: const Icon(Icons.title),
              title: const Text('Text only (wordmark)'),
              subtitle: const Text('Drops the icon/shape mark'),
              onTap: () => Navigator.pop(ctx, 'text_only'),
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.black),
              title: const Text('Monochrome — black'),
              onTap: () => Navigator.pop(ctx, 'mono_black'),
            ),
            ListTile(
              leading: Icon(Icons.circle, color: Colors.grey.shade200),
              title: const Text('Monochrome — white'),
              subtitle: const Text('For a dark-background use'),
              onTap: () => Navigator.pop(ctx, 'mono_white'),
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark-background version'),
              subtitle: const Text('White elements on a navy canvas'),
              onTap: () => Navigator.pop(ctx, 'dark_bg'),
            ),
            ListTile(
              leading: const Icon(Icons.light_mode_outlined),
              title: const Text('Light-background version'),
              subtitle: const Text('Navy elements on a white canvas'),
              onTap: () => Navigator.pop(ctx, 'light_bg'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;

    setState(() => _saving = true);
    try {
      final duplicated = await _api.duplicateFlyerProject(_projectId!);
      final newId = duplicated['id']?.toString();
      if (newId == null) throw Exception('Could not create a variant project');

      List<FlyerElement> variantElements;
      String? bgOverride;
      switch (choice) {
        case 'icon_only':
          variantElements =
              _elements.where((e) => e.type != FlyerElementType.text).map((e) => e.clone()).toList();
          break;
        case 'text_only':
          variantElements =
              _elements.where((e) => e.type == FlyerElementType.text).map((e) => e.clone()).toList();
          break;
        case 'mono_black':
          variantElements = _recolorAllElements(_elements, '#000000');
          break;
        case 'mono_white':
          variantElements = _recolorAllElements(_elements, '#FFFFFF');
          break;
        case 'dark_bg':
          variantElements = _recolorAllElements(_elements, '#FFFFFF');
          bgOverride = '#1B2A4A';
          break;
        case 'light_bg':
          variantElements = _recolorAllElements(_elements, '#1B2A4A');
          bgOverride = '#FFFFFF';
          break;
        default:
          variantElements = _elements.map((e) => e.clone()).toList();
      }

      await _api.updateFlyerProjectCanvas(newId, variantElements.map((e) => e.toJson()).toList());
      if (bgOverride != null) {
        await _api.updateFlyerProject(newId, backgroundColor: bgOverride);
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FlyerStudioScreen(projectId: newId, isLogoMode: widget.isLogoMode),
        ),
      );
    } catch (e) {
      _showSnack('Could not generate variant: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Forces every element's colour to [hex] -- text.color, shape/icon's
  /// shapeColor, and an SVG element's recolour tint (turning svgRecolor on
  /// if it wasn't already, since an un-recoloured multi-colour SVG can't
  /// meaningfully participate in a one-colour monochrome variant).
  /// Images/logos/QR codes are left untouched -- there's no single
  /// "colour" to force on a photo, and forcing a QR's colours here would
  /// silently desync it from the fg/bg it was actually generated with.
  List<FlyerElement> _recolorAllElements(List<FlyerElement> source, String hex) {
    return source.map((e) {
      final copy = e.clone();
      switch (copy.type) {
        case FlyerElementType.text:
          copy.color = hex;
          break;
        case FlyerElementType.shape:
        case FlyerElementType.icon:
          copy.shapeColor = hex;
          break;
        case FlyerElementType.svg:
          copy.svgRecolor = true;
          copy.shapeColor = hex;
          break;
        case FlyerElementType.chart:
        case FlyerElementType.drawing:
          copy.shapeColor = hex;
          break;
        case FlyerElementType.image:
        case FlyerElementType.logo:
        case FlyerElementType.qrcode:
          break;
      }
      return copy;
    }).toList();
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
                if (v == 'exportFormat') _showExportFormatSheet();
                if (v == 'variants') _generateVariants();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'layers', child: Text('Layers')),
                const PopupMenuItem(value: 'background', child: Text('Background & size')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'save', child: Text('Save now')),
                const PopupMenuItem(
                    value: 'exportAll', child: Text('Export all sizes (Story/Post/A4...)')),
                const PopupMenuItem(
                    value: 'exportFormat', child: Text('Export as (JPG/WebP/Favicon)')),
                if (widget.isLogoMode)
                  const PopupMenuItem(
                      value: 'variants', child: Text('Generate variant (mono/dark/icon-only...)')),
              ],
            ),
          ],
        ),
        // Save/Share used to be a Scaffold floatingActionButton, which
        // floats at a fixed screen position with no idea the bottom
        // toolbar (a normal Column child, not a bottomNavigationBar
        // slot) exists -- on Logo Studio's longer "Save to Brand Logos"
        // label it visibly sat on top of and hid several toolbar icons.
        // Making it a real block-level row in the Column instead (see
        // _buildActionBar below) means it can never overlap anything;
        // this fixes the same latent overlap risk for Flyer Studio's
        // shorter "Share" label too, since both share this exact layout.
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : Column(
                    children: [
                      Expanded(child: _buildCanvasArea()),
                      // Multi-page designs (Canva-parity Phase H). Logo
                      // Studio reuses this same screen for a single
                      // artboard mark -- multi-page has no meaning there
                      // (Canva itself treats a logo as one canvas), so
                      // it's hidden in that mode rather than offering a
                      // control that doesn't do anything sensible.
                      if (!widget.isLogoMode && !_exporting) _buildPageBar(),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: Alignment.bottomCenter,
                        child: _drawMode
                            ? _buildDrawToolBar()
                            : (_groupSelectMode
                                ? (_groupSelectedIds.isNotEmpty
                                    ? _buildGroupActionBar()
                                    : const SizedBox(width: double.infinity, height: 0))
                                : (selected != null
                                    ? _buildStylePanel(selected)
                                    : const SizedBox(width: double.infinity, height: 0))),
                      ),
                      _buildActionBar(),
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
            // Checkerboard sits BEHIND the RepaintBoundary, as a sibling
            // rather than inside it, so toImage() export never captures
            // it -- only genuinely-transparent pixels do.
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_backgroundColor == 'transparent')
                  SizedBox(
                    width: displayW,
                    height: displayH,
                    child: CustomPaint(painter: const CheckerboardPainter()),
                  ),
                RepaintBoundary(
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
                                } else if (el.type == FlyerElementType.qrcode) {
                                  _selectElement(el.id);
                                  _editQrCodeData(el);
                                } else if (el.type == FlyerElementType.chart) {
                                  _selectElement(el.id);
                                  _editChartData(el);
                                } else if (el.type == FlyerElementType.drawing) {
                                  _selectElement(el.id);
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
                        // Draw mode's capture surface -- deliberately the
                        // LAST (topmost) child here, opaque-hit-testing,
                        // so while active it swallows every pan gesture
                        // over the canvas before any element underneath
                        // ever sees it (Stack hit-tests in reverse paint
                        // order). Only present in the tree at all while
                        // _drawMode is on, so normal drag/resize/select
                        // is completely unaffected the rest of the time.
                        if (_drawMode && !_exporting)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) =>
                                  setState(() => _liveStrokePoints = [details.localPosition]),
                              onPanUpdate: (details) => setState(
                                  () => _liveStrokePoints = [..._liveStrokePoints, details.localPosition]),
                              onPanEnd: (_) => _finishDrawing(scale),
                              child: CustomPaint(
                                painter: LiveStrokePainter(
                                  points: _liveStrokePoints,
                                  color: _drawColor,
                                  strokeWidth: _drawStrokeWidth * scale,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
              ],
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
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanStart: (_) => _pushUndo(),
                onPanUpdate: (details) => _groupResize(details.delta / scale),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: context.watch<AppearanceSettings>().primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                    ),
                    child: const Icon(Icons.open_in_full, size: 14, color: Colors.white),
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

  /// The former FloatingActionButton, now a normal full-width block
  /// above the toolbar instead of an OS-level overlay -- see the "Save/
  /// Share" comment at the Scaffold's body for why.
  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: FilledButton.icon(
          onPressed: _exporting ? null : (widget.isLogoMode ? _saveAsLogo : _showShareOptions),
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(widget.isLogoMode ? Icons.check : Icons.share, size: 18),
          label: Text(widget.isLogoMode ? 'Save to Brand Logos' : 'Share'),
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
              // Grouped into "insert content" / "canvas tools" /
              // "selection actions" with a thin divider between each --
              // a flat, undifferentiated row of 15 icons read as generic/
              // cheap; grouping mirrors how Canva's own toolbar clusters
              // by purpose, and gives the eye a scan pattern instead of
              // one long strip.
              _toolbarButton(Icons.text_fields, 'Text', _addTextElement, appearance),
              _toolbarButton(
                  Icons.add_photo_alternate, 'Photo', _addImageElement, appearance),
              _toolbarButton(Icons.workspace_premium, 'Logo', _addLogoElement, appearance),
              // Canva-parity Phase A -- Shape/Icon/SVG/Assets used to be
              // 4 separate toolbar buttons, each opening its own bottom
              // sheet with no idea the other 3 existed. One "Elements"
              // button now opens a single searchable, tabbed panel
              // covering all 4 (see _openElementsPanel).
              _toolbarButton(Icons.category_outlined, 'Elements', _openElementsPanel, appearance),
              _toolbarButton(Icons.qr_code, 'QR Code', _addQrCodeElement, appearance),
              _toolbarButton(Icons.bar_chart, 'Chart', _addChartElement, appearance),
              _toolbarDivider(appearance),
              _toolbarToggleButton(Icons.gesture, 'Draw', _drawMode, _toggleDrawMode, appearance),
              _toolbarButton(Icons.grid_view_outlined, 'Grid', _addPhotoGrid, appearance),
              _toolbarButton(
                  Icons.wallpaper, 'Background', _showBackgroundSheet, appearance),
              _toolbarButton(Icons.layers, 'Layers', _showLayersSheet, appearance),
              _toolbarToggleButton(
                  Icons.select_all, 'Group', _groupSelectMode, _toggleGroupSelectMode, appearance),
              _toolbarDivider(appearance),
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
    return _toolbarButtonChrome(
      icon: icon,
      label: label,
      active: active,
      appearance: appearance,
      onTap: () {
        if (appearance.haptics) HapticFeedback.selectionClick();
        onTap();
      },
    );
  }

  Widget _toolbarButton(
      IconData icon, String label, VoidCallback? onTap, AppearanceSettings appearance) {
    return _toolbarButtonChrome(
      icon: icon,
      label: label,
      active: false,
      disabled: onTap == null,
      appearance: appearance,
      onTap: onTap == null
          ? null
          : () {
              if (appearance.haptics) HapticFeedback.selectionClick();
              onTap();
            },
    );
  }

  /// Shared visual chrome for every toolbar button (both the plain
  /// action kind and the toggle kind) -- a soft tinted icon chip rather
  /// than a bare Icon floating over a label, the concrete fix for
  /// "tools icon in flyer and logo designer are also very cheap in case
  /// of looks" (direct user feedback). An active/toggled-on button gets
  /// a filled chip + a subtle glow shadow instead of just a flat colour
  /// swap, so the pressed/on state actually reads as "on" at a glance.
  Widget _toolbarButtonChrome({
    required IconData icon,
    required String label,
    required bool active,
    required AppearanceSettings appearance,
    required VoidCallback? onTap,
    bool disabled = false,
  }) {
    final color = disabled ? Colors.grey.shade400 : appearance.primaryColor;
    return TouchFeedbackWrapper(
      appearance: appearance,
      radius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: disabled
                      ? Colors.grey.withValues(alpha: 0.06)
                      : color.withValues(alpha: active ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: active
                      ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: 0.5)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  /// A thin, low-contrast separator between toolbar groups (insert
  /// content / canvas tools / selection actions) -- lets the eye parse
  /// 15 icons as 3 short clusters instead of one undifferentiated strip.
  Widget _toolbarDivider(AppearanceSettings appearance) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: appearance.primaryColor.withValues(alpha: 0.12),
    );
  }

  // Canva-parity Phase E -- pen colour + thickness, live for the next
  // stroke (each finished stroke bakes in whatever these were set to at
  // the moment it was drawn; changing them here doesn't retroactively
  // recolour strokes already on the canvas, same as every other design
  // tool's pen settings).
  Widget _buildDrawToolBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: context.watch<AppearanceSettings>().primaryColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.gesture, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('Draw mode -- drag on the canvas', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          GestureDetector(
            onTap: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(initial: _drawColor, title: 'Pen colour'),
              );
              if (picked != null) setState(() => _drawColor = picked);
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _drawColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.line_weight, size: 16, color: Colors.grey),
          SizedBox(
            width: 100,
            child: Slider(
              value: _drawStrokeWidth,
              min: 1,
              max: 20,
              onChanged: (v) => setState(() => _drawStrokeWidth = v),
            ),
          ),
        ],
      ),
    );
  }

  // Canva-parity Phase H -- a slim strip of page chips, always visible
  // (even for a single page) so "add a page" stays discoverable rather
  // than hidden behind a menu. Deliberately simple numbered chips, not
  // live-rendered thumbnails -- a thumbnail-per-page preview would need
  // its own RepaintBoundary/toImage pass per page on every edit, real
  // rendering cost for a feature whose core value (multiple pages in one
  // design, each independently editable) doesn't depend on it.
  Widget _buildPageBar() {
    final appearance = context.watch<AppearanceSettings>();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: appearance.primaryColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final active = i == _activePageIndex;
                return GestureDetector(
                  onTap: () => _switchToPage(i),
                  onLongPress: _pages.length > 1 ? () => _deletePage(i) : null,
                  child: Container(
                    width: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? appearance.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
                      border: Border.all(
                          color: active ? appearance.primaryColor : Colors.grey.shade400, width: active ? 1.5 : 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active ? appearance.primaryColor : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined, size: 20),
            tooltip: 'Add page',
            onPressed: _addPage,
          ),
        ],
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
                    if (el.type == FlyerElementType.icon) ..._iconControls(el),
                    if (el.type == FlyerElementType.svg) ..._svgControls(el),
                    if (el.type == FlyerElementType.qrcode) ..._qrCodeControls(el),
                    if (el.type == FlyerElementType.chart) ..._chartControls(el),
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
          IconButton(
            icon: Icon(Icons.format_color_text,
                color: el.outlineColor != null ? activeColor : null),
            tooltip: 'Outline',
            onPressed: () async {
              if (el.outlineColor != null) {
                setState(() => el.outlineColor = null);
                _markDirty();
                return;
              }
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => const ColorPickerDialog(
                    initial: Colors.black, title: 'Outline Colour'),
              );
              if (picked != null) {
                setState(() {
                  el.outlineColor = flyerColorToHex(picked);
                  if (el.outlineWidth <= 0) el.outlineWidth = 2;
                });
                _markDirty();
              }
            },
          ),
        ],
      ),
      if (el.outlineColor != null)
        _sliderRow(
          icon: Icons.line_weight,
          value: el.outlineWidth.clamp(0.5, 12.0),
          min: 0.5,
          max: 12.0,
          onChanged: (v) {
            setState(() => el.outlineWidth = v);
            _markDirty();
          },
        ),
      _sliderRow(
        icon: Icons.waves,
        value: el.curveAmount.clamp(-100.0, 100.0),
        min: -100.0,
        max: 100.0,
        onChanged: (v) {
          setState(() => el.curveAmount = v);
          _markDirty();
        },
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
      // Frames (Canva-parity Phase D) -- masks this image/logo into a
      // shape via the same shapeKind field the 'shape' element type
      // already uses. 'None' (shapeKind 'rect') keeps the plain
      // rounded-rect behaviour every image had before frames existed.
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: kFrameShapeLabels.entries.map((e) {
          final selected = (el.shapeKind.isEmpty ? 'rect' : el.shapeKind) == e.key;
          return ChoiceChip(
            label: Text(e.value),
            selected: selected,
            onSelected: (_) {
              setState(() => el.shapeKind = e.key);
              _markDirty();
            },
          );
        }).toList(),
      ),
      if (el.shapeKind == 'rect' || el.shapeKind.isEmpty)
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
      // Photo adjustments (Canva-parity Phase C) -- real ColorFilter.matrix
      // math (see imageAdjustmentMatrix in flyer_canvas_element_widget.dart),
      // not a fake/cosmetic control.
      Row(
        children: [
          const Text('Adjust', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const Spacer(),
          if (el.brightness != 0 || el.contrast != 0 || el.saturation != 1)
            TextButton(
              onPressed: () {
                setState(() {
                  el.brightness = 0;
                  el.contrast = 0;
                  el.saturation = 1;
                });
                _markDirty();
              },
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      _sliderRow(
        icon: Icons.wb_sunny_outlined,
        value: el.brightness.clamp(-100, 100),
        min: -100,
        max: 100,
        onChanged: (v) {
          setState(() => el.brightness = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.contrast,
        value: el.contrast.clamp(-100, 100),
        min: -100,
        max: 100,
        onChanged: (v) {
          setState(() => el.contrast = v);
          _markDirty();
        },
      ),
      _sliderRow(
        icon: Icons.invert_colors_outlined,
        value: el.saturation.clamp(0, 2),
        min: 0,
        max: 2,
        onChanged: (v) {
          setState(() => el.saturation = v);
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
          PopupMenuButton<String>(
            tooltip: 'Shape kind',
            initialValue: el.shapeKind,
            onSelected: (kind) {
              setState(() => el.shapeKind = kind);
              _markDirty();
            },
            itemBuilder: (ctx) => kFlyerShapeKindLabels.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(kFlyerShapeKindLabels[el.shapeKind] ?? 'Rectangle'),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
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
      if (el.shapeKind == 'rect')
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

  List<Widget> _iconControls(FlyerElement el) {
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
            tooltip: 'Icon colour',
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(initial: flyerHexToColor(el.shapeColor), title: 'Icon Colour'),
              );
              if (picked != null) {
                setState(() => el.shapeColor = flyerColorToHex(picked));
                _markDirty();
              }
            },
          ),
          IconButton(
            icon: Icon(kFlyerIconLibrary[el.iconKey] ?? Icons.star),
            tooltip: 'Change icon',
            onPressed: () => _openIconPicker(replaceTarget: el),
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
    ];
  }

  List<Widget> _svgControls(FlyerElement el) {
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Replace SVG',
            onPressed: () => _importSvgElement(replaceTarget: el),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Save to Asset Library',
            onPressed: () => _saveSvgToLibrary(el),
          ),
          const Spacer(),
          const Text('Force single colour', style: TextStyle(fontSize: 12)),
          Switch(
            value: el.svgRecolor,
            onChanged: (v) {
              setState(() => el.svgRecolor = v);
              _markDirty();
            },
          ),
        ],
      ),
      if (el.svgRecolor)
        Row(
          children: [
            const Text('Colour', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
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
              tooltip: 'SVG colour',
              onPressed: () async {
                final picked = await showDialog<Color>(
                  context: context,
                  builder: (_) =>
                      ColorPickerDialog(initial: flyerHexToColor(el.shapeColor), title: 'SVG Colour'),
                );
                if (picked != null) {
                  setState(() => el.shapeColor = flyerColorToHex(picked));
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
    ];
  }

  // Canva-parity Phase G -- a QR code element renders through the same
  // image codepath as a photo/logo (see FlyerCanvasElementWidget), but its
  // controls edit the encoded data + colours and regenerate the PNG
  // server-side rather than letting the user pick a replacement photo.
  List<Widget> _qrCodeControls(FlyerElement el) {
    return [
      Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit QR data'),
            onPressed: () => _editQrCodeData(el),
          ),
          const Spacer(),
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
            tooltip: 'Foreground colour',
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(
                    initial: flyerHexToColor(el.color), title: 'QR Foreground'),
              );
              if (picked == null) return;
              setState(() => el.color = flyerColorToHex(picked));
              await _regenerateQrCode(el);
            },
          ),
          IconButton(
            icon: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: flyerHexToColor(el.backgroundColor ?? '#FFFFFF'),
                border: Border.all(color: Colors.grey.shade400),
                shape: BoxShape.circle,
              ),
            ),
            tooltip: 'Background colour',
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => ColorPickerDialog(
                    initial: flyerHexToColor(el.backgroundColor ?? '#FFFFFF'),
                    title: 'QR Background'),
              );
              if (picked == null) return;
              setState(() => el.backgroundColor = flyerColorToHex(picked));
              await _regenerateQrCode(el);
            },
          ),
        ],
      ),
      _sliderRow(
        icon: Icons.rounded_corner,
        value: el.cornerRadius.clamp(0.0, 60.0),
        min: 0,
        max: 60,
        onChanged: (v) {
          setState(() => el.cornerRadius = v);
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
    ];
  }

  Future<String?> _promptQrData({String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR code data'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'URL or text to encode'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Future<void> _addQrCodeElement() async {
    if (_projectId == null) return;
    final data = await _promptQrData();
    if (data == null || data.isEmpty) return;
    setState(() => _saving = true);
    try {
      final result = await _api.generateFlyerQrCode(_projectId!, data);
      _addElement(FlyerElement(
        id: _newId(),
        type: FlyerElementType.qrcode,
        x: _canvasWidth * 0.3,
        y: _canvasHeight * 0.3,
        width: _canvasWidth * 0.4,
        height: _canvasWidth * 0.4,
        text: data,
        url: result['image_url']?.toString(),
        fit: 'contain',
        color: '#000000',
        backgroundColor: '#FFFFFF',
        zIndex: _nextZIndex(),
      ));
    } catch (e) {
      _showSnack('QR code generation failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editQrCodeData(FlyerElement el) async {
    if (_projectId == null) return;
    final data = await _promptQrData(initial: el.text ?? '');
    if (data == null || data.isEmpty) return;
    _pushUndo();
    setState(() => el.text = data);
    await _regenerateQrCode(el);
  }

  Future<void> _regenerateQrCode(FlyerElement el) async {
    if (_projectId == null || el.text == null || el.text!.isEmpty) return;
    setState(() => _saving = true);
    try {
      final result = await _api.generateFlyerQrCode(
        _projectId!,
        el.text!,
        fg: el.color,
        bg: el.backgroundColor,
      );
      setState(() => el.url = result['image_url']?.toString());
      _markDirty();
    } catch (e) {
      _showSnack('QR code generation failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Canva-parity Phase F -- a small data-entry dialog (chart kind + a
  // growing list of label/value rows) shared by "add a chart" and "edit
  // this chart's data". Returns null on cancel; on save, returns at least
  // one row (rows with a blank label AND blank value are dropped, but if
  // that would leave zero rows the dialog blocks save with a SnackBar
  // rather than producing an element with no data to render).
  Future<({String kind, List<String> labels, List<double> values})?> _promptChartData({
    String initialKind = 'bar',
    List<String>? initialLabels,
    List<double>? initialValues,
  }) async {
    var kind = initialKind;
    final labels = initialLabels ?? const ['A', 'B', 'C'];
    final values = initialValues ?? const [30.0, 60.0, 45.0];
    final labelControllers = List.generate(labels.length, (i) => TextEditingController(text: labels[i]));
    final valueControllers =
        List.generate(values.length, (i) => TextEditingController(text: values[i].toString()));

    final result = await showDialog<({String kind, List<String> labels, List<double> values})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Chart data'),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final k in ['bar', 'line', 'pie'])
                          ChoiceChip(
                            label: Text(k[0].toUpperCase() + k.substring(1)),
                            selected: kind == k,
                            onSelected: (_) => setDialogState(() => kind = k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < labelControllers.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: labelControllers[i],
                                decoration: const InputDecoration(labelText: 'Label', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: valueControllers[i],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Value', isDense: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () => setDialogState(() {
                                labelControllers.removeAt(i);
                                valueControllers.removeAt(i);
                              }),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add row'),
                      onPressed: () => setDialogState(() {
                        labelControllers.add(TextEditingController());
                        valueControllers.add(TextEditingController(text: '0'));
                      }),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  final outLabels = <String>[];
                  final outValues = <double>[];
                  for (var i = 0; i < labelControllers.length; i++) {
                    final l = labelControllers[i].text.trim();
                    final v = double.tryParse(valueControllers[i].text.trim());
                    if (l.isEmpty && v == null) continue;
                    outLabels.add(l);
                    outValues.add(v ?? 0);
                  }
                  if (outLabels.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Add at least one row with a value')));
                    return;
                  }
                  Navigator.pop(ctx, (kind: kind, labels: outLabels, values: outValues));
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
    for (final c in labelControllers) {
      c.dispose();
    }
    for (final c in valueControllers) {
      c.dispose();
    }
    return result;
  }

  Future<void> _addChartElement() async {
    final data = await _promptChartData();
    if (data == null) return;
    _addElement(FlyerElement(
      id: _newId(),
      type: FlyerElementType.chart,
      x: _canvasWidth * 0.15,
      y: _canvasHeight * 0.3,
      width: _canvasWidth * 0.7,
      height: _canvasWidth * 0.5,
      chartKind: data.kind,
      chartLabels: data.labels,
      chartValues: data.values,
      shapeColor: '#2563EB',
      zIndex: _nextZIndex(),
    ));
  }

  Future<void> _editChartData(FlyerElement el) async {
    final data = await _promptChartData(
      initialKind: el.chartKind,
      initialLabels: el.chartLabels,
      initialValues: el.chartValues,
    );
    if (data == null) return;
    _pushUndo();
    setState(() {
      el.chartKind = data.kind;
      el.chartLabels = data.labels;
      el.chartValues = data.values;
    });
    _markDirty();
  }

  List<Widget> _chartControls(FlyerElement el) {
    return [
      Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit data'),
            onPressed: () => _editChartData(el),
          ),
          const Spacer(),
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
            tooltip: el.chartKind == 'pie' ? 'Colour (bar/line only)' : 'Chart colour',
            onPressed: el.chartKind == 'pie'
                ? null
                : () async {
                    final picked = await showDialog<Color>(
                      context: context,
                      builder: (_) => ColorPickerDialog(
                          initial: flyerHexToColor(el.shapeColor), title: 'Chart Colour'),
                    );
                    if (picked != null) {
                      setState(() => el.shapeColor = flyerColorToHex(picked));
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
      case FlyerElementType.qrcode:
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
      case FlyerElementType.icon:
        content = Icon(kFlyerIconLibrary[el.iconKey] ?? Icons.star, color: flyerHexToColor(el.shapeColor), size: 22);
        break;
      case FlyerElementType.svg:
        content = (el.svgData != null && el.svgData!.isNotEmpty)
            ? SvgPicture.string(
                el.svgData!,
                fit: BoxFit.contain,
                colorFilter: el.svgRecolor
                    ? ColorFilter.mode(flyerHexToColor(el.shapeColor), BlendMode.srcIn)
                    : null,
                errorBuilder: (_, __, ___) => Icon(_iconFor(el.type), size: 18, color: Colors.grey),
              )
            : Icon(_iconFor(el.type), size: 18, color: Colors.grey);
        break;
      case FlyerElementType.chart:
        content = Icon(
          el.chartKind == 'pie'
              ? Icons.pie_chart
              : el.chartKind == 'line'
                  ? Icons.show_chart
                  : Icons.bar_chart,
          color: flyerHexToColor(el.shapeColor),
          size: 22,
        );
        break;
      case FlyerElementType.drawing:
        content = Icon(Icons.gesture, color: flyerHexToColor(el.shapeColor), size: 22);
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
      case FlyerElementType.icon:
        return Icons.emoji_symbols_outlined;
      case FlyerElementType.svg:
        return Icons.polyline;
      case FlyerElementType.qrcode:
        return Icons.qr_code;
      case FlyerElementType.chart:
        return Icons.bar_chart;
      case FlyerElementType.drawing:
        return Icons.gesture;
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
