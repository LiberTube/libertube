-- Table: public.channel_videos

-- DROP TABLE public.channel_videos;

CREATE TABLE public.channel_videos
(
  id text NOT NULL,
  title text,
  published timestamp with time zone,
  updated timestamp with time zone,
  ucid text,
  author text,
  length_seconds integer,
  CONSTRAINT channel_videos_id_key UNIQUE (id)
);

GRANT ALL ON TABLE public.channel_videos TO kemal;

-- Index: public.channel_videos_published_idx

-- DROP INDEX public.channel_videos_published_idx;

CREATE INDEX channel_videos_published_idx
  ON public.channel_videos
  USING btree
  (published);

-- Index: public.channel_videos_ucid_idx

-- DROP INDEX public.channel_videos_ucid_idx;

CREATE INDEX channel_videos_ucid_idx
  ON public.channel_videos
  USING hash
  (ucid COLLATE pg_catalog."default");

