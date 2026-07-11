import Foundation

/// Demo mode (WRANGLERMAC_DEMO=1) short-circuits wrangler/API calls with
/// fabricated data so the app can be screenshotted without exposing a real
/// Cloudflare account. Purely for docs/marketing captures.
enum DemoMode {
    static let on = ProcessInfo.processInfo.environment["WRANGLERMAC_DEMO"] == "1"
}

enum DemoData {
    static let whoamiText = """
     ⛅️ wrangler 4.110.0
    ────────────────────
    Getting User settings...
    👋 You are logged in with an OAuth Token, associated with the email demo@example.com.
    ┌──────────────┬──────────────────────────────────┐
    │ Account Name │ Account ID                       │
    ├──────────────┼──────────────────────────────────┤
    │ Acme Studio  │ 0a1b2c3d4e5f60718293a4b5c6d7e8f9 │
    └──────────────┴──────────────────────────────────┘
    """

    static let workersJSON = """
    [
      {"id":"api-gateway","created_on":"2026-05-02T10:00:00Z","modified_on":"2026-07-09T09:15:00Z","usage_model":"standard"},
      {"id":"image-optimizer","created_on":"2026-04-11T08:00:00Z","modified_on":"2026-07-08T14:22:00Z","usage_model":"standard"},
      {"id":"webhook-relay","created_on":"2026-03-20T12:00:00Z","modified_on":"2026-06-28T11:00:00Z","usage_model":"standard"},
      {"id":"auth-service","created_on":"2026-02-15T09:00:00Z","modified_on":"2026-06-15T16:40:00Z","usage_model":"standard"},
      {"id":"cron-cleaner","created_on":"2026-01-10T09:00:00Z","modified_on":"2026-05-30T07:05:00Z","usage_model":"standard"}
    ]
    """

    static let workerDeploymentsJSON = """
    [
      {"id":"dep-1","source":"wrangler","author_email":"demo@example.com","created_on":"2026-07-09T09:15:00Z","annotations":{"workers/message":"Automatic deployment on upload.","workers/triggered_by":"upload"},"versions":[{"version_id":"a1b2c3d4e5f6","percentage":100}]},
      {"id":"dep-2","source":"wrangler","author_email":"demo@example.com","created_on":"2026-07-08T14:22:00Z","annotations":{"workers/triggered_by":"upload"},"versions":[{"version_id":"f6e7d8c9b0a1","percentage":100}]},
      {"id":"dep-3","source":"dashboard","author_email":"demo@example.com","created_on":"2026-07-01T10:00:00Z","annotations":{},"versions":[{"version_id":"1122334455aa","percentage":100}]}
    ]
    """

    static let workerVersionsJSON = """
    [
      {"id":"a1b2c3d4e5f6a7b8","number":8,"metadata":{"created_on":"2026-07-09T09:15:00Z","source":"wrangler","author_email":"demo@example.com"}},
      {"id":"f6e7d8c9b0a1c2d3","number":7,"metadata":{"created_on":"2026-07-08T14:22:00Z","source":"wrangler","author_email":"demo@example.com"}},
      {"id":"1122334455aa66bb","number":6,"metadata":{"created_on":"2026-07-01T10:00:00Z","source":"dashboard","author_email":"demo@example.com"}}
    ]
    """

    static let secretsJSON = """
    [{"name":"API_KEY","type":"secret_text"},{"name":"DATABASE_URL","type":"secret_text"},{"name":"STRIPE_SECRET","type":"secret_text"}]
    """

    static let kvJSON = """
    [{"id":"3f2a9c1d7e4b8a05","title":"SESSIONS"},{"id":"9b8c7d6e5f4a3b21","title":"CACHE"},{"id":"1d2e3f4a5b6c7d80","title":"FEATURE_FLAGS"}]
    """

    static let d1ListJSON = """
    [{"uuid":"11111111-1111-4111-8111-111111111111","name":"app-db","version":"production"},
     {"uuid":"22222222-2222-4222-8222-222222222222","name":"analytics","version":"production"}]
    """

    static let r2Text = """
     ⛅️ wrangler 4.110.0
    ────────────────────
    Listing buckets...
    name:           assets
    creation_date:  2026-01-15T09:00:00.000Z

    name:           user-uploads
    creation_date:  2026-02-20T10:30:00.000Z

    name:           backups
    creation_date:  2026-03-10T11:45:00.000Z
    """

