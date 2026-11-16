const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/entry-shadow-dash-2026-11-16.html';
await page.setViewportSize({ width: 430, height: 1400 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(1500);
const pos = await page.evaluate(function () {
  const d = document.querySelector('.dashwrap').getBoundingClientRect();
  const boxes = Array.from(document.querySelectorAll('.dashbox')).map(function (b) {
    const r = b.getBoundingClientRect();
    return { x: Math.round(r.left), y: Math.round(r.top + window.scrollY), w: Math.round(r.width), h: Math.round(r.height) };
  });
  return { dashY: Math.round(d.top + window.scrollY), dashH: Math.round(d.height), boxes: boxes, docH: document.documentElement.scrollHeight };
});
globalThis.__pos = pos;
return await page.screenshot({ fullPage: true });
