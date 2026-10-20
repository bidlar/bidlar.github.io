(() => {

  const SUPABASE_URL = "https://uqgmzhtexgbxhrncgeet.supabase.co";
  const SUPABASE_KEY = "sb_publishable_79a6dvW0uC9Yk88ULQI1SQ_BCrlUj4z";


  const pages = {
    home: { title: "Home", path: "" },
    contribute: { title: "Contribute", path: "support/contribute/" }
  };
  const siteRoot = new URL("../", document.currentScript.src).href;
  const profileUrl = new URL("profile/", siteRoot).href;
  const profileReturnKey = "npu.profile.return";
  const configured = !SUPABASE_URL.includes("YOUR_PROJECT") && SUPABASE_KEY !== "YOUR_PUBLISHABLE_KEY";
  const db = configured && window.supabase
    ? window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
        auth: { flowType: "pkce" }
      })
    : null;
  let generation = 0;
  let authUserId;
  let profileGeneration = 0;

  function setProfileReturn(value) {
    try {
      if (value) window.sessionStorage.setItem(profileReturnKey, "1");
      else window.sessionStorage.removeItem(profileReturnKey);
    } catch (_) { /* Sign-in still works if browser storage is unavailable. */ }
  }

  function consumeProfileReturn() {
    try {
      const requested = window.sessionStorage.getItem(profileReturnKey) === "1";
      window.sessionStorage.removeItem(profileReturnKey);
      return requested;
    } catch (_) { return false; }
  }

  async function mountProfile() {
    const version = ++profileGeneration;
    const root = document.querySelector(".npu-profile");
    if (!root) return;
    const alive = () => root.isConnected && version === profileGeneration;
    if (!db) {
      root.textContent = "Your profile is unavailable right now. Please try again later.";
      return;
    }
    root.innerHTML = `
      <section class="npu-profile-card" aria-busy="true">
        <div class="npu-profile-avatar" aria-hidden="true"><span class="npu-profile-initial">?</span></div>
        <div class="npu-profile-info">
          <p class="npu-profile-eyebrow">YOUR ACCOUNT</p>
          <h2 class="npu-profile-name">Loading your profile…</h2>
          <p class="npu-profile-description"></p>
        </div>
      </section>
      <div class="npu-profile-actions">
        <button type="button" class="npu-profile-login" hidden>Sign in with GitHub</button>
        <button type="button" class="npu-profile-logout" hidden>Sign out</button>
        <button type="button" class="npu-profile-retry" hidden>Try again</button>
      </div>
      <p class="npu-profile-message" role="status" aria-live="polite"></p>`;
    const $ = (selector) => root.querySelector(selector);
    const message = (text) => { if (alive()) $(".npu-profile-message").textContent = text; };
    const run = async (button, action) => {
      button.disabled = true;
      try { await action(); }
      catch (error) { message(error.message || "Something went wrong. Please try again."); }
      finally { if (alive()) button.disabled = false; }
    };
    $(".npu-profile-login").onclick = () => run($(".npu-profile-login"), async () => {
      setProfileReturn(true);
      try {
        const { error } = await db.auth.signInWithOAuth({
          provider: "github", options: { redirectTo: siteRoot }
        });
        if (error) throw error;
      } catch (error) { setProfileReturn(false); throw error; }
    });
    $(".npu-profile-logout").onclick = () => run($(".npu-profile-logout"), async () => {
      const { error } = await db.auth.signOut();
      if (error) throw error;
    });
    $(".npu-profile-retry").onclick = () => mountProfile();

    const showGuest = () => {
      $(".npu-profile-card").setAttribute("aria-busy", "false");
      $(".npu-profile-name").textContent = "Make yourself at home";
      $(".npu-profile-description").textContent = "Sign in to see your GitHub photo and name.";
      $(".npu-profile-login").hidden = false;
      $(".npu-profile-logout").hidden = true;
    };
    try {
      const { data: sessionData, error: sessionError } = await db.auth.getSession();
      if (!alive()) return;
      if (sessionError) throw sessionError;
      if (!sessionData.session?.user) { showGuest(); return; }
      $(".npu-profile-logout").hidden = false;

      const { data, error } = await db.auth.getUser();
      if (!alive()) return;
      if (error) throw error;
      if (!data.user) { showGuest(); return; }
      const identity = data.user.identities?.find(item => item.provider === "github")?.identity_data || {};
      const metadata = data.user.user_metadata || {};
      const firstText = (...values) => values.find(value => typeof value === "string" && value.trim())?.trim() || "";
      const name = firstText(identity.full_name, identity.name, metadata.full_name, metadata.name,
        identity.user_name, identity.preferred_username, metadata.user_name, metadata.preferred_username) || "GitHub member";
      $(".npu-profile-name").textContent = name;
      $(".npu-profile-initial").textContent = Array.from(name)[0].toLocaleUpperCase();
      $(".npu-profile-description").textContent = "Connected with GitHub";
      $(".npu-profile-card").setAttribute("aria-busy", "false");
      const avatar = firstText(identity.avatar_url, metadata.avatar_url);
      try {
        const url = new URL(avatar);
        if (url.protocol === "https:" && url.hostname === "avatars.githubusercontent.com" && !url.username && !url.password) {
          const image = document.createElement("img");
          image.alt = "";
          image.width = 120;
          image.height = 120;
          image.referrerPolicy = "no-referrer";
          image.onerror = () => image.remove();
          image.src = url.href;
          $(".npu-profile-avatar").append(image);
        }
      } catch (_) { /* Missing or invalid avatars use the name initial. */ }
    } catch (_) {
      if (!alive()) return;
      $(".npu-profile-card").setAttribute("aria-busy", "false");
      $(".npu-profile-name").textContent = "We couldn't load your profile";
      $(".npu-profile-description").textContent = "Check your connection and try again.";
      $(".npu-profile-retry").hidden = false;
    }
  }

  async function mount() {
    const version = ++generation;
    const root = document.querySelector(".doc-community");
    if (!root) return;
    if (!db) {
      root.textContent = "Community features are unavailable. Please try again later.";
      return;
    }
    const pageId = root.dataset.pageId;
    if (!pages[pageId]) {
      root.textContent = "Community features are not configured for this page.";
      return;
    }
    const alive = () => root.isConnected && version === generation;
    root.innerHTML = `
      <h2>Comments and bookmarks</h2>
      <p class="account">Checking sign-in status…</p>
      <button type="button" class="login">Sign in with GitHub</button>
      <button type="button" class="logout" hidden>Sign out</button>
      <a class="profile-link" hidden>My profile</a>
      <button type="button" class="bookmark" disabled>Bookmark this page</button>
      <p class="message" role="status" aria-live="polite"></p>
      <form>
        <label>Leave a comment<textarea required maxlength="2000" rows="3" disabled></textarea></label>
        <button type="submit" disabled>Submit for review</button>
      </form>
      <p><small>Comments are reviewed before publication. Submit at most once every 60 seconds and 10 times in any 24 hours. Only you can see your pending or rejected comments.</small></p>
      <h3>Latest comments (up to 50)</h3><div class="comments">Loading…</div>
      <h3>My bookmarks (latest 100)</h3><ul class="bookmarks"></ul>`;
    const $ = (selector) => root.querySelector(selector);
    const message = (text) => { if (alive()) $(".message").textContent = text; };
    function errorMessage(error) {
      const messages = {
        COMMENT_BANNED: "Commenting is disabled for this account.",
        COMMENT_RATE_MINUTE: "Please wait at least 60 seconds between submissions.",
        COMMENT_RATE_DAY: "You have reached the limit of 10 submissions in 24 hours. Please try again later.",
        COMMENT_IDENTITY_INVALID: "Your session could not be verified. Please sign in again."
      };
      return messages[error?.message] || error?.message || "Something went wrong. Please try again.";
    }
    async function run(button, action) {
      button.disabled = true;
      try { await action(); }
      catch (error) { message(errorMessage(error)); }
      finally { if (alive()) button.disabled = false; }
    }

    const { data: sessionData, error: sessionError } = await db.auth.getSession();
    if (!alive()) return;
    if (sessionError) { message(sessionError.message); return; }
    const user = sessionData.session?.user;
    $(".account").textContent = user ? "Signed in. You can comment and bookmark pages." : "Sign in to leave a comment and save bookmarks.";
    $(".login").hidden = !!user;
    $(".logout").hidden = !user;
    $(".profile-link").href = profileUrl;
    $(".profile-link").hidden = !user;
    $("textarea").disabled = !user;
    $("button[type=submit]").disabled = !user;

    $(".login").onclick = () => run($(".login"), async () => {
      const { error } = await db.auth.signInWithOAuth({
        provider: "github", options: { redirectTo: siteRoot }
      });
      if (error) throw error;
    });
    $(".logout").onclick = () => run($(".logout"), async () => {
      const { error } = await db.auth.signOut();
      if (error) throw error;
    });

    async function comments() {
      const { data, error } = await db.from("comments")
        .select("id,user_id,content,created_at,status").eq("page_id", pageId)
        .order("created_at", { ascending: false }).limit(50);
      if (!alive()) return;
      if (error) { $(".comments").textContent = "Could not load comments."; throw error; }
      const list = $(".comments");
      list.replaceChildren();
      if (!data.length) list.textContent = "No comments yet.";
      for (const row of data) {
        const article = document.createElement("article");
        const meta = document.createElement("small");
        meta.textContent = `${row.user_id === user?.id ? "You" : "Reader"} · ${new Date(row.created_at).toLocaleString()}`;
        if (row.status === "pending") meta.textContent += " · Pending review (only visible to you)";
        if (row.status === "rejected") meta.textContent += " · Not approved (only visible to you)";
        const text = document.createElement("p");
        text.textContent = row.content;
        article.append(meta, text);
        if (row.user_id === user?.id) {
          const button = document.createElement("button");
          button.type = "button";
          button.textContent = "Delete my comment";
          button.onclick = () => run(button, async () => {
            const { error } = await db.from("comments").delete().eq("id", row.id);
            if (error) throw error;
            await comments();
          });
          article.append(button);
        }
        list.append(article);
      }
    }

    let saved = false;
    async function bookmarks() {
      if (!user) { $(".bookmarks").textContent = "Sign in to view your bookmarks."; return; }
      const { data, error } = await db.from("bookmarks").select("page_id")
        .eq("user_id", user.id).order("created_at", { ascending: false }).limit(100);

      const current = await db.from("bookmarks").select("page_id")
        .eq("user_id", user.id).eq("page_id", pageId).maybeSingle();
      if (!alive()) return;
      if (error) throw error;
      if (current.error) throw current.error;
      saved = !!current.data;
      $(".bookmark").textContent = saved ? "Remove bookmark" : "Bookmark this page";
      $(".bookmark").disabled = false;
      const list = $(".bookmarks");
      list.replaceChildren();
      if (!data.length) list.textContent = "No bookmarks yet.";
      for (const row of data) {
        const item = document.createElement("li");
        const page = pages[row.page_id];
        if (page) {
          const link = document.createElement("a");
          link.href = new URL(page.path, siteRoot).href;
          link.textContent = page.title;
          item.append(link);
        } else { item.textContent = `Page not registered: ${row.page_id}`; }
        list.append(item);
      }
    }
    $(".bookmark").onclick = () => run($(".bookmark"), async () => {
      if (!user) throw new Error("Please sign in first.");
      const result = saved
        ? await db.from("bookmarks").delete().eq("user_id", user.id).eq("page_id", pageId)
        : await db.from("bookmarks").insert({ page_id: pageId });
      if (result.error && result.error.code !== "23505") throw result.error;
      await bookmarks();
    });
    $("form").onsubmit = (event) => {
      event.preventDefault();
      const field = $("textarea");
      const content = field.value.trim();
      if (!content) { message("Please enter a comment."); return; }
      return run($("button[type=submit]"), async () => {
        if (!user) throw new Error("Please sign in first.");
        const { error } = await db.from("comments").insert({ page_id: pageId, content });
        if (error) throw error;
        if (alive()) field.value = "";
        message("Submitted for review. Your comment will be public after approval.");
        try { await comments(); }
        catch (_) { message("Submitted for review. Refresh the page to reload comments."); }
      });
    };
    const results = await Promise.allSettled([comments(), bookmarks()]);
    for (const result of results) if (result.status === "rejected") message(result.reason.message);
  }

  const refresh = () => {
    mountProfile().catch(() => {});
    mount().catch(error => {
    const root = document.querySelector(".doc-community");
    if (root) root.textContent = `Could not load community features: ${error.message}`;
    });
  };

  if (db) db.auth.onAuthStateChange((event, session) => {
    if (session?.user && consumeProfileReturn()) {
      if (window.location.pathname !== new URL(profileUrl).pathname) {
        setTimeout(() => window.location.assign(profileUrl), 0);
      }
    }
    const nextUserId = session?.user?.id ?? null;
    const changed = authUserId !== undefined && authUserId !== nextUserId;
    authUserId = nextUserId;
    if (changed || event === "USER_UPDATED") setTimeout(refresh, 0);
  });

  if (typeof document$ !== "undefined") document$.subscribe(refresh);
  else if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", refresh);
  else refresh();
})();
