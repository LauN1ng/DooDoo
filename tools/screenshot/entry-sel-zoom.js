const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/entry-selection-2026-11-16.html';
await page.setViewportSize({ width: 880, height: 760 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(700);
await page.addStyleTag({ content: 'body{padding:0 6px}.wrap{gap:16px;zoom:2}.hd{display:none}.variant{margin:0 auto}' });
await page.waitForTimeout(300);
await page.evaluate(function () {
  const el = document.querySelector('.v6');
  window.scrollTo(0, el.getBoundingClientRect().top + window.scrollY - 10);
});
await page.waitForTimeout(400);
return await page.screenshot({ fullPage: false });
