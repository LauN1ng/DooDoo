const path = 'file:///D:/Work/WorkBuddy_File/account/design/current/nav-mat.html';
const outDir = 'D:/Work/WorkBuddy_File/account/design/current/';

await page.setViewportSize({ width: 520, height: 1000 });
await page.goto(path, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);

const chips = await page.locator('.chip').all();
const tags = ['A', 'B', 'C', 'D', 'E'];
for (let i = 0; i < chips.length; i++) {
  await chips[i].click();
  await page.waitForTimeout(450);
  try {
    await page.screenshot({ path: outDir + '_mt-' + tags[i] + '.png' });
  } catch (e) {
    await page.screenshot({ path: outDir + '_mt-' + tags[i] + '.png' });
  }
}

// 量测：各变体 tab 的位置/尺寸、与卡片的关系、是否遮挡内容
const geo = await page.evaluate(() => {
  const dev = document.getElementById('dev');
  const screen = dev.querySelector('.screen');
  const sr = screen.getBoundingClientRect();
  const card = dev.querySelector('.lay0');
  const cr = card.getBoundingClientRect();
  const rows = card.querySelector('.rows');
  const rowsR = rows.getBoundingClientRect();
  const fb = (r) => +(sr.bottom - r.bottom).toFixed(1);
  const ft = (r) => +(sr.top + r.top).toFixed(1);
  const pick = (sel) => {
    const el = dev.querySelector(sel);
    if (!el) return null;
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return { visible: false };
    const r = el.getBoundingClientRect();
    return {
      visible: true, left: +(r.left - sr.left).toFixed(1), right: +(r.right - sr.left).toFixed(1),
      w: +r.width.toFixed(1), h: +r.height.toFixed(1),
      topFromScreenTop: ft(r), bottomFromScreenBottom: fb(r),
      bg: cs.backgroundColor, shadow: cs.boxShadow.slice(0, 60)
    };
  };
  return {
    bodyClass: document.body.className,
    cardBottomFromScreenBottom: fb(cr),
    rowsBottomFromScreenBottom: fb(rowsR),
    navA: pick('.navA'), navB: pick('.navB'), navC: pick('.navC'), navD: pick('.navD'),
    htabs: pick('.htabs'), fab: pick('.fab')
  };
});
return { geo };
