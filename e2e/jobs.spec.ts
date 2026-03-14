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
});
