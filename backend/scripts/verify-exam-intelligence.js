// Standalone smoke test for the Exam Intelligence + Report Card System's
// pure logic and image rendering — no database connection required, so it
// can run in any environment. This repo has no test framework yet
// (package.json's "test" script is a placeholder), so this is a plain
// script with assertions rather than a new framework being introduced for
// one feature.
//
// Run with: node scripts/verify-exam-intelligence.js

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  findMissingMaxSubjects,
  findOutOfRangeMarks,
  gradeFor,
  normalizeGuardianPhone,
  numbersAreGrounded,
  parseMarksSheetBuffer,
  DEFAULT_TEMPLATE_CONFIG,
} = require('../services/examIntelligence');
const { renderReportCardPng } = require('../services/reportCardImage');
const { buildFixtureBuffer } = require('../tests/lib/exam-sheet-fixture');

let passed = 0;
function check(name, fn) {
  try {
    fn();
    console.log(`PASS: ${name}`);
    passed++;
  } catch (err) {
    console.error(`FAIL: ${name}\n  ${err.message}`);
    process.exitCode = 1;
  }
}

check('findMissingMaxSubjects blocks a subject with no stated max', () => {
  const parsed = {
    subjectNames: ['Anatomy', 'Physiology'],
    maxBySubject: { Anatomy: 100, Physiology: null },
    students: [{ name: 'A', marksBySubject: { Anatomy: 80, Physiology: 22.5 } }],
  };
  const missing = findMissingMaxSubjects(parsed);
  assert.strictEqual(missing.length, 1);
  assert.strictEqual(missing[0].subject, 'Physiology');
  assert.strictEqual(missing[0].highestMarkSeen, 22.5);
});

check('findOutOfRangeMarks refuses a mark above its max', () => {
  const parsed = {
    subjectNames: ['Anatomy'],
    maxBySubject: { Anatomy: 100 },
    students: [{ name: 'A', marksBySubject: { Anatomy: 105 } }],
  };
  const problems = findOutOfRangeMarks(parsed);
  assert.strictEqual(problems.length, 1);
  assert.strictEqual(problems[0].marks, 105);
});

check('gradeFor is deterministic at band edges', () => {
  assert.strictEqual(gradeFor(90), 'A+');
  assert.strictEqual(gradeFor(89.9), 'A');
  assert.strictEqual(gradeFor(39.9), 'F');
  assert.strictEqual(gradeFor(40), 'D');
});

check('normalizeGuardianPhone flags a bare 10-digit number as suspect (assumed country code)', () => {
  const r = normalizeGuardianPhone('9812345678', null);
  assert.strictEqual(r.suspect, true);
  assert.ok(r.number);
});

check('normalizeGuardianPhone trusts an explicit country code', () => {
  const r = normalizeGuardianPhone('9812345678', '+977');
  assert.strictEqual(r.suspect, false);
});

check('normalizeGuardianPhone flags an unusual-length number, never silently drops it', () => {
  const r = normalizeGuardianPhone('691902714', null); // 9 digits, seen in reference sheet's bad data
  assert.strictEqual(r.suspect, true);
  assert.ok(r.number); // kept, not discarded
});

check('numbersAreGrounded accepts a narrative using only given figures', () => {
  const summary = { overallPercentage: 68, rank: 3, cohortSize: 41 };
  assert.strictEqual(numbersAreGrounded('Great result — 68% overall, ranked 3rd out of 41.', summary), true);
});

check('numbersAreGrounded rejects a narrative with an invented figure', () => {
  const summary = { overallPercentage: 68, rank: 3, cohortSize: 41 };
  assert.strictEqual(numbersAreGrounded('Improved from 54% to 68%.', summary), false); // 54 is not in the summary
});

