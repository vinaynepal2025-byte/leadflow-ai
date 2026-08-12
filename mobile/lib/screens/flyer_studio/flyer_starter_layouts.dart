// Starter layouts for Flyer Studio v2 (Batch E).
//
// These are the spiritual successors to the old server-side SVG templates
// (backend/services/flyerTemplates.js). The critical difference: those were
// *fixed* — you filled in blanks and the server rendered exactly one shape.
// These are *starting points* — every element lands on the canvas as a
// normal FlyerElement and is immediately draggable, resizable, restylable,
// and deletable like anything the user added by hand. Nothing here is
// locked.
//
// Layouts are expressed against a 1080x1350 canvas (the app default). If a
// project uses different dimensions the elements still land proportionally
// sensibly, and the user can adjust — no layout math is hidden server-side
// anymore.

import 'flyer_element.dart';

class FlyerStarterLayout {
  final String id;
  final String name;
  final String description;
  final String backgroundColor;
  final List<Map<String, dynamic>> Function() build;

  const FlyerStarterLayout({
    required this.id,
    required this.name,
    required this.description,
    required this.backgroundColor,
    required this.build,
  });
}

String _uid(String seed, int i) => 'starter-$seed-$i';

// ---------------------------------------------------------------------
// 1. Offer Announcement — bold headline, highlighted offer band, contact
// ---------------------------------------------------------------------
List<Map<String, dynamic>> _offerAnnouncement() {
  const seed = 'offer';
  return [
    FlyerElement(
      id: _uid(seed, 0),
      type: FlyerElementType.text,
      x: 90, y: 90, width: 900, height: 50,
      text: 'YOUR CONSULTANCY NAME',
      fontSize: 30, fontFamily: 'SpaceGrotesk', color: '#FFFFFF',
      fontWeight: 'normal', textAlign: 'center', zIndex: 0,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 1),
      type: FlyerElementType.text,
      x: 80, y: 300, width: 920, height: 180,
      text: 'SPECIAL OFFER',
      fontSize: 72, fontFamily: 'Montserrat', color: '#FFFFFF',
      fontWeight: 'bold', textAlign: 'center', zIndex: 1,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 2),
      type: FlyerElementType.shape,
      x: 140, y: 600, width: 800, height: 220,
      shapeColor: '#FFFFFF', zIndex: 2,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 3),
      type: FlyerElementType.text,
      x: 160, y: 660, width: 760, height: 100,
      text: '50% OFF',
      fontSize: 60, fontFamily: 'Montserrat', color: '#1B2A4A',
      fontWeight: 'bold', textAlign: 'center', zIndex: 3,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 4),
      type: FlyerElementType.text,
      x: 100, y: 900, width: 880, height: 120,
      text: 'Limited seats available. Enrol before the deadline to lock this offer.',
      fontSize: 30, fontFamily: 'Inter', color: '#FFFFFF',
      fontWeight: 'normal', textAlign: 'center', zIndex: 4,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 5),
      type: FlyerElementType.text,
      x: 100, y: 1150, width: 880, height: 70,
      text: 'Call: +91 00000 00000',
      fontSize: 36, fontFamily: 'SpaceGrotesk', color: '#F5C518',
      fontWeight: 'bold', textAlign: 'center', zIndex: 5,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 6),
      type: FlyerElementType.logo,
      x: 460, y: 1240, width: 160, height: 80,
      fit: 'contain', zIndex: 6,
    ).toJson(),
  ];
}

// ---------------------------------------------------------------------
// 2. Admission Open — photo-led, feature list, strong CTA
// ---------------------------------------------------------------------
List<Map<String, dynamic>> _admissionOpen() {
  const seed = 'admission';
  return [
    FlyerElement(
      id: _uid(seed, 0),
      type: FlyerElementType.image,
      x: 0, y: 0, width: 1080, height: 520,
      fit: 'cover', zIndex: 0,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 1),
      type: FlyerElementType.text,
      x: 60, y: 570, width: 960, height: 130,
      text: 'ADMISSIONS OPEN 2026',
      fontSize: 62, fontFamily: 'Montserrat', color: '#0B1B3D',
      fontWeight: 'bold', textAlign: 'center', zIndex: 1,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 2),
      type: FlyerElementType.text,
      x: 80, y: 720, width: 920, height: 60,
      text: 'Top Recognised Universities',
      fontSize: 30, fontFamily: 'Poppins', color: '#C5A059',
      fontWeight: 'bold', textAlign: 'center', zIndex: 2,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 3),
      type: FlyerElementType.text,
      x: 110, y: 820, width: 860, height: 200,
      text: '• Direct admission guidance\n• Scholarship assistance\n• Complete documentation support\n• Visa & travel help',
      fontSize: 28, fontFamily: 'Inter', color: '#1A2B4C',
      fontWeight: 'normal', textAlign: 'left', zIndex: 3,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 4),
      type: FlyerElementType.shape,
      x: 140, y: 1070, width: 800, height: 110,
      shapeColor: '#0B1B3D', zIndex: 4,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 5),
      type: FlyerElementType.text,
      x: 160, y: 1095, width: 760, height: 70,
      text: 'APPLY TODAY — +91 00000 00000',
      fontSize: 34, fontFamily: 'SpaceGrotesk', color: '#FFFFFF',
      fontWeight: 'bold', textAlign: 'center', zIndex: 5,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 6),
      type: FlyerElementType.logo,
      x: 60, y: 1220, width: 140, height: 90,
      fit: 'contain', zIndex: 6,
    ).toJson(),
  ];
}

