// Generates a synthetic exam-result .xlsx buffer reproducing the exact
// structural shape of a real college result sheet this feature was built
// against (Chitwan Medical College, MBBS 1st year 2nd internal assessment)
// — inspected for header structure only, never for student data, and that
// inspection has already been discarded. Every name/number/mark below is
// fabricated. Reproduces:
//   - a free-text title block above the real header rows
//   - a paper-group row whose labels only occupy their first column (every
//     other column in that paper's span is genuinely blank, the same way
//     a real merged cell reads once opened as plain values)
//   - per-subject headers with an inline max, e.g. "ANA(20)"
//   - one paper (Com Med-II) whose 4 subjects state NO max at all — the
//     real case the "subject with no max blocks import" rule exists for
//   - a "Total(N)"/"Result" column pair per paper
//   - two columns both literally headed "Cell Number" (father's, mother's)
//
// Uses the `xlsx` package (SheetJS) — a devDependency added only for
// generating this fixture; the app's own import path still reads with
// `read-excel-file`, unchanged.

const XLSX = require('xlsx');

function buildFixtureRows({ studentNames = ['Aarav Sharma', 'Priya Thapa', 'Rohan Gurung'], includeNoMaxSubjects = true } = {}) {
  const titleBlock = [
    ['Chitwan Medical College (fabricated data)', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', ''],
    ['MBBS 1st Year — 2nd Internal Assessment (fabricated)', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', ''],
    ['', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', ''],
  ];

  // Paper-group row: label appears once per paper span, blank elsewhere —
  // exactly how a real merged cell reads back as plain values.
  const paperGroupRow = [
    '', '', '', '', '', // S.N., Batch, Student ID, Student Name, Category
    'IBMS-MSK(120/60)', '', '', '', '', '', '', '', // 6 subjects + Total + Result
    'Com Med-I(80/40)', '', '', '', '', // 3 subjects + Total + Result
    'Com Med-II(80/40)', '', '', '', '', '', // 4 subjects + Total + Result
    '', '', '', '', // Father's Name, Cell Number, Mother's Name, Cell Number
  ];

  const com2Subjects = includeNoMaxSubjects
    ? ['HP&E', 'FH&N', 'E&OH', 'MS&A'] // no max stated — matches the real sheet exactly
    : ['HP&E(20)', 'FH&N(20)', 'E&OH(20)', 'MS&A(20)'];

  const header = [
    'S.N.', 'Batch', 'Student ID', 'Student Name', 'Category',
    'ANA(20)', 'PHYSIO(20)', 'BIO(20)', 'MICRO(20)', 'PATHO(20)', 'PHARM(20)', 'Total(120)', 'Result',
    'EPIDEMIOLOGY(40)', 'DEMOGRAPHY(16)', 'BIO-STATISTICS(24)', 'Total(80)', 'Result',
    ...com2Subjects, 'Total(80)', 'Result',
    "Father's Name", 'Cell Number', "Mother's Name", 'Cell Number',
  ];

  const dataRows = studentNames.map((name, i) => [
    i + 1, '2081', `STU-${1000 + i}`, name, 'General',
    16, 17, 15, 18, 14, 16, '=SUM', 'Pass', // paper 1 marks (Total/Result left as fabricated placeholders, not parsed)
    32, 12, 19, '=SUM', 'Pass', // paper 2 marks
    ...(includeNoMaxSubjects ? [15, 14, 12, 8] : [15, 14, 12, 8]), '=SUM', 'Pass', // paper 3 marks
    `${name.split(' ')[0]}'s Father`, `98${10000000 + i}`, `${name.split(' ')[0]}'s Mother`, `97${10000000 + i}`,
  ]);

  return [...titleBlock, paperGroupRow, header, ...dataRows];
}

function buildFixtureBuffer(options) {
  const rows = buildFixtureRows(options);
  const worksheet = XLSX.utils.aoa_to_sheet(rows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, 'Results');
  return XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });
}

module.exports = { buildFixtureRows, buildFixtureBuffer };
