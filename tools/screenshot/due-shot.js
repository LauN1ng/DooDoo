const out = 'D:/Work/WorkBuddy_File/account/design/current/';
await page.setViewportSize({ width: 980, height: 1500 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/asset-due-2026-11-12.html', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(500);
await page.addStyleTag({ content: '*,*::before,*::after{animation:none !important;transition:none !important}' });
await page.waitForTimeout(200);

const names = ['A', 'B', 'C', 'D'];
const n = await page.locator('.device').count();
const geo = [];
for (let i = 0; i < n; i++) {
  const el = page.locator('.device').nth(i);
  await el.screenshot({ path: out + '_due-' + names[i] + '.png' });
  const g = await el.evaluate(e => {
    const sc = e.querySelector('.screen');
    const grp = e.querySelectorAll('.grp')[0];
    const gr = grp.getBoundingClientRect();
    const er = e.getBoundingClientRect();
    return {
      w: Math.round(er.width), h: Math.round(er.height),
      contentH: sc.scrollHeight,
      creditTop: Math.round(gr.top - er.top),
      creditBottom: Math.round(gr.bottom - er.top)
    };
  });
  geo.push(Object.assign({ v: names[i] }, g));
}
await page.screenshot({ path: out + '_due-board.png', fullPage: true });
return { devices: n, geo };
