# Security Scan Report: agent44_app
**Scan Date:** April 11, 2026  
**Application:** agent44_app (Rails 8.1.2)  
**Scanned By:** Russ Security Guardian

---

## CRITICAL ISSUES (Requires Immediate Action)

### 1. **Hardcoded Secrets in .env File** — SEVERITY: CRITICAL
- **Location:** `/Users/agent44/apps/agent44_app/.env`
- **Finding:** Secrets are stored in plaintext in a file that's checked into version control or deployed
- **Exposed Credentials:**
  - `SERPAPI_KEY=ac83acc5ddd2737b6ac24387d1558b284ec8524370dedadf567ddf33ead3ca43`
  - `API_TOKEN=974f4b566fd899942f69f6aeeda78ca3942a427fb801fbfffa822ff6d60e6974`
  - `PRODUCTION_URL=https://agent44labs.com`
- **Risk:** Anyone with access to the repo or deployed files can steal API keys and call SerpAPI on your account, incurring charges and potentially using for malicious purposes
- **Recommendation:**
  - Move secrets to Rails credentials or environment variables (encrypted at rest)
  - Rotate all exposed API keys immediately
  - Use `config/credentials.yml.enc` for Rails secrets management
  - Add `.env` to `.gitignore` permanently
  - Audit SerpAPI account for unauthorized usage

### 2. **Hardcoded API Key in Source Code** — SEVERITY: HIGH
- **Location:** `/Users/agent44/apps/agent44_app/app/services/scrapers/welcometothejungle.rb`
- **Finding:** Algolia API credentials are hardcoded as class constants:
  ```ruby
  DEFAULT_API_KEY = "4bd8f6215d0cc52b26430765769e65a0"
  DEFAULT_APP_ID = "CSEKHVMS53"
  DEFAULT_ALGOLIA_URL = "https://CSEKHVMS53-dsn.algolia.net/1/indexes/wttj_jobs_production_en/query"
  ```
- **Risk:** This key is publicly visible in the codebase and git history. Anyone can query your Algolia index
- **Recommendation:**
  - Move to environment variables or Rails credentials
  - Rotate the Algolia API key immediately
  - Check git history for similar patterns in other files
  - Consider restricting Algolia key to read-only operations only

### 3. **Rails Master Key Exposed** — SEVERITY: CRITICAL
- **Location:** `/Users/agent44/apps/agent44_app/config/master.key`
- **Finding:** Master key value: `a1120b68f20cb713ea95c6d131f7d450`
- **Risk:** This is the key to decrypt `config/credentials.yml.enc`. If compromised, all encrypted secrets are exposed
- **Recommendation:**
  - This file should NEVER be committed to version control
  - Verify it's in `.gitignore`
  - Regenerate the key: `RAILS_ENV=production bin/rails credentials:rotate_encryption_key`
  - In production, inject via environment variable `RAILS_MASTER_KEY`

---

## HIGH PRIORITY ISSUES

### 4. **Content Security Policy (CSP) Not Enabled** — SEVERITY: HIGH
- **Location:** `/Users/agent44/apps/agent44_app/config/initializers/content_security_policy.rb`
- **Finding:** CSP is completely commented out/disabled
- **Risk:** Vulnerable to Cross-Site Scripting (XSS) attacks. No protection against inline script injection or unauthorized resource loading
- **Recommendation:**
  - Uncomment and enforce CSP with restrictive defaults:
    ```ruby
    config.content_security_policy do |policy|
      policy.default_src :self
      policy.script_src :self, :https
      policy.style_src :self, :https, :data
      policy.img_src :self, :https, :data
      policy.font_src :self, :https, :data
      policy.connect_src :self, :https
      policy.object_src :none
      policy.frame_ancestors :none
    end
    ```
  - Enable nonce-based CSP for imported scripts

### 5. **Insufficient Session Binding Vulnerability (MCP SDK)** — SEVERITY: HIGH
- **Gem:** `mcp` version 0.8.0
- **CVE:** CVE-2026-33946 / GHSA-qvqr-5cv7-wh35
- **Issue:** MCP Ruby SDK vulnerable to SSE stream hijacking via session ID replay
- **Recommendation:**
  - Upgrade to `mcp >= 0.9.2`
  - Update `Gemfile`: `gem "mcp", ">= 0.9.2"`
  - Run `bundle update mcp`

### 6. **API Information Disclosure** — SEVERITY: HIGH
- **Location:** `/Users/agent44/apps/agent44_app/app/controllers/api/v1/stats_controller.rb`
- **Finding:** `/api/v1/stats/users` endpoint returns recent user signups including display names, emails, and timestamps
- **Risk:** With a valid API token, an attacker can enumerate all users and their signup patterns
- **Recommendation:**
  - Add rate limiting to API endpoints: `rate_limit to: 100, within: 1.hour, only: :users`
  - Consider pagination and time-windowing to prevent bulk enumeration
  - Add audit logging for API access
  - Consider OAuth2 or more granular API scopes instead of single token

---

## MEDIUM PRIORITY ISSUES

