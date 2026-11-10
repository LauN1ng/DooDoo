await page.setViewportSize({ width: 1200, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/home-v3.html', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(800);

const out = {};
for (const n of ['1', '2', '4', '7']) {
  await page.click('.chip[data-n="' + n + '"]', { timeout: 5000 });
  await page.waitForTimeout(450);
  out['n' + n] = await page.evaluate(() => {
    const scr = document.querySelector('.screen');
    const sr = scr.getBoundingClientRect();
    const s = sr.width / 390;
    const rel = (el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return {
        y: +((r.top - sr.top) / s).toFixed(1),
        h: +(r.height / s).toFixed(1),
        bottomFrom: +((sr.bottom - r.bottom) / s).toFixed(1)
      };
    };
    const cards = Array.from(document.querySelectorAll('.deck > .card'));
    const front = document.querySelector('.deck > .card.front');
    const addrow = front ? rel(front.querySelector('.addrow')) : null;
    const rows = front ? rel(front.querySelector('.rows')) : null;
    const layers = cards.map((c) => rel(c)).map((r) => r ? r.bottomFrom : null);
    const tb = rel(document.querySelector('.tabx'));
    const note = front ? rel(front.querySelector('.note')) : null;
    return {
      cardCount: cards.length,
      frontH: front ? +front.getBoundingClientRect().height.toFixed(0) : null,
      frontBottom: layers[0],
      deepestBottom: Math.min.apply(null, layers.filter((x) => x !== null)),
      band: +(Math.max.apply(null, layers) - Math.min.apply(null, layers)).toFixed(1),
      addrow, rowsBottomGap: (addrow && rows) ? +(addrow.y - (rows.y + rows.h)).toFixed(1) : null,
      rowsOverflow: front ? (function(){ const r = front.querySelector('.rows'); return r.scrollHeight - r.clientHeight; })() : null,
      tabBottom: tb ? +(tb.y + tb.h).toFixed(1) : null,
      noteTop: note ? note.y : null,
      addrowClearsBand: addrow ? addrow.bottomFrom >= (Math.max.apply(null, layers) - 8) : null
    };
  });
}
out.empty = await page.evaluate(async () => {
  document.getElementById('emptyChk').click();
  return new Promise((res) => setTimeout(() => {
    const front = document.querySelector('.deck > .card.front');
    res({ hasEmpty: !!front.querySelector('.empty'), emptyText: front.querySelector('.empty') ? front.querySelector('.empty').textContent : null });
  }, 300));
});
return out;
