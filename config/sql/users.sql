-- Table: public.users

-- DROP TABLE public.users;

CREATE TABLE public.users
(
  id text[] NOT NULL,
  updated timestamp with time zone,
  notifications text[],
  subscriptions text[],
  email text NOT NULL,
  preferences text,
  password text,
  token text,
  watched text[],
  CONSTRAINT users_email_key UNIQUE (email)
);

GRANT ALL ON TABLE public.users TO kemal;

-- Index: public.email_unique_idx

-- DROP INDEX public.email_unique_idx;

CREATE UNIQUE INDEX email_unique_idx
  ON public.users
  USING btree
  (lower(email) COLLATE pg_catalog."default");

