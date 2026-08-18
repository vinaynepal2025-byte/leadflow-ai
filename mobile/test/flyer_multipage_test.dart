import 'package:flutter_test/flutter_test.dart';
import 'package:leadflow_ai/screens/flyer_studio/flyer_element.dart';

// Canva-parity Phase H (multi-page designs) touches the saved-data shape
// of every existing flyer/logo project in production, so this is the one
// piece of this feature where a bug could genuinely corrupt real user
// data. parsePagesFromCanvasJson/canvasJsonForPages are pure functions
// (no widget/BuildContext/network) specifically so they can be unit
// tested in isolation like this, independent of the full editor screen.
void main() {
  FlyerElement textEl(String id, String text) => FlyerElement(
        id: id,
        type: FlyerElementType.text,
        x: 10,
        y: 20,
        width: 100,
        height: 50,
        text: text,
      );

  group('parsePagesFromCanvasJson (loading)', () {
    test('empty canvas_json -> one empty page', () {
      final pages = parsePagesFromCanvasJson([]);
      expect(pages.length, 1);
      expect(pages[0], isEmpty);
    });

    test('legacy flat array of elements -> a single page holding them', () {
      final legacy = [
        {'id': 'a', 'type': 'text', 'x': 1.0, 'y': 2.0, 'width': 10.0, 'height': 5.0, 'text': 'Hello'},
        {'id': 'b', 'type': 'shape', 'x': 3.0, 'y': 4.0, 'width': 10.0, 'height': 5.0},
      ];
      final pages = parsePagesFromCanvasJson(legacy);
      expect(pages.length, 1, reason: 'a legacy project must load as exactly one page');
      expect(pages[0].length, 2);
      expect(pages[0][0].id, 'a');
      expect(pages[0][0].text, 'Hello');
      expect(pages[0][1].id, 'b');
      expect(pages[0][1].type, FlyerElementType.shape);
    });

    test('multi-page wrapped array -> multiple pages, each with its own elements', () {
      final wrapped = [
        {
          '__page': true,
          'elements': [
            {'id': 'p1a', 'type': 'text', 'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0, 'text': 'Page 1'}
          ],
        },
        {
          '__page': true,
          'elements': [
            {'id': 'p2a', 'type': 'text', 'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0, 'text': 'Page 2a'},
            {'id': 'p2b', 'type': 'text', 'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0, 'text': 'Page 2b'},
          ],
        },
      ];
      final pages = parsePagesFromCanvasJson(wrapped);
      expect(pages.length, 2);
      expect(pages[0].length, 1);
      expect(pages[0][0].text, 'Page 1');
      expect(pages[1].length, 2);
      expect(pages[1][0].text, 'Page 2a');
      expect(pages[1][1].text, 'Page 2b');
    });

    test('a page with no elements at all still parses (empty page in a multi-page design)', () {
      final wrapped = [
        {'__page': true, 'elements': []},
        {
          '__page': true,
          'elements': [
            {'id': 'x', 'type': 'text', 'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0}
          ],
        },
      ];
      final pages = parsePagesFromCanvasJson(wrapped);
      expect(pages.length, 2);
      expect(pages[0], isEmpty);
      expect(pages[1].length, 1);
    });
  });

  group('canvasJsonForPages (saving)', () {
    test('a single page saves back as the exact legacy flat-array shape, not wrapped', () {
      final pages = [
        [textEl('a', 'Hello'), textEl('b', 'World')],
      ];
      final json = canvasJsonForPages(pages);
      expect(json.length, 2, reason: 'flat array, not [{__page:true,...}]');
      expect(json[0].containsKey('__page'), isFalse);
      expect(json[0]['id'], 'a');
      expect(json[1]['id'], 'b');
    });

    test('an empty single page saves as an empty array, not [{__page:true,elements:[]}]', () {
      final json = canvasJsonForPages([[]]);
      expect(json, isEmpty);
    });

    test('multiple pages save as the wrapped shape with each page intact', () {
      final pages = [
        [textEl('a', 'Page1')],
        [textEl('b', 'Page2a'), textEl('c', 'Page2b')],
      ];
      final json = canvasJsonForPages(pages);
      expect(json.length, 2);
      expect(json[0]['__page'], true);
      expect((json[0]['elements'] as List).length, 1);
      expect(json[1]['__page'], true);
      expect((json[1]['elements'] as List).length, 2);
    });
  });

  group('round-trip (save then load again)', () {
    test('legacy flat array survives save+load unchanged in shape and content', () {
      final legacy = [
        {'id': 'a', 'type': 'text', 'x': 1.0, 'y': 2.0, 'width': 10.0, 'height': 5.0, 'text': 'Hello'},
      ];
      final pages = parsePagesFromCanvasJson(legacy);
      final savedJson = canvasJsonForPages(pages);
      // Must be indistinguishable from the original legacy shape -- no
      // '__page' marker anywhere, so nothing else that reads canvas_json
      // (AI generation, project duplication, a future re-load) ever sees
      // a format it doesn't expect for what is still a single-page design.
      expect(savedJson.every((e) => !e.containsKey('__page')), isTrue);
      final reloaded = parsePagesFromCanvasJson(savedJson);
      expect(reloaded.length, 1);
      expect(reloaded[0][0].text, 'Hello');
    });

    test('a genuinely multi-page design survives save+load with every page and element intact', () {
      final original = [
        [textEl('a', 'One')],
        [textEl('b', 'Two-a'), textEl('c', 'Two-b')],
        <FlyerElement>[],
      ];
      final saved = canvasJsonForPages(original);
      final reloaded = parsePagesFromCanvasJson(saved);
      expect(reloaded.length, 3);
      expect(reloaded[0].map((e) => e.text), ['One']);
      expect(reloaded[1].map((e) => e.text), ['Two-a', 'Two-b']);
      expect(reloaded[2], isEmpty);
    });

    test('an AI-generation-style flat response (no __page) loads as one page even '
        'when the project already had multiple pages saved previously', () {
      // Mirrors what the AI-generate endpoints return: always a flat
      // array (see backend/routes/flyerProjects.js), since AI generation
      // only ever produces one page's worth of content at a time.
      final aiResult = [
        {'id': 'ai1', 'type': 'text', 'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0, 'text': 'AI text'},
      ];
      final pages = parsePagesFromCanvasJson(aiResult);
      expect(pages.length, 1);
      expect(pages[0][0].text, 'AI text');
    });
  });
}
