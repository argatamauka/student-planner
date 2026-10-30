alter table public.tasks
  add column if not exists description text not null default '',
  add column if not exists category text not null default 'Akademik',
  add column if not exists priority text not null default 'medium';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_priority_check'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_priority_check
      check (priority in ('low', 'medium', 'high'));
  end if;
end $$;

create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  description text not null default '',
  category text not null default 'Personal',
  frequency text not null default 'daily'
    check (frequency in ('daily', 'weekly', 'custom')),
  days_of_week smallint[] not null default array[1,2,3,4,5,6,7]::smallint[],
  target_per_week smallint not null default 7
    check (target_per_week between 1 and 7),
  color text not null default 'green',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  completed_on date not null default current_date,
  note text not null default '',
  created_at timestamptz not null default now(),
  constraint habit_logs_one_per_day unique (habit_id, completed_on)
);

create index if not exists habits_user_active_sort_idx
  on public.habits (user_id, active, sort_order, created_at);
create index if not exists habit_logs_user_date_idx
  on public.habit_logs (user_id, completed_on desc);
create index if not exists habit_logs_habit_date_idx
  on public.habit_logs (habit_id, completed_on desc);

alter table public.habits enable row level security;
alter table public.habit_logs enable row level security;

drop policy if exists habits_owner_all on public.habits;
create policy habits_owner_all on public.habits
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists habit_logs_owner_all on public.habit_logs;
create policy habit_logs_owner_all on public.habit_logs
  for all to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.habits h
      where h.id = habit_logs.habit_id
        and h.user_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.habits h
      where h.id = habit_logs.habit_id
        and h.user_id = (select auth.uid())
    )
  );

grant select, insert, update, delete on public.habits to authenticated;
grant select, insert, update, delete on public.habit_logs to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'habits'
  ) then
    alter publication supabase_realtime add table public.habits;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'habit_logs'
  ) then
    alter publication supabase_realtime add table public.habit_logs;
  end if;
end $$;
