import { test, expect } from "@playwright/test";

test.describe("Email Registration", () => {
  test("sign up page is accessible from nav", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("link", { name: "Sign Up", exact: true }).first().click();
    await expect(page).toHaveURL("/registration/new");
    await expect(page.getByRole("heading", { name: "Create an Account" })).toBeVisible();
  });

  test("sign up page is accessible from sign in page", async ({ page }) => {
    await page.goto("/session/new");
    await page.locator('a[href="/registration/new"]').last().click();
    await expect(page).toHaveURL("/registration/new");
  });

  test("successful registration with email and password", async ({ page }) => {
    const email = `reg-success-${Date.now()}@agent44.com`;

    await page.goto("/registration/new");
    await page.fill('input[name="user[email_address]"]', email);
    await page.fill('input[name="user[password]"]', "securepass123");
    await page.fill('input[name="user[password_confirmation]"]', "securepass123");
    await page.getByRole("button", { name: "Sign Up" }).click();

    await expect(page).toHaveURL("/");
    await expect(page.getByText("Welcome to Agent44!")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign Out" })).toBeVisible();
  });

  test("registration fails with short password", async ({ page }) => {
    await page.goto("/registration/new");
    await page.fill('input[name="user[email_address]"]', `reg-short-${Date.now()}@agent44.com`);
    await page.fill('input[name="user[password]"]', "short");
    await page.fill('input[name="user[password_confirmation]"]', "short");
    await page.getByRole("button", { name: "Sign Up" }).click();

    await expect(page.getByText("Password is too short")).toBeVisible();
  });

  test("registration fails with mismatched passwords", async ({ page }) => {
    await page.goto("/registration/new");
    await page.fill('input[name="user[email_address]"]', `reg-mismatch-${Date.now()}@agent44.com`);
    await page.fill('input[name="user[password]"]', "securepass123");
    await page.fill('input[name="user[password_confirmation]"]', "differentpass123");
    await page.getByRole("button", { name: "Sign Up" }).click();

    await expect(page.getByText("Password confirmation doesn't match")).toBeVisible();
  });

  test("registration fails with duplicate email", async ({ page }) => {
    const dupeEmail = `reg-dupe-${Date.now()}@agent44.com`;

    // First registration
    await page.goto("/registration/new");
    await page.fill('input[name="user[email_address]"]', dupeEmail);
    await page.fill('input[name="user[password]"]', "securepass123");
    await page.fill('input[name="user[password_confirmation]"]', "securepass123");
    await page.getByRole("button", { name: "Sign Up" }).click();
    await expect(page).toHaveURL("/");

    // Sign out
    await page.getByRole("button", { name: "Sign Out" }).click();

    // Try to register again with same email
    await page.goto("/registration/new");
    await page.fill('input[name="user[email_address]"]', dupeEmail);
    await page.fill('input[name="user[password]"]', "securepass123");
    await page.fill('input[name="user[password_confirmation]"]', "securepass123");
    await page.getByRole("button", { name: "Sign Up" }).click();

    await expect(page.getByText("already been taken")).toBeVisible();
  });
});

test.describe("Sign in after registration", () => {
  test("can sign in with registered credentials", async ({ page }) => {
    const email = `reg-signin-${Date.now()}@agent44.com`;
    const password = "testpass12345";

    // Register
    await page.goto("/registration/new");
    await page.fill('input[name="user[email_address]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.fill('input[name="user[password_confirmation]"]', password);
    await page.getByRole("button", { name: "Sign Up" }).click();
    await expect(page).toHaveURL("/");

    // Sign out
    await page.getByRole("button", { name: "Sign Out" }).click();

    // Sign in with registered credentials
    await page.goto("/session/new");
    await page.fill('input[name="email_address"]', email);
    await page.fill('input[name="password"]', password);
    await page.getByRole("button", { name: "Sign In" }).click();

    await expect(page).toHaveURL("/");
    await expect(page.getByRole("button", { name: "Sign Out" })).toBeVisible();
  });
});

test.describe("Job listing gate", () => {
  test("job index is accessible without auth", async ({ page }) => {
    await page.goto("/jobs");
    await expect(page.getByRole("heading", { name: /jobs/i })).toBeVisible();
  });

  test("clicking a job redirects to sign in when not authenticated", async ({ page }) => {
    await page.goto("/jobs");

    const jobLink = page.locator("a[href^='/jobs/']").first();
    if (await jobLink.isVisible()) {
      await jobLink.click();
      await expect(page).toHaveURL(/\/session\/new/);
    }
  });

  test("redirects back to job after sign up", async ({ page }) => {
    await page.goto("/jobs");

    const jobLink = page.locator("a[href^='/jobs/']").first();
    if (await jobLink.isVisible()) {
      const href = await jobLink.getAttribute("href");
      await jobLink.click();

      // Should be on sign in page
      await expect(page).toHaveURL(/\/session\/new/);

      // Go to sign up via the in-page link
      await page.locator('a[href="/registration/new"]').last().click();

      // Register
      const email = `reg-gate-${Date.now()}@agent44.com`;
      await page.fill('input[name="user[email_address]"]', email);
      await page.fill('input[name="user[password]"]', "securepass123");
      await page.fill('input[name="user[password_confirmation]"]', "securepass123");
      await page.getByRole("button", { name: "Sign Up" }).click();

      // Should redirect back to the job
      await expect(page).toHaveURL(href!);
    }
  });
});
