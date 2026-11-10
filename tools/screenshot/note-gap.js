// 量「顶部胶囊」与「本月便签」的视觉间隔（纯测量，不截图）
// 便签是 rotate(-3deg) 的，取 bounding box 的 top 才是肉眼看到的最高点
await page.setViewportSize({ width: 900, height: 950 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/home-v2.html#fA', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(700);
await page.evaluate(() => {
  const dev = document.getElementById('dev');
  dev.style.transform = 'none';
  dev.style.left = '0';
  dev.style.marginLeft = '0';
  dev.style.top = '0';
  document.querySelectorAll('.card').forEach((c) => { c.style.transition = 'none'; });
});
await page.waitForTimeout(200);

return await page.evaluate(() => {
  const scr = document.getElementById('screen');
  const sr = scr.getBoundingClientRect();
  const s = sr.width / 390;
  const tab = document.getElementById('tabx').getBoundingClientRect();
  const note = document.querySelector('.lay0 .note').getBoundingClientRect();
  const card = document.querySelector('.lay0').getBoundingClientRect();
  const rows = document.querySelector('.lay0 .rows');
  return {
    deckTop: getComputedStyle(document.querySelector('.deck')).top,
    tabBottom: +((tab.bottom - sr.top) / s).toFixed(1),
    noteTop: +((note.top - sr.top) / s).toFixed(1),
    gapTabToNote: +((note.top - tab.bottom) / s).toFixed(1),
    cardTop: +((card.top - sr.top) / s).toFixed(1),
    cardH: +(card.height / s).toFixed(1),
    noteOutOfCard: +((card.top - note.top) / s).toFixed(1),
    rowsOverflow: rows.scrollHeight - rows.clientHeight
  };
});
