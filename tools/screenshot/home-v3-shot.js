// 单帧截图：n=1 首次使用（空账本）
await page.setViewportSize({ width: 900, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/home-v3.html', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(800);
await page.click('.chip[data-n="1"]', { timeout: 5000 });
await page.waitForTimeout(300);
await page.check('#emptyChk');
await page.waitForTimeout(500);
await page.evaluate(() => {
  const dev = document.getElementById('dev');
  dev.style.transform = 'none';
  dev.style.left = '0';
  dev.style.marginLeft = '0';
  dev.style.top = '0';
});
await page.waitForTimeout(200);
const box = await page.locator('.screen').boundingBox();
await page.screenshot({ path: 'D:/Work/WorkBuddy_File/account/design/current/_hv3-n1.png', clip: box });
return { box };
