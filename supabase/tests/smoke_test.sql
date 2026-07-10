BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

SELECT ok(true, 'pgtap installed and callable');

INSERT INTO auth.users (id, email)
VALUES ('00000000-0000-0000-0000-0000000000aa', 'smoke@test.com');
SELECT ok(
  EXISTS(SELECT 1 FROM auth.users WHERE email = 'smoke@test.com'),
  'postgres role can insert into auth.users'
);

SET LOCAL role authenticated;
SELECT ok(current_user = 'authenticated', 'can impersonate authenticated role');
RESET role;

SELECT * FROM finish();
ROLLBACK;
