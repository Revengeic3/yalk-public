-- NOTE:
--
-- File paths need to be edited. Search for $$PATH$$ and
-- replace it with the path to the directory containing
-- the extracted data files.
--
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.9 (Debian 13.9-0+deb11u1)
-- Dumped by pg_dump version 15.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: db_chat; Type: DATABASE; Schema: -; Owner: -
--

-- CREATE DATABASE db_chat WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'en_US.UTF-8';


--
-- Name: chats; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA chats;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: delete(text); Type: FUNCTION; Schema: chats; Owner: -
--

CREATE FUNCTION chats.delete(chat_id text) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
	c_users text[];
	old_chats text[];
	n_chats text[];
-- 	this_usr text;
	this text;

BEGIN
IF EXISTS (SELECT FROM information_schema.tables 
		   		WHERE table_schema = 'chats' 
		   		AND table_name = (chat_id)) THEN
	EXECUTE format('DROP TABLE IF EXISTS chats.%I', chat_id);
	
	SELECT users FROM public.server_chats 
			WHERE id = (chat_id) INTO c_users;
			
			
	DELETE FROM public.server_chats WHERE id = (chat_id);
	
	FOREACH this IN ARRAY c_users 
		LOOP
			SELECT joined_chats FROM users_settings 
			WHERE id = this INTO old_chats;

			UPDATE users_settings
			SET joined_chats = sub.chats
			FROM (SELECT COALESCE(ARRAY_AGG(elem), '{}') chats
						FROM UNNEST(old_chats) elem
						WHERE elem <> ALL(ARRAY[chat_id])) AS sub
			WHERE id = this;
		END LOOP;
END IF;	
RETURN 'ok';
END$$;


--
-- Name: exists(text[]); Type: FUNCTION; Schema: chats; Owner: -
--

CREATE FUNCTION chats."exists"(chat_users text[]) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
	r_id text;

BEGIN
	SELECT id FROM public.server_chats 
	WHERE users IN (chat_users)
	AND type = 'dm' INTO r_id;
	RETURN r_id;
END$$;


--
-- Name: join(text, text); Type: FUNCTION; Schema: chats; Owner: -
--

CREATE FUNCTION chats."join"(rq_id text, rq_user text) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
	r_id text;
	r_usrs text[];

BEGIN
SELECT id, users FROM public.server_chats 
	WHERE id = rq_id
	AND (users @> (ARRAY[rq_user])::text[] OR 
		  type = 'channel_public') INTO r_id, r_usrs;
IF (r_usrs @> (ARRAY[rq_user])::text[]) THEN
	RAISE INFO 'Already joined, returning';
	RETURN 'exists';
END IF;
	
RAISE INFO 'r_id: %', r_id;
RAISE INFO 'r_usrs: %', r_usrs;
									 
IF (r_id <> '') IS TRUE THEN
	UPDATE public.users_settings
		SET joined_chats = array_append(joined_chats, rq_id) 
		WHERE id = rq_user;
		
	UPDATE public.server_chats
		SET users = array_append(users, rq_user) 
		WHERE id = rq_id;
	RETURN r_id;
ELSE
	RETURN 'err';
END IF;
END$$;


--
-- Name: new(text, text, text, text[]); Type: FUNCTION; Schema: chats; Owner: -
--

CREATE FUNCTION chats.new(name text, type text, id_creator text, users text[]) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	chat_id text;
	user_id text;
	field_to_upd text;
BEGIN
	SELECT * INTO chat_id FROM chats.random_string(8);
	EXECUTE format('CREATE TABLE IF NOT EXISTS chats.%I (LIKE chats.template INCLUDING ALL)', chat_id);

-- 	SELECT CASE type
-- 			WHEN 'dm' THEN 'joined_dms'
-- 			ELSE 'joined_channels'
-- 		END AS field INTO field_to_upd;
		
	FOREACH user_id IN ARRAY users LOOP
		EXECUTE format(
		'UPDATE users_settings SET joined_chats = array_append(joined_chats, %L) WHERE id = %L', 
		chat_id, user_id);
	END LOOP;
	
	INSERT INTO public.server_chats(id, type, users, name, created_by, created_date)
	VALUES 
		(chat_id, type, users, name, id_creator, current_timestamp);

	RETURN chat_id;
END
$$;


--
-- Name: random_string(integer); Type: FUNCTION; Schema: chats; Owner: -
--

CREATE FUNCTION chats.random_string(integer) RETURNS text
    LANGUAGE sql
    AS $_$
SELECT string_agg(substring('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', round(random() * 30)::integer, 1), '') 
FROM generate_series(1, $1);
$_$;


