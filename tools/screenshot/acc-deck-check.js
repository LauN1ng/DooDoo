await page.setViewportSize({ width: 900, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/account-stack.html', { waitUntil: 'domcontentloaded', timeout: 25000 });
await page.waitForTimeout(1200);

const before = await page.evaluate(() => {
  const d = document.querySelector('.hdeck');
  const k0 = d.querySelector('.hc.k0');
  return {
    deckH: +d.getBoundingClientRect().height.toFixed(1),
    k0Bottom: getComputedStyle(k0).bottom,
    layers: d.querySelectorAll('.hc').length,
    hasCnt: !!d.querySelector('.cnt')
  };
});

/* 把信用组临时裁到 1 个账户、储蓄组裁到 2 个，验证层数自适应 */
const after = await page.evaluate(() => {
  CREDIT.splice(1);
  SAVING.splice(2);
  render();
  const decks = Array.from(document.querySelectorAll('.hdeck'));
  return decks.map((d) => ({
    deckH: +d.getBoundingClientRect().height.toFixed(1),
    k0Bottom: getComputedStyle(d.querySelector('.hc.k0')).bottom,
    layers: d.querySelectorAll('.hc').length,
    hasCnt: !!d.querySelector('.cnt')
  }));
});

return { before, after };