### 7. **Multiple Dependency Vulnerabilities** — SEVERITY: MEDIUM
- Found 8 vulnerable gems in `Gemfile.lock`:
  
  | Gem | Version | CVE/GHSA | Issue | Action |
  |-----|---------|----------|-------|--------|
  | action_text-trix | 2.1.17 | GHSA-53p3-c7vp-4mcc | XSS via JSON deserialization in drag-and-drop | Update to >= 2.1.18 |
  | activestorage | 8.1.2 | GHSA-p9fm-f462-ggrg | DoS via multi-range requests | Update to >= 8.1.2.1 |
  | bcrypt | 3.1.21 | GHSA-f27w-vcwj-c954 | Integer overflow at cost=31 (JRuby) | Update to >= 3.1.22 |
  | json | 2.19.1 | GHSA-3m6g-2423-7cp3 | Format string injection | Update to >= 2.19.2 |
  | loofah | 2.25.0 | GHSA-46fp-8f5p-pf2m | Improper URI detection bypass | Update to >= 2.25.1 |

- **Recommendation:**
  - Run: `bundle update --conservative` to patch all vulnerabilities
  - Test after updates in staging environment
  - Consider setting up Dependabot to auto-detect future vulnerabilities

### 8. **No SSL/TLS Enforcement in Development** — SEVERITY: MEDIUM
- **Location:** `/Users/agent44/apps/agent44_app/config/environments/production.rb`
- **Finding:** `config.force_ssl = true` is commented out in production config
- **Risk:** Session cookies and API tokens could be transmitted over HTTP in development, but if accidentally used in production, SSL won't be enforced
- **Recommendation:**
  - Uncomment `config.force_ssl = true` in production
  - Add HSTS header: `config.ssl_options = { hsts: { max_age: 31536000, preload: true } }`

### 9. **No Rate Limiting on API Endpoints** — SEVERITY: MEDIUM
- **Finding:** API endpoints (`/api/v1/jobs`, `/api/v1/scrapers`) have no rate limiting
- **Risk:** Brute force attacks on token validation, DOS via bulk imports
- **Recommendation:**
  - Add rate limiting per IP/token:
    ```ruby
    rate_limit to: 50, within: 1.hour, by: -> { request.remote_ip }, only: [:create, :update]
    ```

---

## LOW PRIORITY ISSUES

### 10. **No CORS Configuration** — SEVERITY: LOW
- **Finding:** No explicit CORS policy defined; defaults may allow unintended origins
- **Recommendation:**
  - Add `rack-cors` gem if needed, or explicitly configure in Rails

### 11. **Weak Parameter Logging Filter** — SEVERITY: LOW
- **Location:** `/Users/agent44/apps/agent44_app/config/initializers/filter_parameter_logging.rb`
- **Finding:** Filter only catches common password/token patterns; could miss custom fields
- **Recommendation:**
  - Audit logs regularly for exposed sensitive data
  - Consider sanitizing at controller layer as well

### 12. **Missing Security Headers** — SEVERITY: LOW
- **Finding:** No explicit X-Frame-Options, X-Content-Type-Options, X-XSS-Protection headers configured
- **Recommendation:**
  - Add to `config/environments/production.rb`:
    ```ruby
    config.action_dispatch.default_headers = {
      'X-Frame-Options' => 'DENY',
      'X-Content-Type-Options' => 'nosniff',
      'X-XSS-Protection' => '1; mode=block',
      'Referrer-Policy' => 'strict-origin-when-cross-origin'
    }
    ```

---

## POSITIVE FINDINGS ✅

- ✅ Uses `has_secure_password` with bcrypt for user passwords
- ✅ Session management uses secure signed cookies (`httponly: true`, `same_site: :lax`)
- ✅ API authentication uses `ActiveSupport::SecurityUtils.secure_compare` (timing attack safe)
- ✅ Rate limiting on authentication endpoints (login, registration, password reset)
- ✅ No dangerous `eval()`, `exec()`, or `system()` calls in codebase
- ✅ Using Rails 8.1.2 (recent, well-maintained version)
- ✅ Parameterized queries throughout (no SQL injection vectors found)

---

## IMMEDIATE ACTION ITEMS (Priority Order)

1. **TODAY:** Rotate SERPAPI_KEY, API_TOKEN, and Algolia API key
2. **TODAY:** Regenerate Rails master key (`bin/rails credentials:rotate_encryption_key`)
3. **TODAY:** Move .env secrets to Rails credentials (`rails credentials:edit`)
4. **TODAY:** Verify .env is in .gitignore permanently
5. **TODAY:** Run `bundle update --conservative` to patch gem vulnerabilities
6. **TOMORROW:** Enable Content Security Policy
7. **TOMORROW:** Enable SSL forcing and HSTS headers
8. **THIS WEEK:** Add rate limiting to API endpoints
9. **THIS WEEK:** Audit git history for other hardcoded secrets

---

## TESTING RECOMMENDATIONS

- Run: `bundle audit check` weekly
- Run: `bundle exec brakeman -A` after installing gems (static analysis)
- Add security linting to CI/CD pipeline
- Conduct monthly manual security reviews of authentication flows

---

**Report Generated:** Russ Security Guardian  
**Scan Time:** ~5 minutes  
**Status:** ⚠️ REQUIRES ATTENTION
