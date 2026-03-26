import { test, expect } from "@playwright/test";

// Helper: selector for job detail links only (not /jobs/globe or other non-numeric paths)
const JOB_LINK = 'a[href*="/jobs/"][href$="0"], a[href*="/jobs/"][href$="1"], a[href*="/jobs/"][href$="2"], a[href*="/jobs/"][href$="3"], a[href*="/jobs/"][href$="4"], a[href*="/jobs/"][href$="5"], a[href*="/jobs/"][href$="6"], a[href*="/jobs/"][href$="7"], a[href*="/jobs/"][href$="8"], a[href*="/jobs/"][href$="9"]';

test.describe("Email verification gate for job details", () => {
  const password = "securepass123";

  test("unverified user is redirected away from job show page", async ({
    page,
  }) => {
    const email = `unverified-${Date.now()}@agent44.com`;

    // Register a new user (unverified by default)
    await page.goto("/registration/new");
    await page.fill('input[name="user[display_name]"]', "Test User");
    await page.fill('input[name="user[email_address]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.fill('input[name="user[password_confirmation]"]', password);
    await page.getByRole("button", { name: "Sign Up" }).click();
    await expect(page).toHaveURL("/");

    // Try to view a job — should be redirected back with verification message
    await page.goto("/jobs");
    const jobLink = page.locator(JOB_LINK).first();
    if (await jobLink.isVisible()) {
      await jobLink.click();

      // Should be redirected to jobs index with verification alert
      await expect(page).toHaveURL("/jobs");
      await expect(
        page.getByText("Please verify your email")
      ).toBeVisible();
    }
  });

  test("verified user can access job show page", async ({ page }) => {
    const email = `verified-${Date.now()}@agent44.com`;

    // Register
    await page.goto("/registration/new");
    await page.fill('input[name="user[display_name]"]', "Verified User");
    await page.fill('input[name="user[email_address]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.fill('input[name="user[password_confirmation]"]', password);
    await page.getByRole("button", { name: "Sign Up" }).click();
    await expect(page).toHaveURL("/");

    // Verify email directly via Rails runner
    const { execSync } = require("child_process");
    execSync(
      `bin/rails runner 'User.find_by(email_address: "${email}").verify_email!'`,
      { cwd: process.cwd(), timeout: 10000 }
    );

    // Now try to view a job — should work
    await page.goto("/jobs");
    const jobLink = page.locator(JOB_LINK).first();
    if (await jobLink.isVisible()) {
      const href = await jobLink.getAttribute("href");
      await jobLink.click();

      // Should be on the job show page
      await expect(page).toHaveURL(href!);
      await expect(page.locator("h1")).toBeVisible();
    }
  });

  test("unauthenticated user is redirected to sign in from job show", async ({
    page,
  }) => {
    await page.goto("/jobs");
    const jobLink = page.locator(JOB_LINK).first();
    if (await jobLink.isVisible()) {
      await jobLink.click();
      await expect(page).toHaveURL(/\/session\/new/);
    }
  });

  test("full flow: sign up, verify email, view job", async ({ page }) => {
    const email = `fullflow-${Date.now()}@agent44.com`;

    // 1. Browse jobs (public)
    await page.goto("/jobs");
    await expect(
      page.getByRole("heading", { name: "SDET & Test Automation Jobs" })
    ).toBeVisible();

    // 2. Click a job — redirected to sign in
    const jobLink = page.locator(JOB_LINK).first();
    if (!(await jobLink.isVisible())) return;

    const jobHref = await jobLink.getAttribute("href");
    await jobLink.click();
    await expect(page).toHaveURL(/\/session\/new/);

    // 3. Go to sign up
    await page.locator('a[href="/registration/new"]').last().click();
    await expect(page).toHaveURL("/registration/new");

    // 4. Register
    await page.fill('input[name="user[display_name]"]', "Full Flow User");
    await page.fill('input[name="user[email_address]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.fill('input[name="user[password_confirmation]"]', password);
    await page.getByRole("button", { name: "Sign Up" }).click();
    await expect(page).toHaveURL("/");

    // 5. Try to view job — blocked (unverified), redirected to /jobs with alert
    await page.goto("/jobs");
    const jobLink2 = page.locator(JOB_LINK).first();
    await jobLink2.click();
    await expect(page).toHaveURL("/jobs");
    await expect(
      page.getByText("Please verify your email")
    ).toBeVisible();

    // 6. Verify email (simulate clicking email link)
    const { execSync } = require("child_process");
    execSync(
      `bin/rails runner 'User.find_by(email_address: "${email}").verify_email!'`,
      { cwd: process.cwd(), timeout: 10000 }
    );

    // 7. Now view job — should work
    await page.goto(jobHref!);
    await expect(page).toHaveURL(jobHref!);
    await expect(page.locator("h1")).toBeVisible();
  });
});
