// 整条对比截图（4 格并排）。单帧截图改动 nth(3) 与文件名即可
await page.setViewportSize({ width: 1740, height: 1320 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/entry-bcd.html', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(900);
const box = await page.locator('.strip').boundingBox();
await page.screenshot({ path: 'D:/Work/WorkBuddy_File/account/design/current/_bcd.png', clip: box });
return { box };
