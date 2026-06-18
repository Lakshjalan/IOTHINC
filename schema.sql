-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Helper function to get the current user's role
create or replace function public.get_my_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql security definer;

-- TABLE: profiles
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  full_name text not null,
  email text not null unique,
  role text not null default 'member' check (role in ('admin', 'coordinator', 'member')),
  department text,
  year text,
  skills text[],
  bio text,
  avatar_url text,
  github_url text,
  linkedin_url text,
  needs_approval boolean not null default true,
  created_at timestamptz default now()
);

-- TABLE: teams
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  department text,
  lead_id uuid references public.profiles(id) on delete set null,
  status text default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz default now()
);

-- TABLE: team_members
create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid references public.teams(id) on delete cascade,
  member_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz default now()
);

-- TABLE: events
create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text check (category in ('WORKSHOP','HACKATHON','SEMINAR','COMPETITION','OTHER')),
  venue text,
  event_date timestamptz,
  registration_deadline timestamptz,
  max_seats integer,
  status text default 'upcoming' check (status in ('upcoming','ongoing','past','cancelled')),
  organiser_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- TABLE: registrations
create table public.registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.events(id) on delete cascade,
  member_id uuid references public.profiles(id) on delete cascade,
  status text default 'confirmed' check (status in ('confirmed','pending','cancelled')),
  notify boolean default true,
  registered_at timestamptz default now(),
  unique(event_id, member_id)
);

-- TABLE: projects
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text,
  status text default 'planned' check (status in ('planned','active','completed','blocked')),
  milestone text,
  progress integer default 0 check (progress >= 0 and progress <= 100),
  deadline date,
  team_id uuid references public.teams(id) on delete set null,
  created_at timestamptz default now()
);

-- TABLE: contributions
create table public.contributions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  photo_url text,
  event_id uuid references public.events(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  categories text[],
  visibility text default 'public' check (visibility in ('public','private')),
  flagged boolean not null default false,
  created_at timestamptz default now()
);

-- TABLE: contribution_comments
create table public.contribution_comments (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid references public.contributions(id) on delete cascade,
  author_id uuid references public.profiles(id) on delete cascade,
  comment text not null,
  created_at timestamptz default now()
);

-- TABLE: tasks
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  assigned_to uuid references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  status text default 'not_started' check (status in ('not_started','in_progress','completed','blocked')),
  priority text default 'medium' check (priority in ('high','medium','low')),
  progress integer default 0 check (progress >= 0 and progress <= 100),
  due_date date,
  admin_comment text,
  created_at timestamptz default now()
);

-- TABLE: notifications
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  type text check (type in ('event','announcement','task','system')),
  priority integer not null check (priority in (1, 2, 3)), -- 1=admin, 2=coordinator, 3=member
  target_role text check (target_role in ('all','admin','coordinator','member')),
  target_member_id uuid references public.profiles(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  sender_id uuid references public.profiles(id) on delete set null,
  is_read boolean default false,
  created_at timestamptz default now()
);

-- TABLE: competitions
create table public.competitions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  type text check (type in ('hackathon','coding_contest','design_jam','other')),
  format text check (format in ('solo','team','both')),
  registration_deadline timestamptz,
  start_date timestamptz,
  prize_pool text,
  status text default 'active' check (status in ('active','completed','archived')),
  hosted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- TABLE: competition_submissions
create table public.competition_submissions (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid references public.competitions(id) on delete cascade,
  member_id uuid references public.profiles(id) on delete cascade,
  team_name text,
  status text default 'draft' check (status in ('draft','submitted','reviewed')),
  result text,
  created_at timestamptz default now()
);

-- TABLE: learning_resources
create table public.learning_resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  type text check (type in ('VIDEO','ARTICLE','PDF','WORKSHOP')),
  description text,
  url text,
  track text,
  duration_mins integer,
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- Enable RLS on all tables
alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.events enable row level security;
alter table public.registrations enable row level security;
alter table public.projects enable row level security;
alter table public.contributions enable row level security;
alter table public.contribution_comments enable row level security;
alter table public.tasks enable row level security;
alter table public.notifications enable row level security;
alter table public.competitions enable row level security;
alter table public.competition_submissions enable row level security;
alter table public.learning_resources enable row level security;

-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- 1. profiles policies
create policy "Authenticated users can read all profiles"
  on public.profiles for select
  using (auth.role() = 'authenticated');

create policy "Users can update own profile or admins can update any"
  on public.profiles for update
  using (auth.uid() = id or public.get_my_role() = 'admin');

create policy "Admins can delete profiles"
  on public.profiles for delete
  using (public.get_my_role() = 'admin');

-- 2. events policies
create policy "Authenticated users can read all events"
  on public.events for select
  using (auth.role() = 'authenticated');

