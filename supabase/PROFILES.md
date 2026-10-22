# 公开作者资料升级

评论作者名字和公开个人主页使用 `public.profiles`，只提供 `id`、`display_name`、`avatar_url` 三列。名字按 GitHub 姓名、用户名、`GitHub member` 的顺序回退；不复制邮箱、令牌或完整用户元数据。头像仅接受 GitHub 的 `avatars.githubusercontent.com/u/数字` 地址，其他地址显示名字首字母。

## 执行一次

1. 已有网站：在 Supabase 项目的 SQL Editor 中，以数据库管理员身份执行完整的 `supabase/profiles.sql`。
2. 新项目：执行 `supabase/schema.sql`，其中已经包含同一段配置。
3. 更新并发布网站前端。

升级脚本可以重复执行，会保留评论、收藏和现有审核规则。它会回填已通过 GitHub 登录的用户，不需要用户重新注册。部署网站本身不会执行 SQL。

## 同步规则

- 资料来自 `auth.identities` 中 `provider = 'github'` 的 `identity_data`。前端不能新增或修改公开资料；客户端可修改的 `user_metadata` 不参与同步。
- 新用户 GitHub 登录、GitHub 身份资料更新时自动同步。GitHub 上改名后，需要再次完成 GitHub 登录，Supabase 收到新资料后才更新；仅刷新网页或刷新会话不会主动请求 GitHub。
- 移除某个 GitHub 身份后，使用剩余的 GitHub 身份；没有剩余 GitHub 身份则删除公开资料。删除 Auth 用户时，外键自动删除其公开资料。
- 同一个用户有多个 GitHub 身份时，优先使用最近更新的身份。
- 主页是公开的，访客无需登录即可看见名字和头像；姓名可以重名或被 GitHub 用户自己修改，不能作为管理员权限或身份唯一标识。

## 验证

先在 SQL Editor 检查回填结果：

```sql
select id, display_name, avatar_url from public.profiles;
```

确认匿名和登录用户都能读取，并且没有写入权限：

```sql
select role_name,
       has_column_privilege(role_name, 'public.profiles', 'id', 'SELECT') as can_read,
       has_any_column_privilege(role_name, 'public.profiles', 'INSERT') as can_insert,
       has_any_column_privilege(role_name, 'public.profiles', 'UPDATE') as can_update,
       has_table_privilege(role_name, 'public.profiles', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as roles(role_name);
```

正常结果是 `can_read = true`，其余三项均为 `false`。

用两个测试账号检查：匿名访客能看到已批准评论的作者名字；点击名字打开对应作者主页；自己登录后仍能访问自己的主页；未审核评论仍仅对作者本人可见。不要为测试而在正式项目删除真实用户或解除真实账号关联。

`supabase/test_profiles.sql` 是可回滚的数据库检查脚本，仅在独立测试项目运行：它会临时创建 Auth 测试用户与身份，验证同步、权限、回填和删除逻辑，最后回滚，不用于正式数据维护。

## 故障处理

如果出现 `profiles` 不存在，先确认升级 SQL 已在当前 Supabase 项目成功执行。如果名字仍是旧的，退出后重新通过 GitHub 登录。

同步使用 Auth 数据库触发器；触发器出错可能影响 GitHub 登录。应先在测试项目验证。紧急停用同步可由管理员执行以下语句，不会删除 Auth 用户或公开资料：

```sql
drop trigger if exists npu_sync_github_profile on auth.identities;
```

修复后重新执行 `profiles.sql` 即可重建触发器并回填。不要通过给浏览器开放写权限来绕过问题。

依据：[Supabase Identities](https://supabase.com/docs/guides/auth/identities)、[用户资料表与触发器](https://supabase.com/docs/guides/auth/managing-user-data)、[数据库函数权限](https://supabase.com/docs/guides/database/functions)。
