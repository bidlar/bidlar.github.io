(() => {

  const SUPABASE_URL = "https://uqgmzhtexgbxhrncgeet.supabase.co";
  const SUPABASE_KEY = "sb_publishable_79a6dvW0uC9Yk88ULQI1SQ_BCrlUj4z";


  const pages = {
    home: { title: "Home", path: "" },
    contribute: { title: "Contribute", path: "support/Contribute/" }
  };
  const siteRoot = new URL("../", document.currentScript.src).href;
  const configured = !SUPABASE_URL.includes("YOUR_PROJECT") && SUPABASE_KEY !== "YOUR_PUBLISHABLE_KEY";
  const db = configured && window.supabase
    ? window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
        auth: { flowType: "pkce" }
      })
    : null;
  let generation = 0;
  let authUserId;

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

  const refresh = () => { mount().catch(error => {
    const root = document.querySelector(".doc-community");
    if (root) root.textContent = `Could not load community features: ${error.message}`;
  }); };

  if (db) db.auth.onAuthStateChange((event, session) => {
    const nextUserId = session?.user?.id ?? null;
    const changed = authUserId !== undefined && authUserId !== nextUserId;
    authUserId = nextUserId;
    if (changed || event === "USER_UPDATED") setTimeout(refresh, 0);
  });
 
  if (typeof document$ !== "undefined") document$.subscribe(refresh);
  else if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", refresh);
  else refresh();
})();