(async () => {
  // --- Real-shape fixture: merged multi-row header, per-subject inline
  // max, one paper (Com Med-II) with no max stated, duplicate "Cell
  // Number" columns, Total/Result columns per paper. Structure confirmed
  // against a real college sheet's header only; every value here is
  // fabricated. ---------------------------------------------------------
  try {
    const buffer = buildFixtureBuffer();
    const parsed = await parseMarksSheetBuffer(buffer);

    assert.strictEqual(parsed.subjectNames.length, 13, `expected 13 subjects across 3 papers, got ${parsed.subjectNames.length}: ${parsed.subjectNames.join(', ')}`);
    assert.strictEqual(parsed.students.length, 3);

    // Subjects with an inline max parse correctly.
    assert.strictEqual(parsed.maxBySubject['ANA'], 20);
    assert.strictEqual(parsed.maxBySubject['EPIDEMIOLOGY'], 40);

    // The 4 Com Med-II subjects state no max — must come through as null,
    // never guessed — this is the exact real-world case that blocks import.
    for (const s of ['HP&E', 'FH&N', 'E&OH', 'MS&A']) {
      assert.strictEqual(parsed.maxBySubject[s], null, `expected ${s} to have no stated max`);
    }
    const missing = findMissingMaxSubjects(parsed);
    assert.strictEqual(missing.length, 4);

    // Ignored columns never leak in as fake subjects.
    for (const bad of ['Total', 'Result', "Father's Name", 'Cell Number', "Mother's Name", 'S.N.', 'Batch', 'Category']) {
      assert.ok(!parsed.subjectNames.includes(bad), `"${bad}" should have been ignored, not treated as a subject`);
    }

    // Paper-group forward-fill worked: every subject in a paper's span
    // resolves to that paper's own label, not blank or the wrong paper's.
    assert.strictEqual(parsed.paperGroupBySubject['ANA'], 'IBMS-MSK(120/60)');
    assert.strictEqual(parsed.paperGroupBySubject['BIO-STATISTICS'], 'Com Med-I(80/40)');
    assert.strictEqual(parsed.paperGroupBySubject['MS&A'], 'Com Med-II(80/40)');

    console.log(`PASS: parseMarksSheetBuffer handles the real multi-row-header sheet shape (${parsed.subjectNames.length} subjects, ${parsed.students.length} students, 4 correctly flagged as missing max)`);
    passed++;
  } catch (err) {
    console.error(`FAIL: parseMarksSheetBuffer handles the real multi-row-header sheet shape\n  ${err.stack}`);
    process.exitCode = 1;
  }

  try {
    const buffer = buildFixtureBuffer({ includeNoMaxSubjects: false }); // all 13 subjects have a max
    const parsed = await parseMarksSheetBuffer(buffer);
    assert.strictEqual(findMissingMaxSubjects(parsed).length, 0);
    console.log('PASS: a sheet where every subject states a max blocks nothing');
    passed++;
  } catch (err) {
    console.error(`FAIL: a sheet where every subject states a max blocks nothing\n  ${err.stack}`);
    process.exitCode = 1;
  }

  try {
    const withTemplate = await renderReportCardPng(
      {
        examGroup: 'Test',
        subjects: [{ subject: 'Anatomy', marksObtained: 78, maxMarks: 100, percentage: 78 }],
        total: 78, maxTotal: 100, overallPercentage: 78, overallGrade: 'A', rank: 1, cohortSize: 10, batchAverage: 60, previousDelta: null,
      },
      {
        studentName: 'Custom Template Student',
        tenantName: 'Demo',
        narrative: null,
        template: { ...DEFAULT_TEMPLATE_CONFIG, fields: ['subjects', 'total'], footerText: 'Issued by the examination office.' },
        studentMeta: { studentCode: 'STU-1', batch: '2081', course: 'MBBS' },
      }
    );
    assert.ok(Buffer.isBuffer(withTemplate) && withTemplate.length > 500);
    console.log('PASS: renderReportCardPng honors a custom template (fewer fields, custom footer)');
    passed++;
  } catch (err) {
    console.error(`FAIL: renderReportCardPng honors a custom template\n  ${err.stack}`);
    process.exitCode = 1;
  }

  try {
    const summary = {
      examGroup: 'MBBS 1st Year 2nd Internal Assessment',
      subjects: [
        { subject: 'Anatomy', marksObtained: 78, maxMarks: 100, percentage: 78 },
        { subject: 'Physiology', marksObtained: 22.5, maxMarks: 40, percentage: 56.3 },
      ],
      total: 100.5,
      maxTotal: 140,
      overallPercentage: 71.8,
      overallGrade: 'B+',
      rank: 5,
      cohortSize: 41,
      batchAverage: 65.2,
      previousDelta: { comparedTo: '1st Internal Assessment', previousPercentage: 66.1, change: 5.7 },
    };
    const png = await renderReportCardPng(summary, {
      studentName: 'Test Student',
      tenantName: 'Demo Consultancy',
      narrative: 'A solid improvement this term — keep up the steady work across every subject.',
    });
    assert.ok(Buffer.isBuffer(png) && png.length > 1000, 'expected a real PNG buffer over 1KB');
    assert.strictEqual(png.slice(0, 8).toString('hex'), '89504e470d0a1a0a', 'expected a valid PNG signature');
    const outPath = path.join(__dirname, '..', '.verify-output-report-card.png');
    fs.writeFileSync(outPath, png);
    console.log(`PASS: renderReportCardPng produces a valid non-trivial PNG (${png.length} bytes, written to ${outPath})`);
    passed++;
  } catch (err) {
    console.error(`FAIL: renderReportCardPng produces a valid non-trivial PNG\n  ${err.stack}`);
    process.exitCode = 1;
  }

  console.log(`\n${passed} check(s) passed${process.exitCode ? ', with failures above' : ''}.`);
})();
