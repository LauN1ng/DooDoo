// home-v2 截图 + 几何回执（一次请求只截一张，换方案改下面 URL 里的 #fX）
// 限制：同一请求里连续 page.screenshot 会超时；有 transform 祖先时元素截图会卡在
// "waiting for element to be stable"。因此固定为：去掉缩放 → page.screenshot + clip。
const variant = 'fB'; // fA / fB / fC / fD
const url = 'file:///D:/Work/WorkBuddy_File/account/design/current/home-v2.html#' + variant;

await page.setViewportSize({ width: 900, height: 950 });
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(700);
await page.evaluate(() => {
  const dev = document.getElementById('dev');
  dev.style.transform = 'none';
  dev.style.left = '0';
  dev.style.marginLeft = '0';
  dev.style.top = '0';
  document.querySelectorAll('.card').forEach((c) => { c.style.transition = 'none'; });
});
await page.waitForTimeout(250);

const geo = await page.evaluate(() => {
  const scr = document.getElementById('screen');
  const sr = scr.getBoundingClientRect();
  const s = sr.width / 390;
  const rel = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return {
      x: +((r.left - sr.left) / s).toFixed(1), y: +((r.top - sr.top) / s).toFixed(1),
      w: +(r.width / s).toFixed(1), h: +(r.height / s).toFixed(1),
      bottomFrom: +((sr.bottom - r.bottom) / s).toFixed(1),
      rightFrom: +((sr.right - r.right) / s).toFixed(1)
    };
  };
  const add = rel(document.getElementById('add'));
  const rows = rel(document.querySelector('.lay0 .rows'));
  const tabx = rel(document.getElementById('tabx'));
  const logo = rel(document.querySelector('.hd .logo'));
  const rEl = document.querySelector('.lay0 .rows');
  return {
    screenClass: scr.className,
    tabx, add,
    gapLogoToTab: tabx && logo ? +(tabx.x - (logo.x + logo.w)).toFixed(1) : null,
    gapRowsToAdd: add && rows ? +((add.y) - (rows.y + rows.h)).toFixed(1) : null,
    cardPadBottom: getComputedStyle(document.querySelector('.lay0')).paddingBottom,
    addClearsLayerBand: add ? add.bottomFrom >= 38 : null,
    rowsOverflow: rEl ? rEl.scrollHeight - rEl.clientHeight : null
  };
});

const box = await page.locator('#screen').boundingBox();
await page.screenshot({
  path: 'D:/Work/WorkBuddy_File/account/design/current/_homev2-' + variant.toLowerCase() + '.png',
  clip: box
});

return geo;
