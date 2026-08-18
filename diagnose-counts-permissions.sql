-- Diagnostic only — run in Supabase SQL Editor, paste the output back.
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'counts';

select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'counts';

select rowsecurity
from pg_tables
where tablename = 'counts';