create policy "Admins and coordinators can modify events"
  on public.events for all
  using (public.get_my_role() in ('admin', 'coordinator'));

-- 3. registrations policies
create policy "Select registration"
  on public.registrations for select
  using (auth.uid() = member_id or public.get_my_role() in ('admin', 'coordinator'));

create policy "Insert registration"
  on public.registrations for insert
  with check (auth.uid() = member_id);

create policy "Delete registration"
  on public.registrations for delete
  using (auth.uid() = member_id or public.get_my_role() = 'admin');

-- 4. contributions policies
create policy "Select contribution"
  on public.contributions for select
  using (visibility = 'public' or auth.uid() = member_id or public.get_my_role() = 'admin');

create policy "Insert contribution"
  on public.contributions for insert
  with check (auth.uid() = member_id);

create policy "Update or delete contribution"
  on public.contributions for all
  using (auth.uid() = member_id or public.get_my_role() = 'admin');

-- 5. contribution_comments policies
create policy "Select comments"
  on public.contribution_comments for select
  using (auth.role() = 'authenticated');

create policy "Insert comment"
  on public.contribution_comments for insert
  with check (auth.uid() = author_id);

create policy "Update or delete comment"
  on public.contribution_comments for all
  using (auth.uid() = author_id or public.get_my_role() = 'admin');

-- 6. tasks policies
create policy "Select task"
  on public.tasks for select
  using (auth.uid() = assigned_to or public.get_my_role() in ('admin', 'coordinator'));

create policy "Insert/update task (admin/coordinator)"
  on public.tasks for all
  using (public.get_my_role() in ('admin', 'coordinator'));

create policy "Update task progress (assigned member)"
  on public.tasks for update
  using (auth.uid() = assigned_to)
  with check (auth.uid() = assigned_to);

-- 7. notifications policies
create policy "Select notification"
  on public.notifications for select
  using (
    auth.uid() = target_member_id 
    or target_role = 'all' 
    or target_role = public.get_my_role()
    or public.get_my_role() = 'admin'
  );

create policy "Insert notification (admin/coordinator)"
  on public.notifications for insert
  with check (public.get_my_role() in ('admin', 'coordinator'));

create policy "Update notification (is_read)"
  on public.notifications for update
  using (auth.uid() = target_member_id)
  with check (auth.uid() = target_member_id);

-- 8. projects, teams, team_members, competitions, competition_submissions, learning_resources policies
-- SELECT: all authenticated
-- INSERT/UPDATE/DELETE: admin only (coordinator for own events/competitions)
-- Let's create policies for these tables.

-- teams
create policy "Select teams" on public.teams for select using (auth.role() = 'authenticated');
create policy "Modify teams" on public.teams for all using (public.get_my_role() = 'admin');

-- team_members
create policy "Select team_members" on public.team_members for select using (auth.role() = 'authenticated');
create policy "Modify team_members" on public.team_members for all using (public.get_my_role() = 'admin');

-- projects
create policy "Select projects" on public.projects for select using (auth.role() = 'authenticated');
create policy "Modify projects" on public.projects for all using (public.get_my_role() in ('admin', 'coordinator'));

-- competitions
create policy "Select competitions" on public.competitions for select using (auth.role() = 'authenticated');
create policy "Modify competitions" on public.competitions for all
  using (public.get_my_role() = 'admin' or (public.get_my_role() = 'coordinator' and hosted_by = auth.uid()));

-- competition_submissions
create policy "Select submissions" on public.competition_submissions for select
  using (auth.role() = 'authenticated');
create policy "Insert submissions" on public.competition_submissions for insert
  with check (auth.uid() = member_id);
create policy "Modify submissions" on public.competition_submissions for all
  using (auth.uid() = member_id or public.get_my_role() = 'admin');

-- learning_resources
create policy "Select resources" on public.learning_resources for select using (auth.role() = 'authenticated');
create policy "Modify resources" on public.learning_resources for all
  using (public.get_my_role() = 'admin' or (public.get_my_role() = 'coordinator' and uploaded_by = auth.uid()));


-- ==========================================
-- AUTHENTICATION NEW USER TRIGGER
-- ==========================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, role, needs_approval)
  values (
    new.id, 
    new.email, 
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), 
    'member',
    true
  );
  return new;
end;
$$ language plpgsql security definer;

-- Trigger definition
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ==========================================
-- STORAGE BUCKETS CONFIGURATION (REFERENCE)
-- ==========================================
-- Safe instructions to create storage buckets.
-- Buckets can be created manually in Supabase Console or through RPC.
-- 1. "contribution-photos" - Public, user folder paths ({user_id}/*), size limit 10MB, mime types image/jpeg, image/png, image/webp
-- 2. "avatars" - Public, user avatar paths ({user_id}/avatar), size limit 2MB, mime types image/jpeg, image/png
