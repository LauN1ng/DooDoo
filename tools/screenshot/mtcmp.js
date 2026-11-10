const path = 'file:///D:/Work/WorkBuddy_File/account/design/current/nav-mat-compare.html';
const outDir = 'D:/Work/WorkBuddy_File/account/design/current/';

await page.setViewportSize({ width: 1340, height: 1200 });
await page.goto(path, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1000);
try {
  await page.screenshot({ path: outDir + 'nav-mat-compare.png', fullPage: true });
} catch (e) {
  await page.screenshot({ path: outDir + 'nav-mat-compare.png', fullPage: true });
}
return { ok: true };
