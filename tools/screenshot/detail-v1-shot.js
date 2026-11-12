const out = 'D:/Work/WorkBuddy_File/account/design/current/';
await page.setViewportSize({ width: 900, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/account-detail.html', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(600);
await page.addStyleTag({ content: '*,*::before,*::after{animation:none !important;transition:none !important}' });
await page.waitForTimeout(200);

async function reset() {
  await page.evaluate(() => {
    const sc = document.querySelector('#screen .dtscroll');
    if (sc) sc.scrollTop = 0;
  });
  await page.waitForTimeout(120);
}
async function shot(name) {
  await page.locator('#screen').screenshot({ path: out + name + '.png' });
}
async function scrollTo(y) {
  await page.evaluate((v) => {
    const sc = document.querySelector('#screen .dtscroll');
    if (sc) sc.scrollTop = v;
  }, y);
  await page.waitForTimeout(160);
}

for (const v of ['A', 'B', 'C']) {
  await page.locator('#pchips .chip[data-p="detail"]').click();
  await page.locator('#vchips .chip[data-v="' + v + '"]').click();
  await page.waitForTimeout(300);
  await reset();
  await shot('_dt-v1-' + v);
}

await page.locator('#vchips .chip[data-v="B"]').click();
await page.waitForTimeout(250);
await scrollTo(560);
await shot('_dt-v1-B-mid');
await scrollTo(1200);
await shot('_dt-v1-B-bot');

await page.locator('#pchips .chip[data-p="inst"]').click();
await page.waitForTimeout(450);
await reset();
await shot('_dt-v1-inst');

await page.locator('#pchips .chip[data-p="bills"]').click();
await page.waitForTimeout(450);
await reset();
await shot('_dt-v1-bills');

await page.locator('#pchips .chip[data-p="detail"]').click();
await page.waitForTimeout(300);
await reset();
await page.locator('.inst').first().click();
await page.waitForTimeout(500);
await reset();
await page.locator('.prow').first().click();
await page.waitForTimeout(500);
await shot('_dt-v1-sheet');

return { ok: true };
