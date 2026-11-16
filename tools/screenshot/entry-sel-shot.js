const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/entry-selection-2026-11-16.html';
await page.setViewportSize({ width: 440, height: 2400 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(1200);
const check = await page.evaluate(function () {
  const els = Array.from(document.querySelectorAll('.ico'));
  const bad = els.filter(function (e) {
    const bg = getComputedStyle(e).backgroundImage;
    return !bg || bg === 'none' || bg.indexOf('data:image/png') !== 0;
  });
  return {
    total: els.length,
    bad: bad.length,
    docHeight: document.documentElement.scrollHeight
  };
});
globalThis.__check = check;
return await page.screenshot({ fullPage: true, clip: { x: 0, y: 0, width: 440, height: check.docHeight } });
