alter table public.pfd_clubs
  add column city text not null default '',
  add column state text not null default '',
  add column country text not null default '',
  add column contact_number text not null default '',
  add column league text not null default '',
  add column sport text not null default '';
alter table public.pfd_clubs drop constraint pfd_clubs_location_check;
alter table public.pfd_clubs add constraint pfd_clubs_location_check check(char_length(location)<=320);
-- Existing clubs are preserved without inventing their missing details.
-- NOT VALID still enforces this constraint on every new INSERT or UPDATE.
alter table public.pfd_clubs add constraint pfd_clubs_required_details check (
  char_length(btrim(city)) between 1 and 80 and
  char_length(btrim(state)) between 1 and 80 and
  char_length(btrim(country)) between 1 and 80 and
  char_length(btrim(league)) between 1 and 160 and
  char_length(btrim(sport)) between 1 and 80 and
  char_length(contact_email) between 3 and 254 and
  contact_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' and
  char_length(contact_number) between 7 and 32 and
  contact_number ~ '^[+0-9() .-]+$' and
  char_length(regexp_replace(contact_number,'[^0-9]','','g')) between 7 and 15
) not valid;
