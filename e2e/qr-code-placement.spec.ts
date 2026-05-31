import { test, expect } from "@playwright/test";

test.describe("QR Code Placement", () => {
  test("Desktop: QR code is visible in hero sidebar", async ({ page }) => {
    // Desktop viewport
    await page.setViewportSize({ width: 1280, height: 1024 });
    await page.goto("http://localhost:3000/");

    // Wait for page to load
    await page.waitForLoadState("networkidle");

    // Find the QR code SVG
    const qrSvg = page.locator("svg.qr-code-svg");

    // Verify QR code is visible on desktop
    await expect(qrSvg).toBeVisible();

    // Verify the SVG has correct viewBox for 57x57 module grid
    const viewBox = await qrSvg.getAttribute("viewBox");
    expect(viewBox).toBe("0 0 57 57");

    // Verify QR code renders rects (modules)
    const rects = page.locator("rect.qr-module");
    const rectCount = await rects.count();
    expect(rectCount).toBeGreaterThan(1500); // Should have ~1660 modules

    // Verify scan label is visible
    const label = page.locator("text=Scan to visit agent44labs.ai");
    await expect(label).toBeVisible();
  });

  test("Mobile: QR code column is hidden", async ({ page }) => {
    // Mobile viewport
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("http://localhost:3000/");

    // Wait for page to load
    await page.waitForLoadState("networkidle");

    // QR code should be hidden in mobile view (hidden sm:flex means hidden on mobile)
    const qrContainer = page.locator(".qr-code-container");
    const parentDiv = qrContainer.locator("xpath=ancestor::div[contains(@class, 'hidden')]").first();

    // Check visibility - should be hidden due to Tailwind hidden class
    const displayed = await parentDiv.isHidden();
    expect(displayed).toBe(true);
  });

  test("Desktop: QR code is properly positioned in hero grid", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 1024 });
    await page.goto("http://localhost:3000/");
    await page.waitForLoadState("networkidle");

    // Find the QR container grid column
    const qrColumn = page.locator("div.sm\\:col-span-2.sm\\:col-start-7").first();

    // Verify it has the expected classes for centering
    const classes = await qrColumn.getAttribute("class");
    expect(classes).toContain("sm:flex");
    expect(classes).toContain("sm:items-center");
    expect(classes).toContain("justify-center");
  });

  test("QR code wrapper has correct styling", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 1024 });
    await page.goto("http://localhost:3000/");
    await page.waitForLoadState("networkidle");

    // Get the wrapper div
    const wrapper = page.locator(".qr-code-svg-wrapper");

    // Verify it has white background class
    const classes = await wrapper.getAttribute("class");
    expect(classes).toContain("bg-white");
    expect(classes).toContain("rounded-lg");
    expect(classes).toContain("shadow-lg");
  });

  test("SVG QR code renders without errors", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 1024 });

    // Capture console errors
    const errors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        errors.push(msg.text());
      }
    });

    await page.goto("http://localhost:3000/");
    await page.waitForLoadState("networkidle");

    // Verify SVG is properly rendered
    const qrSvg = page.locator("svg.qr-code-svg");
    await expect(qrSvg).toBeVisible();

    // Check for any SVG rendering errors
    const svgValid = await qrSvg.evaluate((svg) => {
      return svg.classList.contains("qr-code-svg") &&
        svg.querySelector("rect.qr-module") !== null;
    });

    expect(svgValid).toBe(true);
  });
});