    static let queuesText = """
     ⛅️ wrangler 4.110.0
    ────────────────────
    ┌──────────────────┬──────────────────────────────────┐
    │ name             │ id                               │
    ├──────────────────┼──────────────────────────────────┤
    │ email-queue      │ aaaa1111bbbb2222cccc3333dddd4444 │
    │ image-processing │ eeee5555ffff6666aaaa7777bbbb8888 │
    └──────────────────┴──────────────────────────────────┘
    """

    static let pagesJSON = """
    [
      {"id":"p1","name":"marketing-site","subdomain":"marketing-site.pages.dev","domains":["www.acme.example"],"created_on":"2026-03-01T10:00:00Z","production_branch":"main","framework":"astro","uses_functions":false,
       "latest_deployment":{"id":"pd1","short_id":"ab12cd","environment":"production","url":"https://ab12cd.marketing-site.pages.dev","created_on":"2026-07-09T08:00:00Z","latest_stage":{"name":"deploy","status":"success"},"deployment_trigger":{"metadata":{"branch":"main","commit_hash":"ab12cd34","commit_message":"Update hero section"}}},
       "source":{"type":"github","config":{"owner":"acme","repo_name":"marketing-site"}}},
      {"id":"p2","name":"docs","subdomain":"docs-hub.pages.dev","domains":[],"created_on":"2026-02-01T09:00:00Z","production_branch":"main","framework":"next","uses_functions":true,
       "latest_deployment":{"id":"pd2","short_id":"cd34ef","environment":"preview","url":"https://cd34ef.docs-hub.pages.dev","created_on":"2026-07-07T13:00:00Z","latest_stage":{"name":"deploy","status":"success"},"deployment_trigger":{"metadata":{"branch":"feature/search","commit_hash":"cd34ef56","commit_message":"Add search to docs"}}},
       "source":{"type":"github","config":{"owner":"acme","repo_name":"docs"}}},
      {"id":"p3","name":"status-page","subdomain":"status-page.pages.dev","domains":[],"created_on":"2026-04-20T11:00:00Z","production_branch":"main","framework":"","uses_functions":false,
       "latest_deployment":{"id":"pd3","short_id":"ef56ab","environment":"production","url":"https://ef56ab.status-page.pages.dev","created_on":"2026-06-30T09:30:00Z","latest_stage":{"name":"deploy","status":"success"},"deployment_trigger":{"metadata":{"branch":"main"}}},
       "source":null}
    ]
    """

    static let pagesDeploymentsJSON = """
    [
      {"id":"pd1","short_id":"ab12cd","environment":"production","url":"https://ab12cd.marketing-site.pages.dev","created_on":"2026-07-09T08:00:00Z","latest_stage":{"name":"deploy","status":"success"},"deployment_trigger":{"metadata":{"branch":"main","commit_message":"Update hero section"}}},
      {"id":"pd0","short_id":"99ff00","environment":"preview","url":"https://99ff00.marketing-site.pages.dev","created_on":"2026-07-05T12:00:00Z","latest_stage":{"name":"deploy","status":"success"},"deployment_trigger":{"metadata":{"branch":"feature/pricing","commit_message":"Draft pricing page"}}},
      {"id":"pdx","short_id":"33aa77","environment":"production","url":"https://33aa77.marketing-site.pages.dev","created_on":"2026-06-28T15:00:00Z","latest_stage":{"name":"deploy","status":"success"},"deployment_trigger":{"metadata":{"branch":"main","commit_message":"Fix footer links"}}}
    ]
    """

    // D1 demo schema: users → posts → comments.
    static let schemaTablesJSON = """
    [{"results":[
      {"name":"comments","sql":"CREATE TABLE comments (id INTEGER PRIMARY KEY, post_id INTEGER NOT NULL, user_id INTEGER NOT NULL, body TEXT NOT NULL, created_at TEXT DEFAULT (datetime('now')), FOREIGN KEY (post_id) REFERENCES posts(id), FOREIGN KEY (user_id) REFERENCES users(id))"},
      {"name":"posts","sql":"CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL, body TEXT, published INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')), FOREIGN KEY (user_id) REFERENCES users(id))"},
      {"name":"users","sql":"CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, name TEXT, avatar_color TEXT DEFAULT '#7C5CFC', created_at TEXT DEFAULT (datetime('now')))"}
    ],"success":true,"meta":{}}]
    """

