// Native apps (iOS / Android) authenticate with `Authorization: Bearer <Supabase access token>`. The user id must come
// only from a token Supabase Auth verified; anything malformed, expired, anonymous or forged is rejected, and a bearer
// request never falls back to cookies.
import { beforeEach, describe, expect, it, vi } from "vitest";

const getClaims = vi.fn();
const created: { headers?: Record<string, string> }[] = [];
const cookieClient = { auth: { getClaims: vi.fn(async () => ({ data: { claims: { sub: "99999999-9999-4999-8999-999999999999", role: "authenticated", exp: Date.now() / 1000 + 600 } }, error: null })) } };

vi.mock("@/lib/supabase/config", () => ({ isDemoMode: false, isSupabaseConfigured: true, supabaseUrl: "https://example.supabase.co", supabasePublicKey: "pk" }));
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn(async () => cookieClient) }));
vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn((_url: string, _key: string, opts: { global?: { headers?: Record<string, string> } }) => {
    created.push({ headers: opts.global?.headers });
    return { auth: { getClaims } };
  }),
}));

const { authenticate, bearerToken, sameOrigin } = await import("@/lib/ai/server");
const { handleChat } = await import("@/lib/ai/chat-handler");
const { firstName } = await import("@/lib/ai-settings");

const USER = "11111111-1111-4111-8111-111111111111";
const TOKEN = "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl";
const req = (headers: Record<string, string>, method = "POST") => new Request("https://spendrop.vercel.app/api/ai/chat", { method, headers });
const claims = (c: Record<string, unknown>) => getClaims.mockResolvedValueOnce({ data: { claims: c }, error: null });

beforeEach(() => { getClaims.mockReset(); created.length = 0; cookieClient.auth.getClaims.mockClear(); });

describe("bearer tokens", () => {
  it("accepts only a JWT-shaped bearer token", () => {
    expect(bearerToken(req({ authorization: `Bearer ${TOKEN}` }))).toBe(TOKEN);
    expect(bearerToken(req({ authorization: `bearer ${TOKEN}` }))).toBe(TOKEN);
    for (const bad of ["Bearer", "Bearer ", "Basic abc", `Bearer ${TOKEN} extra`, "Bearer not-a-jwt", "Bearer a.b", `Bearer ${"a".repeat(9000)}.b.c`, "Bearer a.b.c'--"])
      expect(bearerToken(req({ authorization: bad })), bad).toBeNull();
  });

  it("a verified token → the user id from the token, and the database client sends that same token (RLS sees the user)", async () => {
    claims({ sub: USER, role: "authenticated", exp: Date.now() / 1000 + 600 });
    const auth = await authenticate(req({ authorization: `Bearer ${TOKEN}` }));
    expect(auth.ok && auth.userId).toBe(USER);
    expect(getClaims).toHaveBeenCalledWith(TOKEN);
    expect(created[0].headers).toEqual({ Authorization: `Bearer ${TOKEN}` });
    expect(cookieClient.auth.getClaims).not.toHaveBeenCalled(); // never falls back to (or mixes with) cookies
  });

  it("rejects invalid / forged signatures, expired tokens, the anon key and missing subjects with 401", async () => {
    const cases: [string, () => void][] = [
      ["invalid signature", () => getClaims.mockResolvedValueOnce({ data: null, error: new Error("invalid JWT") })],
      ["expired", () => claims({ sub: USER, role: "authenticated", exp: Date.now() / 1000 - 5 })],
      ["anon key", () => claims({ role: "anon", exp: Date.now() / 1000 + 600 })],
      ["service role", () => claims({ sub: USER, role: "service_role", exp: Date.now() / 1000 + 600 })],
      ["not a uuid", () => claims({ sub: "../../etc", role: "authenticated", exp: Date.now() / 1000 + 600 })],
    ];
    for (const [name, setup] of cases) {
      setup();
      const auth = await authenticate(req({ authorization: `Bearer ${TOKEN}` }));
      expect(auth.ok, name).toBe(false);
      if (!auth.ok) expect(auth.response.status, name).toBe(401);
    }
  });

  it("a malformed Authorization header is rejected outright, not treated as a cookie session", async () => {
    const auth = await authenticate(req({ authorization: "Bearer garbage" }));
    expect(auth.ok).toBe(false);
    expect(cookieClient.auth.getClaims).not.toHaveBeenCalled();
  });

  it("web requests without a bearer token still use the cookie session", async () => {
    const auth = await authenticate(req({}));
    expect(auth.ok && auth.userId).toBe("99999999-9999-4999-8999-999999999999");
  });

  it("CSRF: bearer requests need no Origin (browsers never attach them); cookie POSTs still must be same-origin", () => {
    expect(sameOrigin(req({ authorization: `Bearer ${TOKEN}` }))).toBe(true);
    expect(sameOrigin(req({}))).toBe(false);
    expect(sameOrigin(req({ origin: "https://evil.example", host: "spendrop.vercel.app" }))).toBe(false);
    expect(sameOrigin(req({ origin: "https://spendrop.vercel.app", host: "spendrop.vercel.app" }))).toBe(true);
  });

  it("the chat endpoint rejects a client-chosen user id even with a valid token", async () => {
    const authFn = vi.fn();
    const r = await handleChat(new Request("https://spendrop.vercel.app/api/ai/chat", {
      method: "POST", headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
      body: JSON.stringify({ message: "how much did I spend?", userId: USER }),
    }), { authenticate: authFn, repository: vi.fn(), store: vi.fn(), provider: () => null, debug: false } as never);
    expect(r.status).toBe(400);
    expect(authFn).not.toHaveBeenCalled();
  });
});

describe("Show My Name (presentation only)", () => {
  it("uses the profile name's first word, else a readable email local part, else nothing", () => {
    expect(firstName("Touhidul Islam Rukon", "x@y.com")).toBe("Touhidul");
    expect(firstName(null, "rukon6950@gmail.com")).toBe("Rukon");
    expect(firstName(null, "a.b@c.com")).toBeNull();
    expect(firstName(null, "12345@c.com")).toBeNull();
    expect(firstName(null, null)).toBeNull();
  });
});