// ---------------------------------------------------------------------
// 3. Congratulations / Success Story — social-proof post
// ---------------------------------------------------------------------
List<Map<String, dynamic>> _successStory() {
  const seed = 'success';
  return [
    FlyerElement(
      id: _uid(seed, 0),
      type: FlyerElementType.text,
      x: 80, y: 110, width: 920, height: 90,
      text: 'CONGRATULATIONS!',
      fontSize: 54, fontFamily: 'PlayfairDisplay', color: '#B8860B',
      fontWeight: 'bold', textAlign: 'center', zIndex: 0,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 1),
      type: FlyerElementType.image,
      x: 340, y: 250, width: 400, height: 400,
      fit: 'cover', zIndex: 1,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 2),
      type: FlyerElementType.text,
      x: 90, y: 700, width: 900, height: 90,
      text: 'STUDENT NAME',
      fontSize: 52, fontFamily: 'Montserrat', color: '#14213D',
      fontWeight: 'bold', textAlign: 'center', zIndex: 2,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 3),
      type: FlyerElementType.text,
      x: 110, y: 810, width: 860, height: 150,
      text: 'Secured admission at\nUniversity Name',
      fontSize: 34, fontFamily: 'Lato', color: '#3A3A3A',
      fontWeight: 'normal', textAlign: 'center', zIndex: 3,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 4),
      type: FlyerElementType.text,
      x: 110, y: 1010, width: 860, height: 130,
      text: 'Your success story could be next.\nTalk to our counsellors today.',
      fontSize: 28, fontFamily: 'Inter', color: '#5A5A5A',
      fontWeight: 'normal', textAlign: 'center', zIndex: 4,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 5),
      type: FlyerElementType.logo,
      x: 450, y: 1180, width: 180, height: 110,
      fit: 'contain', zIndex: 5,
    ).toJson(),
  ];
}

// ---------------------------------------------------------------------
// 4. Seminar / Event — date-time-venue block
// ---------------------------------------------------------------------
List<Map<String, dynamic>> _seminarEvent() {
  const seed = 'event';
  return [
    FlyerElement(
      id: _uid(seed, 0),
      type: FlyerElementType.shape,
      x: 0, y: 0, width: 1080, height: 260,
      shapeColor: '#14213D', zIndex: 0,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 1),
      type: FlyerElementType.text,
      x: 70, y: 90, width: 940, height: 100,
      text: 'FREE CAREER SEMINAR',
      fontSize: 52, fontFamily: 'SpaceGrotesk', color: '#FFFFFF',
      fontWeight: 'bold', textAlign: 'center', zIndex: 1,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 2),
      type: FlyerElementType.image,
      x: 90, y: 320, width: 900, height: 380,
      fit: 'cover', zIndex: 2,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 3),
      type: FlyerElementType.text,
      x: 90, y: 750, width: 900, height: 70,
      text: 'DATE  •  TIME',
      fontSize: 38, fontFamily: 'Montserrat', color: '#14213D',
      fontWeight: 'bold', textAlign: 'center', zIndex: 3,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 4),
      type: FlyerElementType.text,
      x: 110, y: 840, width: 860, height: 90,
      text: 'Venue name and address here',
      fontSize: 30, fontFamily: 'Inter', color: '#3A3A3A',
      fontWeight: 'normal', textAlign: 'center', zIndex: 4,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 5),
      type: FlyerElementType.text,
      x: 110, y: 960, width: 860, height: 140,
      text: 'What you will learn:\n• Course & country selection\n• Scholarships and funding',
      fontSize: 26, fontFamily: 'Lato', color: '#3A3A3A',
      fontWeight: 'normal', textAlign: 'left', zIndex: 5,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 6),
      type: FlyerElementType.text,
      x: 90, y: 1150, width: 900, height: 70,
      text: 'Register: +91 00000 00000',
      fontSize: 32, fontFamily: 'SpaceGrotesk', color: '#B8860B',
      fontWeight: 'bold', textAlign: 'center', zIndex: 6,
    ).toJson(),
    FlyerElement(
      id: _uid(seed, 7),
      type: FlyerElementType.logo,
      x: 460, y: 1230, width: 160, height: 90,
      fit: 'contain', zIndex: 7,
    ).toJson(),
  ];
}

const List<FlyerStarterLayout> kFlyerStarterLayouts = [
  FlyerStarterLayout(
    id: 'blank',
    name: 'Blank Canvas',
    description: 'Start from scratch',
    backgroundColor: '#FFFFFF',
    build: _blank,
  ),
  FlyerStarterLayout(
    id: 'offer_announcement',
    name: 'Offer Announcement',
    description: 'Bold headline with a highlighted offer',
    backgroundColor: '#1B2A4A',
    build: _offerAnnouncement,
  ),
  FlyerStarterLayout(
    id: 'admission_open',
    name: 'Admissions Open',
    description: 'Photo-led with feature list and CTA',
    backgroundColor: '#FFFFFF',
    build: _admissionOpen,
  ),
  FlyerStarterLayout(
    id: 'success_story',
    name: 'Success Story',
    description: 'Congratulate a student, build social proof',
    backgroundColor: '#FFF8E7',
    build: _successStory,
  ),
  FlyerStarterLayout(
    id: 'seminar_event',
    name: 'Seminar / Event',
    description: 'Date, time and venue for an event',
    backgroundColor: '#FFFFFF',
    build: _seminarEvent,
  ),
];

List<Map<String, dynamic>> _blank() => [];