    // Pragmas in table order: comments, posts, users (table_info then foreign_key_list each).
    static let schemaPragmaJSON = """
    [
      {"results":[
        {"cid":0,"name":"id","type":"INTEGER","notnull":0,"dflt_value":null,"pk":1},
        {"cid":1,"name":"post_id","type":"INTEGER","notnull":1,"dflt_value":null,"pk":0},
        {"cid":2,"name":"user_id","type":"INTEGER","notnull":1,"dflt_value":null,"pk":0},
        {"cid":3,"name":"body","type":"TEXT","notnull":1,"dflt_value":null,"pk":0},
        {"cid":4,"name":"created_at","type":"TEXT","notnull":0,"dflt_value":"datetime('now')","pk":0}
      ],"success":true,"meta":{}},
      {"results":[
        {"id":0,"seq":0,"table":"users","from":"user_id","to":"id"},
        {"id":1,"seq":0,"table":"posts","from":"post_id","to":"id"}
      ],"success":true,"meta":{}},
      {"results":[
        {"cid":0,"name":"id","type":"INTEGER","notnull":0,"dflt_value":null,"pk":1},
        {"cid":1,"name":"user_id","type":"INTEGER","notnull":1,"dflt_value":null,"pk":0},
        {"cid":2,"name":"title","type":"TEXT","notnull":1,"dflt_value":null,"pk":0},
        {"cid":3,"name":"body","type":"TEXT","notnull":0,"dflt_value":null,"pk":0},
        {"cid":4,"name":"published","type":"INTEGER","notnull":0,"dflt_value":"0","pk":0},
        {"cid":5,"name":"created_at","type":"TEXT","notnull":0,"dflt_value":"datetime('now')","pk":0}
      ],"success":true,"meta":{}},
      {"results":[
        {"id":0,"seq":0,"table":"users","from":"user_id","to":"id"}
      ],"success":true,"meta":{}},
      {"results":[
        {"cid":0,"name":"id","type":"INTEGER","notnull":0,"dflt_value":null,"pk":1},
        {"cid":1,"name":"email","type":"TEXT","notnull":1,"dflt_value":null,"pk":0},
        {"cid":2,"name":"name","type":"TEXT","notnull":0,"dflt_value":null,"pk":0},
        {"cid":3,"name":"avatar_color","type":"TEXT","notnull":0,"dflt_value":"'#7C5CFC'","pk":0},
        {"cid":4,"name":"created_at","type":"TEXT","notnull":0,"dflt_value":"datetime('now')","pk":0}
      ],"success":true,"meta":{}},
      {"results":[],"success":true,"meta":{}}
    ]
    """

    /// Dispatch a wrangler command to canned output.
    static func result(for args: [String]) -> CLIResult {
        let cmd = "wrangler " + args.joined(separator: " ")
        func ok(_ s: String) -> CLIResult { CLIResult(command: cmd, exitCode: 0, stdout: s, stderr: "") }

        if args == ["--version"] { return ok("⛅️ wrangler 4.110.0") }
        if args.first == "whoami" { return ok(whoamiText) }
        if args.starts(with: ["kv", "namespace", "list"]) { return ok(kvJSON) }
        if args.starts(with: ["d1", "list"]) { return ok(d1ListJSON) }
        if args.starts(with: ["r2", "bucket", "list"]) { return ok(r2Text) }
        if args.starts(with: ["queues", "list"]) { return ok(queuesText) }
        if args.contains("secret") && args.contains("list") { return ok(secretsJSON) }
        if args.starts(with: ["deployments", "list"]) { return ok(workerDeploymentsJSON) }
        if args.starts(with: ["versions", "list"]) { return ok(workerVersionsJSON) }
        if args.starts(with: ["d1", "execute"]), let i = args.firstIndex(of: "--command"), i + 1 < args.count {
            let sql = args[i + 1]
            if sql.contains("sqlite_master") { return ok(schemaTablesJSON) }
            if sql.contains("PRAGMA table_info") { return ok(schemaPragmaJSON) }
            return ok(#"[{"results":[],"success":true,"meta":{}}]"#)
        }
        return ok("")
    }
}
