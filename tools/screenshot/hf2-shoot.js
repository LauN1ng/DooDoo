const path = 'file:///D:/Work/WorkBuddy_File/account/design/current/home-final.html';
const outDir = 'D:/Work/WorkBuddy_File/account/design/current/';

await page.setViewportSize({ width: 520, height: 1000 });
await page.goto(path, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);

try {
  await page.screenshot({ path: outDir + 'hf2-home.png' });
} catch (e) {
  await page.screenshot({ path: outDir + 'hf2-home.png' });
}

const geo = await page.evaluate(() => {
  const dev = document.getElementById('dev');
  const screen = dev.querySelector('.screen');
  const sr = screen.getBoundingClientRect();
  const card = dev.querySelector('.lay0');
  const cr = card.getBoundingClientRect();
  const rows = card.querySelector('.rows');
  const note = card.querySelector('.note');
  const nav = dev.querySelector('.nav');
  const fab = dev.querySelector('.fab');
  const navR = nav.getBoundingClientRect();
  const fabR = fab.getBoundingClientRect();
  const rowsR = rows.getBoundingClientRect();
  const fromBottom = (r) => +(sr.bottom - r.bottom).toFixed(1);
  return {
    screenH: +sr.height.toFixed(1),
    noteCount: dev.querySelectorAll('.note').length,
    noteVisible: note ? getComputedStyle(note).display !== 'none' : false,
    rowsClientH: rows.clientHeight,
    rowsScrollH: rows.scrollHeight,
    overflowPx: rows.scrollHeight - rows.clientHeight,
    rowsBottomFromScreenBottom: fromBottom(rowsR),
    navTopFromScreenBottom: fromBottom(navR),
    fabTopFromScreenBottom: fromBottom(fabR),
    rowsClearOfFab: rowsR.bottom <= fabR.top,
    rowsClearOfNav: rowsR.bottom <= navR.top,
    fabClearOfRows: fabR.top >= rowsR.bottom,
    gapRowsToFab: +(fabR.top - rowsR.bottom).toFixed(1),
    noteTopFromCardTop: +(note.getBoundingClientRect().top - cr.top).toFixed(1)
  };
});
return { geo };
