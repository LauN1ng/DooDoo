await page.setViewportSize({ width: 1300, height: 1100 });
await page.goto("file:///D:/Work/WorkBuddy_File/account/design/current/nav-final-compare.html", { waitUntil: "domcontentloaded" });
await page.waitForTimeout(900);
await page.screenshot({ path: "D:/Work/WorkBuddy_File/account/design/current/nav-final-compare.png", fullPage: true });
return { ok: true, title: await page.title() };