--
-- Name: create_channel_table(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_channel_table(table_name text) RETURNS integer
    LANGUAGE plpgsql
    AS $$DECLARE
	chan_id int4;
	chan_uid text;
BEGIN

	WITH new_row AS (
    INSERT INTO server_channels
        (name)
    VALUES
        (table_name)
    RETURNING id
	)
	SELECT id INTO chan_id FROM new_row;
	PERFORM update_channel_uid(chan_id);
   EXECUTE format('
      CREATE TABLE IF NOT EXISTS %I (LIKE chat_channel_template INCLUDING ALL)', 'chat_channel_' || chan_id);
	RETURN chan_id;
END
$$;


--
-- Name: create_dm_table(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_dm_table(table_id text, user_id_1 integer, user_id_2 integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
	DECLARE
	dm_id int4;
BEGIN
	UPDATE users_settings
					SET joined_dms = array_append(joined_dms, table_id)
					WHERE id = user_id_1;
	UPDATE users_settings
					SET joined_dms = array_append(joined_dms, table_id)
					WHERE id = user_id_2;
	WITH new_row AS (
    INSERT INTO server_dms(uid, users)
    VALUES
        (table_id, ARRAY[user_id_1, user_id_2])
    RETURNING id
	)
	SELECT "id" INTO dm_id FROM new_row;
   EXECUTE format('
      CREATE TABLE IF NOT EXISTS %I (LIKE chat_dm_template INCLUDING ALL)', table_id);
	RETURN dm_id;
END
$$;


--
-- Name: update_channel_uid(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_channel_uid(chan_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
	chan_uid text;
BEGIN
	chan_uid := ('chat_channel_' || chan_id);
	UPDATE server_channels
		SET uid = chan_uid
	WHERE id = chan_id;
	RETURN chan_uid;
END$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: 0CACFGP5; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."0CACFGP5" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: 0CACFGP5_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."0CACFGP5" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats."0CACFGP5_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1
);


--
-- Name: 1B2GSP5R; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."1B2GSP5R" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: 1B2GSP5R_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."1B2GSP5R" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats."1B2GSP5R_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1
);


--
-- Name: AOSDOA7M; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."AOSDOA7M" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: AOSDOA7M_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."AOSDOA7M" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats."AOSDOA7M_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1
);


--
-- Name: CHATMAIN; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."CHATMAIN" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: CHATRAND; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."CHATRAND" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: E2QBI8NK; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."E2QBI8NK" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: E2QBI8NK_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."E2QBI8NK" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats."E2QBI8NK_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1
);


--
-- Name: GO6EFORS; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats."GO6EFORS" (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: GO6EFORS_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."GO6EFORS" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats."GO6EFORS_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1
);


--
-- Name: server_chats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.server_chats (
    id text NOT NULL,
    type text NOT NULL,
    users text[] NOT NULL,
    name text,
    created_by text NOT NULL,
    created_date date NOT NULL
);


--
-- Name: all_server_chats; Type: VIEW; Schema: chats; Owner: -
--

CREATE VIEW chats.all_server_chats AS
 WITH channel AS (
         SELECT server_chats.id
           FROM public.server_chats
        )
 SELECT channel.id
   FROM channel;


--
-- Name: template; Type: TABLE; Schema: chats; Owner: -
--

CREATE TABLE chats.template (
    id integer NOT NULL,
    "time" timestamp(0) without time zone,
    message character varying(255),
    event character varying(16),
    user_id text
);


--
-- Name: chat_channel_1_copy1_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats.template ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats.chat_channel_1_copy1_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chat_log_copy1_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."CHATRAND" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats.chat_log_copy1_id_seq
    START WITH 5
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chat_log_id_seq; Type: SEQUENCE; Schema: chats; Owner: -
--

ALTER TABLE chats."CHATMAIN" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME chats.chat_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: get; Type: VIEW; Schema: chats; Owner: -
--

CREATE VIEW chats.get AS
 SELECT server_chats.id,
    server_chats.type,
    server_chats.users,
    server_chats.name,
    server_chats.created_by,
    server_chats.created_date
   FROM public.server_chats
  WHERE (server_chats.type ~~ '%_public'::text);


--
-- Name: users_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_settings (
    id text NOT NULL,
    display_name character varying(255),
    color character varying(255),
    is_admin boolean,
    joined_chats text[]
);


--
-- Name: all_messages_profiles_last_100; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.all_messages_profiles_last_100 AS
 SELECT sub.id,
    sub."time",
    sub.message,
    sub.event,
    sub.user_id,
    users_settings.display_name,
    users_settings.color,
    users_settings.is_admin AS isadmin
   FROM (( SELECT "CHATMAIN".id,
            "CHATMAIN"."time",
            "CHATMAIN".message,
            "CHATMAIN".event,
            "CHATMAIN".user_id
           FROM chats."CHATMAIN"
          ORDER BY "CHATMAIN"."time" DESC
         LIMIT 100) sub
     JOIN public.users_settings ON ((sub.user_id = users_settings.id)))
  ORDER BY sub."time";


--
-- Name: login_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_users (
    id text NOT NULL,
    username character varying(255),
    password character varying(255)
);


--
-- Name: user_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_status (
    id text NOT NULL,
    status_fixed character varying,
    status character varying NOT NULL,
    last_login timestamp without time zone,
    last_offline timestamp without time zone,
    is_online boolean
);


--
-- Name: all_user_profiles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.all_user_profiles AS
 SELECT login_users.id,
    login_users.username,
    users_settings.display_name,
    users_settings.color,
    users_settings.is_admin,
    users_settings.joined_chats,
    user_status.status,
    user_status.status_fixed,
    user_status.last_login,
    user_status.last_offline,
    user_status.is_online
   FROM ((public.login_users
     JOIN public.users_settings ON ((users_settings.id = login_users.id)))
     JOIN public.user_status ON ((user_status.id = users_settings.id)));


--
-- Name: http_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.http_sessions (
    user_id character varying(32) NOT NULL,
    expires timestamp(6) without time zone NOT NULL,
    session_token character varying(255) NOT NULL,
    created timestamp(6) without time zone
);


--
-- Name: server_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.server_settings (
    key text NOT NULL,
    value text
);


--
-- Name: tcp_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tcp_sessions (
)
INHERITS (public.http_sessions);


--
-- Name: 0CACFGP5 0CACFGP5_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."0CACFGP5"
    ADD CONSTRAINT "0CACFGP5_pkey" PRIMARY KEY (id);


--
-- Name: 1B2GSP5R 1B2GSP5R_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."1B2GSP5R"
    ADD CONSTRAINT "1B2GSP5R_pkey" PRIMARY KEY (id);


--
-- Name: AOSDOA7M AOSDOA7M_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."AOSDOA7M"
    ADD CONSTRAINT "AOSDOA7M_pkey" PRIMARY KEY (id);


--
-- Name: E2QBI8NK E2QBI8NK_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."E2QBI8NK"
    ADD CONSTRAINT "E2QBI8NK_pkey" PRIMARY KEY (id);


--
-- Name: GO6EFORS GO6EFORS_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."GO6EFORS"
    ADD CONSTRAINT "GO6EFORS_pkey" PRIMARY KEY (id);


--
-- Name: template chat_channel_1_copy1_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats.template
    ADD CONSTRAINT chat_channel_1_copy1_pkey PRIMARY KEY (id);


--
-- Name: CHATRAND chat_log_copy1_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."CHATRAND"
    ADD CONSTRAINT chat_log_copy1_pkey PRIMARY KEY (id);


--
-- Name: CHATMAIN chat_log_pkey; Type: CONSTRAINT; Schema: chats; Owner: -
--

ALTER TABLE ONLY chats."CHATMAIN"
    ADD CONSTRAINT chat_log_pkey PRIMARY KEY (id);


--
-- Name: http_sessions http_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.http_sessions
    ADD CONSTRAINT http_sessions_pkey PRIMARY KEY (session_token);


--
-- Name: login_users login_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_users
    ADD CONSTRAINT login_users_pkey PRIMARY KEY (id);


--
-- Name: server_chats uniq_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.server_chats
    ADD CONSTRAINT uniq_id PRIMARY KEY (id);


--
-- Name: http_sessions unique_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.http_sessions
    ADD CONSTRAINT unique_id UNIQUE (user_id);


--
-- Name: server_settings unique_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.server_settings
    ADD CONSTRAINT unique_key PRIMARY KEY (key);


--
-- Name: http_sessions unique_token; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.http_sessions
    ADD CONSTRAINT unique_token UNIQUE (session_token);


--
-- Name: user_status user_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_status
    ADD CONSTRAINT user_status_pkey PRIMARY KEY (id);


--
-- Name: users_settings users_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_settings
    ADD CONSTRAINT users_settings_pkey PRIMARY KEY (id);


--
-- Name: 0CACFGP5_id_idx; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX "0CACFGP5_id_idx" ON chats."0CACFGP5" USING btree (id);


--
-- Name: 1B2GSP5R_id_idx; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX "1B2GSP5R_id_idx" ON chats."1B2GSP5R" USING btree (id);


--
-- Name: AOSDOA7M_id_idx; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX "AOSDOA7M_id_idx" ON chats."AOSDOA7M" USING btree (id);


--
-- Name: E2QBI8NK_id_idx; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX "E2QBI8NK_id_idx" ON chats."E2QBI8NK" USING btree (id);


--
-- Name: GO6EFORS_id_idx; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX "GO6EFORS_id_idx" ON chats."GO6EFORS" USING btree (id);


--
-- Name: index_id; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX index_id ON chats."CHATMAIN" USING btree (id);


--
-- Name: index_id_copy1; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX index_id_copy1 ON chats."CHATRAND" USING btree (id);


--
-- Name: index_id_copy2; Type: INDEX; Schema: chats; Owner: -
--

CREATE UNIQUE INDEX index_id_copy2 ON chats.template USING btree (id);


--
-- PostgreSQL database dump complete
--

