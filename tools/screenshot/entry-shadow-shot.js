const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/entry-shadow-dash-2026-11-16.html';
await page.setViewportSize({ width: 430, height: 1900 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(900);
const info = await page.evaluate(function () {
  const d = document.querySelector('.dashwrap');
  const r = d.getBoundingClientRect();
  return { h: document.body.scrollHeight, dashTop: Math.round(r.top + window.scrollY), dashH: Math.round(r.height) };
});
globalThis.__shot = info;
return await page.screenshot({ fullPage: true });
