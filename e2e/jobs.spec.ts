import { test, expect } from "@playwright/test";

test.describe("Jobs page", () => {
  test("See listing link opens external job posting in a new tab", async ({
    page,
  }) => {
    await page.goto("/jobs");

    // Find the first "See listing" link
    const seeListingLink = page.getByRole("link", { name: "See listing" }).first();

    // Verify the link is visible on the page
    await expect(seeListingLink).toBeVisible();

    // Verify it opens in a new tab (target="_blank")
    await expect(seeListingLink).toHaveAttribute("target", "_blank");

    // Verify it has security attributes
    const rel = await seeListingLink.getAttribute("rel");
    expect(rel).toContain("noopener");
    expect(rel).toContain("noreferrer");

    // Verify the href points to an external URL
    const href = await seeListingLink.getAttribute("href");
    expect(href).toMatch(/^https?:\/\//);
  });

  test("Hovering on a job title shows a description tooltip", async ({
    page,
  }) => {
    await page.goto("/jobs");

    // Find the first job title wrapper div that has a tooltip
    const titleWrapper = page.locator("div:has(> .job-tooltip)").first();
    const jobTitle = titleWrapper.locator("h2");
    await expect(jobTitle).toBeVisible();

    // Tooltip should be hidden initially
    const tooltip = titleWrapper.locator(".job-tooltip");
    await expect(tooltip).toBeHidden();

    // Hover over the job title
    await jobTitle.hover();

    // Tooltip should now be visible with description text
    await expect(tooltip).toBeVisible();
    await expect(tooltip).not.toBeEmpty();

    // Pause so you can see the tooltip in headed mode
    // eslint-disable-next-line playwright/no-wait-for-timeout
    await page.waitForTimeout(3000);

    // Move mouse away to dismiss
    await page.mouse.move(0, 0);
    await expect(tooltip).toBeHidden();
  });
});
